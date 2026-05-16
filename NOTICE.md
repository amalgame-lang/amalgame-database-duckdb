# NOTICE — amalgame-database-duckdb

Copyright (c) 2026 Bastien Mouget
Licensed under the Apache License, Version 2.0 (the "License"); see
LICENSE for the full text.

## Vendored third-party code

This package vendors the official DuckDB amalgamation under
`runtime/Amalgame_Database/duckdb/`:

| File              | Source                              | Version   | Licence  |
| ----------------- | ----------------------------------- | --------- | -------- |
| `duckdb.cpp`      | duckdb.org `libduckdb-src.zip`      | v1.5.2    | MIT      |
| `duckdb.hpp`      | duckdb.org `libduckdb-src.zip`      | v1.5.2    | MIT      |
| `duckdb.h`        | duckdb.org `libduckdb-src.zip`      | v1.5.2    | MIT      |
| `duckdb_extension.h` | duckdb.org `libduckdb-src.zip`   | v1.5.2    | MIT      |

DuckDB is © DuckDB Labs and contributors and distributed under the
[MIT licence](https://github.com/duckdb/duckdb/blob/main/LICENSE).
A copy of the MIT licence text is reproduced below.

The bindings in `runtime/Amalgame_Database_DuckDB.h` and the test
fixtures under `tests/` are © Bastien Mouget, Apache-2.0.

### DuckDB MIT licence

```
MIT License

Copyright 2018-2025 Stichting DuckDB Foundation

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
```

## Upgrading the vendored amalgamation

```bash
curl -L -o /tmp/libduckdb-src.zip \
    https://github.com/duckdb/duckdb/releases/download/vX.Y.Z/libduckdb-src.zip
cd runtime/Amalgame_Database/duckdb/
unzip -o /tmp/libduckdb-src.zip
# Bump the version row in this file + `amalgame.toml`.
```

Verify the binding still compiles + tests pass:

```bash
./tests/run_tests.sh /path/to/amc
```
