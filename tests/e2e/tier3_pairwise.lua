-- Tier 3: Cross-Feature Pairwise Combinations (12 combinations >= 10)
-- Combines DeepCFF, MBA, OpaquePredicates, upvalues, closures, coroutines,
-- pcall/error propagation, SafeRetryWrapper, Luau syntax, --compact, --seed,
-- narrow sandboxes, host count-hooks, and neutral filenames.

local script_path = debug.getinfo(1, "S").source:sub(2)
local e2e_dir = script_path:match("^(.*)/[^/]+$") or "."
package.path = e2e_dir .. "/lib/?.lua;" .. package.path

local E2E = require("e2e_common")
local suite = E2E.new_suite("Tier3_Pairwise")

suite:test("T3_P01_DeepCFF_MBA_Upvalues_Closures_AzureGodUltra", "FA1+FA2+FA4", function()
    local src = [[
        local function make_acc(seed)
            local state = seed
            local history = {}
            local function step(n)
                local i = 0
                repeat
                    i = i + 1
                    if (i % 2 == 0) and (n > 0) then
                        state = (state * 3 + i) % 1009
                    else
                        state = state + i + n
                    end
                    if i >= 4 then break end
                until false
                history[#history + 1] = state
                return state
            end
            return step, function() return #history, history[#history] end
        end
        local step, peek = make_acc(17)
        step(5)
        step(12)
        step(-3)
        return peek()
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 3101 })
end)

suite:test("T3_P02_Coroutines_pcall_ErrorPropagation_Hardened", "FA1+FA3+FA4", function()
    local src = [[
        local co1 = coroutine.create(function(x)
            local ok, v = pcall(function(n)
                if n < 0 then error("neg", 0) end
                return n * 10
            end, x)
            coroutine.yield(ok, v)
            error({ kind = "fatal", code = 99 }, 0)
        end)
        local r1, ok_in, val_in = coroutine.resume(co1, 7)
        local r2, err_tbl = coroutine.resume(co1)

        local co2 = coroutine.create(function()
            error(false, 0)
        end)
        local r3, err_false = coroutine.resume(co2)
        return r1, ok_in, val_in, r2, err_tbl.kind, err_tbl.code, r3, err_false
    ]]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 3102 })
end)

suite:test("T3_P03_SafeRetry_TransientError_MultiReturn_Varargs_Compact", "FA1+FA4+FA7", function()
    local src = [[
        attempts = attempts + 1
        local a, b, c = ...
        if attempts < 3 then
            error("transient_attempt_" .. attempts, 0)
        end
        return nil, false, a, b == nil, c, attempts, select('#', ...)
    ]]
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 3103 })
    local vok, verr = E2E.validate_compact(out)
    assert(vok, verr)
    local env = E2E.make_clean_env({ attempts = 0 })
    local run = E2E.run_code(out, { env = env, args = E2E.pack("tag", nil, 77) })
    assert(run.ok and E2E.tuple_eq(run.results, E2E.pack(nil, false, "tag", true, 77, 3, 3)))
end)

suite:test("T3_P04_Luau_AzureGodUltra_Compact_MultiSeed", "FA4+FA5+FA8", function()
    local src = [[
        type Order = { id: number, tag: string, qty: number }
        local base_mask: number = 0b1011
        local cap: number = 1_000
        local o: Order = { id = 7, tag = "AZ", qty = 4 }
        local score = (o.id * o.qty) + base_mask
        score += 10
        local tier = if score > 40 then "HIGH" else "STD"
        local msg = `{o.tag}:{tier}:{score}/{cap}`
        return msg
    ]]
    local o1 = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 101, ext = ".luau" })
    local o2 = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 202, ext = ".luau" })
    assert(o1 ~= o2, "Distinct seeds yielded identical Luau AzureGodUltra output")
    local r1 = E2E.run_code(o1)
    local r2 = E2E.run_code(o2)
    assert(r1.ok and r2.ok and r1.results[1] == "AZ:HIGH:49/1000" and r2.results[1] == "AZ:HIGH:49/1000")
end)

suite:test("T3_P05_Metatables_Upvalues_Closures_Hardened", "FA1+FA3+FA4", function()
    local src = [[
        local function make_vec(x, y)
            local secret_scale = 2
            local mt
            mt = {
                __add = function(a, b) return make_vec(a.x + b.x, a.y + b.y) end,
                __tostring = function(v) return "(" .. (v.x * secret_scale) .. "," .. (v.y * secret_scale) .. ")" end,
                __call = function(v, k) return (v.x + v.y) * k end,
            }
            return setmetatable({ x = x, y = y }, mt)
        end
        local v = make_vec(3, 4) + make_vec(1, 2)
        return tostring(v), v(5)
    ]]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 3105 })
end)

