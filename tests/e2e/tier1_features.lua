-- Tier 1: Isolated Feature Coverage (>= 40 cases, >= 5 per FA1..FA8)
-- Tests AzureGodUltra, Hardened, and Luraph15_2 (--compact and default)
-- across lua5.1 and luajit with 100% clean-environment parity.

local script_path = debug.getinfo(1, "S").source:sub(2)
local e2e_dir = script_path:match("^(.*)/[^/]+$") or "."
package.path = e2e_dir .. "/lib/?.lua;" .. package.path

local E2E = require("e2e_common")
local suite = E2E.new_suite("Tier1_Features")

-- ============================================================================
-- FA1: Core VM Execution & Control Flow (6 tests)
-- ============================================================================

suite:test("T1_FA1_closures_upvalues_mutation", "FA1", function()
    local src = [[
        local function make_counter(start, step)
            local acc = start
            local function inc(mult)
                acc = acc + step * (mult or 1)
                return acc
            end
            local function reset(v)
                local prev = acc
                acc = v or start
                return prev
            end
            return inc, reset
        end
        local inc, reset = make_counter(10, 3)
        local a = inc()
        local b = inc(4)
        local p = reset(100)
        local c = inc(2)
        return a, b, p, c
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 101 })
end)

suite:test("T1_FA1_varargs_select_and_nil_holes", "FA1", function()
    local src = [[
        local function collect(...)
            local n = select('#', ...)
            local a, b, c, d, e = ...
            local tail_n = select('#', select(3, ...))
            return n, a, b == nil, c, d, e == nil, tail_n
        end
        return collect("x", nil, false, 42, nil)
    ]]
    E2E.assert_parity(src, { preset = "Luraph15_2", compact = true, seed = 102 })
end)

suite:test("T1_FA1_multi_return_forwarding", "FA1", function()
    local src = [[
        local function inner()
            return 11, nil, false, "ok", 99
        end
        local function middle()
            return "head", inner()
        end
        local function outer()
            local h, a, b, c, d, e = middle()
            local n = select('#', middle())
            return n, h, a, b == nil, c, d, e
        end
        return outer()
    ]]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 103 })
end)

