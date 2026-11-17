-- Tier 2: Boundary Value Analysis & Corner Cases (>= 40 cases, >= 5 per FA1..FA8)
-- Covers empty/comment chunks, 1-instruction chunks, >256 constant pools,
-- >100 element SETLIST, 150 locals, 8-level closures, 32-bit/IEEE-754 bounds,
-- >65KB & binary strings, >8000 VM instructions, and CLI boundary values.

local script_path = debug.getinfo(1, "S").source:sub(2)
local e2e_dir = script_path:match("^(.*)/[^/]+$") or "."
package.path = e2e_dir .. "/lib/?.lua;" .. package.path

local E2E = require("e2e_common")
local suite = E2E.new_suite("Tier2_Boundaries")

-- ============================================================================
-- FA1: VM Execution Boundaries (6 tests)
-- ============================================================================

suite:test("T2_FA1_one_instruction_return", "FA1", function()
    local src = "return 1"
    for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
        E2E.assert_compile_and_match(src, { preset = preset, compact = true, seed = 1001 }, E2E.pack(1))
    end
end)

suite:test("T2_FA1_empty_return_zero_values", "FA1", function()
    local src = "return"
    for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
        local out = E2E.compile(src, { preset = preset, compact = true, seed = 1002 })
        local run = E2E.run_code(out)
        assert(run.ok and run.results.n == 0, preset .. " expected 0 returns, got " .. tostring(run.results.n))
    end
end)

suite:test("T2_FA1_setlist_120_elements", "FA1", function()
    local parts = { "local t = {" }
    for i = 1, 120 do
        parts[#parts + 1] = tostring(i) .. ","
    end
    parts[#parts + 1] = "}; return #t, t[1], t[50], t[51], t[100], t[101], t[120]"
    local src = table.concat(parts, " ")
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 1003 },
        E2E.pack(120, 1, 50, 51, 100, 101, 120))
end)

suite:test("T2_FA1_150_locals_register_pressure", "FA1", function()
    local lines = {}
    local terms = {}
    for i = 1, 150 do
        lines[#lines + 1] = string.format("local v%d = %d", i, i)
        terms[#terms + 1] = string.format("v%d", i)
    end
    lines[#lines + 1] = "return " .. table.concat(terms, " + ")
    local src = table.concat(lines, "\n")
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 1004 },
        E2E.pack(11325))
end)

suite:test("T2_FA1_8_level_nested_closures", "FA1", function()
    local src = [[
        local function l1(a)
            return function(b)
                return function(c)
                    return function(d)
                        return function(e)
                            return function(f)
                                return function(g)
                                    return function(h)
                                        return a + b + c + d + e + f + g + h
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return l1(1)(2)(3)(4)(5)(6)(7)(8)
    ]]
    E2E.assert_compile_and_match(src, { preset = "Hardened", compact = true, seed = 1005 },
        E2E.pack(36))
end)

suite:test("T2_FA1_8000_vm_instructions_loop", "FA1", function()
    local src = [[
        local acc = 0
        for i = 1, 2500 do
            acc = (acc + i * 3) % 1000003
        end
        return acc
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 1006 })
end)

-- ============================================================================
-- FA2: Constants & Numeric/String Boundaries (6 tests)
-- ============================================================================

suite:test("T2_FA2_over_256_unique_constants", "FA2", function()
    local parts = { "local t = {" }
    for i = 1, 300 do
        parts[#parts + 1] = string.format("'K_%03d',", i)
    end
    parts[#parts + 1] = "}; return #t, t[1], t[255], t[256], t[257], t[300]"
    local src = table.concat(parts, " ")
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 2001 },
        E2E.pack(300, "K_001", "K_255", "K_256", "K_257", "K_300"))
end)

suite:test("T2_FA2_32bit_and_53bit_integer_bounds", "FA2", function()
    local src = [[
        local z = 0
        local i32_max = 2147483647
        local i32_min = -2147483648
        local u32_max = 4294967295
        local i53_max = 9007199254740991
        return z, i32_max, i32_min, u32_max, i53_max
    ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 2002 },
        E2E.pack(0, 2147483647, -2147483648, 4294967295, 9007199254740991))
end)

suite:test("T2_FA2_ieee754_nan_inf_negzero", "FA2", function()
    local src = [[
        local nan = 0 / 0
        local pinf = math.huge
        local ninf = -math.huge
        local nz = -1 / math.huge
        return (nan ~= nan), (pinf > 1e308), (ninf < -1e308), (nz == 0), (1 / nz == -math.huge)
    ]]
    E2E.assert_compile_and_match(src, { preset = "Hardened", compact = true, seed = 2003 },
        E2E.pack(true, true, true, true, true))
end)

suite:test("T2_FA2_empty_and_binary_256_byte_string", "FA2", function()
    local src = [[
        local empty = ""
        local bin = "\0\1\255"
        local t = {}
        for i = 0, 255 do
            t[#t + 1] = string.char(i)
        end
        local all = table.concat(t)
        return #empty, #bin, string.byte(bin, 1, 3), #all, string.byte(all, 1), string.byte(all, 256)
    ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 2004 },
        E2E.pack(0, 3, 0, 256, 0, 255))
end)

suite:test("T2_FA2_large_string_over_65kb", "FA2", function()
    local payload = string.rep("AZ9", 22000) -- 66,000 bytes
    local src = string.format('local s = %q; return #s, s:sub(1, 6), s:sub(-6)', payload)
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 2005 },
        E2E.pack(66000, "AZ9AZ9", "AZ9AZ9"))
end)

