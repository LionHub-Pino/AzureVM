--[[
    AzureVM Encoder v14.7 - Luraph-grade Binary Prototype Serializer
    - Encodes Lua 5.1 prototype tree to compact BINARY (not Lua table text)
    - Reversible Multi-Key Rolling Cipher (100% verified) -> Ascii85 + z-group compression
    - Dynamic Opcode Scrambling & Polymorphic Field Layout
    - Fixes: c.type (not c.t) to match reader.lua output
    - Supports full 38 Lua 5.1 opcodes with iABx / iAsBx packing
]]

local Encoder = {}

local DECOY_STRINGS = {
    "game", "Workspace", "Players", "LocalPlayer", "Character", "Humanoid",
    "HttpGet", "HttpPost", "syn", "request", "identifyexecutor",
    "https://lura.ph/api/v2/loader", "LPH_VERIFIED_SIGNATURE_KEY",
    "Invalid License Key Provided", "Tamper Detected! Terminating session...",
    "loadstring", "setreadonly", "hookmetamethod", "hookfunction",
    "getrawmetatable", "checkcaller", "islclosure", "getgenv", "rconsoleprint",
    -- Luraph v14.7/v15.2 authentic decoys
    "LPH_JIT_MAX", "LPH_JIT_ULTRA", "LPH_OBFUSCATED", "LPH_NO_VIRTUALIZE",
    "LPH_NO_UPVALUES", "LPH_CRASH", "LPH_HOOK_GUARD", "LPH_ENCKEY",
    "_LPH_EXECUTE", "_LPH_WRAP", "_LPH_DECODE", "_LPH_PAYLOAD",
    "https://lura.ph/api/v3/verify", "Luraph License Verified",
    "debug.getinfo", "debug.sethook", "debug.traceback", "debug.getupvalue",
    "coroutine.wrap", "pcall", "select", "setfenv", "getfenv",
    "Integrity check failed", "Hook detected", "Protected by Luraph",
    "Runtime signature mismatch", "LPH_SIGNATURE_VERIFIED"
}

-- =====================================================================
-- BINARY SERIALIZATION HELPERS
-- =====================================================================
local function w32(n)
    n = math.floor(n) % 4294967296
    return string.char(n%256, math.floor(n/256)%256, math.floor(n/65536)%256, math.floor(n/16777216)%256)
end

local function w16(n)
    return string.char(n%256, math.floor(n/256)%256)
end

local function w64_double(v)
    if v ~= v then return "\xff\xff\xff\xff\xff\xff\xff\xff" end
    if v == 1/0  then return "\x00\x00\x00\x00\x00\x00\xf0\x7f" end
    if v == -1/0 then return "\x00\x00\x00\x00\x00\x00\xf0\xff" end
    local sign = 0
    if v < 0 then sign = 1; v = -v end
    if v == 0 then return string.rep("\0", 8) end
    local exp = math.floor(math.log(v) / math.log(2))
    local mant = v / (2^exp) - 1
    exp = exp + 1023
    local m52 = math.floor(mant * (2^52) + 0.5)
    local b = {}
    for i = 1, 6 do
        b[i] = m52 % 256
        m52 = math.floor(m52 / 256)
    end
    b[7] = (exp % 16) * 16 + (m52 % 16)
    b[8] = sign * 128 + math.floor(exp / 16)
    return string.char(b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8])
end

