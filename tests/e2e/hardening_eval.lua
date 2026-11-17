-- R2 Opaque-Box Hardening & Anti-Dump Evaluator
-- Evaluates --preset AzureGodUltra --compact and --preset Luraph15_2 --compact across:
--   R2.1: Plaintext source & internal marker leak checks
--   R2.2: Same-seed determinism, cross-seed structural/payload divergence, duplicate-literal diversity
--   R2.3: Runtime anti-dump (string.dump, debug.getupvalue, constant harvesting)
--
-- Exits 0 iff all probes pass.

local script_path = debug.getinfo(1, "S").source:sub(2)
local e2e_dir = script_path:match("^(.*)/[^/]+$") or "."
package.path = e2e_dir .. "/lib/?.lua;" .. package.path

local E2E = require("e2e_common")
local suite = E2E.new_suite("R2_HardeningEval")

local PRESETS = { "AzureGodUltra", "Luraph15_2" }

local R2_FIXTURE = [[
local r2_secret_local_x9 = "R2_SECRET_STR_ALPHA_9182"
local r2_dup_a = "R2_DUP_NONCE_LITERAL_88412"
local r2_dup_b = "R2_DUP_NONCE_LITERAL_88412"
local r2_num_sentinel = 918273645
local r2_tbl = { r2_field_key_z7 = "R2_TOKEN_BETA_7364" }
function R2_GLOBAL_SECRET_FN_Y8(arg)
    return r2_secret_local_x9 .. ":" .. r2_tbl.r2_field_key_z7 .. ":" .. tostring(r2_num_sentinel) .. ":" .. r2_dup_a .. ":" .. r2_dup_b .. ":" .. tostring(arg)
end
return R2_GLOBAL_SECRET_FN_Y8
]]

local R2_EXPECTED_EVAL = "R2_SECRET_STR_ALPHA_9182:R2_TOKEN_BETA_7364:918273645:R2_DUP_NONCE_LITERAL_88412:R2_DUP_NONCE_LITERAL_88412:probe"

local R2_DUP_FIXTURE = [[
local a = "R2_DUP_BLOCK_XYZ_1234567890_ABCDEF"
local b = "R2_DUP_BLOCK_XYZ_1234567890_ABCDEF"
return a .. ":" .. b
]]

local R2_HARVEST_FIXTURE = [[
local harvest_secret = "R2_HARVEST_SECRET_551"
if on_enter then on_enter() end
return function(x)
    if on_commit then on_commit() end
    return harvest_secret .. ":" .. tostring(x)
end
]]

local function strip_line1_header(code)
    -- Strip optional leading long comment header on single-line compact output
    local stripped = code:gsub("^%-%-%[(=*)%[.-%]%1%]%s*", "", 1)
    if stripped == code then
        -- Or line 1 `-- ...` header if multi-line
        stripped = code:gsub("^%-%-[^\r\n]*[\r\n]+", "", 1)
    end
    return stripped
end

local function extract_longest_literal(code)
    local best = ""
    local pos = 1
    while true do
        local s, e, eq = code:find("%[(=*)%[", pos)
        if not s then break end
        local cs, ce = code:find("%]" .. eq .. "%]", e + 1)
        if not cs then break end
        local inner = code:sub(e + 1, cs - 1)
        if #inner > #best then
            best = inner
        end
        pos = ce + 1
    end
    for inner in code:gmatch('"([^"\n\\]+)"') do
        if #inner > #best then
            best = inner
        end
    end
    for inner in code:gmatch("'([^'\n\\]+)'") do
        if #inner > #best then
            best = inner
        end
    end
    return best
end

local function ngrams_4(s)
    local set = {}
    local count = 0
    for i = 1, #s - 3 do
        local g = s:sub(i, i + 3)
        if not set[g] then
            set[g] = true
            count = count + 1
        end
    end
    return set, count
end

local LUA_KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
    ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
    ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
    ["while"] = true,
}