suite:test("T2_FA2_long_bracket_with_markers", "FA2", function()
    local src = [===[
        local s = [==[LPH> AzureVM ]=] "quotes" 'single' %s \n]==]
        return #s, s:find("LPH>", 1, true) == 1, s:find("AzureVM", 1, true) ~= nil
    ]===]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 2006 },
        E2E.pack(40, true, true))
end)

-- ============================================================================
-- FA3: Metatable & Coroutine Boundaries (5 tests)
-- ============================================================================

suite:test("T2_FA3_deep_index_chain_5_levels", "FA3", function()
    local src = [[
        local t1 = { k1 = "A", shared = 1 }
        local t2 = setmetatable({ k2 = "B" }, { __index = t1 })
        local t3 = setmetatable({ k3 = "C" }, { __index = t2 })
        local t4 = setmetatable({ k4 = "D" }, { __index = t3 })
        local t5 = setmetatable({ k5 = "E", shared = 5 }, { __index = t4 })
        return t5.k1 .. t5.k2 .. t5.k3 .. t5.k4 .. t5.k5, t5.shared, t5.missing == nil
    ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 3001 },
        E2E.pack("ABCDE", 5, true))
end)

suite:test("T2_FA3_coroutine_error_propagation_types", "FA3", function()
    local src = [[
        local function run_err(val)
            local co = coroutine.create(function() error(val, 0) end)
            return coroutine.resume(co)
        end
        local ok1, e1 = run_err("str_err")
        local ok2, e2 = run_err({ code = 418 })
        local ok3, e3 = run_err(false)
        local ok4, e4 = run_err(nil)
        return ok1, e1, ok2, e2.code, ok3, e3, ok4, e4 == nil
    ]]
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 3002 },
        E2E.pack(false, "str_err", false, 418, false, false, false, true))
end)

suite:test("T2_FA3_coroutine_many_yields_500", "FA3", function()
    local src = [[
        local co = coroutine.create(function()
            local sum = 0
            for i = 1, 500 do
                sum = sum + i
                coroutine.yield(sum)
            end
            return sum
        end)
        local last
        for i = 1, 501 do
            local ok, v = coroutine.resume(co)
            if not ok then error(v) end
            last = v
        end
        return last, coroutine.status(co)
    ]]
    E2E.assert_compile_and_match(src, { preset = "Hardened", compact = true, seed = 3003 },
        E2E.pack(125250, "dead"))
end)

suite:test("T2_FA3_self_referential_metatable", "FA3", function()
    local src = [[
        local Node = {}
        Node.__index = Node
        function Node:new(v)
            return setmetatable({ val = v }, self)
        end
        function Node:get()
            return self.val * 2
        end
        local n = Node:new(21)
        return n:get(), getmetatable(n) == Node
    ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 3004 },
        E2E.pack(42, true))
end)

suite:test("T2_FA3_pcall_inside_coroutine_between_yields", "FA3", function()
    local src = [[
        local co = coroutine.create(function()
            local ok1, e1 = pcall(function() error("caught_inside", 0) end)
            coroutine.yield(ok1, e1)
            local ok2, v2 = pcall(function(x) return x + 5 end, 37)
            return ok2, v2
        end)
        local r1, a1, b1 = coroutine.resume(co)
        local r2, a2, b2 = coroutine.resume(co)
        return r1, a1, b1, r2, a2, b2
    ]]
    E2E.assert_compile_and_match(src, { preset = "Hardened", compact = true, seed = 3005 },
        E2E.pack(true, false, "caught_inside", true, true, 42))
end)

