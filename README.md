# duckdb.yazi

**Uses  [duckdb](https://github.com/duckdb/duckdb) to quickly preview and summarize data files in [yazi](https://github.com/sxyazi/yazi)!**

<br>

<https://github.com/user-attachments/assets/ff2b11fb-d6fa-4b6a-b1a9-8aceed520189>

<br><br>

## What does it do?

This plugin previews your data files in yazi using DuckDB, with two available view modes:

- Preview .csv, .tsv, .txt (tabular), .json, .parquet, .avro, or .xlsx files in the following modes
    - Standard mode (default): Displays the file as a table
    - Summarized mode: Uses DuckDB's summarize function, enhanced with custom formatting for readability
- Preview duckdb databases
    - See the tables and the number of rows, columns, indexes in each. Plus a list of column names in index order.
- Scroll rows using `J` and `K`
- Scroll columns using your chosen keys (I use `H` and `L`)
- Change modes by pressing K when at the top of a file

Supported file types:

- .csv
- .tsv
- .txt - if tabular data
- .json
- .parquet
- .avro
- .xlsx
- .duckdb
- .db – if file is a duckdb database

<br><br>

## Features

### Column Scrolling

<br>

<https://github.com/user-attachments/assets/b347a7e8-05ea-442d-a88e-e2447975b653>

<br>

- Now supports scrolling horizontally (by column).
- Works in all views
- In the database view you can even scroll through the list of column names.
- Output highlighting should now work across any os (where duckdb supports it).

> Requires a small amount of extra configuration from previous versions. These are keymaps (I use `H` and `L`) and some other additional customisation options.
>
>See the [Installation](https://github.com/wylie102/duckdb.yazi/tree/main?tab=readme-ov-file#installation)
> and [Configuration](https://github.com/wylie102/duckdb.yazi/tree/main?tab=readme-ov-file#configurationcustomisation) sections.

> **Cache changes – update 04/04/25** – If you want info on the latest (cache-related changes), then
> see [here](https://github.com/wylie102/duckdb.yazi?tab=readme-ov-file#setup-and-usage-changes-from-previous-versions). Otherwise, keep reading new features and
> config options below.
<br>

<br>

### Output Syntax Highlighting

- Passes through the colors from the duckdb output as you would see if using directly in the terminal.
- These colors can be configured in your `~/.duckdbrc` file, see the Configuration section for details.

<br>

**Syntax highlighting with duckdb's default color scheme.**
<img width="700" alt="Screenshot 2025-04-02 at 14 53 38" src="https://github.com/user-attachments/assets/d2267298-b91b-496c-ae74-1d432b826f6f" />

<br>

**Syntax highlighting with customized color scheme.**
<img width="700" alt="Screenshot 2025-04-02 at 14 44 08" src="https://github.com/user-attachments/assets/965a0a4e-e4ed-4d88-ab95-84cd543f2a58" />

<br>

### Preview DuckDB Databases

- If you open a `.db` or `.duckdb` file directly, the plugin lists all tables in the database.
- Each entry includes:
    - Table name
    - Rows Count
    - Column count
    - Primary key presence
    - Index count
    - All column names (aggregated and in index order)
- Tables are **alphabetically ordered** and paginated for smooth scrolling.
- Reads directly from the db in read-only mode for file safety.

<br>

<img width="700" alt="Screenshot 2025-04-02 at 14 46 19" src="https://github.com/user-attachments/assets/c640d6f3-d9f6-4d98-acd8-9e4c87c6e728" />

<br>

### More customization options – row_id (row number) and width of the min/max columns

- Row id – in standard view to help keep track when scrolling, Default is off, but can be turned on in `init.lua` options.
- Width of min and max columns. Default is now 21 twice as wide as previously. Is now customizable in the `init.lua`, the unit is the number of characters
  shown.

<br>

<img width="700" alt="Screenshot 2025-04-02 at 14 49 26" src="https://github.com/user-attachments/assets/6c8fb1ae-3de8-41ce-9c90-0279dc3b5e61" />

<br><br>

### Preview mode is now toggleable

- Preview mode can be toggled within yazi
- Press "K" at the top of the file to toggle between "standard" and "summarized."
- The mode enabled at startup is customizable in the `init.lua` see Configuration section.

### Performance improvements through caching

- "Standard" and "summarized" views are cached upon first load, improving scrolling performance

- Note that on entering a directory you haven't entered before (or one containing files that have been changed), caching is triggered. Until caches are
  generated, summarized mode may take longer to show as it will be run on the original file, and scrolling other files during this time (especially large
  ones) can slow things even further as new queries on the file will be competing with cached queries. Instead, it is worth waiting until the caches load (displayed in bottom right corner) or switching to standard view during these first few seconds. This will be most noticeable on large, non-parquet files

<br><br>

## Installation

### Requirements

| Component | Minimum | Recommended | Why |
|-----------|---------|-------------|-----|
| [Yazi](https://yazi-rs.github.io/docs/installation) | 25.4.8 | 25.5.31+ | Plugin API compatibility; newer builds include security fixes in transitive dependencies |
| [DuckDB CLI](https://duckdb.org/docs/installation/) | 1.4.2 | 1.5.0+ | Fixes [CVE-2025-64429](https://github.com/duckdb/duckdb/security/advisories/GHSA-vmp8-hg63-v2hp); 1.5+ uses the modern lambda syntax this fork targets |

Verify your versions:

```sh
yazi --version
duckdb --version
```

### Installing dependencies

Install Yazi and DuckDB using the links above, then add this plugin with the Yazi package manager:

```sh
ya pkg add stevencarpenter/duckdb
```

> This fork (`stevencarpenter/duckdb.yazi`) includes fixes and `.avro` support not yet merged into upstream `wylie102/duckdb.yazi`. Use the command above rather than `ya pkg add wylie102/duckdb`.

### Pre-install DuckDB extensions (recommended)

For `.xlsx` and `.avro` previews, pre-install extensions once so the plugin does not need to download them at preview time:

```sh
duckdb -c "INSTALL spatial; LOAD spatial; INSTALL avro; LOAD avro;"
```

Then use the secure defaults in `init.lua` (see [Configuration](#configurationcustomisation)).

<br>

### yazi.toml

Then navigate to your [yazi.toml](https://yazi-rs.github.io/docs/configuration/yazi#manager.ratio) file this should be the `yazi` folder in your `config`
directory

and add:

```toml
[plugin]
prepend_previewers = [
    { url = "*.csv", run = "duckdb" },
    { url = "*.tsv", run = "duckdb" },
    { url = "*.json", run = "duckdb" },
    { url = "*.parquet", run = "duckdb" },
    { mime = "application/x-parquet", run = "duckdb" },
    { url = "*.avro", run = "duckdb" },
    { url = "*.txt", run = "duckdb" },
    { url = "*.xlsx", run = "duckdb" },
    { url = "*.db", run = "duckdb" },
    { url = "*.duckdb", run = "duckdb" }
]

prepend_preloaders = [
    { url = "*.csv", run = "duckdb", multi = false },
    { url = "*.tsv", run = "duckdb", multi = false },
    { url = "*.json", run = "duckdb", multi = false },
    { url = "*.parquet", run = "duckdb", multi = false },
    { url = "*.avro", run = "duckdb", multi = false },
    { url = "*.txt", run = "duckdb", multi = false },
    { url = "*.xlsx", run = "duckdb", multi = false }
]
```

> Note on .txt: I have tried to exclude files that contain only raw text (if duckdb reads only one column). However, if you don't ever work with .txt files
> which contain tabular data (basically misnamed csv or tsv files), then you can just not include the .txt lines in your setup.

<br>

> Note on .xlsx: This can be temperamental, especially around inferring types. This is due to the way that duckdb handles Excel files. This feature currently
> uses st_read from the spatial extension since it gives the most consistent type results. Hopefully, they will soon implement some of the smart type detection
> from the csv reader in their Excel extension, and then we can use that instead.

<br>

### init.lua

Then create an `init.lua` file in the same folder and add

```lua
-- Recommended secure defaults
require("duckdb"):setup({
  auto_install_extensions = false,
  cache_enabled = true,
})
```

See [SECURITY.md](SECURITY.md) for the full threat model and [Configuration](#configurationcustomisation) for all options.

This is where the configuration/settings can go ([see below](https://github.com/wylie102/duckdb.yazi?tab=readme-ov-file#configurationcustomisation)), but the
init.lua file and this line are required for the plugin to run, even if the settings are blank. Another option is to add all the settings with the defaults
in so that it's easy to change at a later date.

<br>

### keymap.toml

Then in your [keymap.toml](https://yazi-rs.github.io/docs/configuration/keymap) file add:

```toml
[[manager.prepend_keymap]]
on = "H"
run = "plugin duckdb -- -1"
desc = "Scroll one column to the left"

[[manager.prepend_keymap]]
on = "L"
run = "plugin duckdb -- +1"
desc = "Scroll one column to the right"

[[manager.prepend_keymap]]
on = ["g", "o"]
run = "plugin duckdb -- -open"
desc = "open with duckdb"

[[manager.prepend_keymap]]
on = ["g", "u"]
run = "plugin duckdb -- -ui"
desc = "open with duckdb ui"

```

> **Yazi 26.x:** Plugin arguments must be passed after `--` (e.g. `plugin duckdb -- -1`). On Yazi 25.x, `plugin duckdb -1` may still work.

> I use `H` and `L` because it makes logical sense to me.
>
>But these overwrite:
>
>- `H` - previous directory and
>- `L` - next directory
   > (different from standard `h` and `l` for parent and child directory).
>
>So if you use those, you might want to choose something else or remap those to <C-h> and <C-l> instead.

<br>

### Additional setup and recommended plugins for more preview space

Use with a larger preview window – add to your `yazi.toml`

```toml
[manager]
ratio = [1, 2, 5]
```

For reference, the default ratio is 1, 4, 3

Use:

[maximize the preview pane plugin](https://github.com/yazi-rs/plugins/tree/main/toggle-pane.yazi)

<br><br>

## Configuration/Customisation

Configuration of yazi.duckdb is done via the `init.lua` file in `config/yazi` (where your plugin folder and yazi.toml file live).
If you don't have one, you can just create one.
Add the following:

```lua
require("duckdb"):setup({
  mode = "summarized",                       -- "standard" or "summarized"
  cache_size = 500,                          -- rows cached in standard mode
  cache_enabled = true,                      -- false to skip parquet caches (sensitive data)
  auto_install_extensions = false,           -- true to download spatial/avro at preview time
  row_id = false,                            -- true, false, or "dynamic"
  minmax_column_width = 21,
  column_fit_factor = 10,
})
```

If you don't include a setting, it will revert to the default.

But the setup call `require("duckdb"):setup()` is still required for the plugin to initialize correctly.

<br>

### Explanation of settings

- mode – the view that will be the default on startup. The default is summarized, but this can sometimes be slow if running while the files are also being
  cached. Most of the time it will be the same speed as standard, so pick the one you like.


- cache_size – the number of rows cached in the standard mode. Make the number higher if you want to be able to scroll further down in your files. Be aware this
  could impact cache size and cache performance if it was made too large. If you change this setting you will need to run `yazi --clear-cache` for it to take
  effect.

- cache_enabled – when `false`, skips parquet cache generation and always reads from the source file. Use this when previewing sensitive data to avoid writing
  copies under Yazi's cache directory. Default: `true`.

- auto_install_extensions – when `false` (recommended), only runs `LOAD spatial` / `LOAD avro` and expects you to pre-install extensions. When `true`, runs
  `INSTALL` before each preview (requires network access). Default: `false`.

- row_id - displays a row column when viewing in standard mode. If set to dynamic, it will only turn on when scrolling columns and will always be the left most
  column.

- minmax_column_width - is the number of characters displayed in the min and max columns in summarized view. Default is 21, which is roughly enough to see date
  and time in a datetime column. If you need more, set it higher, if you want min/max to take up less space, set it lower.

- column_fit_factor – this one is actually important but might feel a bit counter-intuitive, so have a look below.
    - TLDR: duckdb.yazi is designed to overspill the screen on the right side. Unless all your columns are incredibly narrow/you can see the right border of
      your table when there are still more columns to scroll OR you work with tables with a huge number of columns and scrolling them feels slightly slow,
      you can probably leave it alone.
    - Slightly longer instructions: To fully optimize this, 1. Lower it until your columns no longer spill off the end of the screen (check this on a few files)
      Step 2 – Increase by 1 so that columns again spill over the right border.
    - More detailed explanation: Implementing column scrolling also gave us a mechanism to request only as many columns as we need to fill (in reality
      slightly overfill) the screen. The reason for this is that if the table is incredibly wide (has a high number of columns), it would slow down the query.
      But while the plugin can detect how wide the display area is, it doesn't know how wide your columns are. So this number represents the average amount of
      space (in characters) duckdb.yazi expects each column to take up when deciding how many columns to request. columns_displayed = display_area_width /
      column_fit_factor. So larger number = fewer columns, smaller number = more columns. Ideally, you want the columns to **just** spill over the right border
      of the screen, which will give the feeling of movement when scrolling. The default - 10.0 - should accommodate most column sizes while giving good
      performance. Setting to 7.73 should display even the narrowest columns correctly but may cause queries to be slightly slower when working with huge
      numbers of columns.

### Configuring duckdb

Preview highlighting is configured in-plugin (`.highlight_results on`). Previews also use `duckdb -init /dev/null` so your `~/.duckdbrc` does not affect preview output.

For **interactive** DuckDB sessions (`g` + `o` / `g` + `u`), configuration can be done in the `~/.duckdbrc` file in your home directory ([duckdb docs](https://duckdb.org/docs/stable/operations_manual/footprint_of_duckdb/files_created_by_duckdb)).

You can customize the colors of the preview using the following options

```
.highlight_colors layout gray 
.highlight_colors column_name magenta bold
.highlight_colors column_type gray
.highlight_colors string_value cyan
.highlight_colors numeric_value green
.highlight_colors temporal_value blue
.highlight_colors footer gray
```

The above configuration is what is used in the video at the top of the readme and in the screenshots of the color highlighting section.
Although the actual colors will depend on your terminal/yazi color scheme.
These should be placed in your `~/.duckdbrc` file as is.
No header is needed; they are simply commands to run on the startup of any duckdb instance (when using the CLI).
These will change the color of the output when using DuckDB interactively or via `g` + `o` / `g` + `u`. Preview panes use built-in highlighting instead of `~/.duckdbrc`.

Color options are:
red|green|yellow|blue|magenta|cyan|white

You can also specify bold, underline or bold_underline after the colors
e.g. `.highlight_colors column_type red bold_underline`

If the file is empty or doesn't exist, then the default duckdb color scheme will be used
This uses gray for borders and NULLs and looks like this

<img width="700" alt="Screenshot 2025-04-02 at 14 53 38" src="https://github.com/user-attachments/assets/d2267298-b91b-496c-ae74-1d432b826f6f" />

You can also turn the highlighting off by adding `.highlight_results off`
In which case it will look like below.

<img width="700" alt="Screenshot 2025-03-22 at 18 00 06" src="https://github.com/user-attachments/assets/db09fff9-2db1-4273-9ddf-34d0bf087967" />

More information [here](https://duckdb.org/docs/stable/clients/cli/dot_commands#configuring-the-result-syntax-highlighter)

<br><br>

## Security

Preview and preload operations spawn DuckDB with hardening enabled:

- `duckdb -init /dev/null` — ignores `~/.duckdbrc` startup output (fixes preview breakage when a duckdbrc exists)
- `SET disabled_filesystems = 'HttpFileSystem,S3FileSystem,GcsFileSystem,AzureFileSystem'` — blocks remote filesystem reads (local files still readable for preview)

**Recommended defaults:** `auto_install_extensions = false` with extensions pre-installed (see [Installation](#pre-install-duckdb-extensions-recommended)).

**Residual risks:**

- DuckDB still reads local files you preview; treat untrusted data files (downloads, shared folders) as potentially hostile.
- `.xlsx` and `.avro` require the `spatial` and `avro` extensions — pre-install them to avoid runtime downloads.
- Preview caches write parquet copies under Yazi's cache directory. Set `cache_enabled = false` or run `yazi --clear-cache` after browsing sensitive data.
- Opening files in DuckDB UI (`g` + `o` / `g` + `u`) launches a full interactive DuckDB session without preview hardening.

See [SECURITY.md](SECURITY.md) for the full threat model and reporting instructions.

### Maintenance scripts

```sh
./scripts/smoke-test.sh   # verify DuckDB integration (also run in CI)
./scripts/check-cve.sh    # check OSV for DuckDB advisories (run monthly)
```

<br><br>

## Setup and usage changes from previous versions

### A Note on the Latest update

Added logic for reading `.avro` files and added a toggle for preview mode between schema/summary statistics and full table preview. Make sure you are taking note of the new settings in the yazi.toml file as name has been replaced with url in that configuration. Nothing will work without it.
