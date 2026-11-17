-- Shared opaque-box E2E test infrastructure for AzureVM
-- Portable across PUC Lua 5.1 and LuaJIT 2.1.
-- Always invokes `lua5.1 azure_obf.lua` for compilation.

local M = {}

M.unpack = unpack or table.unpack
M.loadstring = loadstring or load
M.is_luajit = (type(jit) == "table")
M.runtime_name = M.is_luajit and "luajit" or "lua5.1"

function M.pack(...)
    return { n = select("#", ...), ... }
end

function M.shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M.exec_cmd(cmd)
    local r1, r2, r3 = os.execute(cmd)
    if type(r1) == "number" then
        local code = r1
        if code >= 256 then
            code = math.floor(code / 256)
        end
        return (r1 == 0), code
    elseif type(r1) == "boolean" then
        return r1, 0
    elseif r1 == nil then
        if type(r3) == "number" then
            return false, r3
        end
        return false, 1
    end
    return false, 1
end

local function read_all(path)
    local f, err = io.open(path, "rb")
    if not f then
        return nil, err
    end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_all(path, content)
    local f, err = io.open(path, "wb")
    if not f then
        return false, err
    end
    f:write(content)
    f:close()
    return true
end

M.read_all = read_all
M.write_all = write_all

-- Resolve repository root cleanly from e2e_common.lua path
local function resolve_repo_root()
    local src = debug.getinfo(1, "S").source
    local file_path = (src:sub(1, 1) == "@") and src:sub(2) or src
    local lib_dir = file_path:match("^(.*)/[^/]+$") or "."
    local candidates = {
        lib_dir .. "/../../..",
        ".",
        "../..",
        "../../..",
    }
    for _, cand in ipairs(candidates) do
        local p = io.popen("cd " .. M.shell_quote(cand) .. " 2>/dev/null && pwd")
        if p then
            local abs = p:read("*l")
            p:close()
            if abs and abs ~= "" then
                local check = io.open(abs .. "/azure_obf.lua", "rb")
                if check then
                    check:close()
                    return abs
                end
            end
        end
    end
    error("e2e_common: could not locate AzureVM repository root (azure_obf.lua)")
end

M.repo_root = resolve_repo_root()

-- Resolve timeout prefix if GNU timeout is installed
local function detect_timeout_cmd()
    local ok = M.exec_cmd("command -v timeout >/dev/null 2>&1")
    if ok then
        local t = os.getenv("VM_TEST_TIMEOUT") or "30s"
        return "timeout " .. M.shell_quote(t) .. " "
    end
    return ""
end

M._timeout_prefix = detect_timeout_cmd()

-- Resolve cache / compile directory
local function resolve_compile_dir()
    if type(arg) == "table" then
        for i = 1, #arg do
            if arg[i] == "--compile-dir" and arg[i + 1] then
                return arg[i + 1], false
            end
            local inline = arg[i]:match("^%-%-compile%-dir=(.+)$")
            if inline then
                return inline, false
            end
        end
    end
    local env_dir = os.getenv("E2E_COMPILE_DIR")
    if env_dir and env_dir ~= "" then
        return env_dir, false
    end
    local p = io.popen("mktemp -d /tmp/azurevm_e2e_XXXXXX")
    local dir = p and p:read("*l") or nil
    if p then p:close() end
    if not dir or dir == "" then
        dir = "/tmp/azurevm_e2e_" .. tostring(os.time())
        M.exec_cmd("mkdir -p " .. M.shell_quote(dir))
    end
    return dir, true
end

M._compile_dir, M._owns_compile_dir = resolve_compile_dir()
M.exec_cmd("mkdir -p " .. M.shell_quote(M._compile_dir))
M._mem_cache = {}
M._seq = 0

function M.cleanup()
    if M._owns_compile_dir and M._compile_dir and M._compile_dir ~= "" then
        M.exec_cmd("rm -rf " .. M.shell_quote(M._compile_dir))
        M._owns_compile_dir = false
    end
end

