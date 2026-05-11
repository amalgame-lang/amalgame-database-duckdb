/*
 * Amalgame Standard Library — Amalgame.Database.DuckDB
 * Copyright (c) 2026 Bastien MOUGET
 * https://github.com/amalgame-lang/amalgame-database-duckdb
 *
 * DuckDB binding. The official amalgamation
 * (`runtime/Amalgame_Database/duckdb/duckdb.cpp` +
 *  `runtime/Amalgame_Database/duckdb/duckdb.h` + `.hpp`)
 * is vendored from duckdb.org under DuckDB's MIT licence — no
 * external `libduckdb-dev` needed on any supported OS. User projects
 * that import `Amalgame.Database.DuckDB` get the C++ amalgamation
 * compiled with g++ and linked into their binary; the amc compiler
 * itself never imports this header so amc's own build doesn't pull
 * in 25 MB of C++.
 *
 * Sibling backends (SQLite, Postgres, MySQL, …) live under the
 * `Amalgame.Database.<Engine>` namespace family — the convention
 * keeps user code explicit about which engine it talks to.
 *
 * v0.1 surface: open / close, IsOpen, exec (no-result SQL),
 * QueryAll (returns a List<List<string>> with column values as
 * text), LastError. Prepared statements + typed accessors are
 * the next ask, tracked in the repo issues.
 *
 * Threading: DuckDB connections are not thread-safe — open a
 * separate connection per thread. The AmalgameDuckDB struct owns
 * one connection; spawn one per worker if you need concurrency.
 */

#ifndef AMALGAME_DATABASE_DUCKDB_H
#define AMALGAME_DATABASE_DUCKDB_H

#include "_runtime.h"
#include "Amalgame_Collections.h"
#include "Amalgame_Database/duckdb/duckdb.h"
#include <string.h>
#include <stdlib.h>

typedef struct AmalgameDuckDB {
    duckdb_database   db;
    duckdb_connection con;
    char*             last_error;  /* GC-strdup'd snapshot of the last error message */
    int               is_open;
} AmalgameDuckDB;

static inline code_string Amalgame_DuckDB_strdup_err(const char* msg) {
    if (!msg) return NULL;
    size_t n = strlen(msg);
    char* p = (char*) code_alloc(n + 1);
    memcpy(p, msg, n + 1);
    return p;
}

/* Open a DuckDB database at `path`. An empty string or NULL opens
 * a transient in-memory database (great for tests + ETL pipelines
 * that don't need persistence). Returns a non-NULL AmalgameDuckDB*
 * even on failure — call `Db.IsOpen()` to check, or `Db.LastError()`
 * for the message. */
static inline AmalgameDuckDB* Amalgame_Database_DuckDB_Open(code_string path) {
    AmalgameDuckDB* d = (AmalgameDuckDB*) code_alloc(sizeof(AmalgameDuckDB));
    d->db         = NULL;
    d->con        = NULL;
    d->last_error = NULL;
    d->is_open    = 0;
    const char* p = (path && path[0] != '\0') ? path : NULL;
    if (duckdb_open(p, &d->db) != DuckDBSuccess) {
        d->last_error = Amalgame_DuckDB_strdup_err("duckdb_open failed");
        return d;
    }
    if (duckdb_connect(d->db, &d->con) != DuckDBSuccess) {
        d->last_error = Amalgame_DuckDB_strdup_err("duckdb_connect failed");
        duckdb_close(&d->db);
        d->db = NULL;
        return d;
    }
    /* Auto-install + auto-load known DuckDB extensions on first use.
     * The bare amalgamation ships without `core_functions` (which is
     * where SUM / AVG / STDDEV / etc. live), so without this most
     * analytical queries error out with "Scalar Function with name
     * 'sum' is not in the catalog". With these two settings the first
     * such query downloads + caches the extension from extensions.
     * duckdb.org into `~/.duckdb/extensions/<ver>/<plat>/`; subsequent
     * uses hit the cache and need no network. Offline environments
     * (CI without internet, air-gapped boxes) stick to COUNT / MIN /
     * MAX which are built into the parser/core. */
    duckdb_result r0;
    if (duckdb_query(d->con, "SET autoinstall_known_extensions=1;", &r0) == DuckDBSuccess) {
        duckdb_destroy_result(&r0);
    }
    if (duckdb_query(d->con, "SET autoload_known_extensions=1;", &r0) == DuckDBSuccess) {
        duckdb_destroy_result(&r0);
    }
    d->is_open = 1;
    return d;
}

