#!/usr/bin/env bash
set -euo pipefail

# Queries the OSV API for recent DuckDB and Yazi advisories.
# Run monthly or before upgrading DuckDB/Yazi.

query_osv() {
    local ecosystem="$1"
    local package="$2"
    curl -fsSL "https://api.osv.dev/v1/query" \
        -H "Content-Type: application/json" \
        -d "{\"package\":{\"name\":\"${package}\",\"ecosystem\":\"${ecosystem}\"}}" \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
vulns = data.get('vulns', [])
if not vulns:
    print('  No advisories returned by OSV.')
    sys.exit(0)
for v in vulns[:10]:
    vid = v.get('id', 'unknown')
    summary = (v.get('summary') or '')[:120]
    print(f'  - {vid}: {summary}')
if len(vulns) > 10:
    print(f'  ... and {len(vulns) - 10} more')
"

echo "=== Local versions ==="
if command -v duckdb >/dev/null 2>&1; then
    echo "duckdb: $(duckdb --version 2>&1 | head -n1)"
else
    echo "duckdb: not installed"
fi

if command -v yazi >/dev/null 2>&1; then
    echo "yazi: $(yazi --version 2>&1 | head -n1)"
else
    echo "yazi: not installed"
fi

echo
echo "=== OSV: PyPI duckdb (CLI releases track closely) ==="
query_osv "PyPI" "duckdb" || echo "  (OSV query failed)"

echo
echo "=== Manual checks ==="
echo "  DuckDB advisories: https://github.com/duckdb/duckdb/security/advisories"
echo "  Yazi releases:     https://github.com/sxyazi/yazi/releases"
echo
echo "Minimum versions for this plugin: DuckDB >= 1.4.2, Yazi >= 25.4.8 (25.5.31+ recommended)"