suite:test("T1_FA1_close_early_break_return", "FA1", function()
    local src = [[
        local fns = {}
        for i = 1, 5 do
            local captured = i * 10
            fns[#fns + 1] = function(d) return captured + d end
            if i == 3 then
                break
            end
        end
        local function early_ret(limit)
            local out = {}
            local k = 0
            while k < limit do
                k = k + 1
                local local_k = k * 100
                out[#out + 1] = function() return local_k end
                if k == 2 then
                    return out
                end
            end
            return out
        end
        local r = early_ret(5)
        return #fns, fns[1](1), fns[3](2), #r, r[1](), r[2]()
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 104 })
end)

suite:test("T1_FA1_setlist_over_50", "FA1", function()
    local parts = { "local t = {" }
    for i = 1, 75 do
        parts[#parts + 1] = tostring(i * 3) .. ","
    end
    parts[#parts + 1] = "}; local s = 0; for i = 1, #t do s = s + t[i] end; return #t, t[1], t[50], t[51], t[75], s"
    local src = table.concat(parts, " ")
    E2E.assert_parity(src, { preset = "Luraph15_2", compact = false, seed = 105 })
end)

suite:test("T1_FA1_tailcall_and_numeric_for", "FA1", function()
    local src = [[
        local function tsum(n, acc)
            if n <= 0 then return acc end
            return tsum(n - 1, acc + n)
        end
        local down = 0
        for i = 10, 2, -2 do
            down = down + i
        end
        local zero_trip = 77
        for i = 5, 1, 1 do
            zero_trip = 0
        end
        local frac = 0
        for x = 0.5, 2.0, 0.5 do
            frac = frac + x
        end
        return tsum(30, 0), down, zero_trip, frac
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 106 })
end)

-- ============================================================================
-- FA2: Constants, Types & Expressions (6 tests)
-- ============================================================================

suite:test("T1_FA2_booleans_and_nil_constants", "FA2", function()
    local src = [[
        local a = false
        local b = true
        local c = nil
        local t = { false, true, nil, false }
        local pick = (a and "bad") or (b and "good")
        return a, b, c == nil, t[1], t[2], t[3] == nil, t[4], pick
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 201 })
end)

suite:test("T1_FA2_numbers_and_float_precision", "FA2", function()
    local src = [[
        local a = 0
        local b = -42
        local c = 1.25e4
        local d = 0.0625
        local e = 1 / 8
        local f = (2 ^ 20) - 17
        return a, b, c, d, e, f, (d + e) == 0.1875
    ]]
    E2E.assert_parity(src, { preset = "Luraph15_2", compact = true, seed = 202 })
end)

suite:test("T1_FA2_strings_escapes_and_long", "FA2", function()
    local src = [===[
        local s1 = "line1\nline2\t\"quoted\"\\end"
        local s2 = 'single\'quote'
        local s3 = [==[long [=[inner]=] text]==]
        return #s1, s1:sub(1, 5), s2, s3
    ]===]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 203 })
end)

suite:test("T1_FA2_mba_and_arithmetic_expressions", "FA2", function()
    local src = [[
        local function mix(x, y)
            local a = (x * 7 + y * 13) - (x - y) * 3
            local b = (a % 97) + math.floor(a / 5)
            local c = (x < y) and (b + 11) or (b - 11)
            return a, b, c
        end
        local a1, b1, c1 = mix(19, 41)
        local a2, b2, c2 = mix(53, 12)
        return a1, b1, c1, a2, b2, c2
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 204 })
end)

suite:test("T1_FA2_mixed_table_keys_and_length", "FA2", function()
    local src = [[
        local t = { 10, 20, 30, alpha = "A", beta = false, [9] = "nine" }
        local sum_arr = 0
        for i, v in ipairs(t) do
            sum_arr = sum_arr + i * v
        end
        local key_count = 0
        for _ in pairs(t) do
            key_count = key_count + 1
        end
        return #t, sum_arr, key_count, t.alpha, t.beta, t[9]
    ]]
    E2E.assert_parity(src, { preset = "Luraph15_2", compact = true, seed = 205 })
end)

suite:test("T1_FA2_logical_short_circuit_eval", "FA2", function()
    local src = [[
        local calls = 0
        local function bump(ret)
            calls = calls + 1
            return ret
        end
        local r1 = false and bump(1)
        local r2 = true or bump(2)
        local r3 = nil or bump(3)
        local r4 = true and bump(false)
        return calls, r1, r2, r3, r4
    ]]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 206 })
end)

-- ============================================================================
-- FA3: Metatables, OOP & Coroutines (5 tests)
-- ============================================================================

suite:test("T1_FA3_metamethods_index_newindex_call", "FA3", function()
    local src = [[
        local log = {}
        local base = { fallback = 42 }
        local fn_base = setmetatable({}, {
            __index = function(_, k) return "fn:" .. tostring(k) end
        })
        local obj = setmetatable({ x = 10 }, {
            __index = base,
            __newindex = function(t, k, v)
                log[#log + 1] = k .. "=" .. tostring(v)
                rawset(t, k, v * 2)
            end,
            __call = function(t, add)
                return t.x + t.fallback + add
            end
        })
        obj.y = 7
        return obj.x, obj.fallback, obj.y, obj(5), fn_base.abc, log[1]
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 301 })
end)

suite:test("T1_FA3_metamethods_arith_cmp_tostring", "FA3", function()
    local src = [[
        local mt
        mt = {
            __add = function(a, b) return setmetatable({ v = a.v + b.v }, mt) end,
            __sub = function(a, b) return setmetatable({ v = a.v - b.v }, mt) end,
            __mul = function(a, b) return setmetatable({ v = a.v * b.v }, mt) end,
            __unm = function(a) return setmetatable({ v = -a.v }, mt) end,
            __concat = function(a, b) return tostring(a) .. "+" .. tostring(b) end,
            __eq = function(a, b) return a.v == b.v end,
            __lt = function(a, b) return a.v < b.v end,
            __le = function(a, b) return a.v <= b.v end,
            __tostring = function(a) return "V(" .. a.v .. ")" end,
        }
        local function V(n) return setmetatable({ v = n }, mt) end
        local r = (V(5) + V(3)) * V(2) - (-V(4))
        return tostring(r), V(3) == V(3), V(2) < V(3), V(3) <= V(3), V(1) .. V(2)
    ]]
    E2E.assert_parity(src, { preset = "Luraph15_2", compact = true, seed = 302 })
end)

suite:test("T1_FA3_coroutine_yield_resume_multi", "FA3", function()
    local src = [[
        local co = coroutine.create(function(a, b)
            local x, y = coroutine.yield(a + b, "step1")
            local z = coroutine.yield(x * y, "step2")
            return z .. ":done"
        end)
        local ok1, r1a, r1b = coroutine.resume(co, 10, 5)
        local ok2, r2a, r2b = coroutine.resume(co, 6, 7)
        local ok3, r3 = coroutine.resume(co, "final")
        return ok1, r1a, r1b, ok2, r2a, r2b, ok3, r3, coroutine.status(co)
    ]]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 303 })