/* Close the underlying DuckDB connection + database. Idempotent —
 * calling twice (or on a never-opened handle) is a no-op. The
 * AmalgameDuckDB struct is GC-managed; we don't free it here. */
static inline void Amalgame_Database_DuckDB_Close(AmalgameDuckDB* d) {
    if (!d) return;
    if (d->con) { duckdb_disconnect(&d->con); d->con = NULL; }
    if (d->db)  { duckdb_close(&d->db); d->db = NULL; }
    d->is_open = 0;
}

static inline code_bool Amalgame_Database_DuckDB_IsOpen(AmalgameDuckDB* d) {
    return (d && d->is_open) ? 1 : 0;
}

/* Snapshot of the most recent error message (open / connect /
 * malformed SQL / constraint violation). Empty string if no
 * error has been recorded on this handle. */
static inline code_string Amalgame_Database_DuckDB_LastError(AmalgameDuckDB* d) {
    if (!d || !d->last_error) return "";
    return d->last_error;
}

/* Execute a no-result SQL statement (CREATE / INSERT / UPDATE /
 * DELETE / etc.). Returns 1 on success, 0 on failure — call
 * LastError() for the message on failure. */
static inline code_bool Amalgame_Database_DuckDB_Exec(AmalgameDuckDB* d, code_string sql) {
    if (!d || !d->is_open || !sql) return 0;
    duckdb_result r;
    if (duckdb_query(d->con, sql, &r) != DuckDBSuccess) {
        const char* err = duckdb_result_error(&r);
        d->last_error = Amalgame_DuckDB_strdup_err(err ? err : "duckdb_query failed");
        duckdb_destroy_result(&r);
        return 0;
    }
    duckdb_destroy_result(&r);
    return 1;
}

/* Run a SELECT (or any statement that returns rows) and collect
 * every result into a List<List<string>> — outer list is rows,
 * inner list is columns. Every column value is materialized as
 * text via duckdb_value_varchar regardless of declared type;
 * NULL columns become empty strings. Returns an empty list on
 * query failure — check LastError() to distinguish a real empty
 * result from a failure. */
static inline AmalgameList* Amalgame_Database_DuckDB_QueryAll(AmalgameDuckDB* d, code_string sql) {
    AmalgameList* rows = AmalgameList_new();
    if (!d || !d->is_open || !sql) return rows;
    duckdb_result r;
    if (duckdb_query(d->con, sql, &r) != DuckDBSuccess) {
        const char* err = duckdb_result_error(&r);
        d->last_error = Amalgame_DuckDB_strdup_err(err ? err : "duckdb_query failed");
        duckdb_destroy_result(&r);
        return rows;
    }
    idx_t nRows = duckdb_row_count(&r);
    idx_t nCols = duckdb_column_count(&r);
    for (idx_t i = 0; i < nRows; i++) {
        AmalgameList* row = AmalgameList_new();
        for (idx_t j = 0; j < nCols; j++) {
            char* val = duckdb_value_varchar(&r, j, i);
            const char* s = val ? val : "";
            size_t n = strlen(s);
            char* copy = (char*) code_alloc(n + 1);
            memcpy(copy, s, n + 1);
            AmalgameList_add(row, (void*) copy);
            if (val) duckdb_free(val);
        }
        AmalgameList_add(rows, (void*) row);
    }
    duckdb_destroy_result(&r);
    return rows;
}

#endif /* AMALGAME_DATABASE_DUCKDB_H */
