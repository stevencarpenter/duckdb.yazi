#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="${ROOT}/tests/fixtures/sample.csv"
MIN_DUCKDB_VERSION="1.4.2"

if ! command -v duckdb >/dev/null 2>&1; then
    echo "error: duckdb CLI not found on PATH" >&2
    exit 1
fi

version_ge() {
    local installed="$1"
    local required="$2"
    local lowest
    lowest="$(printf '%s\n%s\n' "$required" "$installed" | sort -V | head -n1)"
    [[ "$lowest" == "$required" ]]
}

raw_version="$(duckdb --version 2>&1 | head -n1)"
installed_version="$(printf '%s' "$raw_version" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
if [[ -z "$installed_version" ]]; then
    echo "error: could not parse DuckDB version from: ${raw_version}" >&2
    exit 1
fi

if ! version_ge "$installed_version" "$MIN_DUCKDB_VERSION"; then
    echo "error: DuckDB ${installed_version} < required ${MIN_DUCKDB_VERSION}" >&2
    exit 1
fi

echo "DuckDB version ${installed_version} OK"

# Preview-style spawn: skip duckdbrc, harden, read local fixture
duckdb -init /dev/null \
    -c "SET enable_progress_bar = false;" \
    -c "SET disabled_filesystems = 'HttpFileSystem,S3FileSystem,GcsFileSystem,AzureFileSystem';" \
    -c "SELECT count(*) AS rows FROM read_csv('${FIXTURE}');" \
    >/dev/null

echo "Security-hardened CSV read OK"

# Lambda syntax used by column scrolling (DuckDB 1.5+)
duckdb -init /dev/null \
    -c "SELECT list_filter(['a', 'b', 'c'], lambda x: x = 'b');" \
    >/dev/null

echo "Lambda syntax OK"
echo "Smoke tests passed"
