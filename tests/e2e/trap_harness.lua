-- R1 Adversarial Trap Harness & Clean-Environment Zero-FP Matrix
-- Tests --preset AzureGodUltra and --preset Luraph15_2 (--compact --seed 12345)
-- across short (<15 instr) and multi-closure fixtures.
--
-- Exit semantics:
--   - All Clean-Env Zero-FP probes MUST pass 100% on v2.1.0 and v2.2.0.
--   - Attack probes assert true fail-closed execution (never achieving user sentinel).
--   - Exits 0 iff failed == 0.

local script_path = debug.getinfo(1, "S").source:sub(2)
local e2e_dir = script_path:match("^(.*)/[^/]+$") or "."
package.path = e2e_dir .. "/lib/?.lua;" .. package.path

local E2E = require("e2e_common")
local suite = E2E.new_suite("R1_TrapHarness")

local PRESETS = { "AzureGodUltra", "Luraph15_2" }

local FIXTURES = {
    short_str = {
        src = [[
on_enter()
on_commit()
return "E2E_R1_SHORT_OK_719"
]],
        expected = "E2E_R1_SHORT_OK_719",
        kind = "short_str",
    },
    short_num = {
        src = [[
on_enter()
return 90421
]],
        expected = 90421,
        kind = "short_num",
    },
    multi = {
        src = [[
on_enter()
local secret = "E2E_R1_MULTI_SECRET_882"
local function make_gate(k)
    return function(arg)
        on_commit()
        return secret .. ":" .. tostring(k) .. ":" .. tostring(arg)
    end
end
return make_gate("K1")
]],
        expected = "E2E_R1_MULTI_SECRET_882:K1:A",
        kind = "multi",
    },
}

-- Compile canonical artifacts once per preset+fixture
local COMPILED = {}
for _, preset in ipairs(PRESETS) do
    COMPILED[preset] = {}
    for fname, fspec in pairs(FIXTURES) do
        COMPILED[preset][fname] = E2E.compile(fspec.src, {
            preset = preset,
            compact = true,
            seed = 12345,
        })
    end
end

local function clone_table(tbl)
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = v
    end
    return out
end

local function make_attack_env(on_enter_extra)
    local state = {
        entry_hits = 0,
        commit_hits = 0,
        mid_triggered = false,
    }
    local env = {
        string = clone_table(string),
        table = clone_table(table),
        math = clone_table(math),
        coroutine = clone_table(coroutine),
        debug = clone_table(debug),
    }
    env.on_enter = function()
        state.entry_hits = state.entry_hits + 1
        if on_enter_extra and not state.mid_triggered then
            state.mid_triggered = true
            on_enter_extra(env, state)
        end
    end
    env.on_commit = function()
        state.commit_hits = state.commit_hits + 1
    end
    return setmetatable(env, { __index = _G }), state
end

local function execute_target(code, fspec, env, chunkname)
    local fn, load_err = E2E.loadstring(code, chunkname or "@e2e_r1_target.lua")
    if not fn then
        return false, load_err, false, nil
    end
    setfenv(fn, env)
    local ok, res = pcall(fn)
    if not ok then
        return false, res, false, nil
    end
    if fspec.kind == "multi" then
        if type(res) ~= "function" then
            return true, res, false, nil
        end
        local ok2, res2 = pcall(res, "A")
        return ok, res, ok2, res2
    end
    return ok, res, ok, res
end

local function assert_fail_closed_preload(code, fspec, env, label, chunkname)
    local ok, res, ok2, res2 = execute_target(code, fspec, env, chunkname)
    local state = env._state_ref
    local final_ok = (fspec.kind == "multi") and (ok and ok2) or ok
    local final_res = (fspec.kind == "multi") and res2 or res
    local achieved = final_ok and (final_res == fspec.expected)
    assert(state.entry_hits == 0 and state.commit_hits == 0 and not achieved,
        string.format("%s bypassed pre-load trap (entry=%d, commit=%d, ok=%s, res=%s)",
            label, state.entry_hits, state.commit_hits, tostring(final_ok), tostring(final_res)))
end

