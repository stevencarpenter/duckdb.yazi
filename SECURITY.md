# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| `main` branch of [stevencarpenter/duckdb.yazi](https://github.com/stevencarpenter/duckdb.yazi) | Yes |
| Upstream [wylie102/duckdb.yazi](https://github.com/wylie102/duckdb.yazi) | Unmaintained (last update May 2025) |

Minimum runtime versions:

- **DuckDB CLI** ≥ 1.4.2 (fixes [CVE-2025-64429](https://github.com/duckdb/duckdb/security/advisories/GHSA-vmp8-hg63-v2hp))
- **Yazi** ≥ 25.4.8 (≥ 25.5.31 recommended for transitive dependency fixes)

## Reporting a vulnerability

If you discover a security issue in this plugin, please report it privately:

1. Open a [GitHub Security Advisory](https://github.com/stevencarpenter/duckdb.yazi/security/advisories/new) (preferred), or
2. Email the repository owner via their GitHub profile.

Please do **not** file public issues for exploitable vulnerabilities until a fix is available.

## Threat model

### What this plugin does

- Spawns the **DuckDB CLI** to preview local data files inside [Yazi](https://github.com/sxyazi/yazi)
- Writes optional **parquet preview caches** via Yazi's cache API
- May **load** (and optionally **install**) DuckDB extensions (`spatial`, `avro`) for `.xlsx` and `.avro` files
- Can open files in an interactive DuckDB / DuckDB UI session on explicit user action

### Trust boundaries

| Trusted | Untrusted |
|---------|-----------|
| Your installed DuckDB and Yazi binaries | Data files from downloads, email attachments, shared folders |
| Files you intentionally preview | DuckDB extension CDN (`install.duckdb.org`) when auto-install is enabled |
| Your Yazi config | Malicious filenames (partially mitigated by SQL escaping) |

### Hardening applied (preview/preload only)

Preview spawns use:

- `duckdb -init /dev/null` (or `NUL` on Windows) to ignore `~/.duckdbrc` startup output
- `SET disabled_filesystems = 'HttpFileSystem,S3FileSystem,GcsFileSystem,AzureFileSystem'` to block remote filesystem reads

Note: `enable_external_access = false` is intentionally **not** set because it also blocks reading local preview files.

Interactive open (`g` + `o` / `g` + `u`) intentionally **does not** apply preview hardening.

### Residual risks

1. **Malicious data files** — DuckDB must parse parquet, avro, xlsx, csv, etc. Keep DuckDB updated.
2. **Local filesystem access** — DuckDB reads files you can already read; preview hardening blocks remote FS, not local.
3. **Extension supply chain** — Set `auto_install_extensions = false` and pre-install extensions locally.
4. **Cache persistence** — Preview caches may retain sensitive data on disk. Use `cache_enabled = false` or `yazi --clear-cache`.
5. **Fork maintenance** — Security fixes depend on this fork staying current with DuckDB/Yazi advisories.

## Recommended secure configuration

```lua
require("duckdb"):setup({
  auto_install_extensions = false,
  cache_enabled = true, -- set false when browsing sensitive directories
})
```

Pre-install extensions once:

```sh
duckdb -c "INSTALL spatial; LOAD spatial; INSTALL avro; LOAD avro;"
```

## Security checklist

- [ ] DuckDB ≥ 1.4.2 (`duckdb --version`)
- [ ] Yazi ≥ 25.5.31 (`yazi --version`)
- [ ] `auto_install_extensions = false` in `init.lua`
- [ ] Extensions pre-installed (if using `.xlsx` / `.avro`)
- [ ] Run `scripts/check-cve.sh` monthly
- [ ] `yazi --clear-cache` after browsing sensitive data
