# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| Latest release and `main` branch of [stevencarpenter/duckdb.yazi](https://github.com/stevencarpenter/duckdb.yazi) | Yes |
| Original [wylie102/duckdb.yazi](https://github.com/wylie102/duckdb.yazi) | No. Unmaintained since May 2025 |

Minimum runtime versions:

- **DuckDB CLI** 1.5.0 or later (1.5.x or 2.x). 1.5.0 includes the fix for [CVE-2025-64429](https://github.com/duckdb/duckdb/security/advisories/GHSA-vmp8-hg63-v2hp).
- **Yazi** 25.5.28 or later. 25.5.31 or later is recommended for fixes in transitive dependencies.

## Reporting a vulnerability

Report security issues privately:

1. Open a [GitHub Security Advisory](https://github.com/stevencarpenter/duckdb.yazi/security/advisories/new). This is the preferred method.
2. Or email the repository owner. The address is on their GitHub profile.

Do not open a public issue for an exploitable vulnerability until a fix is available.

## Threat model

### What the plugin does

- Starts the **DuckDB CLI** to preview local data files in [Yazi](https://github.com/sxyazi/yazi).
- Writes **Parquet preview caches** through Yazi's cache API, unless `cache_enabled = false`.
- Loads the DuckDB `spatial` and `avro` extensions for `.xlsx` and `.avro` files. It installs them only when `auto_install_extensions = true`.
- Opens an interactive DuckDB CLI or DuckDB UI session when the user presses `g o` or `g u`.

### Trust boundaries

| Trusted | Untrusted |
|---------|-----------|
| Your installed DuckDB and Yazi binaries | Data files from downloads, email attachments and shared folders |
| Your Yazi configuration | The DuckDB extension repository (`extensions.duckdb.org`) when auto-install is enabled |
| | File names. The plugin escapes quotes in paths and table names before it puts them in SQL |

### Hardening applied to previews and preloads

Preview and preload processes start DuckDB with:

- `-init /dev/null` (`NUL` on Windows), so `~/.duckdbrc` cannot change preview output.
- `SET disabled_filesystems = 'HTTPFileSystem,S3FileSystem,HuggingFaceFileSystem,AzureBlobStorageFileSystem,AzureDfsStorageFileSystem'`, which blocks http(s), s3, gs, r2, hf and Azure reads. DuckDB accepts an unknown file system name without an error, so `scripts/smoke-test.sh` checks that each scheme is refused.
- `SET autoinstall_known_extensions = false` unless `auto_install_extensions = true`. Extension autoinstall uses its own HTTP client, so `disabled_filesystems` does not block it.

The plugin does not set `enable_external_access = false`, because that setting also blocks reads of local files.

`g o` and `g u` do not apply this hardening.

### Remaining risks

1. **Malicious data files.** DuckDB parses every previewed file (Parquet, Avro, XLSX, CSV and others). A parser bug in DuckDB can affect the plugin. Keep DuckDB up to date.
2. **Local file access.** DuckDB can read any file that your user can read. The hardening blocks remote file systems only.
3. **Extension supply chain.** With `auto_install_extensions = true`, DuckDB downloads extensions at preview time. Keep the default `false` and install extensions once by hand.
4. **Cache persistence.** Preview caches keep a copy of previewed data on disk. Set `cache_enabled = false`, or run `yazi --clear-cache`.
5. **Maintenance.** Security fixes depend on this continuation following DuckDB and Yazi advisories.

## Recommended configuration

```lua
require("duckdb"):setup({
  auto_install_extensions = false,
  cache_enabled = true, -- set to false when you browse sensitive directories
})
```

Install the extensions once:

```sh
duckdb -c "INSTALL spatial; INSTALL avro;"
```

## Checklist

- [ ] DuckDB 1.5.0 or later (`duckdb --version`)
- [ ] Yazi 25.5.31 or later (`yazi --version`)
- [ ] `auto_install_extensions = false` in `init.lua`
- [ ] `spatial` and `avro` installed, if you preview `.xlsx` or `.avro` files
- [ ] `./scripts/check-cve.sh` run each month
- [ ] `yazi --clear-cache` run after you browse sensitive data