local function assert_fail_closed_midrun(code, fspec, env, label)
    local ok, res, ok2, res2 = execute_target(code, fspec, env)
    local state = env._state_ref
    local final_ok = (fspec.kind == "multi") and (ok and ok2) or ok
    local final_res = (fspec.kind == "multi") and res2 or res
    local achieved = final_ok and (final_res == fspec.expected)
    assert(state.commit_hits == 0 and not achieved,
        string.format("%s bypassed mid-run trap (entry=%d, commit=%d, ok=%s, res=%s)",
            label, state.entry_hits, state.commit_hits, tostring(final_ok), tostring(final_res)))
end

local function assert_clean_pass(code, fspec, env, label, chunkname)
    local ok, res, ok2, res2 = execute_target(code, fspec, env, chunkname)
    local state = env._state_ref
    local final_ok = (fspec.kind == "multi") and (ok and ok2) or ok
    local final_res = (fspec.kind == "multi") and res2 or res
    local expected_commits = (fspec.kind == "short_num") and 0 or 1
    assert(final_ok and final_res == fspec.expected and state.entry_hits == 1 and state.commit_hits == expected_commits,
        string.format("%s FALSE POSITIVE (ok=%s, res=%s, entry=%d, commit=%d)",
            label, tostring(final_ok), tostring(final_res), state.entry_hits, state.commit_hits))
end

-- ============================================================================
-- CLEAN-ENVIRONMENT ZERO-FP MATRIX (MUST PASS 100%)
-- ============================================================================

for _, preset in ipairs(PRESETS) do
    for _, fname in ipairs({ "short_str", "short_num", "multi" }) do
        local fspec = FIXTURES[fname]
        local code = COMPILED[preset][fname]

        suite:test("R1_CLEAN_std_" .. preset .. "_" .. fname, "R1.Clean", function()
            local env, st = make_attack_env()
            env._state_ref = st
            assert_clean_pass(code, fspec, env, "clean_std")
        end)

        suite:test("R1_CLEAN_narrow_sandbox_" .. preset .. "_" .. fname, "R1.Clean", function()
            local env, st = make_attack_env()
            env._state_ref = st
            env.debug = false
            env.string.dump = false
            env.loadstring = false
            env.load = false
            assert_clean_pass(code, fspec, env, "narrow_sandbox")
        end)
    end

    for _, fname in ipairs({ "short_str", "multi" }) do
        local fspec = FIXTURES[fname]
        local code = COMPILED[preset][fname]
        suite:test("R1_CLEAN_host_count_hook_" .. preset .. "_" .. fname, "R1.Clean", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local old_h, old_m, old_c = debug.gethook()
            local ticks = 0
            local function host_hook() ticks = ticks + 1 end
            debug.sethook(host_hook, "", 100)
            local ok, err = pcall(function()
                assert_clean_pass(code, fspec, env, "host_count_hook")
                local ch, cm, cc = debug.gethook()
                assert(ch == host_hook and cm == "" and cc == 100, "Host count hook modified")
                assert(ticks > 0, "Host count hook did not tick")
            end)
            if old_h then debug.sethook(old_h, old_m, old_c) else debug.sethook() end
            assert(ok, err)
        end)
    end

    for _, cname in ipairs({ "@hook_config.lua", "@dump_report.lua", "@profiler_config.lua", "@extractor_example.lua" }) do
        suite:test("R1_CLEAN_filename_" .. preset .. "_" .. cname:sub(2), "R1.Clean", function()
            local fspec = FIXTURES.short_str
            local code = COMPILED[preset].short_str
            local env, st = make_attack_env()
            env._state_ref = st
            assert_clean_pass(code, fspec, env, "filename:" .. cname, cname)
        end)
    end
end

-- ============================================================================
-- CAT A: PRE-LOAD STDLIB / GLOBAL HOOKS (26 primitives x 2 presets x 2 shapes)
-- ============================================================================

local CAT_A_GLOBALS = {
    { "pcall", pcall },
    { "xpcall", xpcall },
    { "select", select },
    { "type", type },
    { "error", error },
    { "setmetatable", setmetatable },
    { "getmetatable", getmetatable },
    { "rawget", rawget },
    { "rawset", rawset },
    { "rawequal", rawequal },
    { "getfenv", getfenv },
    { "setfenv", setfenv },
    { "loadstring", E2E.loadstring },
}

