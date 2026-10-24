# Changelog

This project uses [Semantic Versioning](https://semver.org/). A change to the minimum
DuckDB or Yazi version is a breaking change.

## [Unreleased]

### Fixed

- `g o` / `g u` open DuckDB again. The opener ran `Command` in a sync block, which Yazi
  does not allow, and passed its queries with `-c`, which makes DuckDB exit after them. It
  now uses `-cmd` and hides Yazi while DuckDB runs.
- Summarized mode with `cache_enabled = false` shows statistics instead of `⏱` placeholders.
- Summarized peek stops waiting for a cache when no preload starts within 30 s. Before, a
  previewer rule without a matching preloader rule waited forever.
- A failed cached preview keeps the current row instead of jumping to the top.
- A preview pane of 6 rows or fewer no longer marks a valid cache as bad.
- Column scroll stops counting at the last column, so `H` moves left on the first press.
- A tabular `.txt` file is checked for plain text once, not on every scroll step.
- `scripts/check-cve.sh` runs (it had a missing `}`) and lists advisories newest first.

### Removed

- The README `mime = "application/x-parquet"` previewer rule. The plugin detects file types
  only by extension, so the rule showed the code previewer.

## [1.0.1] - 2026-10-23

### Security

- Preview hardening named filesystems that do not exist (`HttpFileSystem`, `GcsFileSystem`,
  `AzureFileSystem`), and DuckDB ignores unknown names. HTTP(S), Hugging Face and Azure reads
  were not blocked. The list now uses `HTTPFileSystem`, `S3FileSystem` (also gs:// and r2://),
  `HuggingFaceFileSystem`, `AzureBlobStorageFileSystem` and `AzureDfsStorageFileSystem`. The
  smoke test checks that each remote scheme is refused.
- With `auto_install_extensions = false`, previews set `autoinstall_known_extensions = false`,
  so a previewed file cannot make DuckDB download an extension.

### Fixed

- Column scroll (`H`/`L`) works on a freshly hovered file. Before, the first press reset the
  column offset to 0.

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

[1.0.1]: https://github.com/stevencarpenter/duckdb.yazi/releases/tag/v1.0.1
[1.0.0]: https://github.com/stevencarpenter/duckdb.yazi/releases/tag/v1.0.0