local function extract_ident_set(code)
    -- Remove longest blob so data bytes do not pollute identifier tokens
    local blob = extract_longest_literal(code)
    local scan = code
    if #blob > 0 then
        local s, e = code:find(blob, 1, true)
        if s then
            scan = code:sub(1, s - 1) .. " " .. code:sub(e + 1)
        end
    end
    local set = {}
    local count = 0
    for tok in scan:gmatch("[%a_][%w_]*") do
        if not LUA_KEYWORDS[tok] and not set[tok] then
            set[tok] = true
            count = count + 1
        end
    end
    return set, count
end

local function jaccard(set_a, count_a, set_b, count_b)
    if count_a == 0 and count_b == 0 then
        return 1.0
    end
    local inter = 0
    for k in pairs(set_a) do
        if set_b[k] then
            inter = inter + 1
        end
    end
    local union = count_a + count_b - inter
    if union == 0 then return 0 end
    return inter / union
end

local function has_repeated_block(blob, block_len)
    if #blob < block_len * 2 then
        return false
    end
    local seen = {}
    for i = 1, #blob - block_len + 1 do
        local sub = blob:sub(i, i + block_len - 1)
        local prev = seen[sub]
        if prev and (i - prev) >= block_len then
            return true, sub
        elseif not prev then
            seen[sub] = i
        end
    end
    return false
end