local CAT_A_LIBS = {
    { "string", "byte", string.byte },
    { "string", "char", string.char },
    { "string", "sub", string.sub },
    { "string", "gsub", string.gsub },
    { "string", "find", string.find },
    { "string", "rep", string.rep },
    { "table", "concat", table.concat },
    { "table", "insert", table.insert },
    { "table", "unpack", table.unpack or unpack },
    { "math", "floor", math.floor },
    { "coroutine", "create", coroutine.create },
    { "coroutine", "resume", coroutine.resume },
    { "coroutine", "wrap", coroutine.wrap },
}

for _, preset in ipairs(PRESETS) do
    for _, fname in ipairs({ "short_str", "multi" }) do
        local fspec = FIXTURES[fname]
        local code = COMPILED[preset][fname]

        for _, spec in ipairs(CAT_A_GLOBALS) do
            local name, orig = spec[1], spec[2]
            suite:test("R1_CatA_preload_" .. name .. "_" .. preset .. "_" .. fname, "R1.CatA", function()
                local env, st = make_attack_env()
                env._state_ref = st
                env[name] = function(...)
                    return orig(...)
                end
                assert_fail_closed_preload(code, fspec, env, "CatA:" .. name)
            end)
        end

        for _, spec in ipairs(CAT_A_LIBS) do
            local lib, field, orig = spec[1], spec[2], spec[3]
            suite:test("R1_CatA_preload_" .. lib .. "_" .. field .. "_" .. preset .. "_" .. fname, "R1.CatA", function()
                local env, st = make_attack_env()
                env._state_ref = st
                env[lib][field] = function(...)
                    return orig(...)
                end
                if lib == "table" and field == "unpack" and env.unpack then
                    env.unpack = env[lib][field]
                end
                assert_fail_closed_preload(code, fspec, env, "CatA:" .. lib .. "." .. field)
            end)
        end
    end
end

-- ============================================================================
-- CAT B: MID-RUN STDLIB HOOKS (triggered inside on_enter)
-- ============================================================================

local CAT_B_HOOKS = {
    { "string_byte", function(env) local o = env.string.byte; env.string.byte = function(...) return o(...) end end },
    { "string_sub", function(env) local o = env.string.sub; env.string.sub = function(...) return o(...) end end },
    { "table_concat", function(env) local o = env.table.concat; env.table.concat = function(...) return o(...) end end },
    { "pcall", function(env) local o = pcall; env.pcall = function(...) return o(...) end end },
    { "setmetatable", function(env) local o = setmetatable; env.setmetatable = function(...) return o(...) end end },
}

for _, preset in ipairs(PRESETS) do
    for _, fname in ipairs({ "short_str", "multi" }) do
        local fspec = FIXTURES[fname]
        local code = COMPILED[preset][fname]
        for _, spec in ipairs(CAT_B_HOOKS) do
            local hname, installer = spec[1], spec[2]
            suite:test("R1_CatB_midrun_" .. hname .. "_" .. preset .. "_" .. fname, "R1.CatB", function()
                local env, st = make_attack_env(function(e) installer(e) end)
                env._state_ref = st
                assert_fail_closed_midrun(code, fspec, env, "CatB:" .. hname)
            end)
        end
    end
end

-- ============================================================================
-- CAT C: SIMULATED ROBLOX EXECUTOR HOOKS
-- ============================================================================

