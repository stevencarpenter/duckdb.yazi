-- Runs main.lua's peek, preload and entry against the real DuckDB CLI, with stand-ins for the Yazi API.
-- Usage: lua tests/peek_test.lua (from any directory, with duckdb on PATH)

-- The repository root is the parent of this script's directory.
local ROOT = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/.."
local TMP = assert(io.popen("mktemp -d"):read("l"), "mktemp -d failed")
local FIXTURE = ROOT .. "/tests/fixtures/sample.csv"

local function sh_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Removes TMP when the Lua state closes: at the end, on os.exit(_, true), and after an uncaught error.
local _cleanup = setmetatable({}, {
    __gc = function()
        os.execute("rm -rf " .. sh_quote(TMP))
    end,
})

local function duckdb(sql, db)
    local target = db and sh_quote(db) or ""
    assert(os.execute("DUCKDB_AGENT_MODE=0 duckdb -init /dev/null " .. target .. " -c " .. sh_quote(sql) .. " >/dev/null"))
end

local function write(path, text)
    local f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
end

-- Yazi stand-ins -------------------------------------------------------------

local state, widgets, events = {}, {}, {}
local runs, sleeps = 0, 0
local on_sleep -- optional function(sleeps), runs at each ya.sleep call

local UrlMT = {}
UrlMT.__index = UrlMT
UrlMT.__tostring = function(u)
    return u.path
end
UrlMT.__eq = function(a, b)
    return a.path == b.path
end
function Url(p)
    p = tostring(p)
    local name = p:match("([^/]+)$")
    return setmetatable({ path = p, name = name, stem = name:match("^(.*)%.[^.]+$") or name }, UrlMT)
end

ya = {
    sync = function(fn)
        return function(...)
            return fn(state, ...)
        end
    end,
    err = function(...) end,
    dbg = function(...) end,
    target_os = function()
        return "linux"
    end,
    file_cache = function(job)
        return Url(TMP .. "/cache-" .. job.file.url.name .. "-" .. job.skip)
    end,
    preview_widget = function(_, w)
        table.insert(widgets, w[1].text)
    end,
    emit = function(cmd, a)
        table.insert(events, { cmd = cmd, args = a })
    end,
    sleep = function(_)
        sleeps = sleeps + 1
        assert(sleeps < 1000, "peek waited without limit")
        if on_sleep then
            on_sleep(sleeps)
        end
    end,
}
ui = {
    Text = {
        parse = function(t)
            return {
                text = t,
                area = function(self, _)
                    return self
                end,
            }
        end,
    },
    hide = function()
        table.insert(events, { cmd = "hide" })
        return {
            drop = function()
                table.insert(events, { cmd = "drop" })
            end,
        }
    end,
}
fs = {
    cha = function(u)
        local f = io.open(tostring(u))
        if f then
            f:close()
            return {}
        end
    end,
    remove = function(_, u)
        return os.remove(tostring(u))
    end,
}
cx = { active = { current = {}, preview = { skip = 0 } } }

local Cmd = {}
Cmd.__index = Cmd
Command = setmetatable({ PIPED = 1, INHERIT = 2 }, {
    __call = function(_, program)
        return setmetatable({ program = program, args = {} }, Cmd)
    end,
})
function Cmd:env()
    return self
end
function Cmd:arg(a)
    table.insert(self.args, a)
    return self
end
function Cmd:stdin(mode)
    self.stdin_mode = mode
    return self
end
function Cmd:stdout(mode)
    self.stdout_mode = mode
    return self
end
function Cmd:stderr(mode)
    self.stderr_mode = mode
    return self
end
function Cmd:spawn()
    table.insert(events, { cmd = "spawn", args = self.args, cmd_object = self })
    return self
end
function Cmd:wait() end
function Cmd:wait_with_output()
    runs = runs + 1
    local parts = { "DUCKDB_AGENT_MODE=0", self.program }
    for _, a in ipairs(self.args) do
        table.insert(parts, sh_quote(a))
    end
    local err_path = TMP .. "/stderr"
    local h = io.popen(table.concat(parts, " ") .. " 2>" .. err_path)
    local out = h:read("a")
    local ok = h:close()
    local f = io.open(err_path)
    local err = f:read("a")
    f:close()
    return { stdout = out, stderr = err, status = { success = ok == true } }
end

local code_peeks = 0
package.loaded.code = {
    peek = function(_, _)
        code_peeks = code_peeks + 1
    end,
}

local M = dofile(ROOT .. "/main.lua")
package.loaded.duckdb = M

-- Helpers ---------------------------------------------------------------------

local function job(path, skip, h)
    return { file = { url = Url(path) }, skip = skip or 50, area = { w = 100, h = h or 30 } }
end