suite:test("T3_P06_NarrowSandbox_CountHook_NeutralFilename_AzureGodUltra", "FA4+FA6", function()
    local src = [[
        local total = 0
        for i = 1, 30 do total = total + i end
        return total, "sandbox_clean"
    ]]
    local out_l152 = E2E.compile(src, { preset = "Luraph15_2", compact = true, seed = 3106 })
    local r_narrow = E2E.run_code(out_l152, {
        env = E2E.make_narrow_sandbox(),
        chunkname = "@hook_config.lua",
    })
    assert(r_narrow.ok and r_narrow.results[1] == 465 and r_narrow.results[2] == "sandbox_clean")

    local out_ultra = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 3106 })
    local old_h, old_m, old_c = debug.gethook()
    local count = 0
    local function hook() count = count + 1 end
    debug.sethook(hook, "", 100)
    local ok, err = pcall(function()
        local r = E2E.run_code(out_ultra, { chunkname = "@profiler_config.lua" })
        assert(r.ok and r.results[1] == 465 and r.results[2] == "sandbox_clean")
        local h, m, c = debug.gethook()
        assert(h == hook and m == "" and c == 100 and count > 0)
    end)
    if old_h then debug.sethook(old_h, old_m, old_c) else debug.sethook() end
    assert(ok, err)
end)

suite:test("T3_P07_LargeConstPool_SETLIST_Closures_Luraph15_2", "FA1+FA2+FA4", function()
    local parts = { "local pool = {" }
    for i = 1, 270 do
        parts[#parts + 1] = string.format("'C_%d',", i)
    end
    parts[#parts + 1] = "}; return function(idx) return #pool, pool[1], pool[idx], pool[270] end"
    local src = table.concat(parts, " ")
    local out = E2E.compile(src, { preset = "Luraph15_2", compact = true, seed = 3107 })
    local run = E2E.run_code(out)
    assert(run.ok and type(run.results[1]) == "function")
    local n, a, b, c = run.results[1](258)
    assert(n == 270 and a == "C_1" and b == "C_258" and c == "C_270")
end)

suite:test("T3_P08_Luau_Coroutines_Metatables_Hardened", "FA3+FA4+FA5", function()
    local src = [[
        export type Box = { v: number }
        local mt = {
            __tostring = function(self: Box): string
                return `Box({self.v})`
            end
        }
        local co = coroutine.create(function(start: number)
            local cur = start
            for i = 1, 3 do
                cur += i * 2
                coroutine.yield(setmetatable({ v = cur }, mt))
            end
            return cur
        end)
        local _, b1 = coroutine.resume(co, 10)
        local _, b2 = coroutine.resume(co)
        local _, b3 = coroutine.resume(co)
        local _, done = coroutine.resume(co)
        return tostring(b1), tostring(b2), tostring(b3), done
    ]]
    E2E.assert_compile_and_match(src, { preset = "Hardened", compact = true, seed = 3108, ext = ".luau" },
        E2E.pack("Box(12)", "Box(16)", "Box(22)", 22))
end)

suite:test("T3_P09_Tailcall_MultiReturn_Varargs_MBA_AzureGodUltra", "FA1+FA2+FA4", function()
    local src = [[
        local function rec(n, a, b, ...)
            if n <= 0 then
                return a, b, select('#', ...), ...
            end
            return rec(n - 1, a + b, b * 2, ...)
        end
        return rec(4, 1, 3, "x", nil, false)
    ]]
    E2E.assert_parity(src, { preset = "AzureGodUltra", compact = true, seed = 3109 })
end)

suite:test("T3_P10_Header_RetryCount0_BinaryStrings_Luraph15_2", "FA2+FA4", function()
    local src = [[
        local b = "\0\1\255ABC"
        return #b, string.byte(b, 1, 4)
    ]]
    local out = E2E.compile(src, {
        preset = "Luraph15_2",
        compact = false,
        header = "PAIR_HDR_10",
        retry_count = 0,
        seed = 3110,
    })
    assert(out:find("PAIR_HDR_10", 1, true))
    local run = E2E.run_code(out)
    assert(run.ok and E2E.tuple_eq(run.results, E2E.pack(6, 0, 1, 255, 65)))
end)

suite:test("T3_P11_xpcallFalse_TransientRetry_MultiClosure_AzureGodUltra", "FA1+FA6+FA7", function()
    local src = [[
        tries = tries + 1
        if tries < 2 then
            error("init_blip", 0)
        end
        local base = 100
        return function(delta)
            return base + delta, tries
        end
    ]]
    local out = E2E.compile(src, { preset = "AzureGodUltra", compact = true, seed = 3111 })
    local env = E2E.make_clean_env({ xpcall = false, tries = 0 })
    local run = E2E.run_code(out, { env = env })
    assert(run.ok and type(run.results[1]) == "function")
    local v, t = run.results[1](23)
    assert(v == 123 and t == 2)
end)

suite:test("T3_P12_8LevelClosures_EarlyCloseBreak_DeepCFF_Hardened", "FA1+FA4", function()
    local src = [[
        local getters = {}
        for i = 1, 6 do
            local x = i
            local function f1()
                return function()
                    return function()
                        return function()
                            return function()
                                return function()
                                    return function()
                                        return x * 11
                                    end
                                end
                            end
                        end
                    end
                end
            end
            getters[#getters + 1] = f1()()()()()()
            if i == 4 then break end
        end
        return #getters, getters[1](), getters[4]()
    ]]
    E2E.assert_parity(src, { preset = "Hardened", compact = true, seed = 3112 })
end)

suite:finish()
