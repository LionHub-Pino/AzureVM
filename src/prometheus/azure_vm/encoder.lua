--[[
    AzureVM binary prototype serializer
    - Encodes Lua 5.1 prototype tree to compact BINARY (not Lua table text)
    - F1: Pure-Lua 32-bit ARX PRNG & KDF, 128-bit 2-pass bi-directional S-box+ARX blob cipher,
          128-bit nonce-bound string cipher, and 34-bit 2-round folded instruction keystream
    - F2: Per-constant encrypted 8-byte IEEE-754 doubles, masked/tagged booleans, and decoy constants
    - F3: Polymorphic binary wire descriptor (`vm_spec`): shuffled header fields, section order,
          constant tags, Ascii85 alphabet, and 24-permutation instruction bitfields
    - F5: Per-prototype + instruction + metadata integrity digest (`dg`)
]]

local Encoder = {}

local POW2_16 = 65536
local POW2_17 = 131072
local POW2_32 = 4294967296
local POW2_34 = 17179869184
local DG_MOD  = 4294967291

local DECOY_STRINGS = {
    "game", "Workspace", "Players", "LocalPlayer", "Character", "Humanoid",
    "HttpGet", "HttpPost", "syn", "request", "identifyexecutor",
    "https://lura.ph/api/v2/loader", "LPH_VERIFIED_SIGNATURE_KEY",
    "Invalid License Key Provided", "Tamper Detected! Terminating session...",
    "loadstring", "setreadonly", "hookmetamethod", "hookfunction",
    "getrawmetatable", "checkcaller", "islclosure", "getgenv", "rconsoleprint",
    "LPH_JIT_MAX", "LPH_JIT_ULTRA", "LPH_OBFUSCATED", "LPH_NO_VIRTUALIZE",
    "LPH_NO_UPVALUES", "LPH_CRASH", "LPH_HOOK_GUARD", "LPH_ENCKEY",
    "_LPH_EXECUTE", "_LPH_WRAP", "_LPH_DECODE", "_LPH_PAYLOAD",
    "https://lura.ph/api/v3/verify", "Luraph License Verified",
    "debug.getinfo", "debug.sethook", "debug.traceback", "debug.getupvalue",
    "coroutine.wrap", "pcall", "select", "setfenv", "getfenv",
    "Integrity check failed", "Hook detected", "Protected by Luraph",
    "Runtime signature mismatch", "LPH_SIGNATURE_VERIFIED",
    "ReplicatedStorage", "HttpService", "RunService", "TweenService",
    "TeleportService", "UserInputService", "RenderStepped", "Heartbeat", "Stepped",
    "FindFirstChild", "WaitForChild", "FireServer", "InvokeServer", "OnClientEvent",
    "Destroy", "Clone", "Connect", "Disconnect", "Parent", "Position", "CFrame",
    "Vector3", "CFrame.new", "Vector3.new", "Instance.new", "math.clamp"
}

local DECOY_NUMBERS = {
    0, 1, -1, 0.5, -0.25, 42, 255, 1024, 65537, 3.14159265, -17.25, 0.0009765625
}

-- =====================================================================
-- PURE-LUA 32-BIT ARX PRNG & KDF (< 2^53 EXACT ARITHMETIC)
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

local function make_prng(seed, salt)
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
    function obj:next32()
        return next32()
    end
    function obj:next34()
        return next32() + (next32() % 4) * POW2_32
    end
    function obj:range(lo, hi)
        return lo + (next32() % (hi - lo + 1))
    end
    function obj:odd17()
        return 65537 + (next32() % 32768) * 2
    end
    function obj:odd20()
        return 65537 + (next32() % 491520) * 2
    end
    function obj:shuffle(t)
        for i = #t, 2, -1 do
            local j = 1 + (next32() % i)
            t[i], t[j] = t[j], t[i]
        end
        return t
    end
    return obj
end

local function derive_sbox(k0, k1, k2, k3, mult)
    local s, inv = {}, {}
    for i = 0, 255 do s[i] = i end
    local st0 = (k0 + k2 + 1) % POW2_32
    local st1 = (k1 + k3 + 3) % POW2_32
    for i = 255, 1, -1 do
        st0 = (st0 * mult + st1 + i * 257) % POW2_32
        local hi = math.floor(st0 / POW2_16)
        local lo = st0 % POW2_16
        st1 = (hi * 65537 + lo * 257 + st1 + k1) % POW2_32
        local j = (st0 + st1) % (i + 1)
        s[i], s[j] = s[j], s[i]
    end
    for i = 0, 255 do inv[s[i]] = i end
    return s, inv
