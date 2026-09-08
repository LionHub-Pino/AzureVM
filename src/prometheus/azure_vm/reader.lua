--[[
    AzureVM - Lua 5.1 Bytecode Deserializer
    Architecture inspired by Prometheus & Luraph
    High-fidelity chunk reader supporting 32-bit/64-bit platforms
]]

local Reader = {}

function Reader.parse(dump)
    local pos = 1
    local len = #dump

    local function read_byte()
        if pos > len then error("Unexpected EOF in bytecode chunk") end
        local b = dump:byte(pos)
        pos = pos + 1
        return b
    end

    local function read_bytes(count)
        if pos + count - 1 > len then error("Unexpected EOF in bytecode chunk") end
        local sub = dump:sub(pos, pos + count - 1)
        pos = pos + count
        return sub
    end

    local function read_int()
        local b1, b2, b3, b4 = dump:byte(pos, pos + 3)
        pos = pos + 4
        return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    end

    -- Header Validation
    local sig = read_bytes(4)
    if sig ~= "\27Lua" then
        error("Invalid Lua bytecode signature")
    end

    local version = read_byte()
    if version ~= 0x51 then
        error("Unsupported bytecode version: 0x" .. string.format("%X", version) .. " (expected Lua 5.1 / 0x51)")
    end

    local format = read_byte()
    local endian = read_byte() -- 1 = little endian
    local sizeof_int = read_byte()
    local sizeof_sizet = read_byte()
    local sizeof_inst = read_byte()
    local sizeof_num = read_byte()
    local integral = read_byte()

    -- This reader intentionally supports the canonical Lua 5.1 layout only.
    if format ~= 0 then error("Unsupported Lua bytecode format: " .. tostring(format)) end
    if endian ~= 1 then error("Unsupported bytecode endianness: expected little-endian") end
    if sizeof_int ~= 4 then error("Unsupported Lua integer width: " .. tostring(sizeof_int)) end
    if sizeof_sizet ~= 4 and sizeof_sizet ~= 8 then error("Unsupported Lua size_t width: " .. tostring(sizeof_sizet)) end
    if sizeof_inst ~= 4 then error("Unsupported Lua instruction width: " .. tostring(sizeof_inst)) end
    if sizeof_num ~= 8 then error("Unsupported Lua number width: " .. tostring(sizeof_num)) end
    if integral ~= 0 then error("Integral Lua bytecode is not supported") end

    local function read_size_t()
        if sizeof_sizet == 4 then
            return read_int()
        else
            local b1, b2, b3, b4, b5, b6, b7, b8 = dump:byte(pos, pos + 7)
            pos = pos + 8
            return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        end
    end

    local function read_string()
        local slen = read_size_t()
        if slen == 0 then return "" end
        local s = dump:sub(pos, pos + slen - 2) -- Strip trailing null byte
        pos = pos + slen
        return s
    end

    local function read_double()
        local b1, b2, b3, b4, b5, b6, b7, b8 = dump:byte(pos, pos + 7)
        pos = pos + 8
        local sign = (b8 >= 128) and -1 or 1
        local exp = (b8 % 128) * 16 + math.floor(b7 / 16)
        local mant = (b7 % 16) * 2^48 + b6 * 2^40 + b5 * 2^32 + b4 * 2^24 + b3 * 2^16 + b2 * 2^8 + b1
        if exp == 0 then
            if mant == 0 then return sign * 0 end
            return sign * (mant / 2^52) * 2^-1022
        elseif exp == 2047 then
            return mant == 0 and (sign * (1/0)) or (0/0)
        else
            return sign * (1 + mant / 2^52) * 2^(exp - 1023)
        end
    end

    local function load_function()
        local proto = {}
        proto.source = read_string()
        proto.lineDefined = read_int()
        proto.lastLineDefined = read_int()
        proto.numUpvalues = read_byte()
        proto.numParams = read_byte()
        proto.isVararg = read_byte()
        proto.maxStackSize = read_byte()

        -- Read Instructions
        local num_inst = read_int()
        proto.instructions = {}
        for i = 1, num_inst do
            local inst = read_int()
            local op = inst % 64
            local a = math.floor(inst / 64) % 256
            local c = math.floor(inst / 16384) % 512
            local b = math.floor(inst / 8388608) % 512
            local bx = math.floor(inst / 16384) % 262144
            local sbx = bx - 131071

            proto.instructions[i] = {
                op = op,
                a = a,
                b = b,
                c = c,
                bx = bx,
                sbx = sbx
            }
        end

        -- Read Constants
        local num_consts = read_int()
        proto.constants = {}
        for i = 0, num_consts - 1 do
            local ktype = read_byte()
            if ktype == 0 then -- nil
                proto.constants[i] = { type = 0, value = nil }
            elseif ktype == 1 then -- boolean
                proto.constants[i] = { type = 1, value = (read_byte() ~= 0) }
            elseif ktype == 3 then -- number
                proto.constants[i] = { type = 3, value = read_double() }
            elseif ktype == 4 then -- string
                proto.constants[i] = { type = 4, value = read_string() }
            else
                error("Unknown constant type: " .. tostring(ktype))
            end
        end

        -- Read Child Prototypes
        local num_protos = read_int()
        proto.prototypes = {}
        for i = 0, num_protos - 1 do
            proto.prototypes[i] = load_function()
        end

        -- Strip / Skip Debug Information
        local num_lines = read_int()
        pos = pos + num_lines * 4

        local num_locvars = read_int()
        for i = 1, num_locvars do
            read_string()
            read_int()
            read_int()
        end

        local num_upval_names = read_int()
        for i = 1, num_upval_names do
            read_string()
        end

        return proto
    end

    return load_function()
end

return Reader