end)

suite:test("T1_FA3_coroutine_wrap_and_status", "FA3", function()
    local src = [[
        local gen = coroutine.wrap(function(limit)
            for i = 1, limit do
                coroutine.yield(i * i)
            end
            return "end"
        end)
        return gen(4), gen(), gen(), gen(), gen()
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 304 })
end)

suite:test("T1_FA3_pcall_xpcall_error_capture", "FA3", function()
    local src = [[
        local ok1, err1 = pcall(function() error("boom1", 0) end)
        local ok2, v1, v2 = pcall(function(a, b) return a + 1, b .. "!" end, 9, "hi")
        local ok3, err3 = xpcall(
            function() error("boom2", 0) end,
            function(e) return "handled:" .. tostring(e) end
        )
        return ok1, err1, ok2, v1, v2, ok3, err3
    ]]
    E2E.assert_parity(src, { preset = "Luraph15_2", compact = true, seed = 305 })
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, retry_count = 0, seed = 305 })
end)

-- ============================================================================
-- FA4: Presets, CLI & Output Format (6 tests)
-- ============================================================================

suite:test("T1_FA4_preset_AzureGodUltra_compact", "FA4", function()
    local src = [[ return 7 * 6, "ultra" ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 401 },
        E2E.pack(42, "ultra"))
end)

suite:test("T1_FA4_preset_Hardened_compact", "FA4", function()
    local src = [[ return 8 * 8, "hardened" ]]
    E2E.assert_compile_and_match(src, { preset = "Hardened", compact = true, seed = 402 },
        E2E.pack(64, "hardened"))
end)

suite:test("T1_FA4_preset_Luraph15_2_compact", "FA4", function()
    local src = [[ return 9 * 9, "v152" ]]
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 403 },
        E2E.pack(81, "v152"))
end)

suite:test("T1_FA4_default_non_compact_and_header", "FA4", function()
    local src = [[ return "hdr_ok" ]]
    for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
        local out = E2E.compile(src, {
            preset = preset,
            compact = false,
            header = "E2E_CUSTOM_HEADER_LINE",
            seed = 404,
        })
        assert(out:find("E2E_CUSTOM_HEADER_LINE", 1, true), "Missing custom header for " .. preset)
        assert(out:find("\n", 1, true), "Non-compact output unexpectedly lacked newline for " .. preset)
        local run = E2E.run_code(out)
        assert(run.ok and run.results[1] == "hdr_ok", "Header build failed execution for " .. preset)
    end
end)

suite:test("T1_FA4_seed_determinism_cli", "FA4", function()
    local src = [[ local x = 123; return x * 2, "seed_ok" ]]
    local a1 = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 77777, no_cache = true })
    local a2 = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 77777, no_cache = true })
    local b1 = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 88888, no_cache = true })
    assert(a1 == a2, "Same seed did not yield deterministic identical output")
    assert(a1 ~= b1, "Different seeds produced identical output")
    local run = E2E.run_code(b1)
    assert(run.ok and run.results[1] == 246 and run.results[2] == "seed_ok")
end)

