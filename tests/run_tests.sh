#!/bin/bash
# ─────────────────────────────────────────────────────
#  amalgame-database-duckdb — Test Runner
#  Usage: ./tests/run_tests.sh [/path/to/amc]
#
#  Compiles the test fixture using `amc`, builds the vendored
#  duckdb.cpp amalgamation with g++, links them together, runs
#  the binary, and greps stdout for expected output.
#
#  Discovers amc in this order:
#    1. First positional arg (when present)
#    2. AMC environment variable
#    3. `amc` on PATH
#
#  DuckDB requires amc >= 0.5.3 (C++ source support in
#  PreCompilePackageSources). This runner ALSO works with older
#  amc because it does the g++ link itself rather than relying on
#  `amc test`'s auto-link path.
# ─────────────────────────────────────────────────────

set -u

# ── Locate amc ─────────────────────────────────────────
if [ $# -ge 1 ]; then
    AMC="$1"
elif [ -n "${AMC:-}" ]; then
    : # use env-var as-is
elif command -v amc >/dev/null 2>&1; then
    AMC="$(command -v amc)"
else
    echo "ERROR: amc not found. Pass the path as first arg, set AMC env var, or put amc on PATH." >&2
    exit 2
fi

if [ ! -x "$AMC" ]; then
    echo "ERROR: amc binary at '$AMC' is not executable." >&2
    exit 2
fi

# ── Locate package root ────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_RUNTIME="$PKG_ROOT/runtime"
DUCKDB_CPP="$PKG_ROOT/runtime/Amalgame_Database/duckdb/duckdb.cpp"

if [ ! -f "$DUCKDB_CPP" ]; then
    echo "ERROR: vendored duckdb.cpp not found at $DUCKDB_CPP" >&2
    exit 2
fi

# ── Locate amc's runtime/ ──────────────────────────────
AMC_DIR="$(cd "$(dirname "$AMC")" && pwd)"
if [ -d "$AMC_DIR/runtime" ]; then
    AMC_RUNTIME="$AMC_DIR/runtime"
elif [ -n "${AMC_RUNTIME:-}" ]; then
    : # honor env-var override
else
    echo "ERROR: can't find amc's runtime/ headers." >&2
    echo "       Tried $AMC_DIR/runtime, AMC_RUNTIME env var unset." >&2
    echo "       Either run from a source build of Amalgame, or set" >&2
    echo "       AMC_RUNTIME=/path/to/Amalgame/runtime before running." >&2
    exit 2
fi
echo "  runtime: $AMC_RUNTIME"

# ── Setup ──────────────────────────────────────────────
BUILD_DIR="$(mktemp -d -t addk-tests-XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

PROJ_DIR="$BUILD_DIR/proj"
mkdir -p "$PROJ_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

echo ""
echo "════════════════════════════════════════════"
echo "  amalgame-database-duckdb — Test Suite"
echo "════════════════════════════════════════════"
echo "  amc:     $AMC ($("$AMC" --version 2>&1))"
echo "  package: $PKG_ROOT"
echo ""

# ── Stage a fake cache pointing at the local working tree ──
# Without this, the test .am file's `import Amalgame.Database.DuckDB`
# fails because amc has no way to know about the package. The
# real install flow (`amc package add`) needs a published tag,
# which this CI doesn't have until release time.
#
# Trick: build a cache-dir layout that matches what amc would
# produce, symlink the cache entry to the local working tree,
# then point amc at it via $AMALGAME_PACKAGES_DIR + a manual
# amalgame.lock in the project dir.
FAKE_CACHE="$BUILD_DIR/cache"
PKG_GIT="github.com/amalgame-lang/amalgame-database-duckdb"
PKG_TAG="${PKG_TAG:-v0.1.0}"
FAKE_SHA="deadbeefcafebabe0000000000000000000000ab"
SHORT_SHA="${FAKE_SHA:0:8}"
PKG_CACHE_DIR="$FAKE_CACHE/$PKG_GIT/${PKG_TAG}_${SHORT_SHA}"

mkdir -p "$(dirname "$PKG_CACHE_DIR")"
# Ensure no leftover empty dir at the target — `ln -s` would
# otherwise create the symlink *inside* the directory instead
# of replacing it.
rm -rf "$PKG_CACHE_DIR"
ln -s "$PKG_ROOT" "$PKG_CACHE_DIR"

cat > "$PROJ_DIR/amalgame.lock" <<EOF
[[package]]
name = "amalgame-database-duckdb"
git  = "$PKG_GIT"
tag  = "$PKG_TAG"
rev  = "$FAKE_SHA"
EOF

export AMALGAME_PACKAGES_DIR="$FAKE_CACHE"
echo "  cache:   $FAKE_CACHE → $PKG_ROOT"
echo ""

# ── Pre-compile duckdb.cpp once ────────────────────────
# DuckDB amalgamation is ~25 MB of C++. The runner uses -O0 here
# because optimisation gains nothing for the test path (we don't
# benchmark query performance, just functional correctness) and
# -O2 takes 15-30+ minutes on the official amalgamation.
# Production users of the package via `amc test` pick up the
# manifest's `[stdlib].cxxflags` instead — that's where -O2 lives.
DUCKDB_OBJ="$BUILD_DIR/duckdb.o"
echo "── Pre-compiling DuckDB amalgamation (-O0, ~3-5 min) ──"
g++ -O0 -DNDEBUG -std=c++17 -w -I"$AMC_RUNTIME" -I"$PKG_RUNTIME" -c "$DUCKDB_CPP" -o "$DUCKDB_OBJ"
if [ ! -f "$DUCKDB_OBJ" ]; then
    echo "ERROR: g++ failed to build duckdb.o" >&2
    exit 1
fi
echo "  built: $DUCKDB_OBJ ($(stat -c%s "$DUCKDB_OBJ" 2>/dev/null || stat -f%z "$DUCKDB_OBJ") bytes)"
echo ""

# ── Helper ─────────────────────────────────────────────
run_test() {
    local name="$1"
    local expected="$2"

    printf "  %-38s" "$name"

    cp "$SCRIPT_DIR/stdlib_database_duckdb.am" "$PROJ_DIR/test.am"
    local out_base="$PROJ_DIR/test"

    local out
    out=$(cd "$PROJ_DIR" && "$AMC" -o test test.am 2>&1)
    local amc_exit=$?
    if [ $amc_exit -ne 0 ]; then
        echo -e "${RED}FAIL${NC} (amc exited $amc_exit)"
        echo "$out" | head -3 | sed 's/^/    /'
        FAIL=$((FAIL + 1)); return
    fi
    if [ ! -f "$out_base.c" ]; then
        echo -e "${RED}FAIL${NC} (no .c emitted)"
        FAIL=$((FAIL + 1)); return
    fi
    # Two-stage: amc's emitted .c uses C-style void* conversions
    # which g++ rejects, so compile with gcc, then link with g++
    # (libstdc++ + C++ static-init order for the amalgamation).
    gcc -O2 -I"$AMC_RUNTIME" -I"$PKG_RUNTIME" -c "$out_base.c" -o "$out_base.o" 2>/dev/null
    if [ ! -f "$out_base.o" ]; then
        echo -e "${RED}FAIL${NC} (gcc compile failed)"
        FAIL=$((FAIL + 1)); return
    fi
    g++ -O2 "$out_base.o" "$DUCKDB_OBJ" \
        -lgc -lm -lcurl -ldl -lpthread -o "$out_base" 2>/dev/null
    if [ ! -x "$out_base" ]; then
        echo -e "${RED}FAIL${NC} (g++ link failed)"
        FAIL=$((FAIL + 1)); return
    fi
    local run_output
    run_output=$("$out_base" 2>&1)
    if echo "$run_output" | grep -qF "$expected"; then
        echo -e "${GREEN}PASS${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} (output mismatch)"
        echo "    expected: $expected"
        echo "    got:      $(echo "$run_output" | head -3 | tr '\n' '|')"
        FAIL=$((FAIL + 1))
    fi
}

# ── Cases ──────────────────────────────────────────────
echo "── Database.DuckDB ─────────────────────────"
run_test "open memory"                  "[PASS] open memory"
run_test "create table"                 "[PASS] create table"
run_test "insert batch"                 "[PASS] insert batch"
run_test "query rows"                   "[PASS] query 3 rows"
run_test "column text"                  "[PASS] alice name"
run_test "row int as text"              "[PASS] alice age"
run_test "aggregate count"              "[PASS] aggregate count"
run_test "update reflected"             "[PASS] alice age post-update"
run_test "error reported"               "[PASS] error reported"
run_test "delete + verify"              "[PASS] delete leaves 2"
run_test "close"                        "[PASS] closed"

# ── Summary ────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
echo -e "  ${GREEN}PASS: $PASS${NC}  |  ${RED}FAIL: $FAIL${NC}  |  ${YELLOW}SKIP: $SKIP${NC}"
echo "────────────────────────────────────────────"
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
