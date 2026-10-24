--- @since 25.4.8
-- DuckDB Plugin for Yazi
-- Requires DuckDB CLI >= 1.5.0 (1.5.x or 2.x) and Yazi >= 25.4.8 (Yazi >= 25.5.31 recommended).
local M = {}

-- Preview skip is stored as row offset + OFFSET_BASE, so a scroll above row 0 can toggle the mode.
local OFFSET_BASE = 50

local update_state = ya.sync(function(state, action, category, key, value)
    -- Ensure the subtable for the category exists.
    state[category] = state[category] or {}

    if action == "set" then
        state[category][key] = value
    elseif action == "get" then
        return state[category][key]
    else
        ya.err("Unknown action: " .. tostring(action))
    end
end)

local function set_opts(key, value)
    update_state("set", "opts", key, value)
end

local function get_opts(key)
    return update_state("get", "opts", key)
end

local function add_to_list(category, cache_str)
    update_state("set", category, cache_str, true)
end

local function remove_from_list(category, cache_str)
    update_state("set", category, cache_str, nil)
end

local function is_on_list(category, cache_str)
    return update_state("get", category, cache_str) ~= nil
end

-- flag defaults to "-c" (run and exit); the interactive opener passes "-cmd" (run, then read stdin).
local function add_queries_to_table(target_table, queries, flag)
    flag = flag or "-c"
    if type(queries) == "table" then
        for _, item in ipairs(queries) do
            table.insert(target_table, flag)
            table.insert(target_table, item)
        end
    else
        table.insert(target_table, flag)
        table.insert(target_table, queries)
    end
end

local function command_with_args(program, args)
    -- DuckDB >= 2.0 switches to Markdown output and writes a notice to stderr when it
    -- detects a coding agent (AI_AGENT, CLAUDECODE, ...). Older versions ignore this.
    local cmd = Command(program):env("DUCKDB_AGENT_MODE", "0")
    for _, arg_value in ipairs(args) do
        cmd = cmd:arg(arg_value)
    end
    return cmd
end

local function add_duckdb_security_queries(args)
    -- Do not set enable_external_access=false: it blocks LocalFileSystem reads and
    -- breaks preview of local data files. Remote filesystems are disabled instead.
    -- Names must match FileSystem::GetName() exactly; DuckDB accepts unknown names silently.
    -- S3FileSystem also serves gs:// and r2://.
    add_queries_to_table(args, {
        "SET disabled_filesystems = 'HTTPFileSystem,S3FileSystem,HuggingFaceFileSystem,AzureBlobStorageFileSystem,AzureDfsStorageFileSystem';",
    })
    -- Autoinstall downloads an extension over its own HTTP client, so disabled_filesystems
    -- does not stop it. A view in a previewed .duckdb file can trigger it.
    if not get_opts("auto_install_extensions") then
        add_queries_to_table(args, { "SET autoinstall_known_extensions = false;" })
    end
end

local function duckdb_null_init_path()
    if ya.target_os() == "windows" then
        return "NUL"
    end
    return "/dev/null"
end

local function append_duckdb_preview_args(args)
    table.insert(args, "-init")
    table.insert(args, duckdb_null_init_path())
end

local function add_extension_queries(args, file_type, flag)
    local extension = ({ excel = "spatial", avro = "avro" })[file_type]
    if not extension then
        return
    end
    if get_opts("auto_install_extensions") then
        add_queries_to_table(args, "install " .. extension, flag)
    end
    add_queries_to_table(args, "load " .. extension, flag)
end

local function log_query_output(label, output)
    if output then
        ya.dbg(label .. " stdout: " .. tostring(output.stdout))
        ya.dbg(label .. " stderr: " .. tostring(output.stderr))
    else
        ya.dbg(label .. " run_query returned nil")
    end
end

local function generate_data_source_string(target, file_type)
    -- Escape single quotes in the path for SQL string literal
    local url_string = "'" .. tostring(target):gsub("'", "''") .. "'"
    if file_type == "excel" then
        -- st_read adds GDAL's OGC_FID row id; read_xlsx is not used because it fails on mixed-type columns.
        return string.format("(SELECT COLUMNS(lambda c: c <> 'OGC_FID') FROM st_read(%s))", url_string)
    elseif file_type == "avro" then
        return string.format("read_avro(%s)", url_string)
    elseif file_type == "text" then
        return string.format("read_csv(%s)", url_string)
    else
        return url_string
    end