suite:test("T1_FA4_retry_count_cli_flag", "FA4", function()
    local src = [[ return "retry_flag_ok", 10 ]]
    local out_eq = E2E.compile_cli_raw(src, {
        preset = "Luraph15_2",
        seed = 406,
        compact = true,
        retry_count = 2,
        retry_equals = true,
    })
    assert(out_eq.ok, "Failed --retry-count=2 on Luraph15_2: " .. out_eq.log)
    local run1 = E2E.run_code(out_eq.output)
    assert(run1.ok and run1.results[1] == "retry_flag_ok" and run1.results[2] == 10)

    local out_zero = E2E.compile_cli_raw(src, {
        preset = "AzureGodUltra",
        seed = 406,
        compact = true,
        retry_count = 0,
    })
    assert(out_zero.ok, "Failed --retry-count 0 on AzureGodUltra: " .. out_zero.log)
    local run2 = E2E.run_code(out_zero.output)
    assert(run2.ok and run2.results[1] == "retry_flag_ok" and run2.results[2] == 10)
end)

-- ============================================================================
-- FA5: Luau Transpilation & Cross-Runtime Parity (5 tests)
-- ============================================================================

suite:test("T1_FA5_luau_types_and_casts", "FA5", function()
    local src = [[
        type Pair = { left: number, right: string }
        export type Status = string
        local function fmt(p: Pair, tag: Status): string
            local n: number = (p.left :: any) + 8
            return tag .. ":" .. p.right .. ":" .. tostring(n)
        end
        return fmt({ left = 34, right = "ok" }, "V")
    ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 501, ext = ".luau" },
        E2E.pack("V:ok:42"))
end)

suite:test("T1_FA5_luau_backtick_interpolation", "FA5", function()
    local src = [[
        local user = "Hero"
        local lvl = 7
        local msg = `hi {user}, lvl={lvl + 1}`
        local empty = ``
        return msg, empty
    ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 502, ext = ".luau" },
        E2E.pack("hi Hero, lvl=8", ""))
end)

suite:test("T1_FA5_luau_binary_and_underscores", "FA5", function()
    local src = [[
        local b = 0b101010
        local dec = 1_000_000
        local hex = 0x1F_2A
        return b, dec, hex
    ]]
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 503, ext = ".luau" },
        E2E.pack(42, 1000000, 0x1F2A))
end)

suite:test("T1_FA5_luau_unicode_and_ifelse_expr", "FA5", function()
    local src = [[
        local u1 = "\u{41}\u{42}"
        local u2 = "\u{1F600}"
        local score = 85
        local grade = if score >= 80 then "PASS" else "FAIL"
        local low = if score >= 95 then "S" else "A"
        return u1, #u2, grade, low
    ]]
    E2E.assert_compile_and_match(src, { preset = "Hardened", compact = true, seed = 504, ext = ".luau" },
        E2E.pack("AB", 4, "PASS", "A"))
end)

suite:test("T1_FA5_luau_compound_operators", "FA5", function()
    local src = [[
        local x = 10
        x += 5
        x -= 3
        x *= 4
        x /= 6
        x %= 5
        x ^= 3
        local s = "Az"
        s ..= "VM"
        return x, s
    ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 505, ext = ".luau" },
        E2E.pack(27, "AzVM"))
end)

-- ============================================================================
-- FA6: Clean-Env Sandboxes & Zero-FP Contracts (6 tests)
-- ============================================================================

suite:test("T1_FA6_narrow_sandbox_no_debug_dump_load", "FA6", function()
    local src = [[ return "narrow_ok", 123 ]]
    for _, preset in ipairs({ "AzureGodUltra", "Hardened", "Luraph15_2" }) do
        local env = E2E.make_narrow_sandbox()
        E2E.assert_compile_and_match(src, {
            preset = preset, compact = true, seed = 601, env = env,
        }, E2E.pack("narrow_ok", 123))
    end
end)

suite:test("T1_FA6_xpcall_false_fallback", "FA6", function()
    local src = [[ return nil, false, 7, "xp_fallback" ]]
    for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
        local env = E2E.make_clean_env({ xpcall = false })
        E2E.assert_compile_and_match(src, {
            preset = preset, compact = true, seed = 602, env = env,
        }, E2E.pack(nil, false, 7, "xp_fallback"))
    end
end)