for _, preset in ipairs(PRESETS) do
    for _, fname in ipairs({ "short_num", "multi" }) do
        local fspec = FIXTURES[fname]
        local code = COMPILED[preset][fname]

        suite:test("R1_CatC_lua_wrapper_over_C_pcall_" .. preset .. "_" .. fname, "R1.CatC", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local orig_pcall = pcall
            env.pcall = function(...) return orig_pcall(...) end
            assert_fail_closed_preload(code, fspec, env, "CatC:wrapper_pcall")
        end)

        suite:test("R1_CatC_lua_wrapper_over_C_string_char_" .. preset .. "_" .. fname, "R1.CatC", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local orig_char = string.char
            env.string.char = function(...) return orig_char(...) end
            assert_fail_closed_preload(code, fspec, env, "CatC:wrapper_string.char")
        end)

        suite:test("R1_CatC_executor_hookfunction_islclosure_" .. preset .. "_" .. fname, "R1.CatC", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local orig_byte = string.byte
            env.string.byte = function(...) return orig_byte(...) end
            env.hookfunction = function(target, replacement) return replacement or target end
            env.replaceclosure = env.hookfunction
            env.newcclosure = function(fn) return function(...) return fn(...) end end
            env.islclosure = function(_) return true end
            env.iscclosure = function(_) return false end
            assert_fail_closed_preload(code, fspec, env, "CatC:hookfunction_islclosure")
        end)

        suite:test("R1_CatC_executor_hookmetamethod_getgenv_" .. preset .. "_" .. fname, "R1.CatC", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local spy_reads = 0
            local genv_proxy = setmetatable({}, {
                __index = function(_, k)
                    spy_reads = spy_reads + 1
                    return env[k] or _G[k]
                end,
                __newindex = function(_, k, v)
                    env[k] = v
                end,
            })
            env.getgenv = function() return genv_proxy end
            env.hookmetamethod = function(obj, method, fn) return fn end
            local orig_getmt = getmetatable
            env.getmetatable = function(v)
                if type(v) == "string" then
                    return { __index = env.string }
                end
                return orig_getmt(v)
            end
            assert_fail_closed_preload(code, fspec, env, "CatC:hookmetamethod_getgenv")
        end)
    end
end

-- ============================================================================
-- CAT D: ENVIRONMENT LOGGING (setfenv proxy + library table proxies)
-- ============================================================================