end

local extension_map = {
    csv = "csv",
    tsv = "csv",
    txt = "text",
    json = "json",
    parquet = "parquet",
    xlsx = "excel",
    avro = "avro",
    duckdb = "duckdb",
    db = "duckdb",
}

local function get_extension(filename)
    -- Match the last "dot + word characters" at the end of the string
    return filename:match("^.+%.([a-zA-Z0-9]+)$")
end

local function check_file_type(path)
    local name = path.name or ""
    local ext = get_extension(name)
    if ext then
        local filetype = extension_map[ext:lower()]
        if filetype then
            return filetype
        end
    end
    ya.err("File is not a supported file type")
    return nil
end

local get_hovered_url_string = ya.sync(function()
    return tostring(cx.active.current.hovered.url)
end)

local get_preview_skip = ya.sync(function()
    return cx.active.preview.skip
end)

local function toggle_preview_mode(target_url)
    local mode = get_opts("mode")
    local new_mode = (mode == "summarized") and "standard" or "summarized"
    set_opts("mode", new_mode)
    set_opts("mode_changed", true)
    set_opts("scrolled_columns", 0)

    local only_if = target_url
    if not only_if then
        local hovered = get_hovered_url_string()
        if hovered and hovered ~= "" then
            only_if = Url(hovered)
        end
    end

    if only_if then
        ya.emit("peek", { OFFSET_BASE, only_if = only_if })
    else
        ya.emit("peek", { OFFSET_BASE })
    end
end

-- Runs from the async entry: Command and ui.hide are not available in a ya.sync block.
local function duckdb_opener(arg)
    local hovered_url = Url(get_hovered_url_string())
    local file_type = check_file_type(hovered_url)
    if not file_type then
        return
    end

    local args = {}

    add_extension_queries(args, file_type, "-cmd")

    if file_type ~= "duckdb" then
        -- Use quoted identifier for table name (double quotes inside SQL)
        local table_name = '"' .. tostring(hovered_url.stem):gsub('"', '""') .. '"'
        local data_source_string = generate_data_source_string(hovered_url, file_type)
        local query = string.format("CREATE TABLE %s AS FROM %s;", table_name, data_source_string)
        add_queries_to_table(args, query, "-cmd")
        ya.dbg("duckdb_opener query: " .. query)
    else
        table.insert(args, tostring(hovered_url))
    end

    if arg ~= "-open" then
        table.insert(args, "-ui")
    end

    -- Give the terminal to DuckDB until it exits. Yazi < 25.5.28 names this ya.hide.
    local permit = (ui.hide or ya.hide)()
    local child, err = command_with_args("duckdb", args):stdin(Command.INHERIT):stdout(Command.INHERIT)
        :stderr(Command.INHERIT):spawn()
    if child then
        child:wait()
    end
    permit:drop()

    if not child then
        ya.err("Failed to spawn DuckDB: " .. tostring(err))
    end
end

function M:entry(job)
    local arg = job.args and job.args[1]
    if arg == "-toggle" then
        return toggle_preview_mode(nil)
    end

    if arg ~= "+1" and arg ~= "-1" then
        return duckdb_opener(arg)
    end
    local scroll_delta = tonumber(arg)

    if not scroll_delta then
        ya.err("DuckDB column scroll entry: Invalid or missing scroll delta; exiting.")
        return
    end

    local scrolled_columns = get_opts("scrolled_columns") or 0
    scrolled_columns = math.max(0, scrolled_columns + scroll_delta)
    set_opts("scrolled_columns", scrolled_columns)

    -- A peek at skip 0 means a fresh hover and resets scrolled_columns, so keep the
    -- row offset but never send less than OFFSET_BASE.
    ya.emit("peek", { math.max(OFFSET_BASE, get_preview_skip()), force = true })
end