suite:test("T1_FA6_xpcall_pcall_false_coro_fallback", "FA6", function()
    local src = [[ return nil, false, 19, "coro_fallback" ]]
    local env = E2E.make_clean_env({ xpcall = false, pcall = false })
    E2E.assert_compile_and_match(src, {
        preset = "Luraph15_2", compact = true, seed = 603, env = env,
    }, E2E.pack(nil, false, 19, "coro_fallback"))
end)

suite:test("T1_FA6_benign_host_count_hook", "FA6", function()
    local src = [[ local s = 0; for i = 1, 50 do s = s + i end; return s ]]
    for _, preset in ipairs({ "AzureGodUltra", "Hardened", "Luraph15_2" }) do
        local out = E2E.compile(src, { preset = preset, compact = true, seed = 604 })
        local old_h, old_m, old_c = debug.gethook()
        local calls = 0
        local function host_hook() calls = calls + 1 end
        debug.sethook(host_hook, "", 100)
        local ok, err = pcall(function()
            local run = E2E.run_code(out)
            assert(run.ok and run.results[1] == 1275, "Execution failed under benign count hook: " .. tostring(run.err))
            local cur_h, cur_m, cur_c = debug.gethook()
            assert(cur_h == host_hook and cur_m == "" and cur_c == 100, "Host count hook was altered by " .. preset)
            assert(calls > 0, "Host count hook did not tick")
        end)
        if old_h then debug.sethook(old_h, old_m, old_c) else debug.sethook() end
        assert(ok, err)
    end
end)

suite:test("T1_FA6_neutral_filenames", "FA6", function()
    local src = [[ local t = 0; for i = 1, 40 do t = t + i end; return t ]]
    local names = { "@ordinary.lua", "@hook_config.lua", "@dump_report.lua", "@profiler_config.lua", "@extractor_example.lua" }
    for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
        local out = E2E.compile(src, { preset = preset, compact = true, seed = 605 })
        for _, cname in ipairs(names) do
            local run = E2E.run_code(out, { chunkname = cname })
            assert(run.ok and run.results[1] == 820, preset .. " failed with chunkname " .. cname)
        end
    end
end)

suite:test("T1_FA6_short_clean_scripts_under_15_instr", "FA6", function()
    local cases = {
        { src = "return 1", exp = E2E.pack(1) },
        { src = "return 'ok'", exp = E2E.pack("ok") },
        { src = "return true", exp = E2E.pack(true) },
        { src = "return false", exp = E2E.pack(false) },
        { src = "return ...", args = E2E.pack(10, nil, "z"), exp = E2E.pack(10, nil, "z") },
    }
    for _, preset in ipairs({ "AzureGodUltra", "Hardened", "Luraph15_2" }) do
        for _, c in ipairs(cases) do
            E2E.assert_compile_and_match(c.src, {
                preset = preset, compact = true, seed = 606, args = c.args,
            }, c.exp)
        end
    end
end)

-- ============================================================================
-- FA7: Clean Semantics for Trap-Adjacent Capabilities (5 tests)
-- ============================================================================

suite:test("T1_FA7_clean_global_reads_and_env_isolation", "FA7", function()
    local src = [[
        local function run_in(tbl, fn)
            setfenv(fn, tbl)
            return fn()
        end
        local box = { k = 21, getfenv = getfenv }
        local res = run_in(box, function() return k * 2, getfenv(1).k end)
        return res
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 701 })
end)

suite:test("T1_FA7_clean_string_metatable_methods", "FA7", function()
    local src = [[
        local a = ("azure"):upper()
        local b = ("hello world"):sub(1, 5)
        local c = ("x"):rep(4)
        return a, b, c
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 702 })
end)

suite:test("T1_FA7_clean_rawget_rawset_rawequal", "FA7", function()
    local src = [[
        local t = setmetatable({ a = 1 }, {
            __index = function() return 999 end,
            __newindex = function() error("should not fire", 0) end,
            __eq = function() return false end,
        })
        rawset(t, "b", 2)
        return rawget(t, "a"), rawget(t, "missing") == nil, rawget(t, "b"), rawequal(t, t)
    ]]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 703 })
end)

