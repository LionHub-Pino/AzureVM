local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/regression/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path
local Reader = require("prometheus.azure_vm.reader")
local Encoder = require("prometheus.azure_vm.encoder")
local Generator = require("prometheus.azure_vm.generator")
local function prototype(value)
    local proto = Reader.parse(string.dump(function() return "fixture" end))
    proto.constants[0] = { type = 4, value = value }
    return proto
end
local phrase = "shared-secret-string"
local proto = prototype(phrase)
proto.prototypes[0] = prototype(phrase)
proto.prototypes[1] = prototype(phrase)
local encoder = Encoder.new(12345)
local encoded = encoder:encode_prototype(proto)
local seen, ciphers = {}, {}
local function decode(bytes, nonce)
    local chars, state = {}, (encoder.str_key + nonce) % 2147483647
    for i, byte in ipairs(bytes) do
        chars[i] = string.char((byte - state % 256 - i) % 256)
        state = (state * 48271 + byte + i) % 2147483647
    end
    return table.concat(chars)
end
for _, node in ipairs({encoded, encoded.ps[0], encoded.ps[1]}) do
    local c = node.ks[0]
    assert(type(c.nonce) == "number", "string constant has no independent nonce")
    assert(not seen[c.nonce], "string nonce reused within a build")
    seen[c.nonce] = true
    local cipher = string.char(unpack(c.v))
    assert(not ciphers[cipher], "identical plaintext reused its ciphertext")
    ciphers[cipher] = true
    assert(decode(c.v, c.nonce) == phrase, "independent decoder disagrees")
end
local changed = {}
for i, byte in ipairs(encoded.ks[0].v) do changed[i] = byte end
changed[1] = (changed[1] + 1) % 256
assert(decode(changed, encoded.ks[0].nonce):sub(2, 2) ~= phrase:sub(2, 2),
    "string ciphertext feedback did not affect the next character")
local all_bytes = {}
for i = 0, 255 do all_bytes[#all_bytes + 1] = string.char(i) end
local binary = table.concat(all_bytes)
for _, value in ipairs({"", binary, string.rep("a", 65535), string.rep("b", 65536), string.rep(binary, 274)}) do
    for _, mode in ipairs({14, 15}) do
        local enc = Encoder.new(67890)
        local output = Generator.emit(enc:encode_prototype(prototype(value)), enc, { LuraphVersion = mode })
        assert(assert(loadstring(output))() == value, "string roundtrip failed at length " .. #value)
    end
end
local first = Encoder.new(12345)
local a = Generator.emit(first:encode_prototype(proto), first, { LuraphVersion = 14 })
local second = Encoder.new(12345)
local b = Generator.emit(second:encode_prototype(proto), second, { LuraphVersion = 14 })
assert(a == b, "string nonce generation broke fixed-seed reproducibility")
print("string constants: ok")
