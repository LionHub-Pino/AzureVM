local Runtime = require("prometheus.azure_vm.runtime")
local Generator = {}

local POW2_16 = 65536
local POW2_17 = 131072
local POW2_32 = 4294967296
local POW2_34 = 17179869184
local DG_MOD  = 4294967291

-- Canonical 8-byte non-retryable trap sentinel (never emitted in plaintext)
local SENTINEL_BYTES = { 143, 26, 196, 87, 226, 57, 155, 13 }

-- =====================================================================
-- Pure-Lua 32-bit ARX PRNG (deterministic across Lua 5.1 / LuaJIT / Luau)
-- =====================================================================
local function mul32(a, b)
    a = a % POW2_32
    b = b % POW2_32
    local a_lo = a % POW2_16
    local a_hi = math.floor(a / POW2_16)
    return ((a_lo * b) + ((a_hi * b) % POW2_16) * POW2_16) % POW2_32
end

local function rotl32(x, r)
    x = x % POW2_32
    r = r % 32
    if r == 0 then return x end
    local q = 2 ^ (32 - r)
    local hi = math.floor(x / q)
    local lo = x - hi * q
    return lo * (2 ^ r) + hi
end

local function make_gen_prng(seed, salt)
    local s0 = ((math.floor(tonumber(seed) or 1) % POW2_32) + 2654435761) % POW2_32
    local s1 = ((salt or 0) + 2246822519) % POW2_32
    local s2 = (mul32(s0, 3266489917) + 668265263) % POW2_32
    local s3 = (rotl32(s0, 13) + mul32(s1, 374761393)) % POW2_32
    local function next32()
        local t = (s0 + rotl32(s1, 7) + mul32(s2, 2654435761)) % POW2_32
        s0 = s1
        s1 = s2
        s2 = s3
        s3 = (rotl32(t, 11) + mul32(s3, 2246822519) + 1) % POW2_32
        return (s3 + rotl32(s0, 17)) % POW2_32
    end
    for _ = 1, 16 do next32() end
    local obj = {}
    function obj:next32() return next32() end
    function obj:range(lo, hi) return lo + (next32() % (hi - lo + 1)) end
    function obj:odd17() return 65537 + (next32() % 32768) * 2 end
    function obj:shuffle(t)
        for i = #t, 2, -1 do
            local j = 1 + (next32() % i)
            t[i], t[j] = t[j], t[i]
        end
        return t
    end
    return obj
end