for _, preset in ipairs(PRESETS) do
    for _, fname in ipairs({ "short_num", "multi" }) do
        local fspec = FIXTURES[fname]
        local code = COMPILED[preset][fname]

        suite:test("R1_CatD_setfenv_metatable_logger_" .. preset .. "_" .. fname, "R1.CatD", function()
            local backing, st = make_attack_env()
            local logged = {}
            local spy_env = setmetatable({ _state_ref = st }, {
                __index = function(_, k)
                    logged[#logged + 1] = k
                    return backing[k]
                end,
                __newindex = function(_, k, v)
                    logged[#logged + 1] = k
                    backing[k] = v
                end,
            })
            assert_fail_closed_preload(code, fspec, spy_env, "CatD:setfenv_logger")
        end)

        for _, libname in ipairs({ "_G", "string", "table", "math" }) do
            suite:test("R1_CatD_proxy_" .. libname .. "_" .. preset .. "_" .. fname, "R1.CatD", function()
                local env, st = make_attack_env()
                env._state_ref = st
                local target_tbl = (libname == "_G") and env or env[libname]
                local proxy = setmetatable({}, {
                    __index = target_tbl,
                    __newindex = function(t, k, v) rawset(t, k, v) end,
                })
                env[libname] = proxy
                assert_fail_closed_preload(code, fspec, env, "CatD:proxy_" .. libname)
            end)
        end
    end
end

-- ============================================================================
-- CAT E: METATABLE & GLOBAL SPOOFING
-- ============================================================================

for _, preset in ipairs(PRESETS) do
    for _, fname in ipairs({ "short_str", "multi" }) do
        local fspec = FIXTURES[fname]
        local code = COMPILED[preset][fname]

        suite:test("R1_CatE_getmetatable_string_spoof_" .. preset .. "_" .. fname, "R1.CatE", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local orig_getmt = getmetatable
            env.getmetatable = function(v)
                if type(v) == "string" then
                    return { __index = env.string }
                end
                return orig_getmt(v)
            end
            assert_fail_closed_preload(code, fspec, env, "CatE:getmetatable_str")
        end)

        suite:test("R1_CatE_string_mt_concat_tamper_" .. preset .. "_" .. fname, "R1.CatE", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local smt = getmetatable("")
            local orig_concat = smt and smt.__concat
            if smt then
                smt.__concat = function(a, b) return "TAMPERED_CONCAT" end
            end
            local ok, err = pcall(function()
                assert_fail_closed_preload(code, fspec, env, "CatE:concat_canary")
            end)
            if smt then
                smt.__concat = orig_concat
            end
            assert(ok, err)
        end)

        suite:test("R1_CatE_getfenv_spoof_" .. preset .. "_" .. fname, "R1.CatE", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local fake_env = { _spoof = true }
            env.getfenv = function(_)
                return fake_env
            end
            assert_fail_closed_preload(code, fspec, env, "CatE:getfenv_spoof")
        end)
    end
end

-- ============================================================================
-- CAT F: STACK / DEBUG PROBING & ACTIVE TAMPERING
-- ============================================================================

for _, preset in ipairs(PRESETS) do
    for _, fname in ipairs({ "short_str", "multi" }) do
        local fspec = FIXTURES[fname]
        local code = COMPILED[preset][fname]

        for _, mask in ipairs({ "c", "l", "r", "clr" }) do
            suite:test("R1_CatF_sethook_" .. mask .. "_" .. preset .. "_" .. fname, "R1.CatF", function()
                local env, st = make_attack_env()
                env._state_ref = st
                local old_h, old_m, old_c = debug.gethook()
                local traced = 0
                debug.sethook(function() traced = traced + 1 end, mask)
                local ok, err = pcall(function()
                    assert_fail_closed_preload(code, fspec, env, "CatF:sethook_" .. mask)
                end)
                if old_h then debug.sethook(old_h, old_m, old_c) else debug.sethook() end
                assert(ok, err)
            end)
        end

        suite:test("R1_CatF_debug_getinfo_getlocal_wrapper_" .. preset .. "_" .. fname, "R1.CatF", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local ogi, ogl, ogu = debug.getinfo, debug.getlocal, debug.getupvalue
            env.debug.getinfo = function(...) return ogi(...) end
            env.debug.getlocal = function(...) return ogl(...) end
            env.debug.getupvalue = function(...) return ogu(...) end
            assert_fail_closed_preload(code, fspec, env, "CatF:debug_wrappers")
        end)

        suite:test("R1_CatF_debug_active_setlocal_corrupt_" .. preset .. "_" .. fname, "R1.CatF", function()
            local env, st = make_attack_env()
            env._state_ref = st
            local old_h, old_m, old_c = debug.gethook()
            debug.sethook(function()
                for i = 1, 6 do
                    pcall(debug.setlocal, 2, i, nil)
                end
            end, "c")
            local ok, err = pcall(function()
                assert_fail_closed_preload(code, fspec, env, "CatF:active_setlocal")
            end)
            if old_h then debug.sethook(old_h, old_m, old_c) else debug.sethook() end
            assert(ok, err)
        end)

        for _, sig in ipairs({ "unluac", "deobfuscator" }) do
            suite:test("R1_CatF_traceback_sig_" .. sig .. "_" .. preset .. "_" .. fname, "R1.CatF", function()
                local env, st = make_attack_env()
                env._state_ref = st
                local otb = debug.traceback
                env.debug.traceback = function(...)
                    return tostring(otb(...)) .. "\n\t@" .. sig .. ".lua:1: in main chunk"
                end
                assert_fail_closed_preload(code, fspec, env, "CatF:traceback_" .. sig)
            end)
        end
    end
end

-- ============================================================================
-- CAT G: RUNTIME DATA TAMPERING & ONE-SHOT RETRY NON-BYPASS
-- ============================================================================

local function corrupt_longest_literal(code)
    local best_s, best_e
    local pos = 1
    -- Scan long bracket strings [=*=[...]=*]
    while true do
        local s, e, eq = code:find("%[(=*)%[", pos)
        if not s then break end
        local close_pat = "%]" .. eq .. "%]"
        local cs, ce = code:find(close_pat, e + 1)
        if not cs then break end
        if (cs - e - 1) >= 128 and (not best_s or (cs - e) > (best_e - best_s)) then
            best_s, best_e = e + 1, cs - 1
        end
        pos = ce + 1
    end
    -- Also scan quoted strings if no long literal found
    if not best_s then
        for s, inner, e in code:gmatch('()"([^"\n\\]+)"()') do
            if #inner >= 128 and (not best_s or (e - s) > (best_e - best_s)) then
                best_s, best_e = s + 1, e - 2
            end
        end
    end
    assert(best_s and best_e, "Could not locate >=128 byte payload literal to corrupt")
    local mid = math.floor((best_s + best_e) / 2)
    -- Skip past any leading prefix in first 16 bytes so we corrupt payload body
    if mid < best_s + 16 and best_e >= best_s + 16 then
        mid = best_s + 16
    end
    local ch = code:sub(mid, mid)
    local repl = (ch == "A") and "B" or "A"
    return code:sub(1, mid - 1) .. repl .. code:sub(mid + 1)
end

for _, preset in ipairs(PRESETS) do
    for _, fname in ipairs({ "short_str", "multi" }) do
        local fspec = FIXTURES[fname]
        local code = COMPILED[preset][fname]

        suite:test("R1_CatG_payload_byte_flip_" .. preset .. "_" .. fname, "R1.CatG", function()
            local corrupted = corrupt_longest_literal(code)
            local env, st = make_attack_env()
            env._state_ref = st
            assert_fail_closed_preload(corrupted, fspec, env, "CatG:byte_flip")
        end)
    end

    suite:test("R1_CatG_returned_closure_setupvalue_tamper_" .. preset .. "_multi", "R1.CatG", function()
        local fspec = FIXTURES.multi
        local code = COMPILED[preset].multi
        local env, st = make_attack_env()
        env._state_ref = st
        local fn = assert(E2E.loadstring(code, "@e2e_r1_multi.lua"))
        setfenv(fn, env)
        local ok, gate = pcall(fn)
        assert(ok and type(gate) == "function", "Expected returned closure")
        local uv_name = debug.getupvalue(gate, 1)
        if uv_name ~= nil then
            debug.setupvalue(gate, 1, {})
            local ok2, res2 = pcall(gate, "A")
            assert(st.commit_hits == 0 and (not ok2 or res2 ~= fspec.expected),
                "CatG:setupvalue tamper did not fail closed")
        else
            -- If VM exposes 0 upvalues on returned closure, verify setfenv tamper still fails closed
            setfenv(gate, {})
            local ok2, res2 = pcall(gate, "A")
            assert(st.commit_hits == 0 and (not ok2 or res2 ~= fspec.expected),
                "CatG:sealed_closure tamper did not fail closed")
        end
    end)

    suite:test("R1_CatG_returned_closure_setfenv_tamper_" .. preset .. "_multi", "R1.CatG", function()
        local fspec = FIXTURES.multi
        local code = COMPILED[preset].multi
        local env, st = make_attack_env()
        env._state_ref = st
        local fn = assert(E2E.loadstring(code, "@e2e_r1_multi.lua"))
        setfenv(fn, env)
        local ok, gate = pcall(fn)
        assert(ok and type(gate) == "function", "Expected returned closure")
        setfenv(gate, {})
        local ok2, res2 = pcall(gate, "A")
        assert(st.commit_hits == 0 and (not ok2 or res2 ~= fspec.expected),
            "CatG:setfenv tamper did not fail closed")
    end)
end

suite:test("R1_CatG_oneshot_trap_not_retried_AzureGodUltra", "R1.CatG", function()
    local fspec = FIXTURES.short_str
    local code = COMPILED.AzureGodUltra.short_str
    local env, st = make_attack_env()
    env._state_ref = st
    local orig_gsub = string.gsub
    local triggers = 0
    env.string.gsub = function(...)
        triggers = triggers + 1
        -- Restore clean string.gsub after first trigger (1-shot trap)
        env.string.gsub = orig_gsub
        return orig_gsub(...)
    end
    local ok, res = execute_target(code, fspec, env)
    assert(triggers == 1 and st.entry_hits == 0 and st.commit_hits == 0 and (not ok or res ~= fspec.expected),
        string.format("One-shot trap bypassed via SafeRetryWrapper (triggers=%d, entry=%d, commit=%d, ok=%s, res=%s)",
            triggers, st.entry_hits, st.commit_hits, tostring(ok), tostring(res)))
end)

suite:finish()