-- ============================================================================
-- FA4: CLI & Preset Boundary Values (6 tests)
-- ============================================================================

suite:test("T2_FA4_empty_newline_comment_return_chunks", "FA4", function()
    for _, src in ipairs({ "\n", "-- empty chunk\n", "return\n" }) do
        for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
            local out = E2E.compile(src, { preset = preset, compact = true, seed = 4001 })
            local run = E2E.run_code(out)
            assert(run.ok and run.results.n == 0, "Failed empty-ish chunk on " .. preset)
        end
    end
end)

suite:test("T2_FA4_zero_byte_cli_rejects_cleanly", "FA4", function()
    local res = E2E.compile_cli_raw("", { preset = "Luraph15_2", seed = 4002 })
    assert(not res.ok and res.exit_code ~= 0, "0-byte input unexpectedly succeeded")
end)

suite:test("T2_FA4_seed_bounds_1_and_max_int32", "FA4", function()
    local src = "return 99"
    for _, s in ipairs({ 1, 2147483647 }) do
        E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = s }, E2E.pack(99))
    end
    for _, bad in ipairs({ 0, -1, 2147483648, "1.5", "abc" }) do
        local r = E2E.compile_cli_raw(src, { preset = "Luraph15_2", seed = bad })
        assert(not r.ok and r.exit_code ~= 0, "Invalid seed accepted: " .. tostring(bad))
    end
end)

suite:test("T2_FA4_retry_count_bounds_0_and_100", "FA4", function()
    local src = "return 55"
    for _, rc in ipairs({ 0, 100 }) do
        local r = E2E.compile_cli_raw(src, { preset = "AzureGodUltra", seed = 4004, compact = true, retry_count = rc })
        assert(r.ok, "Valid retry count failed: " .. tostring(rc) .. " -> " .. r.log)
        local run = E2E.run_code(r.output)
        assert(run.ok and run.results[1] == 55)
    end
    for _, bad in ipairs({ -1, 101, "1.5", "nan" }) do
        local r = E2E.compile_cli_raw(src, { preset = "AzureGodUltra", seed = 4004, retry_count = bad })
        assert(not r.ok and r.exit_code ~= 0, "Invalid retry count accepted: " .. tostring(bad))
    end
end)

suite:test("T2_FA4_invalid_cli_flags_rejected", "FA4", function()
    local r1 = E2E.compile_cli_raw("return 1", { preset = "NoSuchPreset999", seed = 4005 })
    assert(not r1.ok and r1.exit_code ~= 0, "Unknown preset accepted")
    local r2 = E2E.compile_cli_raw("return 1", { omit_input = true, input_override = "-", preset = "Luraph15_2", seed = 4005 })
    assert(not r2.ok and r2.exit_code ~= 0, "Stdin '-' accepted")
    local r3 = E2E.compile_cli_raw("return 1", { preset = "Luraph15_2", seed = 4005, extra_args = { "--preset=Luraph" } })
    assert(not r3.ok and r3.exit_code ~= 0, "--preset= syntax accepted")
end)

suite:test("T2_FA4_default_output_filename_luau", "FA4", function()
    local r = E2E.compile_cli_raw("local x: number = 12\nreturn x * 2", {
        preset = "Luraph15_2", seed = 4006, compact = true, omit_out = true, ext = ".luau",
    })
    assert(r.ok and r.output ~= nil, "Default output for .luau missing: " .. r.log)
    local run = E2E.run_code(r.output)
    assert(run.ok and run.results[1] == 24)
end)

-- ============================================================================
-- FA5: Luau Transpiler Boundaries (5 tests)
-- ============================================================================

suite:test("T2_FA5_luau_shebang_stripped", "FA5", function()
    local src = "#!/usr/bin/env luau\nlocal n: number = 42\nreturn n"
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 5001, ext = ".luau" },
        E2E.pack(42))
end)

suite:test("T2_FA5_luau_empty_and_multiline_backticks", "FA5", function()
    local src = "local e = ``\nlocal x = 9\nlocal m = `lineA\nval={x}`\nreturn e, m"
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 5002, ext = ".luau" },
        E2E.pack("", "lineA\nval=9"))
end)

suite:test("T2_FA5_luau_unicode_bmp_and_astral", "FA5", function()
    local src = [[
        local a: string = "\u{0041}"
        local lam: string = "\u{03BB}"
        local grin: string = "\u{1F600}"
        return a, string.byte(lam, 1, 2), string.byte(grin, 1, 4)
    ]]
    E2E.assert_compile_and_match(src, { preset = "Hardened", compact = true, seed = 5003, ext = ".luau" },
        E2E.pack("A", 206, 240, 159, 152, 128))
end)

