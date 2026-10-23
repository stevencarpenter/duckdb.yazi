# Changelog

This project uses [Semantic Versioning](https://semver.org/). A change to the minimum
DuckDB or Yazi version is a breaking change.

## [1.0.0] - 2026-10-23

First tagged release.

### Breaking

- Require DuckDB CLI 1.5.0 or later (1.5.x or 2.x). DuckDB 1.4.x is no longer supported.

### Added

- Support for DuckDB 2.0. The plugin starts DuckDB with `DUCKDB_AGENT_MODE=0`, so
  previews keep the plain table output when Yazi runs inside a coding agent.
- CI smoke tests for DuckDB 1.5.0 and 2.0.0.

### Fixed

- Summarized peek no longer waits forever for `.duckdb` files or for a cache already
  marked bad.
- Column scroll stops at the last column instead of producing a `COLUMNS()` binder error.
  A failed query falls back to the code previewer.
- `.duckdb` table listing shows `schema.table` outside `main`, so same-named tables in
  different schemas stay separate.
- XLSX previews drop the `OGC_FID` row id column. The cache version is now 4, so old
  caches are rebuilt.
- Parquet placeholder summary keeps a stable column order on DuckDB 2.0.

[1.0.0]: https://github.com/stevencarpenter/duckdb.yazi/releases/tag/v1.0.0