local function reset(opts)
    for k in pairs(state) do
        state[k] = nil
    end
    widgets, events, runs, sleeps, code_peeks, on_sleep = {}, {}, 0, 0, 0, nil
    os.execute("rm -f " .. sh_quote(TMP) .. "/cache-*")
    M:setup(opts)
end

local function cache_files(pattern)
    local files = {}
    for path in io.popen("ls " .. sh_quote(TMP) .. "/" .. pattern .. " 2>/dev/null"):lines() do
        table.insert(files, path)
    end
    return files
end

local function last_widget()
    -- Strip ANSI colors so assertions can match plain text.
    return (widgets[#widgets] or ""):gsub("\27%[[%d;]*m", "")
end

local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    print((ok and "ok   " or "FAIL ") .. name .. (ok and "" or ("\n     " .. tostring(err))))
    if not ok then
        failures = failures + 1
    end
end

-- Fixtures --------------------------------------------------------------------

local DB = TMP .. "/t.duckdb"
duckdb("create table a(x int primary key, y text); create schema s; create table s.a(z int);", DB)
local TABLE_TXT = TMP .. "/table.txt"
write(TABLE_TXT, "id,name,value\n1,alice,10\n2,bob,20\n")
local PLAIN_TXT = TMP .. "/notes.txt"
write(PLAIN_TXT, "hello world\nthis is text\n")
local EMPTY_DB = TMP .. "/empty.duckdb"
duckdb("select 1;", EMPTY_DB)
-- Name of the summarized cache that main.lua's get_cache_path builds with the ya.file_cache stand-in.
local SUMMARIZED_CACHE = "cache-sample.csv-1000004_summarized.parquet"

-- Tests -------------------------------------------------------------------------

test("standard peek shows rows and hides the max_scroll line", function()
    reset({ mode = "standard", cache_enabled = false })
    M:peek(job(FIXTURE))
    local w = last_widget()
    assert(w:find("alice") and w:find("carol"), w)
    assert(not w:find("max_scroll"), w)
end)

test("standard column scroll stops at the last column", function()
    reset({ mode = "standard", cache_enabled = false })
    state.opts.scrolled_columns = 99
    M:peek(job(FIXTURE, 51))
    assert(state.opts.scrolled_columns == 2, state.opts.scrolled_columns)
end)

test("summarized mode without cache shows real statistics", function()
    reset({ mode = "summarized", cache_enabled = false })
    M:peek(job(FIXTURE))
    local w = last_widget()
    assert(w:find("alice") and not w:find("⏱"), w)
end)

test("summarized column scroll stops at the last field", function()
    reset({ mode = "summarized", cache_enabled = false })
    state.opts.scrolled_columns = 99
    M:peek(job(FIXTURE, 51))
    assert(state.opts.scrolled_columns == 10, state.opts.scrolled_columns)
    assert(last_widget():find("q75"))
end)

test("duckdb file lists schema-qualified tables and clamps scroll", function()
    reset({ mode = "summarized" })
    M:peek(job(DB))
    assert(last_widget():find("s%.a"), last_widget())
    state.opts.scrolled_columns = 6
    M:peek(job(DB))
    -- 4 metadata fields + widest table (2 columns) - 1
    assert(state.opts.scrolled_columns == 5, state.opts.scrolled_columns)
    -- One step past the end must still show the last column, not an empty table.
    local w = last_widget()
    assert(w:find("│ y") and not w:find("0 rows"), w)
end)

test("an empty duckdb file shows no stray NULL line", function()
    reset({ mode = "summarized" })
    M:peek(job(EMPTY_DB))
    local w = last_widget()
    assert(w:find("table_name") and not w:find("NULL"), w)
end)

test("preload builds caches that both modes read", function()
    reset({ mode = "summarized" })
    assert(M:preload(job(FIXTURE)) == true)
    M:peek(job(FIXTURE))
    assert(last_widget():find("alice") and sleeps == 0, last_widget())
    state.opts.mode = "standard"
    M:peek(job(FIXTURE))
    assert(last_widget():find("carol"), last_widget())
end)

test("summarized peek stops waiting when no preload comes", function()
    reset({ mode = "summarized" })
    M:peek(job(FIXTURE))
    assert(last_widget():find("⏱"), last_widget())
    assert(sleeps > 100 and sleeps < 200, sleeps)
end)

test("a bad cache keeps the row offset", function()
    reset({ mode = "standard" })
    M:preload(job(FIXTURE))
    local caches = cache_files("cache-*_standard.parquet")
    assert(#caches == 1, "expected one standard cache, found " .. #caches)
    write(caches[1], "not parquet")
    local j = job(FIXTURE, 52)
    M:peek(j)
    assert(next(state.bad_cache or {}) ~= nil, "cache not marked bad")
    assert(#cache_files("cache-*_standard.parquet") == 0, "bad cache not removed")
    assert(j.skip == 2, j.skip)
    assert(last_widget():find("carol") and not last_widget():find("alice"), last_widget())
end)

test("a short preview pane does not mark the cache bad", function()
    reset({ mode = "standard" })
    M:preload(job(FIXTURE))
    assert(#cache_files("cache-*_standard.parquet") == 1, "preload built no standard cache")
    M:peek(job(FIXTURE, 50, 5))
    assert(next(state.bad_cache or {}) == nil, "cache marked bad")
    assert(#cache_files("cache-*_standard.parquet") == 1, "cache removed")
end)

test("summarized peek re-peeks the cache when preload finishes", function()
    reset({ mode = "summarized" })
    local j = job(FIXTURE, 52) -- row offset 2: only the "value" column row
    on_sleep = function(n)
        if n == 1 then
            M:preload(job(FIXTURE))
        end
    end
    M:peek(j)
    assert(sleeps == 1, sleeps)
    assert(j.skip == 2, "row offset lost: " .. j.skip)
    local w = last_widget()
    assert(w:find("value") and not w:find("alice") and not w:find("⏱"), w)
    assert((state.completed or {})[SUMMARIZED_CACHE] == nil, "completed entry not consumed")
end)

test("summarized peek keeps waiting while preload runs past 30 s", function()
    reset({ mode = "summarized" })
    on_sleep = function(n)
        if n == 1 then
            -- Preload has started: its cache is listed as preloading.
            state.preloading = { [SUMMARIZED_CACHE] = true }
        elseif n == 200 then
            state.preloading = nil
            M:preload(job(FIXTURE))
        end
    end
    M:peek(job(FIXTURE))
    assert(sleeps == 200, sleeps)
    assert(not last_widget():find("⏱"), last_widget())
end)

test("column scroll keys keep the row offset and skip a fresh-hover reset", function()
    reset({ mode = "standard" })
    cx.active.preview.skip = 0 -- fresh hover
    M:entry({ args = { "+1" } })
    assert(state.opts.scrolled_columns == 1, state.opts.scrolled_columns)
    local peek = events[#events]
    assert(peek.cmd == "peek" and peek.args[1] == 50 and peek.args.force, "peek must use skip 50 with force")
    cx.active.preview.skip = 53
    M:entry({ args = { "-1" } })
    assert(state.opts.scrolled_columns == 0, state.opts.scrolled_columns)
    assert(events[#events].args[1] == 53, events[#events].args[1])
    M:entry({ args = { "-1" } })
    assert(state.opts.scrolled_columns == 0, "scroll went below 0")
end)

test("a tabular .txt file is sniffed once", function()
    reset({ mode = "standard", cache_enabled = false })
    M:peek(job(TABLE_TXT))
    runs = 0
    M:peek(job(TABLE_TXT))
    assert(runs == 1, runs)
    assert(last_widget():find("alice"), last_widget())
end)

test("plain text falls back to the code previewer", function()
    reset({ mode = "standard", cache_enabled = false })
    M:peek(job(PLAIN_TXT))
    assert(code_peeks == 1 and #widgets == 0)
end)

test("a failed plain-text check is retried", function()
    reset({ mode = "standard", cache_enabled = false })
    local real = Cmd.wait_with_output
    Cmd.wait_with_output = function()
        return nil
    end
    local ok, err = pcall(M.peek, M, job(PLAIN_TXT))
    Cmd.wait_with_output = real
    assert(ok, err)
    M:peek(job(PLAIN_TXT))
    assert(code_peeks >= 1 and #widgets == 0, "plain text rendered as a table after one failed check")
end)

test("a .txt file inside the Yazi cache directory does not crash", function()
    reset({ mode = "standard", cache_enabled = false })
    local real = ya.file_cache
    ya.file_cache = function()
        return nil
    end
    local ok, err = pcall(M.peek, M, job(TABLE_TXT))
    ya.file_cache = real
    assert(ok, err)
end)

test("open hides Yazi while DuckDB runs", function()
    reset({})
    cx.active.current.hovered = { url = FIXTURE }
    M:entry({ args = { "-open" } })
    local names = {}
    for _, e in ipairs(events) do
        table.insert(names, e.cmd)
    end
    assert(table.concat(names, ",") == "hide,spawn,drop", table.concat(names, ","))
    -- "-c" would run the query and exit; "-cmd" runs it and then reads stdin.
    local args = table.concat(events[2].args, " ")
    assert(args:find('^%-cmd CREATE TABLE "sample" AS FROM'), args)
    -- DuckDB needs the terminal for all three streams, or it exits at once.
    local cmd = events[2].cmd_object
    assert(cmd.stdin_mode == Command.INHERIT, "stdin not inherited")
    assert(cmd.stdout_mode == Command.INHERIT and cmd.stderr_mode == Command.INHERIT, "output not inherited")
end)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1, true)
end
print("All peek tests passed")