end

-- Generate all 24 permutations of {op(8), a(8), b(9), c(9)} bitfield packings
local function build_all_24_layouts()
    local fields = {
        { name = "op", bits = 8, mod = 256 },
        { name = "a",  bits = 8, mod = 256 },
        { name = "b",  bits = 9, mod = 512 },
        { name = "c",  bits = 9, mod = 512 },
    }
    local perms = {}
    local function permute(arr, l)
        if l == 4 then
            local shift = 0
            local spec = {}
            for idx = 1, 4 do
                local f = arr[idx]
                spec[idx] = {
                    name = f.name,
                    bits = f.bits,
                    mod = f.mod,
                    shift = shift,
                    mul = 2 ^ shift,
                }
                shift = shift + f.bits
            end
            perms[#perms + 1] = spec
            return
        end
        for i = l, 4 do
            arr[l], arr[i] = arr[i], arr[l]
            permute(arr, l + 1)
            arr[l], arr[i] = arr[i], arr[l]
        end
    end
    permute({ fields[1], fields[2], fields[3], fields[4] }, 1)
    return perms
end

local ALL_24_LAYOUTS = build_all_24_layouts()

-- =====================================================================
-- BINARY SERIALIZATION HELPERS
-- =====================================================================
local function w16(n)
    n = math.floor(n) % POW2_16
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function w32(n)
    n = math.floor(n) % POW2_32
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function w64_double_bytes(v)
    if v ~= v then return { 0, 0, 0, 0, 0, 0, 248, 127 } end
    local sign = 0
    if v < 0 or (v == 0 and 1 / v < 0) then sign = 1 end
    v = math.abs(v)
    local exp, m52
    if v == math.huge then
        exp, m52 = 2047, 0
    elseif v == 0 then
        exp, m52 = 0, 0
    elseif v < 2^-1022 then
        exp, m52 = 0, v / 2^-1074
    else
        local fraction, exponent = math.frexp(v)
        exp = exponent + 1022
        m52 = (fraction * 2 - 1) * 2^52
    end
    local b = {}
    for i = 1, 6 do
        b[i] = m52 % 256
        m52 = math.floor(m52 / 256)
    end
    b[7] = (exp % 16) * 16 + (m52 % 16)
    b[8] = sign * 128 + math.floor(exp / 16)
    return b
end

local function mod_inverse_256(m)
    for inv = 1, 255, 2 do
        if (m * inv) % 256 == 1 then
            return inv
        end
    end
    return 1
end

-- =====================================================================
-- F1 / F2 PRIMITIVE CIPHERS (used during serialize_to_blob)
-- =====================================================================
function Encoder:inst_key(i, prev_enc, pk)
    local ik = self.inst_keys
    local p_lo = prev_enc % POW2_17
    local p_hi = math.floor(prev_enc / POW2_17)
    local h = (ik.ik0 + i * ik.im1 + p_lo * ik.im2 + p_hi * ik.im3 + ik.ia1 + pk * 65537) % POW2_34
    local h_lo = h % POW2_17
    local h_hi = math.floor(h / POW2_17)
    local rot = h_lo * POW2_17 + h_hi
    return (rot * ik.im2 + h_hi * ik.im3 + ik.ia1) % POW2_34
end

local function encrypt_string_f1(bytes_in, nonce, sk, sm, sr0, S1, S2)
    local n = #bytes_in
    local out = {}
    local s0 = rotl32((((sk[1] + nonce) % POW2_32) * sm[1] + sk[2]) % POW2_32, sr0)
    local s1 = (sk[3] + (nonce * sm[2]) % POW2_32 + sk[4]) % POW2_32
    for _ = 1, 2 do
        s0 = rotl32((((s0 + s1 + 1) % POW2_32) * sm[1]) % POW2_32, sr0)
        s1 = (((s1 + s0 + sk[4]) % POW2_32) * sm[2]) % POW2_32
    end
    for i = 1, n do
        local b = bytes_in[i]
        local ks = (S1[(s0 + s1) % 256] + math.floor(s0 / 16777216) + math.floor(s1 / POW2_16)) % 256
        local enc = S2[(b + ks + (i % 256)) % 256]
        out[i] = string.char(enc)
        s0 = rotl32((((s0 + enc + i) % POW2_32) * sm[1]) % POW2_32, sr0)
        s1 = (((s1 + math.floor(s0 / POW2_16) + (s0 % POW2_16) * 257 + enc) % POW2_32) * sm[2]) % POW2_32
    end
    return table.concat(out)
end

local function encrypt_number_f2(val, n_nonce, pk, ci, nk, nm, nr0, perm8, S1, S2)
    local raw8 = w64_double_bytes(val)
    local s0 = rotl32((((nk[1] + n_nonce) % POW2_32) * nm[1] + pk * 65537 + ci) % POW2_32, nr0)
    local s1 = (nk[2] + (n_nonce * nm[2]) % POW2_32 + pk * 257) % POW2_32
    local enc8 = {}
    for idx = 1, 8 do
        local pos_b = perm8[idx]
        local ks = (S1[(s0 + s1) % 256] + math.floor(s0 / 16777216) + math.floor(s1 / POW2_16)) % 256
        local eb = S2[(raw8[pos_b] + ks + idx) % 256]
        enc8[idx] = string.char(eb)
        s0 = rotl32((((s0 + eb + idx) % POW2_32) * nm[1]) % POW2_32, nr0)
        s1 = (((s1 + math.floor(s0 / POW2_16) + (s0 % POW2_16) * 257 + eb) % POW2_32) * nm[2]) % POW2_32
    end
    return w32(n_nonce) .. table.concat(enc8)
end

local function encrypt_bool_f2(val, r_mask, bool_key, pk, ci, S1)
    local mask = (S1[(r_mask + bool_key + pk + ci) % 256] + math.floor(bool_key / 256)) % 256
    local tag_bit = (r_mask % 128) * 2 + (val and 1 or 0)
    local enc_b = (tag_bit + mask) % 256
    return string.char(r_mask, enc_b)
end

-- 2-pass bi-directional 128-bit S-box + ARX blob cipher
local function azure_encrypt_f1(data, bk, bm, br, S1, S2)
    local n = #data
    local buf = {}
    -- Pass 1: forward 1..n
    local s0, s1 = bk[1], bk[2]
    for i = 1, n do
        local b = data:byte(i)
        local ks = (S1[(s0 + s1) % 256] + math.floor(s0 / 16777216) + math.floor(s1 / POW2_16)) % 256
        local enc = S2[(b + ks) % 256]
        buf[i] = enc
        s0 = rotl32((((s0 + enc + i) % POW2_32) * bm[1]) % POW2_32, br[1])
        s1 = (((s1 + math.floor(s0 / POW2_16) + (s0 % POW2_16) * 257 + enc) % POW2_32) * bm[2]) % POW2_32
    end
    -- Pass 2: backward n..1
    s0, s1 = bk[3], bk[4]
    local out = {}
    for i = n, 1, -1 do
        local b = buf[i]
        local ks = (S2[(s0 + s1) % 256] + math.floor(s0 / 16777216) + math.floor(s1 / POW2_16)) % 256
        local enc = S1[(b + ks) % 256]
        out[i] = string.char(enc)
        s0 = rotl32((((s0 + enc + i) % POW2_32) * bm[3]) % POW2_32, br[2])
        s1 = (((s1 + math.floor(s0 / POW2_16) + (s0 % POW2_16) * 257 + enc) % POW2_32) * bm[4]) % POW2_32
    end
    return table.concat(out)
end

local function payload_checksum(data)
    local a, b = 1, 0
    for i = 1, #data do
        a = (a + data:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local function base85_z_encode_f3(data, a85_alpha)
    local result = {}
    local pad = (4 - (#data % 4)) % 4
    if pad > 0 then data = data .. string.rep("\0", pad) end
    for i = 1, #data, 4 do
        local b1, b2, b3, b4 = data:byte(i, i + 3)
        local val = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
        if val == 0 then
            result[#result + 1] = "z"
        else
            local chunk = {}
            for j = 5, 1, -1 do
                chunk[j] = a85_alpha[val % 85]
                val = math.floor(val / 85)
            end
            result[#result + 1] = table.concat(chunk)
        end
    end
    return table.concat(result), pad
end

-- =====================================================================
-- Encoder constructor (100% pure-Lua ARX PRNG, zero math.random)
-- =====================================================================
function Encoder.new(seed)
    seed = seed or require("prometheus.azure_vm.seed").random()
    local self = setmetatable({}, { __index = Encoder })
    self.seed = seed

    -- Primary deterministic PRNG (pure Lua ARX, Lua 5.1 / LuaJIT identical)
    local rng = make_prng(seed, 0)
    self._rng = rng

    -- Dynamic Multi-Handler Opcode Scrambling (0..37 mapped to 2 unique variants in 1..250)
    local used = {}
    self.opcode_map = {}
    self.reverse_op_map = {}
    self.opcode_map2 = {}
    self.reverse_op_map2 = {}
    for op = 0, 37 do
        local r1
        repeat r1 = rng:range(1, 250) until not used[r1]
        used[r1] = true
        self.opcode_map[op] = r1
        self.reverse_op_map[r1] = op

        local r2
        repeat r2 = rng:range(1, 250) until not used[r2]
        used[r2] = true
        self.opcode_map2[op] = r2
        self.reverse_op_map2[r2] = op
    end

    -- Legacy fields kept for encode_prototype whitebox compatibility
    self.initial_key = rng:range(100000, 9999999)
    self.l_mult = 1664525
    self.l_add  = 1013904223
    self.l_mod  = POW2_34
    self.str_key = rng:range(13, 241)
    self.used_string_nonces = {}

    -- Hardened F1 / F2 / F3 / F5 key schedule derived via independent domain PRNG
    local hrng = make_prng(seed, 2770310097) -- 0xA51F93D1
    self.blob_keys = { hrng:next32(), hrng:next32(), hrng:next32(), hrng:next32() }
    self.bm = { hrng:odd20(), hrng:odd20(), hrng:odd20(), hrng:odd20() }
    self.br = { hrng:range(5, 27), hrng:range(5, 27) }

    self.str_keys = { hrng:next32(), hrng:next32(), hrng:next32(), hrng:next32() }
    self.sm = { hrng:odd20(), hrng:odd20() }
    self.sr0 = hrng:range(5, 27)

    self.num_keys = { hrng:next32(), hrng:next32() }
    self.nm = { hrng:odd20(), hrng:odd20() }
    self.nr0 = hrng:range(5, 27)
    self.bool_key = hrng:range(1, 65535)
    self.perm8 = hrng:shuffle({ 1, 2, 3, 4, 5, 6, 7, 8 })

    self.inst_keys = {
        ik0 = hrng:next34(),
        ia1 = hrng:next34(),
        im1 = hrng:odd17(),
        im2 = hrng:odd17(),
        im3 = hrng:odd17(),
        layout_salt = hrng:range(0, 255),
    }

    self.dg_keys = {
        dg_init = hrng:range(1, DG_MOD - 1),
        dg_mul = hrng:odd17(),
    }

    self.sbox1, self.sbox1_inv = derive_sbox(self.blob_keys[1], self.blob_keys[2], self.blob_keys[3], self.blob_keys[4], self.bm[1])
    self.sbox2, self.sbox2_inv = derive_sbox(self.blob_keys[3], self.blob_keys[4], self.blob_keys[1], self.blob_keys[2], self.bm[3])

    -- Polymorphic binary wire specification
    local tag_pool = {}
    for b = 0, 255 do tag_pool[b + 1] = b end
    hrng:shuffle(tag_pool)

    local a85_chars = {}
    for b = 33, 117 do a85_chars[#a85_chars + 1] = string.char(b) end
    hrng:shuffle(a85_chars)
    local a85_alpha = {}
    for idx = 0, 84 do a85_alpha[idx] = a85_chars[idx + 1] end

    local layout_pool = {}
    for i = 1, #ALL_24_LAYOUTS do layout_pool[i] = ALL_24_LAYOUTS[i] end
    hrng:shuffle(layout_pool)

    local prefix_chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789_+-.:;~@"
    local plen = hrng:range(4, 9)
    local pbuf = {}
    for i = 1, plen do
        local idx = hrng:range(1, #prefix_chars)
        pbuf[i] = prefix_chars:sub(idx, idx)
    end
    local pstr = table.concat(pbuf)
    if pstr:sub(1, 4) == "LPH>" then pstr = "X" .. pstr end

    local pkey_ids = hrng:shuffle({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 })
    local pkeys = {
        np = pkey_ids[1], up = pkey_ids[2], ms = pkey_ids[3], iv = pkey_ids[4],
        om = pkey_ids[5], oa = pkey_ids[6], lm = pkey_ids[7], pk = pkey_ids[8],
        ins = pkey_ids[9], ks = pkey_ids[10], ps = pkey_ids[11], rt = pkey_ids[12],
        dg = pkey_ids[13],
    }

    self.vm_spec = {
        proto_field_order = hrng:shuffle({ "np", "up", "ms", "iv", "om", "oa", "lm", "pk", "dg" }),
        section_order = hrng:shuffle({ "ins", "ks", "ps" }),
        const_tags = { [0] = tag_pool[1], [1] = tag_pool[2], [3] = tag_pool[3], [4] = tag_pool[4] },
        const_branch_order = hrng:shuffle({ 0, 1, 3, 4 }),
        a85_alpha = a85_alpha,
        a85_str = table.concat(a85_chars),
        layouts = { [0] = layout_pool[1], [1] = layout_pool[2], [2] = layout_pool[3] },
        prefix = pstr,
        proto_keys = pkeys,
    }

    return self
end

-- =====================================================================
-- Intermediate per-constant string encoding (compatible with whitebox tests)
-- =====================================================================
function Encoder:encrypt_string(str)
    local nonce
    repeat nonce = self._rng:range(1, 2147483646) until not self.used_string_nonces[nonce]
    self.used_string_nonces[nonce] = true
    local bytes = {}
    local state = (self.str_key + nonce) % 2147483647
    for i = 1, #str do
        local b = str:byte(i)
        local enc = (b + state % 256 + i) % 256
        bytes[i] = enc
        state = (state * 48271 + enc + i) % 2147483647
    end
    return bytes, nonce
end

-- =====================================================================
-- Encode prototype tree recursively
-- =====================================================================
function Encoder:encode_prototype(proto)
    local layout_mode = self._rng:range(0, 2)
    local op_mul = 1 + self._rng:range(0, 127) * 2
    local op_add = self._rng:range(0, 255)
    local op_minv = mod_inverse_256(op_mul)

    local encoded = {
        s  = proto.source or "",
        np = proto.numParams or 0,
        up = proto.numUpvalues or 0,
        ms = proto.maxStackSize or 0,
        iv = proto.isVararg or 0,
        om = op_minv,
        oa = op_add,
        lm = layout_mode,
        ks = {},
        ins = {},
        ps = {},
        _nb_decoys = {},
    }

    -- Real constants
    local max_ci = -1
    for ci, c in pairs(proto.constants) do
        if type(ci) == "number" and ci > max_ci then max_ci = ci end
        local ct = c.type
        if ct == 4 then
            local bytes, nonce = self:encrypt_string(c.value)
            encoded.ks[ci] = { t = 4, v = bytes, nonce = nonce, rl = #c.value }
        elseif ct == 3 then
            encoded.ks[ci] = { t = 3, v = c.value }
        elseif ct == 1 then
            encoded.ks[ci] = { t = 1, v = c.value }
        else
            encoded.ks[ci] = { t = 0, v = nil }
        end
    end

    -- Inject decoy constants (strings, numbers, and booleans) after max_ci
    local nc = max_ci + 1
    for _, decoy in ipairs(DECOY_STRINGS) do
        if self._rng:range(1, 3) == 1 then
            local bytes, nonce = self:encrypt_string(decoy)
            encoded.ks[nc] = { t = 4, v = bytes, nonce = nonce, rl = #decoy }
            nc = nc + 1
        end
    end
    local num_decoy_n = self._rng:range(3, 6)
    for _ = 1, num_decoy_n do
        local nv = DECOY_NUMBERS[self._rng:range(1, #DECOY_NUMBERS)]
        encoded.ks[nc] = { t = 3, v = nv }
        encoded._nb_decoys[#encoded._nb_decoys + 1] = nc
        nc = nc + 1
    end
    local bool_decoy_n = self._rng:range(2, 3)
    for _ = 1, bool_decoy_n do
        local bv = (self._rng:range(0, 1) == 1)
        encoded.ks[nc] = { t = 1, v = bv }
        encoded._nb_decoys[#encoded._nb_decoys + 1] = nc
        nc = nc + 1
    end

    -- Intermediate instructions (preserving chained-layout contract)
    local prev_enc = 0
    for i, inst in ipairs(proto.instructions) do
        local std_op = inst.op
        local variant = ((i + prev_enc) % 2 == 0) and 1 or 2
        local global_op = (variant == 1) and (self.opcode_map[std_op] or std_op) or (self.opcode_map2[std_op] or self.opcode_map[std_op] or std_op)
        local rand_op = (global_op * op_mul + op_add) % 256
        local a, b, c = inst.a, inst.b, inst.c
        if std_op == 1 or std_op == 5 or std_op == 7 or std_op == 36
           or std_op == 22 or std_op == 31 or std_op == 32 then
            b = inst.bx % 512
            c = math.floor(inst.bx / 512) % 512
        end

        local instruction_layout = (layout_mode + prev_enc % 3) % 3
        local raw
        if instruction_layout == 0 then
            raw = rand_op + a * 256 + b * 65536 + c * 33554432
        elseif instruction_layout == 1 then
            raw = a + rand_op * 256 + c * 65536 + b * 33554432
        else
            raw = rand_op + b * 256 + c * 131072 + a * 67108864
        end

        local key = (self.seed + i * self.l_mult + self.l_add + prev_enc * 37) % self.l_mod
        encoded.ins[i] = (raw + key) % self.l_mod
        prev_enc = encoded.ins[i]
    end

    -- Children
    for ci, child in pairs(proto.prototypes) do
        encoded.ps[ci] = self:encode_prototype(child)
    end

    return encoded
end

-- =====================================================================
-- Serialize encoded AST to hardened F1/F2/F3/F5 binary + Ascii85 blob
-- (Never mutates `encoded_ast`!)
-- =====================================================================
local function decode_intermediate_str_bytes(bytes, nonce, str_key)
    local raw = {}
    local state = (str_key + nonce) % 2147483647
    for i = 1, #bytes do
        local eb = bytes[i]
        raw[i] = (eb - (state % 256) - i) % 256
        state = (state * 48271 + eb + i) % 2147483647
    end
    return raw
end

local function pack_with_layout(layout, vals)
    local w = 0
    for idx = 1, 4 do
        local f = layout[idx]
        w = w + (vals[f.name] % f.mod) * f.mul
    end
    return w
end

function Encoder:serialize_to_blob(encoded_ast)
    local ser_rng = make_prng(self.seed, 1579262219) -- 0x5E21A10B
    local used_f1_nonces = {}
    local spec = self.vm_spec
    local tags = spec.const_tags
    local layout_salt = self.inst_keys.layout_salt
    local dg_init = self.dg_keys.dg_init
    local dg_mul = self.dg_keys.dg_mul

    local function serialize_node(node)
        local pk = ser_rng:range(1, 65535)
        local np = node.np or 0
        local up = node.up or 0
        local ms = node.ms or 0
        local iv = node.iv or 0
        local om = node.om or 1
        local oa = node.oa or 0
        local lm = node.lm or 0

        -- Re-encode instructions from intermediate `node.ins` into F1/F3 24-perm + 2-round ARX keystream
        local src_ins = node.ins or {}
        local num_ins = #src_ins
        local f1_ins = {}
        local old_prev = 0
        local new_prev = 0
        for i = 1, num_ins do
            local enc_w = src_ins[i]
            local old_key = (self.seed + i * self.l_mult + self.l_add + old_prev * 37) % self.l_mod
            local old_raw = (enc_w - old_key) % self.l_mod
            local old_mode = (lm + old_prev % 3) % 3
            local rand_op, a, b, c
            if old_mode == 0 then
                rand_op = old_raw % 256
                a = math.floor(old_raw / 256) % 256
                b = math.floor(old_raw / 65536) % 512
                c = math.floor(old_raw / 33554432) % 512
            elseif old_mode == 1 then
                a = old_raw % 256
                rand_op = math.floor(old_raw / 256) % 256
                c = math.floor(old_raw / 65536) % 512
                b = math.floor(old_raw / 33554432) % 512
            else
                rand_op = old_raw % 256
                b = math.floor(old_raw / 256) % 512
                c = math.floor(old_raw / 131072) % 512
                a = math.floor(old_raw / 67108864) % 256
            end
            old_prev = enc_w

            local new_mode = (lm + ((new_prev + layout_salt) % 3)) % 3
            local rop_key = (dg_init + i * 37 + new_prev) % 256
            local rolled_op = (rand_op + rop_key) % 256
            local new_raw = pack_with_layout(spec.layouts[new_mode], {
                op = rolled_op, a = a, b = b, c = c
            })
            local new_key = self:inst_key(i, new_prev, pk)
            local new_enc = (new_raw + new_key) % POW2_34
            f1_ins[i] = new_enc
            new_prev = new_enc
        end

        -- Compute F5 prototype metadata + instruction digest (mod DG_MOD, < 2^53)
        local dg = dg_init
        local meta = { np, up, ms, iv, om, oa, lm, pk, num_ins }
        for _, mv in ipairs(meta) do
            dg = (dg * dg_mul + mv + 1) % DG_MOD
        end
        for i = 1, num_ins do
            dg = (dg * dg_mul + f1_ins[i] + i) % DG_MOD
        end

        -- Build sections in `spec.section_order`
        local ins_buf = { w32(num_ins) }
        for i = 1, num_ins do
            local w = f1_ins[i]
            ins_buf[#ins_buf + 1] = string.char(
                w % 256,
                math.floor(w / 256) % 256,
                math.floor(w / 65536) % 256,
                math.floor(w / 16777216) % 256,
                math.floor(w / 4294967296) % 256
            )
        end

        local ks = node.ks or {}
        local max_k = -1
        for k, _ in pairs(ks) do
            if type(k) == "number" and k > max_k then max_k = k end
        end
        local num_ks = max_k + 1
        local ks_buf = { w32(num_ks) }
        for i = 0, max_k do
            local c = ks[i]
            if not c or c.t == 0 then
                ks_buf[#ks_buf + 1] = string.char(tags[0])
            elseif c.t == 1 then
                local r_mask = ser_rng:range(0, 255)
                ks_buf[#ks_buf + 1] = string.char(tags[1]) .. encrypt_bool_f2(c.v, r_mask, self.bool_key, pk, i, self.sbox1)
            elseif c.t == 3 then
                local n_nonce = ser_rng:range(1, 4294967295)
                ks_buf[#ks_buf + 1] = string.char(tags[3]) .. encrypt_number_f2(c.v, n_nonce, pk, i, self.num_keys, self.nm, self.nr0, self.perm8, self.sbox1, self.sbox2)
            elseif c.t == 4 then
                local raw_bytes = decode_intermediate_str_bytes(c.v, c.nonce, self.str_key)
                local f1_nonce
                repeat f1_nonce = ser_rng:range(1, 4294967295) until not used_f1_nonces[f1_nonce]
                used_f1_nonces[f1_nonce] = true
                local enc_str = encrypt_string_f1(raw_bytes, f1_nonce, self.str_keys, self.sm, self.sr0, self.sbox1, self.sbox2)
                assert(#enc_str <= 4294967295, "String constant exceeds 32-bit payload length")
                ks_buf[#ks_buf + 1] = string.char(tags[4]) .. w32(#enc_str) .. w32(f1_nonce) .. enc_str
            end
        end

        local ps = node.ps or {}
        local ps_keys = {}
        for k, _ in pairs(ps) do
            if type(k) == "number" then ps_keys[#ps_keys + 1] = k end
        end
        table.sort(ps_keys)
        local ps_buf = { w32(#ps_keys) }
        for _, k in ipairs(ps_keys) do
            ps_buf[#ps_buf + 1] = serialize_node(ps[k])
        end

        local field_bytes = {
            np = string.char(np),
            up = string.char(up),
            ms = string.char(ms),
            iv = string.char(iv),
            om = string.char(om),
            oa = string.char(oa),
            lm = string.char(lm),
            pk = w16(pk),
            dg = w32(dg),
        }

        local node_out = {}
        for _, fname in ipairs(spec.proto_field_order) do
            node_out[#node_out + 1] = field_bytes[fname]
        end
        local sec_map = {
            ins = table.concat(ins_buf),
            ks = table.concat(ks_buf),
            ps = table.concat(ps_buf),
        }
        for _, sname in ipairs(spec.section_order) do
            node_out[#node_out + 1] = sec_map[sname]
        end
        return table.concat(node_out)
    end

    local binary = serialize_node(encoded_ast)
    local encrypted = azure_encrypt_f1(binary, self.blob_keys, self.bm, self.br, self.sbox1, self.sbox2)
    local blob, pad = base85_z_encode_f3(encrypted, spec.a85_alpha)
    return blob, pad, payload_checksum(binary)
end

return Encoder