-- Setup from init.lua:
-- require("duckdb"):setup({
--   mode = "standard"/"summarized",
--   auto_install_extensions = false,  -- recommended; pre-install spatial + avro
--   cache_enabled = true,             -- set false when previewing sensitive data
-- })
function M:setup(opts)
    opts = opts or {}

    local mode = opts.mode or "summarized"
    local column_width = opts.minmax_column_width or 21
    local row_id = opts.row_id
    if row_id == nil then
        row_id = false
    end
    local column_fit_factor = opts.column_fit_factor or 10
    local limit = opts.cache_size or 500
    local auto_install_extensions = opts.auto_install_extensions
    if auto_install_extensions == nil then
        auto_install_extensions = false
    end
    local cache_enabled = opts.cache_enabled
    if cache_enabled == nil then
        cache_enabled = true
    end

    set_opts("mode", mode)
    set_opts("mode_changed", false)
    set_opts("re_peek", false)
    set_opts("column_width", column_width)
    set_opts("row_id", row_id)
    set_opts("scrolled_columns", 0)
    set_opts("column_fit_factor", column_fit_factor)
    set_opts("limit", limit)
    set_opts("auto_install_extensions", auto_install_extensions)
    set_opts("cache_enabled", cache_enabled)
end

local function generate_preload_query(job, mode, file_type, limit)
    local data_source_string = generate_data_source_string(job.file.url, file_type)
    local limit_string = ""
    if limit then
        limit_string = "LIMIT " .. tostring(limit)
    end
    if mode == "standard" then
        return "FROM " .. data_source_string .. limit_string
    else
        return string.format(
            "SELECT * EXCLUDE(null_percentage), CAST(null_percentage AS DOUBLE) AS null_percentage FROM (SUMMARIZE FROM %s)",
            data_source_string
        )
    end
end

-- Formats one SUMMARIZE statistic as a short number (k/m/b). {col} is replaced by the column name.
local STAT_CASE = [[
    CASE
        WHEN {col} IS NULL THEN NULL{timestamp}
        WHEN TRY_CAST({col} AS DOUBLE) IS NULL THEN CAST({col} AS VARCHAR)
        WHEN CAST({col} AS DOUBLE) < 100000 THEN CAST(ROUND(CAST({col} AS DOUBLE), 2) AS VARCHAR)
        WHEN CAST({col} AS DOUBLE) < 1000000 THEN CAST(ROUND(CAST({col} AS DOUBLE) / 1000, 1) AS VARCHAR) || 'k'
        WHEN CAST({col} AS DOUBLE) < 1000000000 THEN CAST(ROUND(CAST({col} AS DOUBLE) / 1000000, 2) AS VARCHAR) || 'm'
        WHEN CAST({col} AS DOUBLE) < 1000000000000 THEN CAST(ROUND(CAST({col} AS DOUBLE) / 1000000000, 2) AS VARCHAR) || 'b'
        ELSE '∞'
    END AS {col}]]
local STAT_TIMESTAMP =
    "\n        WHEN column_type = 'TIMESTAMP' THEN coalesce(strftime(try_strptime({col}::VARCHAR, '%c.%f'), '%c'), {col}::VARCHAR)"

local function generate_summary_cte(target)
    local column_width = get_opts("column_width")
    local stats = {}
    for _, col in ipairs({ "avg", "std", "q25", "q50", "q75" }) do
        -- Only the quantiles of a TIMESTAMP column are reformatted.
        local timestamp = col:sub(1, 1) == "q" and STAT_TIMESTAMP or ""
        -- A function replacement keeps the % in strftime formats literal.
        local stat = STAT_CASE:gsub("{timestamp}", function()
            return timestamp
        end):gsub("{col}", col)
        table.insert(stats, stat)
    end
    return string.format(
        [[
SELECT
    column_name AS column,
    column_type AS type,
    count,
    approx_unique AS unique,
    null_percentage AS "null%%",
    LEFT(min, %d) AS min,
    LEFT(max, %d) AS max,
%s
FROM %s
        ]],
        column_width,
        column_width,
        table.concat(stats, ",\n"),
        target
    )
end

-- Get preview cache path
local function get_cache_path(job, mode, extension)
    local suffix = "_" .. mode .. ".parquet"
    if extension then
        suffix = "_" .. extension .. "." .. extension
    end
    local cache_version = 4
    local skip = job.skip
    job.skip = 1000000 + cache_version
    local base = ya.file_cache(job)
    job.skip = skip

    if not base then
        return nil, nil
    end

    local base_str = tostring(base) .. suffix
    local path_url = Url(base_str)
    local path_str = tostring(path_url.name)
    return path_str, path_url
end