for _, preset in ipairs(PRESETS) do
    local out_12345_a = E2E.compile(R2_FIXTURE, { preset = preset, compact = true, seed = 12345 })
    local out_12345_b = E2E.compile(R2_FIXTURE, { preset = preset, compact = true, seed = 12345, no_cache = true })
    local out_67890 = E2E.compile(R2_FIXTURE, { preset = preset, compact = true, seed = 67890 })
    local out_99999 = E2E.compile(R2_FIXTURE, { preset = preset, compact = true, seed = 99999 })
    local out_246810 = E2E.compile(R2_FIXTURE, { preset = preset, compact = true, seed = 246810 })

    -- ========================================================================
    -- R2.1: Plaintext Source & Internal Marker Leak Scans
    -- ========================================================================

    suite:test("R2_1_single_line_and_source_leaks_" .. preset, "R2.1", function()
        local vok, verr = E2E.validate_compact(out_12345_a)
        assert(vok, verr)
        local body = strip_line1_header(out_12345_a)
        local forbidden_source = {
            "R2_SECRET_STR_ALPHA_9182",
            "R2_TOKEN_BETA_7364",
            "R2_DUP_NONCE_LITERAL_88412",
            "r2_secret_local_x9",
            "r2_field_key_z7",
            "R2_GLOBAL_SECRET_FN_Y8",
            "918273645",
        }
        local leaked = {}
        for _, pat in ipairs(forbidden_source) do
            if body:find(pat, 1, true) then
                leaked[#leaked + 1] = pat
            end
        end
        assert(#leaked == 0, "Leaked source plaintext/identifiers: " .. table.concat(leaked, ", "))
    end)

    suite:test("R2_1_internal_markers_and_branding_" .. preset, "R2.1", function()
        local body = strip_line1_header(out_12345_a)
        local forbidden_markers = {
            "__az_retry",
            "_LPH_",
            "LPH>",
            "AzureVM",
            "Luraph",
            "SafeRetryWrapper",
            "runtime integrity",
            "payload integrity",
        }
        local leaked = {}
        for _, m in ipairs(forbidden_markers) do
            if body:find(m, 1, true) then
                leaked[#leaked + 1] = m
            end
        end
        assert(#leaked == 0, "Leaked internal markers/branding: " .. table.concat(leaked, ", "))
    end)

    -- ========================================================================
    -- R2.2: Same-Seed Determinism, Cross-Seed Divergence & Duplicate Diversity
    -- ========================================================================

    suite:test("R2_2_same_seed_determinism_and_exec_" .. preset, "R2.2", function()
        assert(out_12345_a == out_12345_b, "Same seed 12345 produced non-deterministic outputs")
        local run = E2E.run_code(out_12345_a, { chunkname = "@eval_target.lua" })
        assert(run.ok and type(run.results[1]) == "function", "Failed execution: " .. tostring(run.err))
        local ok_call, val = pcall(run.results[1], "probe")
        assert(ok_call and val == R2_EXPECTED_EVAL, "Returned closure output mismatch: " .. tostring(val))
    end)

    suite:test("R2_2_cross_seed_payload_and_struct_divergence_" .. preset, "R2.2", function()
        local builds = {
            { seed = 12345, code = out_12345_a },
            { seed = 67890, code = out_67890 },
            { seed = 99999, code = out_99999 },
            { seed = 246810, code = out_246810 },
        }
        for i = 1, #builds do
            for j = i + 1, #builds do
                local a, b = builds[i], builds[j]
                assert(a.code ~= b.code, "Identical output for seeds " .. a.seed .. " and " .. b.seed)

                local blob_a = extract_longest_literal(a.code)
                local blob_b = extract_longest_literal(b.code)
                assert(#blob_a >= 64 and #blob_b >= 64, "Encoded payload blob unexpectedly tiny")
                local ga, ca = ngrams_4(blob_a)
                local gb, cb = ngrams_4(blob_b)
                local blob_sim = jaccard(ga, ca, gb, cb)
                assert(blob_sim < 0.20,
                    string.format("Payload 4-gram Jaccard too high (%.3f >= 0.20) between seeds %d & %d",
                        blob_sim, a.seed, b.seed))

                local ia, ica = extract_ident_set(a.code)
                local ib, icb = extract_ident_set(b.code)
                local id_sim = jaccard(ia, ica, ib, icb)
                assert(id_sim < 0.25,
                    string.format("Identifier Jaccard overlap too high (%.3f >= 0.25) between seeds %d & %d",
                        id_sim, a.seed, b.seed))
            end
        end
    end)

    suite:test("R2_2_duplicate_literal_nonce_diversity_" .. preset, "R2.2", function()
        local dup_out = E2E.compile(R2_DUP_FIXTURE, { preset = preset, compact = true, seed = 55555 })
        assert(not dup_out:find("R2_DUP_BLOCK_XYZ_1234567890_ABCDEF", 1, true), "Duplicate literal leaked in plaintext")
        local blob = extract_longest_literal(dup_out)
        local rep, sub = has_repeated_block(blob, 24)
        assert(not rep, "Duplicate literal produced repeated identical >=24-byte ciphertext block: " .. tostring(sub))
        local run = E2E.run_code(dup_out)
        assert(run.ok and run.results[1] == "R2_DUP_BLOCK_XYZ_1234567890_ABCDEF:R2_DUP_BLOCK_XYZ_1234567890_ABCDEF")
    end)

    -- ========================================================================
    -- R2.3: Runtime Anti-Dump & Extraction Resistance
    -- ========================================================================

    suite:test("R2_3_string_dump_resistance_" .. preset, "R2.3", function()
        local run = E2E.run_code(out_12345_a, { chunkname = "@eval_target.lua" })
        assert(run.ok and type(run.results[1]) == "function", "Target did not return closure")
        local closure = run.results[1]

        local function check_dump_safe(target_fn, label)
            local dok, dumped = pcall(string.dump, target_fn)
            if not dok then
                return true
            end
            assert(#dumped <= 1024, string.format("%s dumped %d bytes (>1024B VM engine leak)", label, #dumped))
            for _, tok in ipairs({ "R2_SECRET_STR_ALPHA_9182", "ins", "ks", "ps", "AzureVM", "Luraph" }) do
                assert(not dumped:find(tok, 1, true), label .. " dumped bytes leaked token: " .. tok)
            end
            local reload_fn = E2E.loadstring(dumped)
            if reload_fn then
                local rok, rval = pcall(reload_fn, "probe")
                assert(not (rok and tostring(rval):find("R2_SECRET_STR_ALPHA_9182", 1, true)),
                    label .. " dumped stub replayed user secret")
            end
            return true
        end

        check_dump_safe(closure, "returned_closure")
        for i = 1, 30 do
            local uv_name, uv_val = debug.getupvalue(closure, i)
            if uv_name == nil then break end
            if type(uv_val) == "function" then
                check_dump_safe(uv_val, "upvalue_fn[" .. tostring(uv_name) .. "]")
            end
        end
    end)

    suite:test("R2_3_getupvalue_proto_shielding_" .. preset, "R2.3", function()
        local run = E2E.run_code(out_12345_a, { chunkname = "@eval_target.lua" })
        assert(run.ok and type(run.results[1]) == "function")
        local closure = run.results[1]

        local proto_keys = { "ins", "ks", "ps", "om", "oa", "lm" }
        for i = 1, 30 do
            local uv_name, uv_val = debug.getupvalue(closure, i)
            if uv_name == nil then break end
            if type(uv_val) == "table" then
                local hits = 0
                local found = {}
                for _, pk in ipairs(proto_keys) do
                    if rawget(uv_val, pk) ~= nil then
                        hits = hits + 1
                        found[#found + 1] = pk
                    end
                end
                assert(hits < 2,
                    string.format("Upvalue %d (%s) exposes prototype table keys: %s",
                        i, tostring(uv_name), table.concat(found, ",")))
                for _, v in pairs(uv_val) do
                    assert(v ~= "R2_SECRET_STR_ALPHA_9182",
                        "Upvalue table exposes plaintext secret string")
                end
            elseif uv_val == "R2_SECRET_STR_ALPHA_9182" then
                error("Upvalue " .. i .. " directly exposes plaintext secret string")
            end
        end
    end)

    local harvest_out = E2E.compile(R2_HARVEST_FIXTURE, { preset = preset, compact = true, seed = 33333 })

    for _, probe_name in ipairs({ "table.concat", "string.char", "string.byte", "getmetatable", "rawget" }) do
        suite:test("R2_3_harvest_" .. probe_name:gsub("%.", "_") .. "_" .. preset, "R2.3", function()
            local captured = false
            local entry_hits, commit_hits = 0, 0
            local env = E2E.make_clean_env({
                on_enter = function() entry_hits = entry_hits + 1 end,
                on_commit = function() commit_hits = commit_hits + 1 end,
            })

            local function inspect_val(v)
                if type(v) == "string" and v:find("R2_HARVEST_SECRET_551", 1, true) then
                    captured = true
                elseif type(v) == "table" then
                    for _, item in pairs(v) do
                        if type(item) == "string" and item:find("R2_HARVEST_SECRET_551", 1, true) then
                            captured = true
                        end
                    end
                end
            end

            if probe_name == "table.concat" then
                local t = {}
                for k, v in pairs(table) do t[k] = v end
                local orig = table.concat
                t.concat = function(arr, ...)
                    inspect_val(arr)
                    local r = orig(arr, ...)
                    inspect_val(r)
                    return r
                end
                env.table = t
            elseif probe_name == "string.char" or probe_name == "string.byte" then
                local s = {}
                for k, v in pairs(string) do s[k] = v end
                local field = probe_name:match("%.(.+)$")
                local orig = string[field]
                s[field] = function(...)
                    local r = orig(...)
                    inspect_val(r)
                    return r
                end
                env.string = s
            elseif probe_name == "getmetatable" then
                local orig = getmetatable
                env.getmetatable = function(v)
                    local r = orig(v)
                    inspect_val(r)
                    return r
                end
            elseif probe_name == "rawget" then
                local orig = rawget
                env.rawget = function(t, k)
                    local r = orig(t, k)
                    inspect_val(r)
                    return r
                end
            end

            local fn = assert(E2E.loadstring(harvest_out, "@eval_harvest.lua"))
            setfenv(fn, env)
            local ok, gate = pcall(fn)
            local ok2, res2 = false, nil
            if ok and type(gate) == "function" then
                ok2, res2 = pcall(gate, "Y")
            end
            local clean_completed = ok and ok2 and commit_hits > 0 and res2 == "R2_HARVEST_SECRET_551:Y"
            assert((not clean_completed) or (not captured),
                probe_name .. " harvested R2_HARVEST_SECRET_551 while script completed cleanly")
        end)
    end
end

suite:finish()
