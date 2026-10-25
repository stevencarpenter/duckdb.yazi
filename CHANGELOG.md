# Changelog

This project uses [Semantic Versioning](https://semver.org/). A change to the minimum
DuckDB or Yazi version is a breaking change.

## [2.0.1] - 2026-10-25

The plugin code did not change.

### Changed

- Rewrote the README. It now has a recorded demo GIF in place of the MP4 embeds that did
  not play on GitHub.
- Rewrote `SECURITY.md`. The extension host is `extensions.duckdb.org`.
- The bug report template asks for current Yazi and DuckDB versions.

### Added

- `scripts/record-demo.sh` and `docs/demo/`, which generate the sample data and record
  `docs/demo.gif` with VHS.

## [2.0.0] - 2026-10-23

### Breaking

- Require Yazi 25.5.28 or later. The plugin already needed it, because it uses `ya.emit` and
  `ya.preview_widget`, which Yazi added in 25.5.28. The docs said 25.4.8, but Yazi 25.4.8 to
  25.5.27 could not run the plugin.

### Security

- Preview hardening named filesystems that do not exist (`HttpFileSystem`, `GcsFileSystem`,
  `AzureFileSystem`), and DuckDB ignores unknown names. HTTP(S), Hugging Face and Azure reads
  were not blocked. The list now uses `HTTPFileSystem`, `S3FileSystem` (also gs:// and r2://),
  `HuggingFaceFileSystem`, `AzureBlobStorageFileSystem` and `AzureDfsStorageFileSystem`. The
  smoke test checks that https, s3, gs, r2, hf, az and abfss reads are refused.
- With `auto_install_extensions = false`, previews set `autoinstall_known_extensions = false`,
  so a previewed file cannot make DuckDB download an extension.

### Fixed

- `g o` / `g u` open DuckDB again. The opener ran `Command` in a sync block, which Yazi
  does not allow, and passed its queries with `-c`, which makes DuckDB exit after them. It
  now uses `-cmd` and hides Yazi while DuckDB runs.
- Summarized mode with `cache_enabled = false` shows statistics instead of `⏱` placeholders.
- Summarized peek stops waiting for a cache when no preload starts within 30 s. Before, a
  previewer rule without a matching preloader rule waited forever.
- A failed cached preview keeps the current row instead of jumping to the top.
- A preview pane of 6 rows or fewer no longer marks a valid cache as bad.
- Column scroll (`H`/`L`) works on a freshly hovered file. Before, the first press reset the
  column offset to 0.
- Column scroll stops counting at the last column, so `H` moves left on the first press. In
  the `.duckdb` view, one step past the last column no longer shows an empty table.
- An empty `.duckdb` file no longer shows a stray `NULL` line.
- A tabular `.txt` file is checked for plain text once, not on every scroll step. A failed
  check is tried again on the next peek instead of being remembered.
- `scripts/check-cve.sh` runs (it had a missing `}`) and lists advisories newest first.

### Removed

- The README `mime = "application/x-parquet"` previewer rule. The plugin detects file types
  only by extension, so the rule showed the code previewer.

### Added

- `tests/peek_test.lua`, which runs the plugin against the DuckDB CLI with stand-ins for the
  Yazi API. CI runs it and the smoke tests on DuckDB 1.5.0, 1.5.6 and 2.0.0.

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

[2.0.1]: https://github.com/stevencarpenter/duckdb.yazi/releases/tag/v2.0.1
[2.0.0]: https://github.com/stevencarpenter/duckdb.yazi/releases/tag/v2.0.0
[1.0.0]: https://github.com/stevencarpenter/duckdb.yazi/releases/tag/v1.0.0