suite:test("T2_FA5_luau_multiline_type_tables", "FA5", function()
    local src = [[
        export type Config = {
            host: string,
            port: number,
            tls: boolean
        }
        local c: Config = { host = "localhost", port = 8443, tls = true }
        return c.host, c.port, c.tls
    ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 5004, ext = ".luau" },
        E2E.pack("localhost", 8443, true))
end)

suite:test("T2_FA5_luau_compound_field_and_index", "FA5", function()
    local src = [[
        local obj = { x = 10 }
        local arr = { "hi" }
        obj.x += 15
        obj.x -= 5
        arr[1] ..= "_luau"
        return obj.x, arr[1]
    ]]
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 5005, ext = ".luau" },
        E2E.pack(20, "hi_luau"))
end)

-- ============================================================================
-- FA6: Sandbox & Short-Script Edge Boundaries (5 tests)
-- ============================================================================

suite:test("T2_FA6_minimal_1_instr_narrow_sandbox", "FA6", function()
    local src = "return 7"
    for _, preset in ipairs({ "AzureGodUltra", "Luraph15_2" }) do
        local env = E2E.make_narrow_sandbox()
        E2E.assert_compile_and_match(src, { preset = preset, compact = true, seed = 6001, env = env },
            E2E.pack(7))
    end
end)

suite:test("T2_FA6_count_hook_1_instruction_interval", "FA6", function()
    local src = "local a = 1; local b = 2; return a + b"
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 6002 })
    local old_h, old_m, old_c = debug.gethook()
    local ticks = 0
    local function h() ticks = ticks + 1 end
    debug.sethook(h, "", 1)
    local ok, err = pcall(function()
        local run = E2E.run_code(out)
        assert(run.ok and run.results[1] == 3)
        local ch, cm, cc = debug.gethook()
        assert(ch == h and cm == "" and cc == 1 and ticks > 0)
    end)
    if old_h then debug.sethook(old_h, old_m, old_c) else debug.sethook() end
    assert(ok, err)
end)

suite:test("T2_FA6_long_filename_with_keywords", "FA6", function()
    local src = "return 'fname_ok'"
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 6003 })
    local run = E2E.run_code(out, { chunkname = "@path/to/hook_dump_profiler_extractor_test.lua" })
    assert(run.ok and run.results[1] == "fname_ok")
end)

suite:test("T2_FA6_extra_unused_globals_false", "FA6", function()
    local src = "return 12 + 30"
    local env = E2E.make_clean_env({ jit = false, bit = false, bit32 = false })
    E2E.assert_compile_and_match(src, { preset = "Hardened", compact = true, seed = 6004, env = env },
        E2E.pack(42))
end)

suite:test("T2_FA6_vararg_only_script", "FA6", function()
    local src = "return select('#', ...), ..."
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 6005 })
    local r0 = E2E.run_code(out, { args = E2E.pack() })
    assert(r0.ok and r0.results.n == 1 and r0.results[1] == 0)
    local r5 = E2E.run_code(out, { args = E2E.pack(nil, false, 0, "", 99) })
    assert(r5.ok and r5.results.n == 6 and r5.results[1] == 5 and r5.results[2] == nil and r5.results[3] == false and r5.results[4] == 0 and r5.results[5] == "" and r5.results[6] == 99)
end)

-- ============================================================================
-- FA7: Retry & Error Boundary Semantics (5 tests)
-- ============================================================================

suite:test("T2_FA7_safe_retry_preserves_nil_false_multi_return", "FA7", function()
    local src = [[ return nil, false, 42, nil, "end" ]]
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 7001 },
        E2E.pack(nil, false, 42, nil, "end"))
end)

suite:test("T2_FA7_safe_retry_no_register_leak_across_attempts", "FA7", function()
    local src = [[
        local x = 1
        seen[#seen + 1] = x
        x = x + 99
        if #seen < 3 then
            error("retry_me", 0)
        end
        return x, #seen
    ]]
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 7002 })
    local seen = {}
    local env = E2E.make_clean_env({ seen = seen })
    local run = E2E.run_code(out, { env = env })
    assert(run.ok and run.results[1] == 100 and run.results[2] == 3)
    assert(seen[1] == 1 and seen[2] == 1 and seen[3] == 1)
end)