-- Run queries.
local function run_query(job, query, target, file_type)
    local width = math.max((job.area and job.area.w * 3 or 80), 80)
    local height = math.max((job.area and job.area.h or 25), 25)

    local args = {}
    append_duckdb_preview_args(args)

    if file_type == "duckdb" then
        table.insert(args, "-readonly")
        table.insert(args, tostring(target))
    else
        add_extension_queries(args, file_type)
    end

    add_duckdb_security_queries(args)

    -- Duckbox config
    add_queries_to_table(args, {
        ".mode duckbox",
        ".timer off",
        "SET enable_progress_bar = false;",
        string.format(".maxwidth %d", width),
        string.format(".maxrows %d", height),
        ".highlight_results on",
    })

    -- Add query or list of queries
    add_queries_to_table(args, query)

    local child = command_with_args("duckdb", args):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
    if not child then
        ya.err("Failed to spawn DuckDB")
        return nil
    end

    local output, err = child:wait_with_output()
    if err or not output or not output.status.success then
        ya.err("DuckDB error: " .. (err or (output and output.stderr) or "[unknown error]"))
        return nil
    end

    return output
end

-- Prints "max_scroll=N" after the table, so peek can stop scrolled_columns at the last column.
-- peek removes the line before it renders the output.
local function with_max_scroll(queries, max_scroll_select)
    table.insert(queries, ".mode list")
    table.insert(queries, ".headers off")
    table.insert(queries, "select 'max_scroll=' || (" .. max_scroll_select .. ");")
    return queries
end

local function generate_db_query(limit, offset)
    local scroll = get_opts("scrolled_columns") or 0

    local metadata_fields = { "rows", "columns", "has_pk", "indexes" }
    local visible_column_count = 10
    local max_scroll_metadata = #metadata_fields
    local metadata_projection = { "table_name" }
    -- Tables with the same name can exist in several schemas; show the schema when it is not main.
    local qualified_table_name =
        "CASE WHEN t.schema_name = 'main' THEN t.table_name ELSE t.schema_name || '.' || t.table_name END"

    local query
    if scroll < max_scroll_metadata then
        for i = scroll + 1, #metadata_fields do
            table.insert(metadata_projection, metadata_fields[i])
        end
        table.insert(metadata_projection, "column_names") -- always show

        local projection = table.concat(metadata_projection, ", ")
        query = string.format(
            [[
WITH table_info AS (
  SELECT
    DISTINCT %s AS table_name,
    t.estimated_size AS rows,
    t.column_count AS columns,
    t.has_primary_key AS has_pk,
    t.index_count AS indexes,
    STRING_AGG(c.column_name, ', ' ORDER BY c.column_index) OVER (PARTITION BY t.table_oid) AS column_names
  FROM duckdb_tables() t
  LEFT JOIN duckdb_columns() c ON t.table_oid = c.table_oid
)
SELECT %s FROM table_info
ORDER BY table_name
LIMIT %d OFFSET %d;
]],
            qualified_table_name,
            projection,
            limit,
            offset
        )
    else
        local column_scroll = scroll - max_scroll_metadata
        local start_pos = column_scroll + 1
        local end_pos = column_scroll + visible_column_count

        query = string.format(
            [[
WITH raw AS (
  SELECT
    t.table_oid,
    %s AS table_name,
    c.column_name,
    row_number() OVER (PARTITION BY t.table_oid ORDER BY c.column_index) AS col_pos
  FROM duckdb_tables() t
  LEFT JOIN duckdb_columns() c ON t.table_oid = c.table_oid
),
scrolling AS (
  SELECT
    table_oid,
    table_name,
    column_name,
    col_pos
  FROM raw
  WHERE col_pos >= %d AND col_pos < %d
),
aggregated AS (
  SELECT
    table_name,
    STRING_AGG(column_name, ', ' ORDER BY col_pos) AS column_names
  FROM scrolling
  GROUP BY table_oid, table_name
)
SELECT table_name, column_names FROM aggregated
ORDER BY table_name
LIMIT %d OFFSET %d;
]],
            qualified_table_name,
            start_pos,
            end_pos,
            limit,
            offset
        )
    end
    -- The last scroll position shows the last column of the widest table.
    local max_scroll = string.format("select max(column_count) + %d from duckdb_tables()", max_scroll_metadata - 1)
    return with_max_scroll({ query }, max_scroll)
end