-- Pure-Lua dual 32-bit rolling hash strictly within 53-bit IEEE-754 integer precision
-- Max product: 4294967296 * 65521 = 2.81e14 << 9.007e15 (2^53)
local function hash_key(s)
    local h1 = 2166136261
    local h2 = 33554467
    local mod = 4294967296
    for i = 1, #s do
        local b = string.byte(s, i)
        h1 = (h1 * 131 + b + i) % mod
        h2 = (h2 * 65521 + b * 17 + (h1 % 256) + i) % mod
    end
    return string.format("%08x_%08x_%d", h1, h2, #s)
end

function M.build_cache_key(source, opts)
    opts = opts or {}
    local preset = tostring(opts.preset or "Luraph"):gsub("[^%w_]", "_")
    local seed = tostring(opts.seed or 12345):gsub("[^%w_]", "_")
    local compact = opts.compact and "1" or "0"
    local retry = tostring(opts.retry_count or "def"):gsub("[^%w_]", "_")
    local parts = {
        tostring(opts.preset or "Luraph"),
        tostring(opts.seed or 12345),
        compact,
        tostring(opts.header or ""),
        tostring(opts.retry_count or ""),
        source,
    }
    return string.format("%s_s%s_c%s_r%s_%s", preset, seed, compact, retry, hash_key(table.concat(parts, "\0")))
end

-- Opaque-box raw CLI compilation (no caching; always cleans temp dir)
function M.compile_cli_raw(source, opts)
    opts = opts or {}
    local p = io.popen("mktemp -d /tmp/azurevm_cli_XXXXXX")
    local tmp = p and p:read("*l") or nil
    if p then p:close() end
    if not tmp or tmp == "" then
        tmp = M._compile_dir .. "/raw_" .. tostring(M._seq)
        M._seq = M._seq + 1
        M.exec_cmd("mkdir -p " .. M.shell_quote(tmp))
    end

    local ext = opts.ext or ".lua"
    local in_path = tmp .. "/input" .. ext
    local out_path = opts.out_path or (tmp .. "/output.lua")
    local log_path = tmp .. "/cli.log"
    assert(write_all(in_path, source))

    local args = {
        "lua5.1",
        M.shell_quote(M.repo_root .. "/azure_obf.lua"),
    }
    if not opts.omit_input then
        args[#args + 1] = M.shell_quote(opts.input_override or in_path)
    end
    if opts.preset then
        args[#args + 1] = "--preset"
        args[#args + 1] = M.shell_quote(opts.preset)
    end
    if opts.seed ~= nil then
        args[#args + 1] = "--seed"
        args[#args + 1] = M.shell_quote(tostring(opts.seed))
    end
    if opts.compact then
        args[#args + 1] = "--compact"
    end
    if opts.header ~= nil then
        args[#args + 1] = "--header"
        args[#args + 1] = M.shell_quote(tostring(opts.header))
    end
    if opts.retry_count ~= nil then
        if opts.retry_equals then
            args[#args + 1] = "--retry-count=" .. M.shell_quote(tostring(opts.retry_count))
        else
            args[#args + 1] = "--retry-count"
            args[#args + 1] = M.shell_quote(tostring(opts.retry_count))
        end
    end
    if opts.extra_args then
        for _, ea in ipairs(opts.extra_args) do
            args[#args + 1] = ea
        end
    end
    if not opts.omit_out then
        args[#args + 1] = "-o"
        args[#args + 1] = M.shell_quote(out_path)
    end

    local cmd = M._timeout_prefix .. table.concat(args, " ") .. " >" .. M.shell_quote(log_path) .. " 2>&1"
    local ok, code = M.exec_cmd(cmd)
    local log = read_all(log_path) or ""

    local effective_out = out_path
    if opts.omit_out then
        if ext == ".lua" then
            effective_out = in_path:gsub("%.lua$", "") .. "_protected.lua"
        else
            effective_out = in_path .. "_protected.lua"
        end
    end
    local output = read_all(effective_out)

    M.exec_cmd("rm -rf " .. M.shell_quote(tmp))
    return {
        ok = ok and output ~= nil,
        exit_code = code,
        log = log,
        output = output,
    }
end

-- Cached opaque-box CLI compiler (safe across lua5.1 -> luajit when E2E_COMPILE_DIR is shared)
function M.compile(source, opts)
    opts = opts or {}
    local key = M.build_cache_key(source, opts)
    if not opts.no_cache and M._mem_cache[key] then
        return M._mem_cache[key]
    end

    local cached_out = M._compile_dir .. "/" .. key .. ".lua"
    if not opts.no_cache then
        local existing = read_all(cached_out)
        if existing and #existing > 0 then
            M._mem_cache[key] = existing
            return existing
        end
    end

    M._seq = M._seq + 1
    local ext = opts.ext or ".lua"
    local in_path = M._compile_dir .. "/" .. key .. "_" .. M._seq .. ext
    local tmp_out = M._compile_dir .. "/" .. key .. "_" .. M._seq .. ".out.lua"
    local log_path = M._compile_dir .. "/" .. key .. "_" .. M._seq .. ".log"
    assert(write_all(in_path, source))

    local args = {
        "lua5.1",
        M.shell_quote(M.repo_root .. "/azure_obf.lua"),
        M.shell_quote(in_path),
        "--preset",
        M.shell_quote(opts.preset or "AzureGodUltra"),
        "--seed",
        M.shell_quote(tostring(opts.seed or 12345)),
    }
    if opts.compact then
        args[#args + 1] = "--compact"
    end
    if opts.header ~= nil then
        args[#args + 1] = "--header"
        args[#args + 1] = M.shell_quote(tostring(opts.header))
    end
    if opts.retry_count ~= nil then
        args[#args + 1] = "--retry-count"
        args[#args + 1] = M.shell_quote(tostring(opts.retry_count))
    end
    args[#args + 1] = "-o"
    args[#args + 1] = M.shell_quote(tmp_out)

    local cmd = M._timeout_prefix .. table.concat(args, " ") .. " >" .. M.shell_quote(log_path) .. " 2>&1"
    local ok, code = M.exec_cmd(cmd)
    local out = read_all(tmp_out)
    local log = read_all(log_path) or ""

    os.remove(in_path)
    os.remove(log_path)

    if not ok or not out or #out == 0 then
        os.remove(tmp_out)
        M.cleanup()
        error(string.format("CLI compile failed (preset=%s, seed=%s, exit=%s):\n%s",
            tostring(opts.preset), tostring(opts.seed), tostring(code), log))
    end

    if not opts.no_cache then
        os.rename(tmp_out, cached_out)
        M._mem_cache[key] = out
    else
        os.remove(tmp_out)
    end
    return out
end

function M.validate_compact(code)
    if type(code) ~= "string" or #code == 0 then
        return false, "compact output is empty"
    end
    if code:find("\n", 1, true) then
        return false, "compact output contains LF (\\n)"
    end
    if code:find("\r", 1, true) then
        return false, "compact output contains CR (\\r)"
    end
    return true
end

function M.make_clean_env(overrides)
    local env = {}
    if overrides then
        for k, v in pairs(overrides) do
            env[k] = v
        end
    end
    return setmetatable(env, { __index = _G })
end

function M.make_narrow_sandbox(overrides)
    local narrow_string = {}
    for k, v in pairs(string) do
        narrow_string[k] = v
    end
    narrow_string.dump = false
    local env = {
        string = narrow_string,
        debug = false,
        loadstring = false,
        load = false,
    }
    if overrides then
        for k, v in pairs(overrides) do
            env[k] = v
        end
    end
    return setmetatable(env, { __index = _G })
end

function M.run_code(code, opts)
    opts = opts or {}
    local chunkname = opts.chunkname or "@e2e_target.lua"
    local fn, load_err = M.loadstring(code, chunkname)
    if not fn then
        return { ok = false, load_err = load_err, results = M.pack(load_err) }
    end
    local env = opts.env or M.make_clean_env()
    setfenv(fn, env)
    local args = opts.args or {}
    local res = M.pack(pcall(fn, M.unpack(args, 1, args.n or #args)))
    local ok = res[1]
    local out = { n = res.n - 1 }
    for i = 2, res.n do
        out[i - 1] = res[i]
    end
    local err
    if not ok then
        err = out[1]
    end
    return {
        ok = ok,
        results = out,
        err = err,
        env = env,
    }
end

function M.deep_eq(a, b, seen)
    if a == b then
        return true
    end
    if a ~= a and b ~= b then
        return true -- NaN == NaN for structural comparison
    end
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return false
    end
    seen = seen or {}
    if seen[a] and seen[a][b] then
        return true
    end
    seen[a] = seen[a] or {}
    seen[a][b] = true
    for k, v in pairs(a) do
        if not M.deep_eq(v, b[k], seen) then
            return false
        end
    end
    for k, v in pairs(b) do
        if not M.deep_eq(a[k], v, seen) then
            return false
        end
    end
    return true
end

function M.tuple_eq(ta, tb)
    if (ta.n or #ta) ~= (tb.n or #tb) then
        return false
    end
    local n = ta.n or #ta
    for i = 1, n do
        if not M.deep_eq(ta[i], tb[i]) then
            return false
        end
    end
    return true
end

function M.assert_compile_and_match(source, opts, expected_fn_or_vals)
    opts = opts or {}
    local out = M.compile(source, opts)
    if opts.compact then
        local vok, verr = M.validate_compact(out)
        assert(vok, verr)
    end
    local run = M.run_code(out, {
        chunkname = opts.chunkname,
        env = opts.env,
        args = opts.args,
    })
    assert(run.ok, "VM execution failed: " .. tostring(run.err))
    if type(expected_fn_or_vals) == "function" then
        expected_fn_or_vals(run.results, out, run)
    elseif type(expected_fn_or_vals) == "table" then
        assert(M.tuple_eq(run.results, expected_fn_or_vals),
            string.format("Result mismatch: got n=%d (%s), expected n=%d (%s)",
                run.results.n, tostring(run.results[1]),
                expected_fn_or_vals.n or #expected_fn_or_vals, tostring(expected_fn_or_vals[1])))
    end
    return out, run
end

-- Execute clean Lua 5.1 source directly as oracle reference (never used for Luau syntax)
function M.eval_lua_source(source, args, env)
    local fn = assert(M.loadstring(source, "@e2e_oracle.lua"))
    setfenv(fn, env or M.make_clean_env())
    args = args or {}
    local res = M.pack(pcall(fn, M.unpack(args, 1, args.n or #args)))
    assert(res[1], "Oracle failed: " .. tostring(res[2]))
    local out = { n = res.n - 1 }
    for i = 2, res.n do
        out[i - 1] = res[i]
    end
    return out
end

function M.assert_parity(source, opts)
    opts = opts or {}
    local expected = M.eval_lua_source(source, opts.args, opts.oracle_env)
    return M.assert_compile_and_match(source, opts, expected)
end

-- Structured test suite reporter
function M.new_suite(name)
    local suite = {
        name = name,
        passed = 0,
        failed = 0,
        skipped = 0,
        failures = {},
    }

    function suite:test(id, area, fn)
        local ok, err = pcall(fn)
        if ok then
            self.passed = self.passed + 1
            print(string.format("[PASS] [%s] %s (%s)", M.runtime_name, id, area))
        else
            self.failed = self.failed + 1
            local msg = tostring(err)
            self.failures[#self.failures + 1] = { id = id, area = area, err = msg }
            print(string.format("[FAIL] [%s] %s (%s): %s", M.runtime_name, id, area, msg))
        end
    end

    function suite:skip(id, area, reason)
        self.skipped = self.skipped + 1
        print(string.format("[SKIP] [%s] %s (%s): %s", M.runtime_name, id, area, tostring(reason)))
    end

    function suite:summary()
        M.cleanup()
        print(string.format("SUMMARY [%s] [%s]: passed=%d failed=%d skipped=%d total=%d",
            self.name, M.runtime_name, self.passed, self.failed, self.skipped,
            self.passed + self.failed + self.skipped))
        return (self.failed == 0) and 0 or 1
    end

    function suite:finish()
        os.exit(self:summary())
    end

    return suite
end

return M