-- =====================================================================
-- Polymorphic identifier generator (Lua 5.1 + Luau keyword & global safe)
-- =====================================================================
local function make_name_gen(seed)
    local rng = make_gen_prng(seed, 1938472911)
    local used = {
        ["and"]=true,["break"]=true,["continue"]=true,["do"]=true,["else"]=true,["elseif"]=true,
        ["end"]=true,["false"]=true,["for"]=true,["function"]=true,["if"]=true,
        ["in"]=true,["local"]=true,["nil"]=true,["not"]=true,["or"]=true,
        ["repeat"]=true,["return"]=true,["then"]=true,["true"]=true,["until"]=true,
        ["while"]=true,["_G"]=true,["_ENV"]=true,["string"]=true,["table"]=true,["math"]=true,
        ["debug"]=true,["coroutine"]=true,["select"]=true,["pcall"]=true,["xpcall"]=true,
        ["type"]=true,["error"]=true,["assert"]=true,["tostring"]=true,["tonumber"]=true,
        ["pairs"]=true,["ipairs"]=true,["next"]=true,["rawget"]=true,["rawequal"]=true,
        ["setmetatable"]=true,["getmetatable"]=true,["unpack"]=true,["loadstring"]=true,
        ["load"]=true,["getfenv"]=true,["setfenv"]=true,["_az_capscheck"]=true,
    }
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local first = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
    return function()
        local r
        repeat
            local len = rng:range(3, 7)
            local f_idx = rng:range(1, #first)
            r = first:sub(f_idx, f_idx)
            for _ = 2, len do
                local c_idx = rng:range(1, #chars)
                r = r .. chars:sub(c_idx, c_idx)
            end
        until not used[r]
        used[r] = true
        return r
    end
end

-- =====================================================================
-- Helpers for zero-plaintext v[c] byte expressions & collision-safe brackets
-- =====================================================================
local function bracket_literal(s)
    local eq = "="
    while s:find("]" .. eq .. "]", 1, true) do
        eq = eq .. "="
    end
    return "[" .. eq .. "[" .. s .. "]" .. eq .. "]"
end

local function encode_vtab_bytes(bytes, vtab_var, rng)
    local parts = {}
    for i = 1, #bytes do
        local b = bytes[i]
        local k = rng:range(19, 233)
        local enc = (b + k) % 256
        parts[i] = string.format("%s[(%d-%d)%%256]", vtab_var, enc, k)
    end
    return table.concat(parts, "..")
end

local function encode_vtab_str(s, vtab_var, rng)
    local bytes = {}
    for i = 1, #s do bytes[i] = s:byte(i) end
    return encode_vtab_bytes(bytes, vtab_var, rng)
end

local function subst(tmpl, map)
    return (tmpl:gsub("@@([A-Z0-9_]+)@@", function(k)
        return map[k] or ("@@" .. k .. "@@")
    end))
end

local function minify(code)
    local res = {}
    for line in code:gmatch("[^\r\n]+") do
        local t = line:match("^%s*(.-)%s*$")
        if t ~= "" and not t:match("^%-%-") then
            res[#res + 1] = t
        end
    end
    return table.concat(res, " ")
end

-- =====================================================================
-- Polymorphic decoy opcode handler generator (no hardcoded locals/params)
-- =====================================================================
local function gen_decoys(disp_fn, formal_params, reg_name, used_ops, density, rng, V, bank_split)
    local HL = {
        t = V.hl_t, x = V.hl_q, y = V.hl_w, z = V.hl_s,
    }
    local A, B, C, BX, SBX = V.h_a, V.h_b, V.h_c, V.h_bx, V.h_sbx
    local TY, FL = V.typefn, V.floor
    local templates = {
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s[%s%%8] %s[%s%%8]=%s end", formal_params, HL.t, R, A, R, A, HL.t) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=(%s+%s*%s)%%256 %s[%s%%8]=%s end", formal_params, HL.t, A, B, C, R, A, HL.t) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)if %s>0 then %s[%s%%8]=%s[%s%%8]end end", formal_params, B, R, A, R, B) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s[%s%%8]if %s(%s)==\"number\"then %s[%s%%8]=%s%%256 end end", formal_params, HL.x, R, B, TY, HL.x, R, A, HL.x) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s,%s=%s[%s%%8],%s[%s%%8]if %s(%s)==\"number\"and %s(%s)==\"number\"then %s[%s%%8]=(%s+%s)%%65536 end end", formal_params, HL.x, HL.y, R, B, R, C, TY, HL.x, TY, HL.y, R, A, HL.x, HL.y) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s,%s=%s[%s%%8],%s[%s%%8]if %s(%s)==\"number\"and %s(%s)==\"number\"then %s[%s%%8]=(%s-%s)%%65536 end end", formal_params, HL.x, HL.y, R, B, R, C, TY, HL.x, TY, HL.y, R, A, HL.x, HL.y) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s,%s=%s[%s%%8],%s[%s%%8]if %s(%s)==\"number\"and %s(%s)==\"number\"then %s[%s%%8]=(%s*%s)%%65536 end end", formal_params, HL.x, HL.y, R, B, R, C, TY, HL.x, TY, HL.y, R, A, HL.x, HL.y) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s[%s%%8]if %s(%s)==\"number\"then %s[%s%%8]=%s(%s)end end", formal_params, HL.x, R, B, TY, HL.x, R, A, FL, HL.x) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s[%s%%8]if %s(%s)==\"number\"then %s[%s%%8]=-%s end end", formal_params, HL.x, R, B, TY, HL.x, R, A, HL.x) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s[%s%%8]if %s(%s)==\"number\"and %s>0 then %s[%s%%8]=%s%%%s end end", formal_params, HL.x, R, B, TY, HL.x, C, R, A, HL.x, C) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s%%256 if %s>127 then %s=%s-256 end %s[%s%%8]=%s end", formal_params, HL.t, A, HL.t, HL.t, HL.t, R, A, HL.t) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s%%512 if %s>255 then %s=%s-256 end %s[%s%%8]=%s end", formal_params, HL.t, BX, HL.t, HL.t, HL.t, R, A, HL.t) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s if %s<0 then %s=-%s end %s[%s%%8]=%s%%256 end", formal_params, HL.t, SBX, HL.t, HL.t, HL.t, R, A, HL.t) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)if %s[%s%%8]then %s[%s%%8]=1 else %s[%s%%8]=0 end end", formal_params, R, B, R, A, R, A) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s(%s[%s%%8])if %s==\"table\"or %s==\"string\"then %s[%s%%8]=#%s[%s%%8]end end", formal_params, HL.t, TY, R, B, HL.t, HL.t, R, A, R, B) end,
        function(op, R) return disp_fn(op) .. string.format("=function(%s)local %s=%s[%s%%8]if %s(%s)==\"table\"and %s<8 then %s[%s%%8]=%s[%s[%s%%8]]end end", formal_params, HL.t, R, B, TY, HL.t, C, R, A, HL.t, R, C) end,
    }
    density = tonumber(density) or 1.0
    if density < 0 then density = 0 elseif density > 2 then density = 2 end
    local count = math.floor(rng:range(25, 45) * density + 0.5)
    local decoys = {}
    local decoy_ops = {}
    for idx = 1, count do
        local op
        if bank_split then
            -- Populate both banks symmetrically when 2-bank split is active
            local want_low = (idx % 2 == 1)
            repeat
                op = want_low and rng:range(1, bank_split - 1) or rng:range(bank_split, 250)
            until not used_ops[op]
        else
            repeat op = rng:range(1, 250) until not used_ops[op]
        end
        used_ops[op] = true
        local tmpl = templates[rng:range(1, #templates)]
        decoys[#decoys + 1] = tmpl(op, reg_name)
        decoy_ops[#decoy_ops + 1] = op
    end
    return decoys, decoy_ops
end

-- =====================================================================
-- MAIN EMIT FUNCTION
-- =====================================================================
function Generator.emit(encoded_root, encoder_instance, options)
    options = options or {}
    local retries = Runtime.validate(options)
    local protected_init = options.RuntimeChecks or retries > 0
    local trap_harness = (options.TrapHarness == true)
    local use_join = (options.RuntimeChecks == true) or trap_harness
    local op_map = encoder_instance.opcode_map
    local lph_ver = options.LuraphVersion or 15
    local spec = encoder_instance.vm_spec

    local blob, pad, checksum = encoder_instance:serialize_to_blob(encoded_root)

    local gen_rng = make_gen_prng(encoder_instance.seed, 987654321)

    local O = {}
    local O2 = {}
    local used_ops = {}
    for i = 0, 37 do
        O[i] = op_map[i]
        used_ops[op_map[i]] = true
        if encoder_instance.opcode_map2 and encoder_instance.opcode_map2[i] then
            O2[i] = encoder_instance.opcode_map2[i]
            used_ops[O2[i]] = true
        else
            O2[i] = op_map[i]
        end
    end

    -- Generate polymorphic variable names for 100% of identifiers
    local ng = make_name_gen(encoder_instance.seed + 7919)
    local V = {}
    local var_keys = {
        -- Runtime decoder & helpers
        "byte","sub","char","gsub","setmt","pcall","host_pcall_fn","typefn","tostr","assert","loadstr","unpack","floor","vtab",
        "pack","voff","a85dec","a85s","a85i","rawbin","a85n","a85t","a85k","b1","b2","b3","b4","b5","d1","d2","d3","d4","d5","a85y",
        "mksbox","s1","s1inv","s2","s2inv","si","sj","st0","st1","shi","slo",
        "rotl","rq","rhi","rr","join","jtbl","jn","jw","ji","js","jj",
        "r16","r32","r64","rs","ri","ra","rb","rc2","rd2","re2","rx","rsign","rexp","rmant",
        "decode","dbin","dpad","dn","dout","ds0","ds1","denc","dks",
        "readp","pbin","ppos","proto","strings","p_idx","p_ent","p_C","p_st0","p_st1","p_x","p_b","p_dec","p_ks","p_slen","p_non","p_s2",
        "p_ni","p_nk","p_np2","p_ch","p_t","p_rm","p_eb","p_mk","p_rb","p_j",
        "bin_v","chk_a","chk_b","chk_i","ast_v",
        -- VM engine, vault & integrity
        "strlib","tbllib","dbglib","corolib","errorfn","selectfn","absfn","getmtfn","concat_ref","pairsfn","orig_dump","base_ex","base_pr","fhash","fh_s","fh_h","fh_i","di",
        "vpr","venv","vuv","tokmt","owned","tramp","tok","pr_v","env_v","uv_v","p_in","e_in","u_in","w_fn","w_tok","cur_env",
        "wrap","exec","poison","call_cnt","active_ins","trap","tr_msg","tr_ins","tr_t","tr_i","tr_s",
        "parse","pw","ppe","play","pmode","pop","pa","pb","pc","pbx",
        "disp","dispref","disp1","dispref1","raw_disp","raw_dispref","raw_disp1","raw_dispref1","nops_chk","ksum_chk","disp_k","disp_v",
        -- __EXEC internals
        "pr","env","upvals","reg","vargs","openuvs","stop","ipc","storage","stride","shift","pk_k","pk_v",
        "vlen","instr","konst","protos","layout","rk","rk_i","closeuv","lim","uv_x","nextk","nk_ipc","nk_pe","nk_plo","nk_phi","nk_h","nk_hlo","nk_hhi","nk_rot",
        "pom","poa","ppk","pdg","dg_v","dg_m","dg_i","root_p","dec_reg","dacc","d_idx","d_val",
        -- Handler params & internal locals
        "h_r","h_a","h_b","h_c","h_bx","h_sbx",
        "hl_i","hl_u","hl_q","hl_w","hl_s","hl_g","hl_n","hl_r","hl_l","hl_cb","hl_var","hl_pe","hl_e","hl_nk","hl_nw","hl_cbx","hl_o","hl_t","hl_p","hl_uv","hl_pb","hl_op",
        -- Close loop & checks
        "ctr","c_e","c_pe","c_k","c_w","c_op","c_a","c_b","c_c","c_bx","c_sbx","c_f","c_rf","c_tk","c_r","c_df","c_drf","c_dv",
        "genv","c_can","c_k2","c_strmt","c_sa","c_sb","c_sab","c_ok","c_err","c_info","c_co","c_ef","c_tb","c_ok2","c_res","rok","hrok","magic_boot",
    }
    for _, k in ipairs(var_keys) do V[k] = ng() end

    -- Permute handler parameter order (6! = 720 combinations)
    local p_vars = { V.h_r, V.h_a, V.h_b, V.h_c, V.h_bx, V.h_sbx }
    local p_order = gen_rng:shuffle({ 1, 2, 3, 4, 5, 6 })
    local formal_params_list = {}
    for idx = 1, 6 do formal_params_list[idx] = p_vars[p_order[idx]] end
    local formal_params = table.concat(formal_params_list, ",")

    -- Helper to format call arguments in matching permuted order
    local function perm_call_args(arg6)
        local out = {}
        for idx = 1, 6 do out[idx] = arg6[p_order[idx]] end
        return table.concat(out, ",")
    end

    -- Polymorphic v[c] loop topology (4 modes)
    local v_mode = gen_rng:range(0, 3)
    local vtab_init_code
    if v_mode == 0 then
        vtab_init_code = string.format("for %s=0,255 do %s[%s]=%s(%s)end;", V.si, V.vtab, V.si, V.char, V.si)
    elseif v_mode == 1 then
        vtab_init_code = string.format("for %s=255,0,-1 do %s[%s]=%s(%s)end;", V.si, V.vtab, V.si, V.char, V.si)
    elseif v_mode == 2 then
        local off = gen_rng:range(17, 239)
        vtab_init_code = string.format("for %s=0,255 do local %s=(%s+%d)%%256 %s[%s]=%s(%s)end;", V.si, V.sj, V.si, off, V.vtab, V.sj, V.char, V.sj)
    else
        vtab_init_code = string.format("for %s=0,127 do %s[%s]=%s(%s) %s[%s+128]=%s(%s+128)end;", V.si, V.vtab, V.si, V.char, V.si, V.vtab, V.si, V.char, V.si)
    end

    -- Zero-plaintext error / sentinel / tool strings
    local err_decode_expr  = encode_vtab_str("AzureVM payload decode error: invalid payload", V.vtab, gen_rng)
    local err_payload_expr = encode_vtab_str("AzureVM payload integrity check failed", V.vtab, gen_rng)
    local err_runtime_expr = encode_vtab_str("AzureVM runtime integrity check failed", V.vtab, gen_rng)
    local sentinel_expr    = encode_vtab_bytes(SENTINEL_BYTES, V.vtab, gen_rng)

    -- Random split string for concat canary (replaces "lura".."ph")
    local split_a = ng() .. ng()
    local split_b = ng() .. ng()

    local pkeys = spec.proto_keys
    local prefix_str = trap_harness and spec.prefix or "LPH>"
    local v_off_val = #prefix_str + 1
    local payload_s = bracket_literal(prefix_str .. blob:gsub("\n", ""))
    local a85_lit = bracket_literal(spec.a85_str)
    local a85_zero5_lit = bracket_literal(string.rep(spec.a85_alpha[0], 5))

    -- Build __READP field-reading & section-reading snippets from vm_spec
    local read_field_lines = {}
    local field_readers = {
        np = string.format("local %s=%s(%s,%s)%s=%s+1", V.p_C, V.byte, V.pbin, V.ppos, V.ppos, V.ppos),
        up = string.format("local %s=%s(%s,%s)%s=%s+1", V.p_x, V.byte, V.pbin, V.ppos, V.ppos, V.ppos),
        ms = string.format("local %s=%s(%s,%s)%s=%s+1", V.p_b, V.byte, V.pbin, V.ppos, V.ppos, V.ppos),
        iv = string.format("local %s=%s(%s,%s)%s=%s+1", V.p_dec, V.byte, V.pbin, V.ppos, V.ppos, V.ppos),
        om = string.format("local %s=%s(%s,%s)%s=%s+1", V.p_ks, V.byte, V.pbin, V.ppos, V.ppos, V.ppos),
        oa = string.format("local %s=%s(%s,%s)%s=%s+1", V.p_slen, V.byte, V.pbin, V.ppos, V.ppos, V.ppos),
        lm = string.format("local %s=%s(%s,%s)%s=%s+1", V.p_non, V.byte, V.pbin, V.ppos, V.ppos, V.ppos),
        pk = string.format("local %s=%s(%s,%s)%s=%s+2", V.p_s2, V.r16, V.pbin, V.ppos, V.ppos, V.ppos),
        dg = string.format("local %s=%s(%s,%s)%s=%s+4", V.p_ni, V.r32, V.pbin, V.ppos, V.ppos, V.ppos),
    }
    local field_var_for = {
        np = V.p_C, up = V.p_x, ms = V.p_b, iv = V.p_dec, om = V.p_ks,
        oa = V.p_slen, lm = V.p_non, pk = V.p_s2, dg = V.p_ni,
    }
    for _, fname in ipairs(spec.proto_field_order) do
        read_field_lines[#read_field_lines + 1] = field_readers[fname]
    end
    local proto_init_pairs = {}
    for _, fname in ipairs(spec.proto_field_order) do
        proto_init_pairs[#proto_init_pairs + 1] = string.format("[%d]=%s", pkeys[fname], field_var_for[fname])
    end
    proto_init_pairs[#proto_init_pairs + 1] = string.format("[%d]={}", pkeys.ins)
    proto_init_pairs[#proto_init_pairs + 1] = string.format("[%d]={}", pkeys.ks)
    proto_init_pairs[#proto_init_pairs + 1] = string.format("[%d]={}", pkeys.ps)

    -- Const branch generator in shuffled order
    local sk = encoder_instance.str_keys
    local sm = encoder_instance.sm
    local nk = encoder_instance.num_keys
    local nm = encoder_instance.nm
    local perm8 = encoder_instance.perm8
    local tags = spec.const_tags

    local perm8_assigns = {}
    for idx = 1, 8 do
        perm8_assigns[idx] = string.format("local %s=%s(%s,%s+%d)", V.p_eb, V.byte, V.pbin, V.ppos, idx - 1)
    end
    -- Build unrolled 8-byte decrypt loop for t == num (exact inverse of encrypt_number_f2)
    local num_decrypt_code = string.format([==[
local %s=%s(%s,%s)%s=%s+4
local %s={}
local %s=%s((((%d+%s)%%4294967296)*%d+%s[%d]*65537+%s)%%4294967296,%d)
local %s=(%d+(%s*%d)%%4294967296+%s[%d]*257)%%4294967296
local %s={%s}
for %s=1,8 do
local %s=%s(%s,%s+%s-1)
local %s=(%s[(%s+%s)%%256]+%s(%s/16777216)+%s(%s/65536))%%256
%s[%s[%s]]=(%s[%s]-%s-%s+256)%%256
%s=%s((((%s+%s+%s)%%4294967296)*%d)%%4294967296,%d)
%s=(((%s+%s(%s/65536)+(%s%%65536)*257+%s)%%4294967296)*%d)%%4294967296
end
%s[%d][%s]=%s(%s)
%s=%s+8]==],
        V.p_non, V.r32, V.pbin, V.ppos, V.ppos, V.ppos,
        V.p_rb,
        V.p_st0, V.rotl, nk[1], V.p_non, nm[1], V.proto, pkeys.pk, V.p_idx, encoder_instance.nr0,
        V.p_st1, nk[2], V.p_non, nm[2], V.proto, pkeys.pk,
        V.p_C, table.concat(perm8, ","),
        V.p_j,
        V.p_eb, V.byte, V.pbin, V.ppos, V.p_j,
        V.p_ks, V.s1, V.p_st0, V.p_st1, V.floor, V.p_st0, V.floor, V.p_st1,
        V.p_rb, V.p_C, V.p_j, V.s2inv, V.p_eb, V.p_ks, V.p_j,
        V.p_st0, V.rotl, V.p_st0, V.p_eb, V.p_j, nm[1], encoder_instance.nr0,
        V.p_st1, V.p_st1, V.floor, V.p_st0, V.p_st0, V.p_eb, nm[2],
        V.proto, pkeys.ks, V.p_idx, V.r64, V.p_rb,
        V.ppos, V.ppos)

    local bool_decrypt_code = string.format([[
local %s,%s=%s(%s,%s,%s+1)%s=%s+2
local %s=(%s[(%s+%d+%s[%d]+%s)%%256]+%s(%d/256))%%256
local %s=(%s-%s+256)%%256
if %s(%s/2)~=(%s%%128)then error(%s,0)end
%s[%d][%s]=(%s%%2==1)]],
        V.p_rm, V.p_eb, V.byte, V.pbin, V.ppos, V.ppos, V.ppos, V.ppos,
        V.p_mk, V.s1, V.p_rm, encoder_instance.bool_key, V.proto, pkeys.pk, V.p_idx, V.floor, encoder_instance.bool_key,
        V.p_dec, V.p_eb, V.p_mk,
        V.floor, V.p_dec, V.p_rm, err_payload_expr,
        V.proto, pkeys.ks, V.p_idx, V.p_dec)

    local str_read_code = string.format([[
local %s=%s(%s,%s)%s=%s+4
local %s=%s(%s,%s)%s=%s+4
local %s=%s(%s,%s,%s+%s-1)%s=%s+%s
%s[%s]={%s,%s}]],
        V.p_slen, V.r32, V.pbin, V.ppos, V.ppos, V.ppos,
        V.p_non, V.r32, V.pbin, V.ppos, V.ppos, V.ppos,
        V.p_s2, V.sub, V.pbin, V.ppos, V.ppos, V.p_slen, V.ppos, V.ppos, V.p_slen,
        V.strings, V.p_idx, V.p_s2, V.p_non)

    local nil_read_code = string.format("%s[%d][%s]=nil", V.proto, pkeys.ks, V.p_idx)

    local branch_bodies = {
        [0] = nil_read_code,
        [1] = bool_decrypt_code,
        [3] = num_decrypt_code,
        [4] = str_read_code,
    }
    local const_branches = {}
    for bi, ctype in ipairs(spec.const_branch_order) do
        local kw = (bi == 1) and "if" or "elseif"
        const_branches[#const_branches + 1] = string.format("%s %s==%d then\n%s", kw, V.p_t, tags[ctype], branch_bodies[ctype])
    end
    const_branches[#const_branches + 1] = string.format("else error(%s,0) end", err_payload_expr)

    local sec_ins_code = string.format([[
local %s=%s(%s,%s)%s=%s+4
for %s=1,%s do
local %s,%s,%s,%s,%s=%s(%s,%s,%s+4)%s=%s+5
%s[%d][%s]=%s+%s*256+%s*65536+%s*16777216+%s*4294967296
end]],
        V.p_ni, V.r32, V.pbin, V.ppos, V.ppos, V.ppos,
        V.p_idx, V.p_ni,
        V.ra, V.rb, V.rc2, V.rd2, V.re2, V.byte, V.pbin, V.ppos, V.ppos, V.ppos, V.ppos,
        V.proto, pkeys.ins, V.p_idx, V.ra, V.rb, V.rc2, V.rd2, V.re2)

    local str_join_expr = use_join
        and string.format("%s(%s,#%s)", V.join, V.p_C, V.p_s2)
        or string.format("table.concat(%s)", V.p_C)

    local sec_ks_code = string.format([[
local %s=%s(%s,%s)%s=%s+4
for %s=0,%s-1 do
local %s=%s(%s,%s)%s=%s+1
%s
end
%s(%s[%d],{__index=function(_,%s)
local %s=%s[%s]
if not %s then return nil end
local %s=%s[1]
local %s=%s[2]
local %s={}
local %s=%s((((%d+%s)%%4294967296)*%d+%d)%%4294967296,%d)
local %s=(%d+(%s*%d)%%4294967296+%d)%%4294967296
for %s=1,2 do
%s=%s((((%s+%s+1)%%4294967296)*%d)%%4294967296,%d)
%s=(((%s+%s+%d)%%4294967296)*%d)%%4294967296
end
for %s=1,#%s do
local %s=%s(%s,%s)
local %s=(%s[(%s+%s)%%256]+%s(%s/16777216)+%s(%s/65536))%%256
local %s=(%s[%s]-%s-(%s%%256)+512)%%256
%s[%s]=%s[%s]
%s=%s((((%s+%s+%s)%%4294967296)*%d)%%4294967296,%d)
%s=(((%s+%s(%s/65536)+(%s%%65536)*257+%s)%%4294967296)*%d)%%4294967296
end
return %s
end})]],
        V.p_nk, V.r32, V.pbin, V.ppos, V.ppos, V.ppos,
        V.p_idx, V.p_nk,
        V.p_t, V.byte, V.pbin, V.ppos, V.ppos, V.ppos,
        table.concat(const_branches, "\n"),
        V.setmt, V.proto, pkeys.ks, V.p_idx,
        V.p_ent, V.strings, V.p_idx,
        V.p_ent,
        V.p_s2, V.p_ent,
        V.p_non, V.p_ent,
        V.p_C,
        V.p_st0, V.rotl, sk[1], V.p_non, sm[1], sk[2], encoder_instance.sr0,
        V.p_st1, sk[3], V.p_non, sm[2], sk[4],
        V.p_x,
        V.p_st0, V.rotl, V.p_st0, V.p_st1, sm[1], encoder_instance.sr0,
        V.p_st1, V.p_st1, V.p_st0, sk[4], sm[2],
        V.p_x, V.p_s2,
        V.p_b, V.byte, V.p_s2, V.p_x,
        V.p_ks, V.s1, V.p_st0, V.p_st1, V.floor, V.p_st0, V.floor, V.p_st1,
        V.p_dec, V.s2inv, V.p_b, V.p_ks, V.p_x,
        V.p_C, V.p_x, V.vtab, V.p_dec,
        V.p_st0, V.rotl, V.p_st0, V.p_b, V.p_x, sm[1], encoder_instance.sr0,
        V.p_st1, V.p_st1, V.floor, V.p_st0, V.p_st0, V.p_b, sm[2],
        str_join_expr)

    local sec_ps_code = string.format([[
local %s=%s(%s,%s)%s=%s+4
for %s=0,%s-1 do
local %s;%s,%s=%s(%s,%s)%s[%d][%s]=%s
end]],
        V.p_np2, V.r32, V.pbin, V.ppos, V.ppos, V.ppos,
        V.p_idx, V.p_np2,
        V.p_ch, V.p_ch, V.ppos, V.readp, V.pbin, V.ppos, V.proto, pkeys.ps, V.p_idx, V.p_ch)

    local sec_map = { ins = sec_ins_code, ks = sec_ks_code, ps = sec_ps_code }
    local ordered_secs = {}
    for _, sname in ipairs(spec.section_order) do
        ordered_secs[#ordered_secs + 1] = sec_map[sname]
    end

    local decode_join_expr = use_join
        and string.format("%s(%s,%s)", V.join, V.dout, V.dn)
        or string.format("table.concat(%s)", V.dout)

    local join_def_code = use_join and string.format([[
local function %s(%s,%s)
if %s<=0 then return "" end
if %s==1 then return %s[1] end
while %s>1 do
local %s,%s=0,1
while %s+7<=%s do
%s=%s+1
%s[%s]=%s[%s]..%s[%s+1]..%s[%s+2]..%s[%s+3]..%s[%s+4]..%s[%s+5]..%s[%s+6]..%s[%s+7]
%s=%s+8
end
if %s<=%s then
local %s=%s[%s]
for %s=%s+1,%s do %s=%s..%s[%s] end
%s=%s+1
%s[%s]=%s
end
%s=%s
end
return %s[1]
end]],
        V.join, V.jtbl, V.jn,
        V.jn, V.jn, V.jtbl, V.jn,
        V.jw, V.ji, V.ji, V.jn, V.jw, V.jw,
        V.jtbl, V.jw, V.jtbl, V.ji, V.jtbl, V.ji, V.jtbl, V.ji, V.jtbl, V.ji, V.jtbl, V.ji, V.jtbl, V.ji, V.jtbl, V.ji, V.jtbl, V.ji,
        V.ji, V.ji,
        V.ji, V.jn, V.js, V.jtbl, V.ji, V.jj, V.ji, V.jn, V.js, V.js, V.jtbl, V.jj,
        V.jw, V.jw, V.jtbl, V.jw, V.js, V.jn, V.jw, V.jtbl) or ""

    local bk = encoder_instance.blob_keys
    local bm = encoder_instance.bm
    local br = encoder_instance.br

    local decoder_tmpl = [==[
local @@HOST_PCALL_FN@@=(type(pcall)=="function");
local @@BYTE@@,@@SUB@@,@@CHAR@@,@@GSUB@@,@@SETMT@@,@@PCALL@@,@@TYPEFN@@,@@TOSTR@@,@@ASSERT@@,@@LOADSTR@@,@@UNPACK@@,@@FLOOR@@,@@VTAB@@=string.byte,string.sub,string.char,string.gsub,setmetatable,(type(pcall)=="function" and pcall or (coroutine and coroutine.create and function(f,...)local c=coroutine.create(function(...)return f(...)end)return coroutine.resume(c,...)end) or function(f,...)return true,f(...)end),type,tostring,assert,loadstring,unpack or (table and table.unpack),math.floor,{};
local function @@TPACK@@(...)return{[0]=select("#",...),...}end
@@VTAB_INIT@@
local @@VOFF@@=@@VOFF_VAL@@;
local @@A85DEC@@={};
do local @@A85S@@=@@A85_LIT@@;for @@A85I@@=1,85 do @@A85DEC@@[@@BYTE@@(@@A85S@@,@@A85I@@)]=@@A85I@@-1;end;end;
local @@RAWBIN@@=(function(@@A85N@@)@@A85N@@=@@GSUB@@(@@A85N@@,"z",@@A85_ZERO5@@);return @@GSUB@@(@@A85N@@,".....",@@SETMT@@({},{__index=function(@@A85T@@,@@A85K@@)local @@B1@@,@@B2@@,@@B3@@,@@B4@@,@@B5@@=@@BYTE@@(@@A85K@@,1,5);local @@D1@@,@@D2@@,@@D3@@,@@D4@@,@@D5@@=@@A85DEC@@[@@B1@@]or 0,@@A85DEC@@[@@B2@@]or 0,@@A85DEC@@[@@B3@@]or 0,@@A85DEC@@[@@B4@@]or 0,@@A85DEC@@[@@B5@@]or 0;local @@A85Y@@=(@@D5@@+@@D4@@*85+@@D3@@*7225+@@D2@@*614125+@@D1@@*52200625)%4294967296;local @@CH@@=@@CHAR@@(@@FLOOR@@(@@A85Y@@/16777216)%256,@@FLOOR@@(@@A85Y@@/65536)%256,@@FLOOR@@(@@A85Y@@/256)%256,@@A85Y@@%256);@@A85T@@[@@A85K@@]=@@CH@@;return @@CH@@;end}));end)(@@SUB@@(@@PAYLOAD_LIT@@,@@VOFF@@));
@@ASSERT@@(@@RAWBIN@@ and @@TYPEFN@@(@@RAWBIN@@)=="string",@@ERR_DECODE@@);
local function @@ROTL@@(@@RX@@,@@RR@@)local @@RQ@@=2^(32-@@RR@@)local @@RHI@@=@@FLOOR@@(@@RX@@/@@RQ@@)return (@@RX@@-@@RHI@@*@@RQ@@)*(2^@@RR@@)+@@RHI@@ end
local function @@MKSBOX@@(k0,k1,k2,k3,m0)
local s,inv={},{}
for @@SI@@=0,255 do s[@@SI@@]=@@SI@@ end
local @@ST0@@=(k0+k2+1)%4294967296
local @@ST1@@=(k1+k3+3)%4294967296
for @@SI@@=255,1,-1 do
@@ST0@@=(@@ST0@@*m0+@@ST1@@+@@SI@@*257)%4294967296
local @@SHI@@=@@FLOOR@@(@@ST0@@/65536)
local @@SLO@@=@@ST0@@%65536
@@ST1@@=(@@SHI@@*65537+@@SLO@@*257+@@ST1@@+k1)%4294967296
local @@SJ@@=(@@ST0@@+@@ST1@@)%(@@SI@@+1)
s[@@SI@@],s[@@SJ@@]=s[@@SJ@@],s[@@SI@@]
end
for @@SI@@=0,255 do inv[s[@@SI@@]]=@@SI@@ end
return s,inv
end
local @@S1@@,@@S1INV@@=@@MKSBOX@@(@@BK0@@,@@BK1@@,@@BK2@@,@@BK3@@,@@BM0@@)
local @@S2@@,@@S2INV@@=@@MKSBOX@@(@@BK2@@,@@BK3@@,@@BK0@@,@@BK1@@,@@BM2@@)
@@JOIN_DEF@@
local function @@R16@@(@@RS@@,@@RI@@)local @@RA@@,@@RB@@=@@BYTE@@(@@RS@@,@@RI@@,@@RI@@+1)return @@RA@@+@@RB@@*256 end
local function @@R32@@(@@RS@@,@@RI@@)local @@RA@@,@@RB@@,@@RC2@@,@@RD2@@=@@BYTE@@(@@RS@@,@@RI@@,@@RI@@+3)return @@RA@@+@@RB@@*256+@@RC2@@*65536+@@RD2@@*16777216 end
local function @@R64@@(@@RB@@)
local @@RSIGN@@=(@@RB@@[8]>=128)and -1 or 1
local @@REXP@@=(@@RB@@[8]%128)*16+@@FLOOR@@(@@RB@@[7]/16)
local @@RMANT@@=(@@RB@@[7]%16)*(2^48)+@@RB@@[6]*(2^40)+@@RB@@[5]*(2^32)+@@RB@@[4]*(2^24)+@@RB@@[3]*(2^16)+@@RB@@[2]*256+@@RB@@[1]
if @@REXP@@==0 then if @@RMANT@@==0 then return (@@RSIGN@@<0)and(-1/(1/0))or 0 end return @@RSIGN@@*(@@RMANT@@/2^52)*2^-1022 end
if @@REXP@@==2047 then return @@RMANT@@==0 and @@RSIGN@@*(1/0) or (0/0) end
return @@RSIGN@@*(1+@@RMANT@@/2^52)*2^(@@REXP@@-1023)
end
local function @@DECODE@@(@@DBIN@@,@@DPAD@@)
if @@DPAD@@>0 then @@DBIN@@=@@SUB@@(@@DBIN@@,1,-@@DPAD@@-1) end
local @@DN@@=#@@DBIN@@
local @@DOUT@@={}
local @@DS0@@,@@DS1@@=@@BK2@@,@@BK3@@
for @@DI@@=@@DN@@,1,-1 do
local @@DENC@@=@@BYTE@@(@@DBIN@@,@@DI@@)
local @@DKS@@=(@@S2@@[(@@DS0@@+@@DS1@@)%256]+@@FLOOR@@(@@DS0@@/16777216)+@@FLOOR@@(@@DS1@@/65536))%256
@@DOUT@@[@@DI@@]=(@@S1INV@@[@@DENC@@]-@@DKS@@+256)%256
@@DS0@@=@@ROTL@@((((@@DS0@@+@@DENC@@+@@DI@@)%4294967296)*@@BM2@@)%4294967296,@@BR1@@)
@@DS1@@=(((@@DS1@@+@@FLOOR@@(@@DS0@@/65536)+(@@DS0@@%65536)*257+@@DENC@@)%4294967296)*@@BM3@@)%4294967296
end
@@DS0@@,@@DS1@@=@@BK0@@,@@BK1@@
for @@DI@@=1,@@DN@@ do
local @@DENC@@=@@DOUT@@[@@DI@@]
local @@DKS@@=(@@S1@@[(@@DS0@@+@@DS1@@)%256]+@@FLOOR@@(@@DS0@@/16777216)+@@FLOOR@@(@@DS1@@/65536))%256
@@DOUT@@[@@DI@@]=@@VTAB@@[(@@S2INV@@[@@DENC@@]-@@DKS@@+256)%256]
@@DS0@@=@@ROTL@@((((@@DS0@@+@@DENC@@+@@DI@@)%4294967296)*@@BM0@@)%4294967296,@@BR0@@)
@@DS1@@=(((@@DS1@@+@@FLOOR@@(@@DS0@@/65536)+(@@DS0@@%65536)*257+@@DENC@@)%4294967296)*@@BM1@@)%4294967296
end
return @@DECODE_JOIN@@
end
local function @@READP@@(@@PBIN@@,@@PPOS@@)
@@READ_FIELDS@@
local @@PROTO@@={@@PROTO_INIT@@}
local @@STRINGS@@={}
@@ORDERED_SECS@@
return @@PROTO@@,@@PPOS@@
end
local @@BINV@@=@@DECODE@@(@@RAWBIN@@,@@PAD_VAL@@)
local @@CHKA@@,@@CHKB@@=1,0
for @@CHKI@@=1,#@@BINV@@ do
@@CHKA@@=(@@CHKA@@+@@BYTE@@(@@BINV@@,@@CHKI@@))%65521
@@CHKB@@=(@@CHKB@@+@@CHKA@@)%65521
end
if @@CHKB@@*65536+@@CHKA@@~=CHECKSUM_VAL then error(@@ERR_PAYLOAD@@,0) end
local @@ASTV@@=(@@READP@@(@@BINV@@,1))
@@BINV@@=nil @@RAWBIN@@=nil
@@ASTV@@[@@P_RT@@]=true
]==]
    decoder_tmpl = decoder_tmpl:gsub("CHECKSUM_VAL", tostring(checksum))
    local decoder = subst(decoder_tmpl, {
        HOST_PCALL_FN = V.host_pcall_fn,
        BYTE = V.byte, SUB = V.sub, CHAR = V.char, GSUB = V.gsub, SETMT = V.setmt,
        PCALL = V.pcall, TYPEFN = V.typefn, TOSTR = V.tostr, ASSERT = V.assert,
        LOADSTR = V.loadstr, UNPACK = V.unpack, FLOOR = V.floor, VTAB = V.vtab,
        TPACK = V.pack, VTAB_INIT = vtab_init_code, VOFF = V.voff, VOFF_VAL = tostring(v_off_val),
        A85DEC = V.a85dec, A85S = V.a85s, A85I = V.a85i, A85_LIT = a85_lit, A85_ZERO5 = a85_zero5_lit,
        RAWBIN = V.rawbin, A85N = V.a85n, A85T = V.a85t, A85K = V.a85k,
        B1 = V.b1, B2 = V.b2, B3 = V.b3, B4 = V.b4, B5 = V.b5,
        D1 = V.d1, D2 = V.d2, D3 = V.d3, D4 = V.d4, D5 = V.d5, A85Y = V.a85y,
        CH = V.p_ch, PAYLOAD_LIT = payload_s, ERR_DECODE = err_decode_expr,
        ROTL = V.rotl, RX = V.rx, RR = V.rr, RQ = V.rq, RHI = V.rhi,
        MKSBOX = V.mksbox, SI = V.si, SJ = V.sj, ST0 = V.st0, ST1 = V.st1, SHI = V.shi, SLO = V.slo,
        S1 = V.s1, S1INV = V.s1inv, S2 = V.s2, S2INV = V.s2inv,
        BK0 = tostring(bk[1]), BK1 = tostring(bk[2]), BK2 = tostring(bk[3]), BK3 = tostring(bk[4]),
        BM0 = tostring(bm[1]), BM1 = tostring(bm[2]), BM2 = tostring(bm[3]), BM3 = tostring(bm[4]),
        BR0 = tostring(br[1]), BR1 = tostring(br[2]),
        JOIN_DEF = join_def_code,
        R16 = V.r16, R32 = V.r32, R64 = V.r64,
        RS = V.rs, RI = V.ri, RA = V.ra, RB = V.rb, RC2 = V.rc2, RD2 = V.rd2, RE2 = V.re2,
        RSIGN = V.rsign, REXP = V.rexp, RMANT = V.rmant,
        DECODE = V.decode, DBIN = V.dbin, DPAD = V.dpad, DN = V.dn, DOUT = V.dout,
        DS0 = V.ds0, DS1 = V.ds1, DI = V.hl_i, DENC = V.denc, DKS = V.dks,
        DECODE_JOIN = decode_join_expr,
        READP = V.readp, PBIN = V.pbin, PPOS = V.ppos,
        READ_FIELDS = table.concat(read_field_lines, "\n"),
        PROTO = V.proto, PROTO_INIT = table.concat(proto_init_pairs, ","),
        STRINGS = V.strings, ORDERED_SECS = table.concat(ordered_secs, "\n"),
        BINV = V.bin_v, PAD_VAL = tostring(pad),
        CHKA = V.chk_a, CHKB = V.chk_b, CHKI = V.chk_i,
        ERR_PAYLOAD = err_payload_expr, ASTV = V.ast_v, P_RT = tostring(pkeys.rt),
    })

    if protected_init then
        decoder = Runtime.wrap(decoder, {
            V.setmt, V.typefn, V.floor, V.pack, V.unpack, V.ast_v,
            V.pcall, V.tostr, V.byte, V.sub, V.char, V.vtab,
        }, options)
    end

    local code_parts = { minify(decoder) }

    -- === Build polymorphic __PARSE from 3 of 24 bitfield permutations ===
    local parse_branches = {}
    for m = 0, 2 do
        local lay = spec.layouts[m]
        local assigns = {}
        local pvar_for = { op = V.pop, a = V.pa, b = V.pb, c = V.pc }
        for idx = 1, 4 do
            local f = lay[idx]
            if f.shift == 0 then
                assigns[idx] = string.format("%s=%s%%%d", pvar_for[f.name], V.pw, f.mod)
            else
                assigns[idx] = string.format("%s=%s(%s/%d)%%%d", pvar_for[f.name], V.floor, V.pw, f.mul, f.mod)
            end
        end
        local kw = (m == 0) and "if" or ((m == 1) and "elseif" or "else")
        if m < 2 then
            parse_branches[#parse_branches + 1] = string.format("%s %s==%d then %s", kw, V.pmode, m, table.concat(assigns, " "))
        else
            parse_branches[#parse_branches + 1] = string.format("else %s end", table.concat(assigns, " "))
        end
    end
    local parse_body = string.format(
        "local %s,%s,%s,%s local %s=(%s+((%s+%d)%%3))%%3 %s local %s=%s+%s*512 return %s,%s,%s,%s,%s,%s-131071",
        V.pop, V.pa, V.pb, V.pc, V.pmode, V.play, V.ppe, encoder_instance.inst_keys.layout_salt,
        table.concat(parse_branches, " "), V.pbx, V.pb, V.pc,
        V.pop, V.pa, V.pb, V.pc, V.pbx, V.pbx
    )

    -- === Polymorphic Dispatcher Topology (mode 0: single bijection; mode 1: 2-bank split) ===
    local disp_mode = gen_rng:range(0, 1)
    local split_thr = (disp_mode == 1) and gen_rng:range(80, 175) or nil
    local d_mul0 = 1 + 2 * gen_rng:range(1, 127)
    local d_add0 = gen_rng:range(0, 255)
    local d_mul1 = 1 + 2 * gen_rng:range(1, 127)
    local d_add1 = gen_rng:range(0, 255)

    local function disp_slot(op)
        if disp_mode == 0 then
            local tk = (op * d_mul0 + d_add0) % 256
            return string.format("%s[%d]", V.raw_disp, tk)
        else
            if op < split_thr then
                local tk = (op * d_mul0 + d_add0) % 256
                return string.format("%s[%d]", V.raw_disp, tk)
            else
                local tk = (op * d_mul1 + d_add1) % 256
                return string.format("%s[%d]", V.raw_disp1, tk)
            end
        end
    end

    -- Build VM_ENGINE with opaque-token vault, F4 string.dump guard, F5 digest & immediate __TRAP
    local fh_seed = gen_rng:range(1, 4294967290)
    local fh_mul  = gen_rng:odd17()
    local dacc_init = gen_rng:range(1000, 999999)
    local ik = encoder_instance.inst_keys
    local dgk = encoder_instance.dg_keys
    local shift_mul = gen_rng:range(131, 997)
    local shift_salt = gen_rng:range(10000, 999999)

    local dump_check_init = string.format([[
local %s=(%s(%s)=="table" and %s(%s.dump)=="function")and %s.dump or nil
local %s,%s
if %s then
if %s and %s(%s,%s)then %s(nil)end
if %s(%s)=="table" and %s(%s.getinfo)=="function" then
local %s=%s.getinfo(%s,"S")
if not %s or %s.what~="C" then %s(nil)end
end
local %s,%s=%s(%s,%s)
local %s,%s=%s(%s,%s)
if not %s or not %s or %s(%s)~="string" or %s(%s)~="string" then %s(nil)end
%s,%s=%s(%s),%s(%s)
end]],
        V.orig_dump, V.typefn, V.strlib, V.typefn, V.strlib, V.strlib,
        V.base_ex, V.base_pr,
        V.orig_dump,
        V.host_pcall_fn, V.pcall, V.orig_dump, V.pcall, V.trap,
        V.typefn, V.dbglib, V.typefn, V.dbglib,
        V.di, V.dbglib, V.orig_dump,
        V.di, V.di, V.trap,
        V.c_ok, V.b1, V.pcall, V.orig_dump, V.exec,
        V.c_ok2, V.b2, V.pcall, V.orig_dump, V.parse,
        V.c_ok, V.c_ok2, V.typefn, V.b1, V.typefn, V.b2, V.trap,
        V.base_ex, V.base_pr, V.fhash, V.b1, V.fhash, V.b2)

    local dump_check_exec = string.format([[
if %s then
if %s(%s)~="table" or %s.dump~=%s then %s(nil,%s)end
if %s[%d] or (%s%%32==1) then
local %s,%s=%s(%s,%s)
local %s,%s=%s(%s,%s)
if not %s or not %s or %s(%s)~=%s or %s(%s)~=%s then %s(nil,%s)end
end
end]],
        V.orig_dump,
        V.typefn, V.strlib, V.strlib, V.orig_dump, V.trap, V.instr,
        V.pr, pkeys.rt, V.call_cnt,
        V.c_ok, V.b1, V.pcall, V.orig_dump, V.exec,
        V.c_ok2, V.b2, V.pcall, V.orig_dump, V.parse,
        V.c_ok, V.c_ok2, V.fhash, V.b1, V.base_ex, V.fhash, V.b2, V.base_pr, V.trap, V.instr)

    local concat_check_exec = use_join and string.format([[
if %s and (%s(%s)~="table" or %s.concat~=%s) then %s(nil,%s) end]],
        V.concat_ref, V.typefn, V.tbllib, V.tbllib, V.concat_ref, V.trap, V.instr) or ""

    local disp_decl = (disp_mode == 0)
        and string.format("local %s,%s={},{} local %s=%s({},{__index=%s,__newindex=function() %s(nil) end,__metatable=false})",
            V.raw_disp, V.raw_dispref, V.disp, V.setmt, V.raw_disp, V.trap)
        or string.format("local %s,%s,%s,%s={},{},{},{} local %s=%s({},{__index=%s,__newindex=function() %s(nil) end,__metatable=false}) local %s=%s({},{__index=%s,__newindex=function() %s(nil) end,__metatable=false})",
            V.raw_disp, V.raw_dispref, V.raw_disp1, V.raw_dispref1, V.disp, V.setmt, V.raw_disp, V.trap, V.disp1, V.setmt, V.raw_disp1, V.trap)

    local engine_tmpl = [==[
local @@STRLIB@@,@@TBLLIB@@,@@DBGLIB@@,@@COROLIB@@,@@ERRORFN@@,@@SELECTFN@@,@@ABSFN@@,@@GETMTFN@@,@@PAIRSFN@@=string,table,debug,coroutine,error,select,math and math.abs,getmetatable,pairs
local @@CONCAT_REF@@=(@@TYPEFN@@(@@TBLLIB@@)=="table" and @@TYPEFN@@(@@TBLLIB@@.concat)=="function")and @@TBLLIB@@.concat or nil
local @@VPR@@=@@SETMT@@({},{__mode="k",__metatable=false})
local @@VENV@@=@@SETMT@@({},{__mode="k",__metatable=false})
local @@VUV@@=@@SETMT@@({},{__mode="k",__metatable=false})
local @@TOKMT@@={__metatable=false}
local @@OWNED@@=@@SETMT@@({},{__mode="k",__metatable=false})
local @@POISON@@=0
local @@CALL_CNT@@=0
local @@ACTIVE_INS@@
local function @@TRAP@@(@@TR_MSG@@,@@TR_INS@@)
@@POISON@@=@@POISON@@+1
local @@TR_T@@=@@TR_INS@@ or @@ACTIVE_INS@@
if @@TYPEFN@@(@@TR_T@@)=="table" then for @@TR_I@@=1,#@@TR_T@@ do @@TR_T@@[@@TR_I@@]=0 end end
local @@TR_S@@=@@SENTINEL_EXPR@@
@@ERRORFN@@(@@TR_S@@..(@@TR_MSG@@ or @@ERR_RUNTIME@@),0)
end
local function @@FHASH@@(@@FH_S@@)
local @@FH_H@@=@@FH_SEED@@
for @@FH_I@@=1,#@@FH_S@@ do @@FH_H@@=(@@FH_H@@*@@FH_MUL@@+@@BYTE@@(@@FH_S@@,@@FH_I@@))%4294967291 end
return @@FH_H@@
end
local function @@PARSE@@(@@PW@@,@@PPE@@,@@PLAY@@)
@@PARSE_BODY@@
end
local @@WRAP@@,@@EXEC@@
local function @@TRAMP@@(@@TOK@@,@@CURENV@@,...)
local @@PRV@@,@@ENVV@@,@@UVV@@=@@VPR@@[@@TOK@@],@@CURENV@@ or @@VENV@@[@@TOK@@],@@VUV@@[@@TOK@@]
if not @@PRV@@ or not @@ENVV@@ then @@TRAP@@(nil) end
return @@EXEC@@(@@PRV@@,@@ENVV@@,@@UVV@@,...)
end
@@OWNED@@[@@TRAMP@@]=true
@@WRAP@@=function(@@PIN@@,@@EIN@@,@@UIN@@)
local @@WTOK@@=@@SETMT@@({},@@TOKMT@@)
@@VPR@@[@@WTOK@@],@@VENV@@[@@WTOK@@],@@VUV@@[@@WTOK@@]=@@PIN@@,@@EIN@@,@@UIN@@
local @@WFN@@=function(...)local @@TOK@@=@@WTOK@@ local @@CURENV@@=(getfenv and getfenv()) or @@VENV@@[@@TOK@@] return @@TRAMP@@(@@TOK@@,@@CURENV@@,...)end
if setfenv and @@EIN@@ then setfenv(@@WFN@@,@@EIN@@) end
@@OWNED@@[@@WFN@@]=true
return @@WFN@@
end
@@OWNED@@[@@WRAP@@]=true
@@EXEC@@=function(@@PR@@,@@ENV@@,@@UPVALS@@,...)
if setfenv and @@ENV@@ then setfenv(1,@@ENV@@) end
if @@POISON@@>0 then @@TRAP@@(nil,@@PR@@[@@P_INS@@]) end
local @@INSTR@@,@@KONST@@,@@PROTOS@@=@@PR@@[@@P_INS@@],@@PR@@[@@P_KS@@],@@PR@@[@@P_PS@@]
@@ACTIVE_INS@@=@@INSTR@@
@@CALL_CNT@@=(@@CALL_CNT@@+1)%1024
@@DUMP_CHECK_EXEC@@
@@CONCAT_CHECK_EXEC@@
local @@DGM@@={@@PR@@[@@P_NP@@],@@PR@@[@@P_UP@@],@@PR@@[@@P_MS@@],@@PR@@[@@P_IV@@],@@PR@@[@@P_OM@@],@@PR@@[@@P_OA@@],@@PR@@[@@P_LM@@],@@PR@@[@@P_PK@@],#@@INSTR@@}
local @@DGV@@=@@DG_INIT@@
for @@DGI@@=1,9 do @@DGV@@=(@@DGV@@*@@DG_MUL@@+@@DGM@@[@@DGI@@]+1)%4294967291 end
for @@DGI@@=1,#@@INSTR@@ do @@DGV@@=(@@DGV@@*@@DG_MUL@@+@@INSTR@@[@@DGI@@]+@@DGI@@)%4294967291 end
if @@DGV@@~=@@PR@@[@@P_DG@@]then @@TRAP@@(nil,@@INSTR@@) end
local @@REG@@,@@VARGS@@,@@OPENUVS@@,@@STOP@@,@@IPC@@={},{...},{},0,1
local @@STORAGE@@={} local @@STRIDE@@=@@PR@@[@@P_OM@@]*2+1
local @@SHIFT@@=(@@SHIFT_SALT@@+@@PR@@[@@P_OA@@]*@@SHIFT_MUL@@+@@CALL_CNT@@*79)%4294967296
@@SETMT@@(@@REG@@,{
__index=function(_,@@PKK@@)return @@STORAGE@@[(@@PKK@@*@@STRIDE@@+@@SHIFT@@)%4294967296]end,
__newindex=function(_,@@PKK@@,@@PKV@@)@@STORAGE@@[(@@PKK@@*@@STRIDE@@+@@SHIFT@@)%4294967296]=@@PKV@@ end,
__metatable=false
})
local @@VLEN@@=@@SELECTFN@@("#",...)
local @@LAYOUT@@=@@PR@@[@@P_LM@@]
local function @@RK@@(@@RKI@@)
if @@RKI@@>=256 then return @@KONST@@[@@RKI@@-256]end
return @@REG@@[@@RKI@@]
end
local @@POM@@,@@POA@@,@@PPK@@=@@PR@@[@@P_OM@@],@@PR@@[@@P_OA@@],@@PR@@[@@P_PK@@]
for @@DGI@@=0,(@@PR@@[@@P_NP@@]) -1 do @@REG@@[@@DGI@@]=@@VARGS@@[@@DGI@@+1] end
@@STOP@@=(@@PR@@[@@P_NP@@])-1
local function @@CLOSEUV@@(@@LIM@@)for @@RKI@@,@@UVX@@ in @@PAIRSFN@@(@@OPENUVS@@)do if @@RKI@@>=@@LIM@@ then @@UVX@@[1]={@@UVX@@[1][@@UVX@@[2]]}@@UVX@@[2]=1 @@OPENUVS@@[@@RKI@@]=nil end end end
local function @@NEXTK@@(@@NK_IPC@@,@@NK_PE@@)
local @@NK_PLO@@=@@NK_PE@@%131072
local @@NK_PHI@@=@@FLOOR@@(@@NK_PE@@/131072)
local @@NK_H@@=(@@IK0@@+@@NK_IPC@@*@@IM1@@+@@NK_PLO@@*@@IM2@@+@@NK_PHI@@*@@IM3@@+@@IA1@@+@@PPK@@*65537)%17179869184
local @@NK_HLO@@=@@NK_H@@%131072
local @@NK_HHI@@=@@FLOOR@@(@@NK_H@@/131072)
local @@NK_ROT@@=@@NK_HLO@@*131072+@@NK_HHI@@
return (@@NK_ROT@@*@@IM2@@+@@NK_HHI@@*@@IM3@@+@@IA1@@)%17179869184
end
local @@DEC_REG@@={[0]=0,1,2,3,4,5,6,7}
local @@DACC@@=@@DACC_INIT@@
@@DISP_DECL@@
]==]

    local engine = subst(engine_tmpl, {
        STRLIB = V.strlib, TBLLIB = V.tbllib, DBGLIB = V.dbglib, COROLIB = V.corolib,
        ERRORFN = V.errorfn, SELECTFN = V.selectfn, ABSFN = V.absfn, GETMTFN = V.getmtfn, PAIRSFN = V.pairsfn,
        TYPEFN = V.typefn, BYTE = V.byte, SETMT = V.setmt, FLOOR = V.floor,
        CONCAT_REF = V.concat_ref,
        VPR = V.vpr, VENV = V.venv, VUV = V.vuv, TOKMT = V.tokmt, OWNED = V.owned,
        POISON = V.poison, CALL_CNT = V.call_cnt, ACTIVE_INS = V.active_ins,
        TRAP = V.trap, TR_MSG = V.tr_msg, TR_INS = V.tr_ins, TR_T = V.tr_t, TR_I = V.tr_i, TR_S = V.tr_s,
        SENTINEL_EXPR = sentinel_expr, ERR_RUNTIME = err_runtime_expr,
        FHASH = V.fhash, FH_S = V.fh_s, FH_H = V.fh_h, FH_I = V.fh_i,
        FH_SEED = tostring(fh_seed), FH_MUL = tostring(fh_mul),
        PARSE = V.parse, PW = V.pw, PPE = V.ppe, PLAY = V.play, PARSE_BODY = parse_body,
        WRAP = V.wrap, EXEC = V.exec, TRAMP = V.tramp, TOK = V.tok, CURENV = V.cur_env,
        PRV = V.pr_v, ENVV = V.env_v, UVV = V.uv_v,
        PIN = V.p_in, EIN = V.e_in, UIN = V.u_in, WTOK = V.w_tok, WFN = V.w_fn,
        DISP_DECL = disp_decl,
        PR = V.pr, ENV = V.env, UPVALS = V.upvals,
        P_NP = tostring(pkeys.np), P_UP = tostring(pkeys.up), P_MS = tostring(pkeys.ms),
        P_IV = tostring(pkeys.iv), P_OM = tostring(pkeys.om), P_OA = tostring(pkeys.oa),
        P_LM = tostring(pkeys.lm), P_PK = tostring(pkeys.pk), P_INS = tostring(pkeys.ins),
        P_KS = tostring(pkeys.ks), P_PS = tostring(pkeys.ps), P_RT = tostring(pkeys.rt),
        P_DG = tostring(pkeys.dg),
        INSTR = V.instr, KONST = V.konst, PROTOS = V.protos,
        DUMP_CHECK_EXEC = dump_check_exec, CONCAT_CHECK_EXEC = concat_check_exec,
        DGM = V.dg_m, DGV = V.dg_v, DGI = V.dg_i,
        DG_INIT = tostring(dgk.dg_init), DG_MUL = tostring(dgk.dg_mul),
        REG = V.reg, VARGS = V.vargs, OPENUVS = V.openuvs, STOP = V.stop, IPC = V.ipc,
        STORAGE = V.storage, STRIDE = V.stride, SHIFT = V.shift,
        SHIFT_SALT = tostring(shift_salt), SHIFT_MUL = tostring(shift_mul),
        PKK = V.pk_k, PKV = V.pk_v, VLEN = V.vlen, LAYOUT = V.layout,
        RK = V.rk, RKI = V.rk_i, POM = V.pom, POA = V.poa, PPK = V.ppk,
        CLOSEUV = V.closeuv, LIM = V.lim, UVX = V.uv_x,
        NEXTK = V.nextk, NK_IPC = V.nk_ipc, NK_PE = V.nk_pe, NK_PLO = V.nk_plo, NK_PHI = V.nk_phi,
        NK_H = V.nk_h, NK_HLO = V.nk_hlo, NK_HHI = V.nk_hhi, NK_ROT = V.nk_rot,
        IK0 = tostring(ik.ik0), IA1 = tostring(ik.ia1),
        IM1 = tostring(ik.im1), IM2 = tostring(ik.im2), IM3 = tostring(ik.im3),
        DEC_REG = V.dec_reg, DACC = V.dacc, DACC_INIT = tostring(dacc_init),
    })
    code_parts[#code_parts + 1] = minify(engine)

    -- === Build all 38 Dispatch Handlers (zero hardcoded locals/params/fields) ===
    local D, R, K = V.disp, V.reg, V.konst
    local PC, TOP, INS, PS = V.ipc, V.stop, V.instr, V.protos
    local CL, OUV, WR = V.closeuv, V.openuvs, V.wrap
    local PK, UPK, PRS, NEXTK = V.pack, V.unpack, V.parse, V.nextk
    local VA, VLEN, LAY = V.vargs, V.vlen, V.layout
    local PR, ENV, UV = V.pr, V.env, V.upvals
    local HR, HA, HB, HC, HBX, HSBX = V.h_r, V.h_a, V.h_b, V.h_c, V.h_bx, V.h_sbx
    local RK_FN, KMOD_S = V.rk, "17179869184"
    local HI, HU, HQ, HW, HS, HG, HN, HR_L, HL, HCB, HVAR, HPE, HE, HNK, HNW, HCBX, HO, HT, HP, HUV, HPB, HOP =
        V.hl_i, V.hl_u, V.hl_q, V.hl_w, V.hl_s, V.hl_g, V.hl_n, V.hl_r, V.hl_l, V.hl_cb, V.hl_var,
        V.hl_pe, V.hl_e, V.hl_nk, V.hl_nw, V.hl_cbx, V.hl_o, V.hl_t, V.hl_p, V.hl_uv, V.hl_pb, V.hl_op

    local d_entries = {}
    local function add_h(op_idx, body)
        d_entries[#d_entries + 1] = string.format("%s=function(%s)%s end", disp_slot(O[op_idx]), formal_params, body)
    end
    local function add_h2(op_idx, body)
        d_entries[#d_entries + 1] = string.format("%s=function(%s)%s end", disp_slot(O2[op_idx]), formal_params, body)
    end

    add_h(0,  string.format("%s[%s]=%s[%s]", HR, HA, HR, HB))
    add_h(1,  string.format("%s[%s]=%s[%s]", HR, HA, K, HBX))
    add_h(2,  string.format("%s[%s]=(%s~=0)if %s~=0 then %s=%s+1 end", HR, HA, HB, HC, PC, PC))
    add_h(3,  string.format("for %s=%s,%s do %s[%s]=nil end", HI, HA, HB, HR, HI))
    add_h(4,  string.format("local %s=%s[%s] %s[%s]=%s[1][%s[2]]", HU, UV, HB, HR, HA, HU, HU))
    add_h(5,  string.format("%s[%s]=%s[%s[%s]]", HR, HA, ENV, K, HBX))
    add_h(6,  string.format("local %s=%s[%s]local %s=%s(%s)%s[%s]=%s[%s]", HQ, HR, HB, HW, RK_FN, HC, HR, HA, HQ, HW))
    add_h(7,  string.format("%s[%s[%s]]=%s[%s]", ENV, K, HBX, HR, HA))
    add_h(8,  string.format("local %s=%s[%s] %s[1][%s[2]]=%s[%s]", HU, UV, HB, HU, HU, HR, HA))
    add_h(9,  string.format("local %s=%s(%s)local %s=%s(%s)%s[%s][%s]=%s", HQ, RK_FN, HB, HW, RK_FN, HC, HR, HA, HQ, HW))
    add_h(10, string.format("%s[%s]={}", HR, HA))
    add_h(11, string.format("local %s=%s[%s]local %s=%s(%s)%s[%s+1]=%s %s[%s]=%s[%s]", HQ, HR, HB, HW, RK_FN, HC, HR, HA, HQ, HR, HA, HQ, HW))
    add_h(12, string.format("local %s=%s(%s)local %s=%s(%s)%s[%s]=%s+%s", HQ, RK_FN, HB, HW, RK_FN, HC, HR, HA, HQ, HW))
    add_h(13, string.format("local %s=%s(%s)local %s=%s(%s)%s[%s]=%s-%s", HQ, RK_FN, HB, HW, RK_FN, HC, HR, HA, HQ, HW))
    add_h(14, string.format("local %s=%s(%s)local %s=%s(%s)%s[%s]=%s*%s", HQ, RK_FN, HB, HW, RK_FN, HC, HR, HA, HQ, HW))
    add_h(15, string.format("local %s=%s(%s)local %s=%s(%s)%s[%s]=%s/%s", HQ, RK_FN, HB, HW, RK_FN, HC, HR, HA, HQ, HW))
    add_h(16, string.format("local %s=%s(%s)local %s=%s(%s)%s[%s]=%s%%%s", HQ, RK_FN, HB, HW, RK_FN, HC, HR, HA, HQ, HW))
    add_h(17, string.format("local %s=%s(%s)local %s=%s(%s)%s[%s]=%s^%s", HQ, RK_FN, HB, HW, RK_FN, HC, HR, HA, HQ, HW))
    add_h(18, string.format("%s[%s]=-%s[%s]", HR, HA, HR, HB))
    add_h(19, string.format("%s[%s]=not %s[%s]", HR, HA, HR, HB))
    add_h(20, string.format("%s[%s]=#%s[%s]", HR, HA, HR, HB))
    add_h(21, string.format("local %s=%s[%s]for %s=%s+1,%s do %s=%s..%s[%s]end %s[%s]=%s", HS, HR, HB, HI, HB, HC, HS, HS, HR, HI, HR, HA, HS))
    add_h(22, string.format("%s=%s+%s", PC, PC, HSBX))
    add_h(23, string.format("local %s=%s(%s)local %s=%s(%s)if(%s==%s)~=(%s~=0)then %s=%s+1 end", HQ, RK_FN, HB, HW, RK_FN, HC, HQ, HW, HA, PC, PC))
    add_h(24, string.format("local %s=%s(%s)local %s=%s(%s)if(%s<%s)~=(%s~=0)then %s=%s+1 end", HQ, RK_FN, HB, HW, RK_FN, HC, HQ, HW, HA, PC, PC))
    add_h(25, string.format("local %s=%s(%s)local %s=%s(%s)if(%s<=%s)~=(%s~=0)then %s=%s+1 end", HQ, RK_FN, HB, HW, RK_FN, HC, HQ, HW, HA, PC, PC))
    add_h(26, string.format("if(not %s[%s])==(%s~=0)then %s=%s+1 end", HR, HA, HC, PC, PC))
    add_h(27, string.format("if(not %s[%s])==(%s~=0)then %s=%s+1 else %s[%s]=%s[%s]end", HR, HB, HC, PC, PC, HR, HA, HR, HB))
    add_h(28, string.format("local %s={}local %s=(%s==0)and(%s-%s)or(%s-1)for %s=1,%s do %s[%s]=%s[%s+%s]end local %s=%s(%s[%s](%s(%s,1,%s)))local %s=%s[0]if %s==0 then %s=%s+%s-1 for %s=1,%s do %s[%s+%s-1]=%s[%s]end else for %s=1,%s-1 do %s[%s+%s-1]=%s[%s]end end",
        HG, HN, HB, TOP, HA, HB, HI, HN, HG, HI, HR, HA, HI, HR_L, PK, HR, HA, UPK, HG, HN, HL, HR_L, HC, TOP, HA, HL, HI, HL, HR, HA, HI, HR_L, HI, HI, HC, HR, HA, HI, HR_L, HI))
    add_h(29, string.format("local %s={}local %s=(%s==0)and(%s-%s)or(%s-1)for %s=1,%s do %s[%s]=%s[%s+%s]end %s(0)if %s[%d]then for %s=1,#%s do %s[%s]=0 end end return true,%s[%s](%s(%s,1,%s))",
        HG, HN, HB, TOP, HA, HB, HI, HN, HG, HI, HR, HA, HI, CL, PR, pkeys.rt, HI, INS, INS, HI, HR, HA, UPK, HG, HN))
    add_h(30, string.format("%s(0)if %s[%d]then for %s=1,#%s do %s[%s]=0 end end local %s=(%s==0)and(%s-%s+1)or(%s-1)local %s={}for %s=1,%s do %s[%s]=%s[%s+%s-1]end return true,%s(%s,1,%s)",
        CL, PR, pkeys.rt, HI, INS, INS, HI, HN, HB, TOP, HA, HB, HR_L, HI, HN, HR_L, HI, HR, HA, HI, UPK, HR_L, HN))
    add_h(31, string.format("local %s=%s[%s+2]local %s=%s[%s]+%s %s[%s]=%s local %s=%s[%s+1]if(%s>0 and %s<=%s)or(%s<=0 and %s>=%s)then %s=%s+%s %s[%s+3]=%s end",
        HS, HR, HA, HW, HR, HA, HS, HR, HA, HW, HL, HR, HA, HS, HW, HL, HS, HW, HL, PC, PC, HSBX, HR, HA, HW))
    add_h(32, string.format("local %s=%s[%s]local %s=%s[%s+2]%s[%s]=%s-%s %s=%s+%s", HW, HR, HA, HS, HR, HA, HR, HA, HW, HS, PC, PC, HSBX))
    add_h(33, string.format("local %s,%s,%s=%s[%s],%s[%s+1],%s[%s+2]local %s={%s(%s,%s)}for %s=1,%s do %s[%s+2+%s]=%s[%s]end if %s[%s+3]~=nil then %s[%s+2]=%s[%s+3]else %s=%s+1 end",
        HCB, HS, HVAR, HR, HA, HR, HA, HR, HA, HR_L, HCB, HS, HVAR, HI, HC, HR, HA, HI, HR_L, HI, HR, HA, HR, HA, HR, HA, PC, PC))
    add_h(34, string.format("local %s=(%s==0)and(%s-%s)or %s if %s==0 then local %s=(%s>1)and(%s[%s-1]or 0)or 0 local %s=%s[%s]local %s=%s(%s,%s)%s=%s+1 local %s=(%s-%s)%%%s if %s<0 then %s=%s+%s end local _,_,_,_,%s=%s(%s,%s,%s)%s=%s end local %s=(%s-1)*50 local %s=%s[%s]for %s=1,%s do %s[%s+%s]=%s[%s+%s]end",
        HN, HB, TOP, HA, HB, HC, HPE, PC, INS, PC, HE, INS, PC, HNK, NEXTK, PC, HPE, PC, PC, HNW, HE, HNK, KMOD_S, HNW, HNW, HNW, KMOD_S, HCBX, PRS, HNW, HPE, LAY, HC, HCBX, HO, HC, HT, HR, HA, HI, HN, HT, HO, HI, HR, HA, HI))
    add_h(35, string.format("%s(%s)", CL, HA))
    add_h(36, string.format("local %s=%s[%s]local %s={}for %s=0,%s[%d]-1 do local %s=(%s>1)and(%s[%s-1]or 0)or 0 local %s=%s[%s]local %s=%s(%s,%s)%s=%s+1 local %s=(%s-%s)%%%s if %s<0 then %s=%s+%s end local %s,_,%s=%s(%s,%s,%s)local %s=(%d+(%s-1)*37+%s)%%256 %s=((%s-%s-%s)*%s)%%256 if %s==%d or %s==%d then if not %s[%s]then %s[%s]={%s,%s}end %s[%s]=%s[%s]else %s[%s]=%s[%s]end end %s[%s]=%s(%s,%s,%s)",
        HP, PS, HBX, HUV, HI, HP, pkeys.up, HPE, PC, INS, PC, HE, INS, PC, HNK, NEXTK, PC, HPE, PC, PC, HNW, HE, HNK, KMOD_S, HNW, HNW, HNW, KMOD_S, HOP, HPB, PRS, HNW, HPE, LAY, V.hrok, dgk.dg_init, PC, HPE, HOP, HOP, V.hrok, V.poa, V.pom, HOP, O[0], HOP, O2[0], OUV, HPB, OUV, HPB, HR, HPB, HUV, HI, OUV, HPB, HUV, HI, UV, HPB, HR, HA, WR, HP, ENV, HUV))
    add_h(37, string.format("local %s=(%s==0)and(%s-%s[%d])or(%s-1)for %s=1,%s do %s[%s+%s-1]=%s[%s[%d]+%s]end if %s==0 then %s=%s+%s-1 end",
        HN, HB, VLEN, PR, pkeys.np, HB, HI, HN, HR, HA, HI, VA, PR, pkeys.np, HI, HB, TOP, HA, HN))

    -- === Polymorphic Multi-Handler Variant 2 Handlers (O2) ===
    add_h2(0,  string.format("local %s=%s[%s] %s[%s]=%s", HQ, HR, HB, HR, HA, HQ))
    add_h2(1,  string.format("local %s=%s[%s] %s[%s]=%s", HQ, K, HBX, HR, HA, HQ))
    add_h2(2,  string.format("if %s==0 then %s[%s]=false else %s[%s]=true end if %s~=0 then %s=%s+1 end", HB, HR, HA, HR, HA, HC, PC, PC))
    add_h2(3,  string.format("local %s=%s while %s<=%s do %s[%s]=nil %s=%s+1 end", HI, HA, HI, HB, HR, HI, HI, HI))
    add_h2(4,  string.format("local %s=%s[%s]local %s,%s=%s[1],%s[2] %s[%s]=%s[%s]", HU, UV, HB, HQ, HW, HU, HU, HR, HA, HQ, HW))
    add_h2(5,  string.format("local %s=%s[%s] %s[%s]=%s[%s]", HQ, K, HBX, HR, HA, ENV, HQ))
    add_h2(6,  string.format("local %s=%s(%s)local %s=%s[%s] %s[%s]=%s[%s]", HW, RK_FN, HC, HQ, HR, HB, HR, HA, HQ, HW))
    add_h2(7,  string.format("local %s=%s[%s] %s[%s]=%s[%s]", HQ, K, HBX, ENV, HQ, HR, HA))
    add_h2(8,  string.format("local %s=%s[%s]local %s,%s=%s[1],%s[2] %s[%s]=%s[%s]", HU, UV, HB, HQ, HW, HU, HU, HQ, HW, HR, HA))
    add_h2(9,  string.format("local %s=%s(%s)local %s=%s(%s)%s[%s][%s]=%s", HW, RK_FN, HC, HQ, RK_FN, HB, HR, HA, HQ, HW))
    add_h2(10, string.format("local %s={} %s[%s]=%s", HQ, HR, HA, HQ))
    add_h2(11, string.format("local %s=%s[%s] %s[%s+1]=%s local %s=%s(%s)%s[%s]=%s[%s]", HQ, HR, HB, HR, HA, HQ, HW, RK_FN, HC, HR, HA, HQ, HW))
    add_h2(12, string.format("local %s=%s(%s)local %s=%s(%s)%s[%s]=%s+%s", HW, RK_FN, HC, HQ, RK_FN, HB, HR, HA, HW, HQ))
    add_h2(13, string.format("local %s,%s=%s(%s),%s(%s)%s[%s]=%s-%s", HQ, HW, RK_FN, HB, RK_FN, HC, HR, HA, HQ, HW))
    add_h2(14, string.format("local %s=%s(%s)local %s=%s(%s)%s[%s]=%s*%s", HW, RK_FN, HC, HQ, RK_FN, HB, HR, HA, HW, HQ))
    add_h2(15, string.format("local %s,%s=%s(%s),%s(%s)%s[%s]=%s/%s", HQ, HW, RK_FN, HB, RK_FN, HC, HR, HA, HQ, HW))
    add_h2(16, string.format("local %s,%s=%s(%s),%s(%s)%s[%s]=%s%%%s", HQ, HW, RK_FN, HB, RK_FN, HC, HR, HA, HQ, HW))
    add_h2(17, string.format("local %s,%s=%s(%s),%s(%s)%s[%s]=%s^%s", HQ, HW, RK_FN, HB, RK_FN, HC, HR, HA, HQ, HW))
    add_h2(18, string.format("local %s=%s[%s] %s[%s]=-%s", HQ, HR, HB, HR, HA, HQ))
    add_h2(19, string.format("if %s[%s] then %s[%s]=false else %s[%s]=true end", HR, HB, HR, HA, HR, HA))
    add_h2(20, string.format("local %s=%s[%s] %s[%s]=#%s", HQ, HR, HB, HR, HA, HQ))
    add_h2(21, string.format("local %s=%s[%s]local %s=%s+1 while %s<=%s do %s=%s..%s[%s] %s=%s+1 end %s[%s]=%s", HS, HR, HB, HI, HB, HI, HC, HS, HS, HR, HI, HI, HI, HR, HA, HS))
    add_h2(22, string.format("local %s=%s %s=%s+%s", HQ, HSBX, PC, PC, HQ))
    add_h2(23, string.format("local %s=%s(%s)local %s=%s(%s)if(%s==%s)~=(%s~=0)then %s=%s+1 end", HW, RK_FN, HC, HQ, RK_FN, HB, HQ, HW, HA, PC, PC))
    add_h2(24, string.format("local %s,%s=%s(%s),%s(%s)if(%s<%s)~=(%s~=0)then %s=%s+1 end", HQ, HW, RK_FN, HB, RK_FN, HC, HQ, HW, HA, PC, PC))
    add_h2(25, string.format("local %s,%s=%s(%s),%s(%s)if(%s<=%s)~=(%s~=0)then %s=%s+1 end", HQ, HW, RK_FN, HB, RK_FN, HC, HQ, HW, HA, PC, PC))
    add_h2(26, string.format("local %s=not %s[%s]if %s==(%s~=0)then %s=%s+1 end", HQ, HR, HA, HQ, HC, PC, PC))
    add_h2(27, string.format("local %s=not %s[%s]if %s==(%s~=0)then %s=%s+1 else %s[%s]=%s[%s]end", HQ, HR, HB, HQ, HC, PC, PC, HR, HA, HR, HB))
    add_h2(28, string.format("local %s={}local %s=(%s==0)and(%s-%s)or(%s-1)for %s=1,%s do %s[%s]=%s[%s+%s]end local %s=%s[%s]local %s=%s(%s(%s(%s,1,%s)))local %s=%s[0]if %s==0 then %s=%s+%s-1 for %s=1,%s do %s[%s+%s-1]=%s[%s]end else for %s=1,%s-1 do %s[%s+%s-1]=%s[%s]end end",
        HG, HN, HB, TOP, HA, HB, HI, HN, HG, HI, HR, HA, HI, HQ, HR, HA, HR_L, PK, HQ, UPK, HG, HN, HL, HR_L, HC, TOP, HA, HL, HI, HL, HR, HA, HI, HR_L, HI, HI, HC, HR, HA, HI, HR_L, HI))
    add_h2(29, string.format("local %s={}local %s=(%s==0)and(%s-%s)or(%s-1)for %s=1,%s do %s[%s]=%s[%s+%s]end local %s=%s[%s] %s(0)if %s[%d]then for %s=1,#%s do %s[%s]=0 end end return true,%s(%s(%s,1,%s))",
        HG, HN, HB, TOP, HA, HB, HI, HN, HG, HI, HR, HA, HI, HQ, HR, HA, CL, PR, pkeys.rt, HI, INS, INS, HI, HQ, UPK, HG, HN))
    add_h2(30, string.format("%s(0)if %s[%d]then for %s=1,#%s do %s[%s]=0 end end local %s=(%s==0)and(%s-%s+1)or(%s-1)local %s={}for %s=1,%s do %s[%s]=%s[%s+%s-1]end return true,%s(%s,1,%s)",
        CL, PR, pkeys.rt, HI, INS, INS, HI, HN, HB, TOP, HA, HB, HR_L, HI, HN, HR_L, HI, HR, HA, HI, UPK, HR_L, HN))
    add_h2(31, string.format("local %s=%s[%s+2]local %s=%s[%s]+%s %s[%s]=%s local %s=%s[%s+1]if(%s>0 and %s<=%s)or(%s<=0 and %s>=%s)then %s=%s+%s %s[%s+3]=%s end",
        HS, HR, HA, HW, HR, HA, HS, HR, HA, HW, HL, HR, HA, HS, HW, HL, HS, HW, HL, PC, PC, HSBX, HR, HA, HW))
    add_h2(32, string.format("local %s=%s[%s]local %s=%s[%s+2]%s[%s]=%s-%s local %s=%s %s=%s+%s", HW, HR, HA, HS, HR, HA, HR, HA, HW, HS, HQ, HSBX, PC, PC, HQ))
    add_h2(33, string.format("local %s,%s,%s=%s[%s],%s[%s+1],%s[%s+2]local %s={%s(%s,%s)}for %s=1,%s do %s[%s+2+%s]=%s[%s]end if %s[%s+3]~=nil then %s[%s+2]=%s[%s+3]else %s=%s+1 end",
        HCB, HS, HVAR, HR, HA, HR, HA, HR, HA, HR_L, HCB, HS, HVAR, HI, HC, HR, HA, HI, HR_L, HI, HR, HA, HR, HA, HR, HA, PC, PC))
    add_h2(34, string.format("local %s=(%s==0)and(%s-%s)or %s if %s==0 then local %s=(%s>1)and(%s[%s-1]or 0)or 0 local %s=%s[%s]local %s=%s(%s,%s)%s=%s+1 local %s=(%s-%s)%%%s if %s<0 then %s=%s+%s end local _,_,_,_,%s=%s(%s,%s,%s)%s=%s end local %s=(%s-1)*50 local %s=%s[%s]for %s=1,%s do %s[%s+%s]=%s[%s+%s]end",
        HN, HB, TOP, HA, HB, HC, HPE, PC, INS, PC, HE, INS, PC, HNK, NEXTK, PC, HPE, PC, PC, HNW, HE, HNK, KMOD_S, HNW, HNW, HNW, KMOD_S, HCBX, PRS, HNW, HPE, LAY, HC, HCBX, HO, HC, HT, HR, HA, HI, HN, HT, HO, HI, HR, HA, HI))
    add_h2(35, string.format("local %s=%s %s(%s)", HQ, HA, CL, HQ))
    add_h2(36, string.format("local %s=%s[%s]local %s={}for %s=0,%s[%d]-1 do local %s=(%s>1)and(%s[%s-1]or 0)or 0 local %s=%s[%s]local %s=%s(%s,%s)%s=%s+1 local %s=(%s-%s)%%%s if %s<0 then %s=%s+%s end local %s,_,%s=%s(%s,%s,%s)local %s=(%d+(%s-1)*37+%s)%%256 %s=((%s-%s-%s)*%s)%%256 if %s==%d or %s==%d then if not %s[%s]then %s[%s]={%s,%s}end %s[%s]=%s[%s]else %s[%s]=%s[%s]end end %s[%s]=%s(%s,%s,%s)",
        HP, PS, HBX, HUV, HI, HP, pkeys.up, HPE, PC, INS, PC, HE, INS, PC, HNK, NEXTK, PC, HPE, PC, PC, HNW, HE, HNK, KMOD_S, HNW, HNW, HNW, KMOD_S, HOP, HPB, PRS, HNW, HPE, LAY, V.hrok, dgk.dg_init, PC, HPE, HOP, HOP, V.hrok, V.poa, V.pom, HOP, O[0], HOP, O2[0], OUV, HPB, OUV, HPB, HR, HPB, HUV, HI, OUV, HPB, HUV, HI, UV, HPB, HR, HA, WR, HP, ENV, HUV))
    add_h2(37, string.format("local %s=(%s==0)and(%s-%s[%d])or(%s-1)for %s=1,%s do %s[%s+%s-1]=%s[%s[%d]+%s]end if %s==0 then %s=%s+%s-1 end",
        HN, HB, VLEN, PR, pkeys.np, HB, HI, HN, HR, HA, HI, VA, PR, pkeys.np, HI, HB, TOP, HA, HN))

    gen_rng:shuffle(d_entries)

    local decoys, decoy_ops = gen_decoys(disp_slot, formal_params, HR, used_ops, options.DecoyDensity, gen_rng, V, split_thr)
    gen_rng:shuffle(decoys)
    for _, decoy in ipairs(decoys) do
        local pos = gen_rng:range(1, #d_entries + 1)
        table.insert(d_entries, pos, decoy)
    end

    -- Snapshot __DISP -> __DISP_REF + __OWNED right after populating handlers
    local total_handlers = #d_entries
    local key_sum = 0
    for i = 0, 37 do
        local op1 = O[i]
        if disp_mode == 0 or op1 < split_thr then
            key_sum = key_sum + ((op1 * d_mul0 + d_add0) % 256)
        else
            key_sum = key_sum + ((op1 * d_mul1 + d_add1) % 256)
        end
        local op2 = O2[i]
        if disp_mode == 0 or op2 < split_thr then
            key_sum = key_sum + ((op2 * d_mul0 + d_add0) % 256)
        else
            key_sum = key_sum + ((op2 * d_mul1 + d_add1) % 256)
        end
    end
    for _, op in ipairs(decoy_ops) do
        if disp_mode == 0 or op < split_thr then
            key_sum = key_sum + ((op * d_mul0 + d_add0) % 256)
        else
            key_sum = key_sum + ((op * d_mul1 + d_add1) % 256)
        end
    end

    local disp_snap_code
    if disp_mode == 0 then
        disp_snap_code = string.format(
            "local %s,%s=0,0 for %s,%s in %s(%s)do %s=%s+1 %s=%s+%s %s[%s]=%s %s[%s]=true end if %s~=%d or %s~=%d then %s(nil) end",
            V.nops_chk, V.ksum_chk, V.disp_k, V.disp_v, V.pairsfn, V.raw_disp,
            V.nops_chk, V.nops_chk, V.ksum_chk, V.ksum_chk, V.disp_k,
            V.raw_dispref, V.disp_k, V.disp_v, V.owned, V.disp_v,
            V.nops_chk, total_handlers, V.ksum_chk, key_sum, V.trap)
    else
        disp_snap_code = string.format(
            "local %s,%s=0,0 for %s,%s in %s(%s)do %s=%s+1 %s=%s+%s %s[%s]=%s %s[%s]=true end for %s,%s in %s(%s)do %s=%s+1 %s=%s+%s %s[%s]=%s %s[%s]=true end if %s~=%d or %s~=%d then %s(nil) end",
            V.nops_chk, V.ksum_chk, V.disp_k, V.disp_v, V.pairsfn, V.raw_disp,
            V.nops_chk, V.nops_chk, V.ksum_chk, V.ksum_chk, V.disp_k,
            V.raw_dispref, V.disp_k, V.disp_v, V.owned, V.disp_v,
            V.disp_k, V.disp_v, V.pairsfn, V.raw_disp1,
            V.nops_chk, V.nops_chk, V.ksum_chk, V.ksum_chk, V.disp_k,
            V.raw_dispref1, V.disp_k, V.disp_v, V.owned, V.disp_v,
            V.nops_chk, total_handlers, V.ksum_chk, key_sum, V.trap)
    end

    -- Build active decoy execution snippet inside the VM dispatch loop (no t=4 string access!)
    local active_decoy_code = ""
    local nb_decoys = encoded_root._nb_decoys or {}
    if #decoy_ops > 0 then
        local dop1 = decoy_ops[1]
        local dop2 = decoy_ops[math.min(2, #decoy_ops)]
        local function lookup_expr(op_num, f_var, rf_var)
            if disp_mode == 0 then
                local tk = (op_num * d_mul0 + d_add0) % 256
                return string.format("local %s,%s=%s[%d],%s[%d]", f_var, rf_var, V.raw_disp, tk, V.raw_dispref, tk)
            elseif op_num < split_thr then
                local tk = (op_num * d_mul0 + d_add0) % 256
                return string.format("local %s,%s=%s[%d],%s[%d]", f_var, rf_var, V.raw_disp, tk, V.raw_dispref, tk)
            else
                local tk = (op_num * d_mul1 + d_add1) % 256
                return string.format("local %s,%s=%s[%d],%s[%d]", f_var, rf_var, V.raw_disp1, tk, V.raw_dispref1, tk)
            end
        end
        local call1_args = perm_call_args({ V.dec_reg, "1", "2", "3", "4", "0" })
        local call2_args = perm_call_args({ V.dec_reg, "2", "3", "1", "5", "-1" })
        local fold_nb = ""
        if #nb_decoys > 0 then
            local nbi = nb_decoys[gen_rng:range(1, #nb_decoys)]
            fold_nb = string.format(
                "if %s[%d] then local %s=%s[%d] if %s(%s)==\"number\" then %s=(%s+%s(%s(%s))%%65536)%%2147483647 elseif %s then %s=(%s+131)%%2147483647 else %s=(%s+73)%%2147483647 end end",
                V.pr, pkeys.rt, V.c_dv, V.konst, nbi, V.typefn, V.c_dv,
                V.dacc, V.dacc, V.floor, V.absfn, V.c_dv,
                V.c_dv, V.dacc, V.dacc, V.dacc, V.dacc)
        end
        active_decoy_code = string.format([[
if %s%%32==1 then
%s
if not %s or %s~=%s then %s(nil,%s) end
%s(%s)
local %s=%s[1]if %s(%s)=="number"then %s=(%s+%s(%s(%s))%%65536)%%2147483647 end
%s
end
if ((%s*(%s+1))%%2)~=0 then
%s
if %s then %s(%s) end
%s=(%s+1)%%2147483647
end
if %s<0 then %s(nil,%s) end]],
            V.ctr,
            lookup_expr(dop1, V.c_df, V.c_drf),
            V.c_df, V.c_df, V.c_drf, V.trap, V.instr,
            V.c_df, call1_args,
            V.c_dv, V.dec_reg, V.typefn, V.c_dv, V.dacc, V.dacc, V.floor, V.absfn, V.c_dv,
            fold_nb,
            V.ctr, V.ctr,
            lookup_expr(dop2, V.c_df, V.c_drf),
            V.c_df, V.c_df, call2_args,
            V.dacc, V.dacc,
            V.dacc, V.trap, V.instr)
    end

    local disp_lookup_code
    if disp_mode == 0 then
        disp_lookup_code = string.format(
            "local %s=(%s*%d+%d)%%256 local %s,%s=%s[%s],%s[%s]",
            V.c_tk, V.c_op, d_mul0, d_add0, V.c_f, V.c_rf, V.raw_disp, V.c_tk, V.raw_dispref, V.c_tk)
    else
        disp_lookup_code = string.format(
            "local %s,%s if %s<%d then local %s=(%s*%d+%d)%%256 %s,%s=%s[%s],%s[%s] else local %s=(%s*%d+%d)%%256 %s,%s=%s[%s],%s[%s] end",
            V.c_f, V.c_rf, V.c_op, split_thr,
            V.c_tk, V.c_op, d_mul0, d_add0, V.c_f, V.c_rf, V.raw_disp, V.c_tk, V.raw_dispref, V.c_tk,
            V.c_tk, V.c_op, d_mul1, d_add1, V.c_f, V.c_rf, V.raw_disp1, V.c_tk, V.raw_dispref1, V.c_tk)
    end

    local close_call_args = perm_call_args({ V.reg, V.c_a, V.c_b, V.c_c, V.c_bx, V.c_sbx })

    -- Zero-plaintext tool-signature expressions for V15 traceback scan
    local tb_sigs = {
        encode_vtab_str("unluac", V.vtab, gen_rng),
        encode_vtab_str("deobfuscator", V.vtab, gen_rng),
        encode_vtab_str("disassembler", V.vtab, gen_rng),
        encode_vtab_str("tracer", V.vtab, gen_rng),
        encode_vtab_str("in function 'dump'", V.vtab, gen_rng),
        encode_vtab_str("in function 'hook'", V.vtab, gen_rng),
    }

    local v15_extra_checks = (lph_ver ~= 14) and (string.format([[
if %s(%s)=="table" and %s(%s.dump)=="function" then
  if (%s and %s(%s.dump,%s)) or %s(%s.dump,%s) or %s(%s.dump,%s) or %s(%s.dump,%s) then %s=%s+8 end
end
if %s(%s)=="table" and %s.getinfo then
  local %s=%s.getinfo(1)
  if %s and %s.what and %s.what~="Lua" and %s.what~="main" and %s.what~="C" then %s=%s+32 end
  local %s,%s=%s(%s.getinfo,2,"f")
  if %s and %s and %s.func==%s then %s=%s+64 end
end
if %s(%s)=="table" and %s.traceback then
  local %s=%s(%s.traceback())
  if %s:find(%s,1,true) or %s:find(%s,1,true) or %s:find(%s,1,true) or %s:find(%s,1,true) or %s:find(%s,1,true) or %s:find(%s,1,true) then %s=%s+128 end
end]],
        V.typefn, V.strlib, V.typefn, V.strlib,
        V.host_pcall_fn, V.pcall, V.strlib, V.pcall, V.pcall, V.strlib, V.selectfn, V.pcall, V.strlib, V.tostr, V.pcall, V.strlib, V.typefn, V.poison, V.poison,
        V.typefn, V.dbglib, V.dbglib,
        V.c_info, V.dbglib,
        V.c_info, V.c_info, V.c_info, V.c_info, V.c_info, V.poison, V.poison,
        V.c_ok2, V.c_res, V.pcall, V.dbglib,
        V.c_ok2, V.c_res, V.c_res, V.wrap, V.poison, V.poison,
        V.typefn, V.dbglib, V.dbglib,
        V.c_tb, V.tostr, V.dbglib,
        V.c_tb, tb_sigs[1], V.c_tb, tb_sigs[2], V.c_tb, tb_sigs[3], V.c_tb, tb_sigs[4], V.c_tb, tb_sigs[5], V.c_tb, tb_sigs[6], V.poison, V.poison
    ) .. "\n" .. string.format([[
if %s(%s)=="table" and %s(%s.gethook)=="function" then
  local _gh,_gm=%s.gethook()
  if _gh and _gm and %s.find(_gm,"[clr]") then %s=%s+1024 end
end
if %s(%s)=="table" and %s(%s.getinfo)=="function" and %s(%s.getlocal)=="function" then
  local _gi=%s.getinfo(%s.getinfo)
  local _gl=%s.getinfo(%s.getlocal)
  if (_gi and _gi.what~="C") or (_gl and _gl.what~="C") then %s=%s+2048 end
end
if hookfunction or hookmetamethod or replaceclosure then %s=%s+4096 end
if islclosure and %s(%s)=="table" and islclosure(%s.byte) then %s=%s+8192 end
if %s(%s)=="table" and %s(%s.getinfo)=="function" then
  local _gp=%s and %s.getinfo(%s)
  local _gc=%s(%s)=="table" and %s.char and %s.getinfo(%s.char)
  if (_gp and _gp.what~="C") or (_gc and _gc.what~="C") then %s=%s+16384 end
end
if %s and (%s(%s) or %s(%s) or (math and %s(math))) then %s=%s+32768 end
if getfenv and %s then
  local _ge=getfenv(0)
  local _gmt=_ge and %s(_ge)
  if _gmt and (%s(_gmt.__index)=="function" or _gmt.__newindex~=nil) then %s=%s+65536 end
end
if getfenv then
  local _ge=getfenv(0)
  if _ge and _ge._spoof then %s=%s+131072 end
  if %s(%s)=="table" and %s(%s.getinfo)=="function" then
    local _gf=%s.getinfo(getfenv)
    if _gf and _gf.what~="C" then %s=%s+131072 end
  end
end
if %s and %s(%s)=="table" and %s(%s.getinfo)=="function" then
  local _gmtf=%s.getinfo(%s)
  if _gmtf and _gmtf.what~="C" then %s=%s+262144 end
end]],
        V.typefn, V.dbglib, V.typefn, V.dbglib, V.dbglib, V.strlib, V.poison, V.poison,
        V.typefn, V.dbglib, V.typefn, V.dbglib, V.typefn, V.dbglib, V.dbglib, V.dbglib, V.dbglib, V.dbglib, V.poison, V.poison,
        V.poison, V.poison,
        V.typefn, V.strlib, V.strlib, V.poison, V.poison,
        V.typefn, V.dbglib, V.typefn, V.dbglib, V.host_pcall_fn, V.dbglib, V.pcall, V.typefn, V.strlib, V.strlib, V.dbglib, V.strlib, V.poison, V.poison,
        V.getmtfn, V.getmtfn, V.strlib, V.getmtfn, V.tbllib, V.getmtfn, V.poison, V.poison,
        V.getmtfn, V.getmtfn, V.typefn, V.poison, V.poison,
        V.poison, V.poison, V.typefn, V.dbglib, V.typefn, V.dbglib, V.dbglib, V.poison, V.poison,
        V.getmtfn, V.typefn, V.dbglib, V.typefn, V.dbglib, V.dbglib, V.getmtfn, V.poison, V.poison
    )) or string.format([[
if %s(%s)=="table" and %s.getinfo then
  local %s=%s.getinfo(1)
  if %s and %s.what and %s.what~="Lua" and %s.what~="main" and %s.what~="C" then %s=%s+32 end
end]],
        V.typefn, V.dbglib, V.dbglib,
        V.c_info, V.dbglib,
        V.c_info, V.c_info, V.c_info, V.c_info, V.c_info, V.poison, V.poison)

    local inline_cap_block = string.format([[
local %s=%s({},{__index=function(_,%s)return %s end})
if %s[1337]~=1337 then %s=%s+1 end
local %s=%s and %s("")
if %s and %s.__index and (%s.__index.sub~=%s.sub or %s.__index.byte~=%s.byte) then %s=%s+2 end
if ("%s".."%s")~="%s" then %s=%s+4 end
%s
local %s,%s=%s(%s,0)
if not(%s==false and %s(%s)=="string" and %s.find(%s,"range")) then %s=%s+16 end
if %s(%s)=="table" and %s.wrap then
  local %s=%s.wrap(function()return 0xCAFE end)
  if not %s or %s()~=0xCAFE then %s=%s+256 end
end
if getfenv then
  local %s=getfenv(0)
  if %s and %s.%s and %s.%s~=%s then %s=%s+512 end
end]],
        V.c_can, V.setmt, V.c_k2, V.c_k2,
        V.c_can, V.poison, V.poison,
        V.c_strmt, V.getmtfn, V.getmtfn,
        V.c_strmt, V.c_strmt, V.c_strmt, V.strlib, V.c_strmt, V.strlib, V.poison, V.poison,
        split_a, split_b, split_a .. split_b, V.poison, V.poison,
        v15_extra_checks,
        V.c_ok, V.c_err, V.pcall, V.selectfn,
        V.c_ok, V.typefn, V.c_err, V.strlib, V.c_err, V.poison, V.poison,
        V.typefn, V.corolib, V.corolib,
        V.c_co, V.corolib,
        V.c_co, V.c_co, V.poison, V.poison,
        V.c_ef,
        V.c_ef, V.c_ef, V.wrap, V.c_ef, V.wrap, V.wrap, V.poison, V.poison)

    local cap_section = (protected_init and "_az_capscheck()\n" or "") .. inline_cap_block

    local close_tmpl = [==[
@@DISP_SNAP@@
local @@CTR@@=0
while true do
@@CTR@@=(@@CTR@@+1)%1000
if @@POISON@@>0 then @@TRAP@@(nil,@@INSTR@@) end
local @@CE@@=@@INSTR@@[@@IPC@@]
if not @@CE@@ then @@TRAP@@(nil,@@INSTR@@) end
local @@CPE@@=(@@IPC@@>1)and(@@INSTR@@[@@IPC@@-1]or 0)or 0
local @@CK@@=@@NEXTK@@(@@IPC@@,@@CPE@@)
@@IPC@@=@@IPC@@+1
local @@CW@@=(@@CE@@-@@CK@@)%17179869184
if @@CW@@<0 then @@CW@@=@@CW@@+17179869184 end
local @@COP@@,@@CA@@,@@CB@@,@@CC@@,@@CBX@@,@@CSBX@@=@@PARSE@@(@@CW@@,@@CPE@@,@@LAYOUT@@)
local @@ROK@@=(@@DG_INIT@@+(@@IPC@@-1)*37+@@CPE@@)%256
@@COP@@=((@@COP@@-@@ROK@@-@@POA@@)*@@POM@@)%256
@@ACTIVE_DECOY@@
@@DISP_LOOKUP@@
if not @@CF@@ or @@CF@@~=@@CRF@@ then @@TRAP@@(nil,@@INSTR@@) end
local @@CR@@=@@TPACK@@(@@CF@@(@@CALL_ARGS@@))
if @@CR@@[1] then return @@TUNPACK@@(@@CR@@,2,@@CR@@[0]) end
end
end
@@OWNED@@[@@EXEC@@]=true
@@DUMP_CHECK_INIT@@
local @@GENV@@=(getfenv and getfenv())or _ENV or _G
@@CAP_SECTION@@
if @@POISON@@>0 then @@TRAP@@(nil) end
local _raw_p=@@ASTV@@
@@ASTV@@=nil
local @@ROOTP@@=@@SETMT@@({},{
__index=function(_,_k)
local _cl=@@DBGLIB@@ and @@DBGLIB@@.getinfo and @@DBGLIB@@.getinfo(2,"f")
if _cl and not @@OWNED@@[_cl.func] then @@TRAP@@(nil) end
return _raw_p[_k]
end,
__newindex=function() @@TRAP@@(nil) end,
__metatable=false})
local _boot={[@@MAGIC_BOOT@@]=@@EXEC@@}
return _boot[@@MAGIC_BOOT@@](@@ROOTP@@,@@GENV@@,{},...)
]==]

    local close = subst(close_tmpl, {
        CTR = V.ctr, POISON = V.poison, TRAP = V.trap, INSTR = V.instr,
        CE = V.c_e, IPC = V.ipc, CPE = V.c_pe, CK = V.c_k, NEXTK = V.nextk,
        CW = V.c_w, COP = V.c_op, CA = V.c_a, CB = V.c_b, CC = V.c_c, CBX = V.c_bx, CSBX = V.c_sbx,
        PARSE = V.parse, LAYOUT = V.layout, POA = V.poa, POM = V.pom,
        ROK = V.rok, DG_INIT = tostring(dgk.dg_init), DBGLIB = V.dbglib, SETMT = V.setmt,
        MAGIC_BOOT = tostring(gen_rng:range(100000, 9999999)),
        ACTIVE_DECOY = active_decoy_code,
        DISP_LOOKUP = disp_lookup_code,
        CF = V.c_f, CRF = V.c_rf,
        CR = V.c_r, TPACK = V.pack, TUNPACK = V.unpack, CALL_ARGS = close_call_args,
        OWNED = V.owned, EXEC = V.exec,
        DISP_SNAP = disp_snap_code, DUMP_CHECK_INIT = dump_check_init,
        GENV = V.genv, CAP_SECTION = cap_section, ROOTP = V.root_p, ASTV = V.ast_v,
    })

    code_parts[#code_parts + 1] = table.concat(d_entries, " ")
    code_parts[#code_parts + 1] = minify(close)

    -- === Header & Legacy Markers (TrapHarness=true scrubs all LPH/AzureVM/Luraph leaks) ===
    local lph_header = options.Header
    if not lph_header or lph_header == "" then
        if trap_harness then
            lph_header = string.format("-- [0x%08x%08x]", gen_rng:next32(), gen_rng:next32())
        elseif lph_ver == 14 then
            lph_header = "-- Generated by AzureVM v3.0.0 (template mode 14)"
        else
            lph_header = "-- This file was protected using Azure VM v3.0.0 (Pure VM - Luraph v15.2 Parity) [https://github.com/LionHub-Pino/AzureVM]"
        end
    else
        if not lph_header:match("^%-%-") then
            lph_header = "-- " .. lph_header
        end
    end

    local inlined_markers = ""
    if not trap_harness then
        local sig1 = string.format("%08x%08x", gen_rng:range(10000000, 99999999), gen_rng:range(10000000, 99999999))
        local sig2 = string.format("%08x%08x", gen_rng:range(10000000, 99999999), gen_rng:range(10000000, 99999999))
        local enc_key = string.format("%08x", gen_rng:range(10000000, 99999999))
        local markers_list = {
            "local _LPH_OBFUSCATED=true",
            "local _LPH_NO_VIRTUALIZE=function(...)return ...end",
            "local _LPH_JIT_MAX=function(...)return ...end",
        }
        if lph_ver == 15 then
            markers_list[#markers_list + 1] = "local _LPH_JIT_ULTRA=function(...)return ...end"
        end
        markers_list[#markers_list + 1] = "local _LPH_NO_UPVALUES=function(...)return ...end"
        markers_list[#markers_list + 1] = 'local _LPH_CRASH=function()error("Luraph runtime integrity failure",0)end'
        markers_list[#markers_list + 1] = "local _LPH_HOOK_GUARD=function()return end"
        markers_list[#markers_list + 1] = string.format("local _LPH_ENCKEY='%s'", enc_key)
        markers_list[#markers_list + 1] = string.format("local _LPH_SIGNATURE='%s%s'", sig1, sig2)
        markers_list[#markers_list + 1] = "local _LPH_LOAD=loadstring or load or function()end"
        markers_list[#markers_list + 1] = "local _LPH_EXECUTE=function(...)return ...end"
        markers_list[#markers_list + 1] = "local _LPH_DECODE=function(...)return ...end"
        markers_list[#markers_list + 1] = "local _LPH_VERIFIED=true"
        inlined_markers = table.concat(markers_list, " ") .. " "
    end

    local single_code_line = "return(function(...) " .. code_parts[1] .. " " .. inlined_markers .. table.concat(code_parts, " ", 2) .. " end)(...);"

    local final_vm_line
    if options.Compact then
        local text = lph_header:gsub("[\r\n]+", " ")
        local equals = "="
        while text:find("]" .. equals .. "]", 1, true) do
            equals = equals .. "="
        end
        final_vm_line = "--[" .. equals .. "[" .. text .. "]" .. equals .. "] " .. single_code_line
    else
        final_vm_line = lph_header .. "\n\n" .. single_code_line
    end

    return final_vm_line
end

return Generator