local function generate_standard_query(target, job, limit, offset)
    local scroll = get_opts("scrolled_columns") or 0
    local actual_width = math.max((job.area and job.area.w or 80), 80)
    local column_fit_factor = get_opts("column_fit_factor") or 7
    local fetched_columns = math.floor(actual_width / column_fit_factor) + scroll
    local row_id_mode = get_opts("row_id")

    -- Determine if row_id should be prepended
    local row_id_prefix = ""
    local row_id_enabled = (row_id_mode == true) or (row_id_mode == "dynamic" and scroll > 0)
    if row_id_enabled then
        row_id_prefix = "row_number() over () as row, "
    end

    local included_columns_cte = string.format(
        [[
set variable included_columns = (
    with column_list as (
        select column_name, row_number() over () as row
        from (describe select * from %s)
    )
    select list(column_name)
    from column_list
    -- Clamp the scroll so the last column stays visible; an empty COLUMNS() set is a binder error.
    where row > least(%d, (select count(*) from column_list) - 1) and row <= (%d)
);
]],
        target,
        scroll,
        fetched_columns
    )

    local filtered_select = string.format(
        "select %scolumns(lambda c: list_contains(getvariable('included_columns'), c)) from %s limit %d offset %d;",
        row_id_prefix,
        target,
        limit,
        offset
    )
    local max_scroll = string.format("select count(*) - 1 from (describe select * from %s)", target)
    return with_max_scroll({ included_columns_cte, filtered_select }, max_scroll)
end

