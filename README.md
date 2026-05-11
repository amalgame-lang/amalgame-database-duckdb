# amalgame-database-duckdb

[DuckDB](https://duckdb.org) binding for [Amalgame](https://github.com/amalgame-lang/Amalgame).
Embedded analytical (OLAP) database — think "SQLite for analytics".
Vendored C++ amalgamation, MIT-licensed, no external `libduckdb-dev`
needed.

## Requirements

- amc **>= 0.5.3** (C++ source support in the package manager)
- A C++17-capable g++ (any g++ ≥ 8 will do)
- ~30–60 seconds the first time you build a project that uses
  it — DuckDB's amalgamation is ~25 MB of C++.

## Install

```bash
amc package add github.com/amalgame-lang/amalgame-database-duckdb@v0.1.0
# or via the curated index:
amc package add duckdb@v0.1.0
```

## Use

```amalgame
namespace Demo

import Amalgame.Collections
import Amalgame.Database.DuckDB

public class Program {
    public static void Main(string[] args) {
        // Empty path = in-memory ephemeral database.
        // Pass a filename like "analytics.db" for persistence.
        let db = DuckDB.Open("")
        if (!DuckDB.IsOpen(db)) {
            Console.WriteError("open failed: " + DuckDB.LastError(db))
            return
        }

        DuckDB.Exec(db, "CREATE TABLE events (ts TIMESTAMP, kind VARCHAR, count INTEGER)")
        DuckDB.Exec(db, "INSERT INTO events VALUES (NOW(), 'login', 42), (NOW(), 'logout', 17)")

        let rows = DuckDB.QueryAll(db, "SELECT kind, SUM(count) FROM events GROUP BY kind")
        let n: int = rows.Count()
        for i in 0..n {
            let row: List<string> = rows.Get(i)
            Console.WriteLine(row.Get(0) + " → " + row.Get(1))
        }

        DuckDB.Close(db)
    }
}
```

Run it:

```bash
amc test                  # auto-resolves the dep, links the amalgamation
```

## Surface

| Method                          | Returns         | Description |
| ------------------------------- | --------------- | ----------- |
| `DuckDB.Open(path)`             | `AmalgameDuckDB*` | Opens a database; empty path → in-memory. |
| `DuckDB.Close(db)`              | `void`            | Closes connection + database. Idempotent. |
| `DuckDB.IsOpen(db)`             | `bool`            | True if `Open` succeeded. |
| `DuckDB.LastError(db)`          | `string`          | Last error message (empty if none). |
| `DuckDB.Exec(db, sql)`          | `bool`            | Runs a no-result statement. Returns success. |
| `DuckDB.QueryAll(db, sql)`      | `List<List<string>>` | Runs a SELECT; every value materialised as text. |

## Why DuckDB?

DuckDB is the SQLite of analytics — embedded, single-file, no
server, but optimised for columnar OLAP queries on millions of
rows. Use it for:

- ETL pipelines that don't fit in memory but don't need a full
  warehouse;
- Local analytics on Parquet / CSV / JSON without a separate
  process;
- Read-heavy workloads where SQLite's row-based storage caps
  performance.

For OLTP / row-by-row writes, prefer `amalgame-database-sqlite`.

## Roadmap

- Prepared statements via `?` placeholders
- Typed column accessors (`AsInt(row, col)`, `AsDouble`, etc.)
- Parquet ingest helpers (`DuckDB.LoadParquet(path)`)
- Transactions (`BEGIN`/`COMMIT`/`ROLLBACK`) as first-class methods
- Result-streaming for queries that don't fit in memory

## Licence

Apache-2.0 for the binding (see `LICENSE`). The vendored DuckDB
amalgamation is MIT — see `NOTICE.md` for attribution.

## Authorship + contributions

Bastien Mouget is the sole author of the binding. External pull
requests are paused, mirroring the upstream
[Amalgame contribution policy](https://github.com/amalgame-lang/Amalgame/blob/main/CONTRIBUTING.md).
Bug reports via Issues remain open.
