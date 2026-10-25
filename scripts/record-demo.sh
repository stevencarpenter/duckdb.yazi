#!/usr/bin/env bash
# Record docs/demo.gif from docs/demo/demo.tape.
# Needs vhs, yazi, the DuckDB CLI with the avro extension installed, and the
# "DejaVuSansM Nerd Font Mono" font.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "${work:?}"' EXIT

mkdir -p "$work/home/data" "$work/config/plugins" "$work/cache"
# Load the plugin from this checkout, and keep the installed DuckDB extensions under the fake HOME.
ln -s "$repo" "$work/config/plugins/duckdb.yazi"
ln -s "$HOME/.duckdb" "$work/home/.duckdb"

cp "$repo/docs/demo/config/init.lua" "$repo/docs/demo/config/keymap.toml" "$work/config/"
{
    cat "$repo/docs/demo/config/yazi.toml"
    printf '\n[preview]\ncache_dir = "%s"\n' "$work/cache"
} >"$work/config/yazi.toml"

(cd "$work/home/data" && DUCKDB_AGENT_MODE=0 duckdb -init /dev/null -bail <"$repo/docs/demo/gen.sql" >/dev/null)

cd "$repo"
DEMO_DIR="$work" vhs docs/demo/demo.tape