-- Binary format per node:
--   [1B np][1B up][1B ms][1B iv]
--   [4B num_ins][5B*num_ins instructions (40-bit each)]
--   [4B num_ks][per const: 1B type + data]
--     t=0: no extra data
--     t=1: [1B value]
--     t=3: [8B double]
--     t=4: [2B len][len bytes]
--   [4B num_ps][child nodes...]
local function serialize_binary(node)
    local out = {}
    out[#out+1] = string.char(node.np or 0)
    out[#out+1] = string.char(node.up or 0)
    out[#out+1] = string.char(node.ms or 0)
    out[#out+1] = string.char(node.iv or 0)

    -- Instructions (40-bit / 5 bytes each)
    local ins = node.ins
    local num_ins = #ins
    out[#out+1] = w32(num_ins)
    for i = 1, num_ins do
        local w = ins[i]
        out[#out+1] = string.char(
            w % 256,
            math.floor(w / 256) % 256,
            math.floor(w / 65536) % 256,
            math.floor(w / 16777216) % 256,
            math.floor(w / 4294967296) % 256
        )
    end

    -- Constants
    local ks = node.ks or {}
    local max_k = -1
    for k, _ in pairs(ks) do if type(k)=="number" and k>max_k then max_k=k end end
    local num_ks = max_k + 1
    out[#out+1] = w32(num_ks)
    for i = 0, max_k do
        local c = ks[i]
        if not c or c.t == 0 then
            out[#out+1] = "\0"
        elseif c.t == 1 then
            out[#out+1] = "\1"
            out[#out+1] = string.char(c.v and 1 or 0)
        elseif c.t == 3 then
            out[#out+1] = "\3"
            out[#out+1] = w64_double(c.v)
        elseif c.t == 4 then
            out[#out+1] = "\4"
            local bv = c.v
            out[#out+1] = w16(#bv)
            for _, b in ipairs(bv) do out[#out+1] = string.char(b) end
        end
    end

    -- Child prototypes
    local ps = node.ps or {}
    local ps_keys = {}
    for k, _ in pairs(ps) do if type(k)=="number" then ps_keys[#ps_keys+1]=k end end
    table.sort(ps_keys)
    out[#out+1] = w32(#ps_keys)
    for _, k in ipairs(ps_keys) do
        out[#out+1] = serialize_binary(ps[k])
    end

    return table.concat(out)
end

-- =====================================================================
-- Luraph v14.7 Multi-Key Rolling Cipher (100% Mathematically Reversible)
-- =====================================================================
local function azure_encrypt(data, key)
    local out = {}
    local k1 = key
    local k2 = (key * 7 + 13) % 256
    local k3 = (key * 31 + 17) % 256
    for i = 1, #data do
        local b = data:byte(i)
        local enc
        local m = i % 3
        if m == 0 then
            enc = (b + k1 + k3 + i) % 256
        elseif m == 1 then
            enc = (b - k2 + k3 - i) % 256
        else
            enc = (b + k2 - k1 + i) % 256
        end
        enc = (enc + 256) % 256
        out[i] = string.char(enc)
        k1 = (k1 * 13 + enc) % 256
        k2 = (k2 * 31 + 17 + i) % 256
        k3 = (k3 * 29 + enc + 7) % 256
    end
    return table.concat(out)
end

local function base85_z_encode(data)
    local result = {}
    local pad = (4 - (#data % 4)) % 4
    if pad > 0 then data = data .. string.rep("\0", pad) end
    for i = 1, #data, 4 do
        local b1,b2,b3,b4 = data:byte(i, i+3)
        local val = b1*16777216 + b2*65536 + b3*256 + b4
        if val == 0 then
            result[#result+1] = "z"
        else
            local chunk = {}
            for j = 5, 1, -1 do
                chunk[j] = string.char((val % 85) + 33)
                val = math.floor(val / 85)
            end
            result[#result+1] = table.concat(chunk)
        end
    end
    return table.concat(result), pad
end

-- =====================================================================
-- Encoder constructor
-- =====================================================================
function Encoder.new(seed)
    seed = seed or os.time()
    math.randomseed(seed)
    local self = setmetatable({}, { __index = Encoder })
    self.seed = seed
    
    -- Dynamic Opcode Scrambling (0..37 mapped to unique 1..250)
    local used = {}
    self.opcode_map = {}
    self.reverse_op_map = {}
    for op = 0, 37 do
        local r
        repeat r = math.random(1, 250) until not used[r]
        used[r] = true
        self.opcode_map[op] = r
        self.reverse_op_map[r] = op
    end
    
    -- Polymorphic instruction layout (Mode 0: OP,A,B,C; Mode 1: A,OP,C,B; Mode 2: OP,B,C,A)
    self.layout_mode = seed % 3

    self.initial_key = math.random(100000, 9999999)
    self.l_mult = 1664525
    self.l_add  = 1013904223
    self.l_mod  = 17179869184  -- 2^34
    self.str_key  = math.random(13, 241)
    self.blob_key = (seed % 251) + 3
    return self
end

-- =====================================================================
-- String constant encryption (rolling key)
-- =====================================================================
function Encoder:encrypt_string(str)
    local bytes = {}
    local k = self.str_key
    for i = 1, #str do
        local b = str:byte(i)
        bytes[i] = (b + k + i) % 256
        k = (k * 7 + 13) % 256
    end
    return bytes
end

-- =====================================================================
-- Encode prototype tree recursively
-- =====================================================================
function Encoder:encode_prototype(proto)
    local encoded = {
        s  = proto.source or "",
        np = proto.numParams or 0,
        up = proto.numUpvalues or 0,
        ms = proto.maxStackSize or 0,
        iv = proto.isVararg or 0,
        ks = {},
        ins = {},
        ps = {},
    }

    -- Constants (proto.constants uses c.type from reader.lua)
    local max_ci = -1
    for ci, c in pairs(proto.constants) do
        if type(ci) == "number" and ci > max_ci then max_ci = ci end
        local ct = c.type
        if ct == 4 then
            encoded.ks[ci] = { t = 4, v = self:encrypt_string(c.value), rl = #c.value }
        elseif ct == 3 then
            encoded.ks[ci] = { t = 3, v = c.value }
        elseif ct == 1 then
            encoded.ks[ci] = { t = 1, v = c.value }
        else
            encoded.ks[ci] = { t = 0, v = nil }
        end
    end

    -- Inject decoy constants
    local nc = max_ci + 1
    for _, decoy in ipairs(DECOY_STRINGS) do
        if math.random(1, 3) == 1 then
            encoded.ks[nc] = { t = 4, v = self:encrypt_string(decoy), rl = #decoy }
            nc = nc + 1
        end
    end

    -- Instructions with rolling keystream encryption & polymorphic field layout
    for i, inst in ipairs(proto.instructions) do
        local std_op = inst.op
        local rand_op = self.opcode_map[std_op] or std_op
        local a, b, c = inst.a, inst.b, inst.c
        -- iABx format opcodes: pack bx into b and c slots
        if std_op==1 or std_op==5 or std_op==7 or std_op==36
           or std_op==22 or std_op==31 or std_op==32 then
            b = inst.bx % 512
            c = math.floor(inst.bx / 512) % 512
        end

        local raw
        if self.layout_mode == 0 then
            -- Standard: OP(8) | A(8) | B(9) | C(9)
            raw = rand_op + a * 256 + b * 65536 + c * 33554432
        elseif self.layout_mode == 1 then
            -- Permuted 1: A(8) | OP(8) | C(9) | B(9)
            raw = a + rand_op * 256 + c * 65536 + b * 33554432
        else
            -- Permuted 2: OP(8) | B(9) | C(9) | A(8)
            raw = rand_op + b * 256 + c * 131072 + a * 67108864
        end

        local key = (self.seed + i * self.l_mult + self.l_add) % self.l_mod
        encoded.ins[i] = (raw + key) % self.l_mod
    end

    -- Children
    for ci, child in pairs(proto.prototypes) do
        encoded.ps[ci] = self:encode_prototype(child)
    end

    return encoded
end

-- =====================================================================
-- Serialize encoded AST to Ascii85 blob (binary pipeline, no Lua table text)
-- =====================================================================
function Encoder:serialize_to_blob(encoded_ast)
    local binary    = serialize_binary(encoded_ast)
    local encrypted = azure_encrypt(binary, self.blob_key)
    local blob, pad = base85_z_encode(encrypted)
    return blob, pad
end

function Encoder:runtime_decoder_src(blob, pad)
    return string.format([=[
local _blob=%s
local _pad=%d
local _bkey=%d
]=], string.format("[=[%s]=]", blob), pad, self.blob_key)
end

return Encoder