suite:test("T1_FA7_clean_safe_retry_transient_user_error", "FA7", function()
    local src = [[
        attempts = attempts + 1
        if attempts < 2 then
            error("transient_fault", 0)
        end
        return "recovered", attempts
    ]]
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 704 })
    local env = E2E.make_clean_env({ attempts = 0 })
    local run = E2E.run_code(out, { env = env })
    assert(run.ok and run.results[1] == "recovered" and run.results[2] == 2 and env.attempts == 2,
        "Transient retry failed: ok=" .. tostring(run.ok) .. " attempts=" .. tostring(env.attempts))
end)

suite:test("T1_FA7_clean_safe_retry_exhausted_error", "FA7", function()
    local src = [[
        attempts = attempts + 1
        error("persistent_user_error", 0)
    ]]
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, retry_count = 1, seed = 705 })
    local env = E2E.make_clean_env({ attempts = 0 })
    local run = E2E.run_code(out, { env = env })
    assert(not run.ok, "Exhausted error unexpectedly succeeded")
    assert(env.attempts == 2, "Expected 2 attempts (1 initial + 1 retry), got " .. tostring(env.attempts))
    assert(tostring(run.err):find("persistent_user_error", 1, true), "Lost error message: " .. tostring(run.err))
end)

-- ============================================================================
-- FA8: Output Integrity & Cross-Runtime Determinism Checks (5 tests)
-- ============================================================================

suite:test("T1_FA8_source_string_not_verbatim", "FA8", function()
    local secret = "TIER1_UNIQUE_SECRET_MARKER_X91"
    local src = 'return "' .. secret .. '"'
    for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
        local out = E2E.compile(src, { preset = preset, compact = true, seed = 801 })
        assert(not out:find(secret, 1, true), preset .. " leaked source string verbatim")
        local run = E2E.run_code(out)
        assert(run.ok and run.results[1] == secret)
    end
end)

suite:test("T1_FA8_compact_header_embedded", "FA8", function()
    local src = [[ return "compact_hdr_val" ]]
    for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
        local out = E2E.compile(src, {
            preset = preset, compact = true, header = "TIER1_HDR_TAG", seed = 802,
        })
        local vok, verr = E2E.validate_compact(out)
        assert(vok, verr)
        assert(out:find("TIER1_HDR_TAG", 1, true), "Missing header tag in " .. preset)
        local run = E2E.run_code(out)
        assert(run.ok and run.results[1] == "compact_hdr_val")
    end
end)

suite:test("T1_FA8_returned_closure_multi_call_isolated", "FA8", function()
    local src = [[
        return function(x, y)
            local tmp = x * 3 + y
            return tmp, x - y
        end
    ]]
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 803 })
    local run = E2E.run_code(out)
    assert(run.ok and type(run.results[1]) == "function")
    local fn = run.results[1]
    for i = 1, 5 do
        local a, b = fn(i * 10, i)
        assert(a == i * 31 and b == i * 9)
    end
end)

suite:test("T1_FA8_nested_module_table_return", "FA8", function()
    local src = [[
        local state = 5
        return {
            get = function() return state end,
            set = function(v) state = v end,
            inc = function(d) state = state + d; return state end,
        }
    ]]
    local out = E2E.compile(src, { preset = "Hardened", compact = true, seed = 804 })
    local run = E2E.run_code(out)
    assert(run.ok and type(run.results[1]) == "table")
    local mod = run.results[1]
    assert(mod.get() == 5 and mod.inc(4) == 9)
    mod.set(20)
    assert(mod.inc(-3) == 17 and mod.get() == 17)
end)

suite:test("T1_FA8_seed_cross_build_distinct", "FA8", function()
    local src = [[ local k = "cross_seed_val"; return k, 99 ]]
    local out1 = E2E.compile(src, { preset = "Luraph15_2", compact = true, seed = 11111 })
    local out2 = E2E.compile(src, { preset = "Luraph15_2", compact = true, seed = 22222 })
    assert(out1 ~= out2, "Distinct seeds yielded identical output")
    local r1 = E2E.run_code(out1)
    local r2 = E2E.run_code(out2)
    assert(r1.ok and r2.ok and E2E.tuple_eq(r1.results, r2.results))
end)

suite:finish()