suite:test("T2_FA7_safe_retry_non_string_errors", "FA7", function()
    local src = [[
        local mode = ...
        if mode == "false" then error(false, 0) end
        if mode == "nil" then error(nil, 0) end
        if mode == "table" then error({ code = 503 }, 0) end
    ]]
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, retry_count = 1, seed = 7003 })
    local r1 = E2E.run_code(out, { args = E2E.pack("false") })
    assert(not r1.ok and r1.err == false)
    local r2 = E2E.run_code(out, { args = E2E.pack("nil") })
    assert(not r2.ok and r2.err == nil)
    local r3 = E2E.run_code(out, { args = E2E.pack("table") })
    assert(not r3.ok and type(r3.err) == "table" and r3.err.code == 503)
end)

suite:test("T2_FA7_retry_count_zero_single_attempt", "FA7", function()
    local src = [[ hits = hits + 1; error("once_only", 0) ]]
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, retry_count = 0, seed = 7004 })
    local env = E2E.make_clean_env({ hits = 0 })
    local run = E2E.run_code(out, { env = env })
    assert(not run.ok and env.hits == 1)
end)

suite:test("T2_FA7_nested_pcall_inside_retry_single_attempt", "FA7", function()
    local src = [[
        hits = hits + 1
        local ok, e = pcall(function() error("inner_err", 0) end)
        return hits, ok, e
    ]]
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 7005 })
    local env = E2E.make_clean_env({ hits = 0 })
    local run = E2E.run_code(out, { env = env })
    assert(run.ok and run.results[1] == 1 and run.results[2] == false and run.results[3] == "inner_err")
end)

-- ============================================================================
-- FA8: Large Payload & Encoding Stress Boundaries (5 tests)
-- ============================================================================

suite:test("T2_FA8_duplicate_long_strings_10x", "FA8", function()
    local block = string.rep("DUPLICATE_STR_BOUNDARY_01234567_", 4) -- 128 chars
    local parts = { "local acc = {}" }
    for i = 1, 10 do
        parts[#parts + 1] = string.format("acc[%d] = %q", i, block)
    end
    parts[#parts + 1] = "local s = table.concat(acc); return #s, s:sub(1, 16)"
    local src = table.concat(parts, "\n")
    E2E.assert_compile_and_match(src, { preset = "AzureGodUltra", compact = true, seed = 8001 },
        E2E.pack(1280, "DUPLICATE_STR_BO"))
end)

suite:test("T2_FA8_many_unique_strings_100", "FA8", function()
    local parts = { "local list = {" }
    for i = 1, 100 do
        parts[#parts + 1] = string.format("'STR_%03d_%d',", i, i * 17)
    end
    parts[#parts + 1] = "}; return #list, list[1], list[50], list[100]"
    local src = table.concat(parts, " ")
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 8002 },
        E2E.pack(100, "STR_001_17", "STR_050_850", "STR_100_1700"))
end)

suite:test("T2_FA8_deep_recursion_200_frames", "FA8", function()
    local src = [[
        local function rec(n)
            if n <= 0 then return 0 end
            return 1 + rec(n - 1)
        end
        return rec(200)
    ]]
    E2E.assert_compile_and_match(src, { preset = "Luraph15_2", compact = true, seed = 8003 },
        E2E.pack(200))
end)

suite:test("T2_FA8_mixed_numeric_literal_pool_40", "FA8", function()
    local src = [[
        local nums = {
            0, 1, -1, 42, -42, 255, 256, 65535, 65536, -65536,
            1e-10, -1e-10, 1e10, -1e10, 1.5, -1.5, 3.141592653589793,
            1 + 2^-52, 1 - 2^-53, 2^-1022, 1.7976931348623157e308, -1.7976931348623157e308,
            2^31 - 1, -(2^31), 2^32 - 1, 2^53 - 1, -(2^53 - 1), 0.125, 0.25, 0.5,
            1000001, 2000002, 3000003, 4000004, 5000005, 6000006, 7000007, 8000008, 9000009, 10000010
        }
        return #nums, nums[1], nums[17], nums[21], nums[26], nums[40]
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 8004 })
end)

suite:test("T2_FA8_compact_output_zero_crlf_large_script", "FA8", function()
    local lines = { "local function f(x) return x * 2 + 1 end", "local sum = 0" }
    for i = 1, 40 do
        lines[#lines + 1] = string.format("sum = sum + f(%d)", i)
    end
    lines[#lines + 1] = "return sum"
    local src = table.concat(lines, "\n")
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 8005 })
    local vok, verr = E2E.validate_compact(out)
    assert(vok, verr)
    local run = E2E.run_code(out)
    assert(run.ok and run.results[1] == 1680)
end)

suite:finish()