local function generate_summarized_query(source, limit, offset)
    -- These are the scrollable fields, in display order
    local fields = {
        '"type"',
        '"count"',
        '"unique"',
        '"null%"',
        '"min"',
        '"max"',
        '"avg"',
        '"std"',
        '"q25"',
        '"q50"',
        '"q75"',
    }
    -- Stop at the last field, so H moves left on the first press.
    local scroll = math.min(get_opts("scrolled_columns") or 0, #fields - 1)
    set_opts("scrolled_columns", scroll)

    -- Always include the column name
    local selected_fields = { '"column"' }

    -- Add scrollable fields from scroll onwards
    for i = scroll + 1, #fields do
        table.insert(selected_fields, fields[i])
    end

    local summary_cte = generate_summary_cte(source)
    local projection = table.concat(selected_fields, ", ")

    return string.format(
        [[
WITH summary_cte AS (
    %s
)
SELECT %s FROM summary_cte LIMIT %d OFFSET %d;
]],
        summary_cte,
        projection,
        limit,
        offset
    )
end

-- Summary rows shown until the summarized cache exists. {p} is the placeholder, {source} the file.
local PLACEHOLDER_SUMMARY = [[(select
          column_name,
          column_type,
          '   {p} ' as count,
          '   {p} ' as "approx_unique",
          '   {p} ' as "null_percentage",
          '   {p} ' as min,
          '   {p} ' as max,
          '   {p} ' as avg,
          '   {p} ' as std,
          '   {p} ' as q25,
          '   {p} ' as q50,
          '   {p} ' as q75
          from (describe select * from {source}))]]

-- Parquet keeps count, min and max in its metadata, so those show at once.
local PARQUET_PLACEHOLDER_SUMMARY = [[
        (select
        d.column_name,
        d.column_type,
        sum(m.num_values) as count,
        '   {p} ' as "approx_unique",
        '   {p} ' as "null_percentage",
        case when min(m.stats_min) is null then '{p}' else min(m.stats_min) end as min,
        case when min(m.stats_max) is null then '{p}' else max(m.stats_max) end as max,
        '   {p} ' as "avg",
        '   {p} ' as "std",
        '   {p} ' as q25,
        '   {p} ' as q50,
        '   {p} ' as q75
        from (select *, row_number() over () as pos from (describe select * from {source})) d
        left join parquet_metadata({source}) m
        on d.column_name = m.path_in_schema
        group by all
        order by min(d.pos))
        ]]

local function generate_peek_query(target, job, limit, offset, file_type, cache_str)
    local mode = get_opts("mode")
    local is_original_file = (target == job.file.url)

    -- If the file itself is a DuckDB database, list tables/columns
    if is_original_file and file_type == "duckdb" then
        return generate_db_query(limit, offset)
    end

    local target_type = is_original_file and file_type or "cache"
    local source = generate_data_source_string(target, target_type)

    if mode == "standard" then
        return generate_standard_query(source, job, limit, offset)
    end
    local summary_source = source
    if is_original_file and not get_opts("cache_enabled") then
        -- No cache is ever built, so summarize the file now instead of showing placeholders.
        summary_source = "(" .. generate_preload_query(job, "summarized", file_type) .. ")"
    elseif is_original_file then
        local placeholder = is_on_list("bad_cache", cache_str) and "∅" or "⏱"
        local template = file_type == "parquet" and PARQUET_PLACEHOLDER_SUMMARY or PLACEHOLDER_SUMMARY
        -- A function replacement keeps any % in the path literal.
        summary_source = template:gsub("{p}", placeholder):gsub("{source}", function()
            return source
        end)
    end
    return generate_summarized_query(summary_source, limit, offset)
end

local function render_output(stdout, job)
    local cleaned = stdout:gsub("\r", "")
    ya.preview_widget(job, {
        ui.Text.parse(cleaned):area(job.area),
    })
end

local function output_is_valid(output, mode, job)
    if output then
        if output.stderr and output.stderr ~= "" then
            ya.err("DuckDB returned an error or:\n" .. output.stderr)
            return false
        elseif not output.stdout or output.stdout == "" then
            ya.err(string.format("Peek - No stdout/stderr from %s cache for %s", mode, job.file.url))
            return false
        else
            return true
        end
    else
        ya.err("Duckdb failed to return output")
        return false
    end
end

local function prepare_peek_context(job)
    local file_url = job.file.url
    local re_peek = get_opts("re_peek")
    local mode = get_opts("mode")
    local mode_changed = get_opts("mode_changed")

    -- Handle scroll reset and peek triggering
    if not re_peek then
        local raw_skip = job.skip or 0
        if raw_skip == 0 or mode_changed then
            set_opts("scrolled_columns", 0)
        end
        if mode_changed then
            set_opts("mode_changed", false)
        end
        job.skip = math.max(0, raw_skip - OFFSET_BASE)
    end
    set_opts("re_peek", false)

    local cache_str, cache_url = get_cache_path(job, mode)
    local scrolled_columns = get_opts("scrolled_columns")

    local cache_enabled = get_opts("cache_enabled")
    local use_cache = cache_enabled
        and cache_url
        and fs.cha(cache_url)
        and not is_on_list("preloading", cache_str)
        and not is_on_list("bad_cache", cache_str)

    local target = use_cache and cache_url or file_url
    local file_type = check_file_type(use_cache and cache_url or file_url)
    local area = job.area or { h = 25 }
    -- A negative LIMIT is a DuckDB error, and a failed cached peek marks the cache bad.
    local limit = math.max(1, area.h - 7)
    local offset = job.skip

    return {
        file_url = file_url,
        mode = mode,
        file_type = file_type,
        cache_str = cache_str,
        cache_url = cache_url,
        scrolled_columns = scrolled_columns,
        use_cache = use_cache,
        target = target,
        limit = limit,
        offset = offset,
    }
end

local function remove_file(cache_url)
    if fs.cha(cache_url) then
        local ok, err = fs.remove("file", cache_url)
        if not ok then
            ya.err(
                string.format("[duckdb] failed to remove partial cache at %s: %s", tostring(cache_url), tostring(err))
            )
        end
    end
end

local function finish_preload(success, cache_str)
    if not success then
        add_to_list("bad_cache", cache_str)
    end
    remove_from_list("preloading", cache_str)
    add_to_list("completed", cache_str)
    return success
end

local function create_cache(job, mode, file_type, limit)
    if not get_opts("cache_enabled") then
        return true
    end

    local cache_str, cache_url = get_cache_path(job, mode)
    if not cache_url or fs.cha(cache_url) or is_on_list("bad_cache", cache_str) then
        return true
    end

    add_to_list("preloading", cache_str)

    local target = tostring(cache_url)
    local escaped_target = target:gsub("'", "''")

    local base_query = generate_preload_query(job, mode, file_type, limit)
    local query = string.format("COPY (%s) TO '%s' (FORMAT 'parquet');", base_query, escaped_target)
    local output = run_query(job, query, nil, file_type)
    log_query_output("[duckdb] create_cache", output)

    if not output or (output.stderr and output.stderr ~= "") then
        ya.err(
            output
            and string.format(
                "[duckdb] error creating %s cache for %s: %s",
                mode,
                tostring(job.file.url),
                output.stderr
            )
            or string.format(
                "[duckdb] no output returned while creating %s cache for %s",
                mode,
                tostring(job.file.url)
            )
        )
        remove_file(cache_url)
        return finish_preload(false, cache_str)
    end

    return finish_preload(true, cache_str)
end

local function is_plain_text(job, file_type)
    file_type = file_type or check_file_type(job.file.url)
    if file_type ~= "text" then
        return false
    end

    -- Remember both answers, so a tabular .txt file is not sniffed again on every scroll.
    local file_hash, _ = get_cache_path(job, "standard", "text")
    local known = update_state("get", "is_plain_text", file_hash)
    if known ~= nil then
        return known
    end

    local escaped_url = tostring(job.file.url):gsub("'", "''")
    local query = {
        ".mode csv",
        ".headers off",
        string.format("select count(column_name) from (describe from read_csv('%s'));", escaped_url),
    }
    local output = run_query(job, query, nil, file_type)
    local result = output ~= nil and output.stdout == "1\r\n"
    update_state("set", "is_plain_text", file_hash, result)
    return result
end

-- Preload summarized and standard preview caches
function M:preload(job)
    if not job or not job.file or not job.file.url then
        return true
    end

    if is_plain_text(job, nil) then
        return true
    end

    if not get_opts("cache_enabled") then
        return true
    end

    local limit = get_opts("limit")
    local file_type = check_file_type(job.file.url)
    if not file_type then
        return true
    end
    local all_done = true

    if file_type == "duckdb" then
        return true
    end

    for _, mode in ipairs({ "standard", "summarized" }) do
        local success = create_cache(job, mode, file_type, limit)
        if not success then
            all_done = false
        end
    end

    return all_done
end

-- Peek with mode toggle if scrolling at top
function M:peek(job)
    local args = prepare_peek_context(job)
    if not args.file_type then
        return require("code"):peek(job)
    end
    if is_plain_text(job, args.file_type) then
        return require("code"):peek(job)
    end

    local query = generate_peek_query(args.target, job, args.limit, args.offset, args.file_type, args.cache_str)
    ya.dbg("query: " .. tostring(query))
    local output = run_query(job, query, args.target, args.file_type)
    log_query_output("[duckdb] peek", output)
    if not output_is_valid(output, args.mode, job) then
        if args.target == args.cache_url and args.scrolled_columns == 0 then
            add_to_list("bad_cache", args.cache_str)
            remove_file(args.cache_url)
            -- job.skip already has OFFSET_BASE removed; do not remove it twice.
            set_opts("re_peek", true)
            return require("duckdb"):peek(job)
        end
        return require("code"):peek(job)
    end

    local stdout = output.stdout
    local table_text, max_scroll = stdout:match("^(.*)max_scroll=(%-?%d+)%s*$")
    if table_text then
        stdout = table_text
        max_scroll = math.max(0, tonumber(max_scroll))
        if (get_opts("scrolled_columns") or 0) > max_scroll then
            set_opts("scrolled_columns", max_scroll)
        end
    end

    -- Only wait for a cache that preload can still build: DuckDB databases are never cached,
    -- and preload skips a cache already marked bad.
    local cache_pending = args.cache_url and args.file_type ~= "duckdb" and not is_on_list("bad_cache", args.cache_str)
    if
        args.target == args.file_url
        and args.mode == "summarized"
        and get_opts("cache_enabled")
        and not args.use_cache
        and cache_pending
    then
        render_output(stdout, job)
        -- shortcut: gives up when preload has not started after 30 s (no preloader rule matches, or
        -- Yazi already preloaded the file). A preload queued longer than that needs a re-hover.
        local waited = 0
        while not is_on_list("completed", args.cache_str) do
            if waited >= 30 and not is_on_list("preloading", args.cache_str) then
                return
            end
            ya.sleep(0.2)
            waited = waited + 0.2
        end
        remove_from_list("completed", args.cache_str)
        set_opts("re_peek", true)
        return require("duckdb"):peek(job)
    end

    render_output(stdout, job)
end

-- Seek, also triggers mode change if skip negative.
function M:seek(job)
    local current_skip = math.max(0, cx.active.preview.skip - OFFSET_BASE)
    local units = job.units or 0
    local new_skip = current_skip + units

    if new_skip < 0 then
        toggle_preview_mode(job.file.url)
    else
        ya.emit("peek", { new_skip + OFFSET_BASE, only_if = job.file.url })
    end
end

return M
