local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path

local Reader = require("prometheus.azure_vm.reader")
local Encoder = require("prometheus.azure_vm.encoder")
local AzureVM = require("prometheus.azure_vm")

local source = [[
local x = 0
for i = 1, 20 do x = x + i end
local function f(a) return a * 2 + x end
return f(3)
]]
local root = Reader.parse(string.dump(assert(loadstring(source))))
local encoder = Encoder.new(12345)
local encoded = encoder:encode_prototype(root)

local previous, modes = 0, {}
for i, inst in ipairs(root.instructions) do
    local encrypted = encoded.ins[i]
    local key = (encoder.seed + i * encoder.l_mult + encoder.l_add + previous * 37) % encoder.l_mod
    local raw = (encrypted - key) % encoder.l_mod
    local mode = (encoded.lm + previous % 3) % 3
    modes[mode] = true
    local scrambled
    if mode == 1 then scrambled = math.floor(raw / 256) % 256
    else scrambled = raw % 256 end
    local mapped = ((scrambled - encoded.oa) * encoded.om) % 256
    assert(encoder.reverse_op_map[mapped] == inst.op,
        "instruction layout does not follow prior ciphertext at position " .. i)
    previous = encrypted
end

local mode_count = 0
for _ in pairs(modes) do mode_count = mode_count + 1 end
assert(mode_count > 1, "instruction layout never varies within the prototype")

for seed = 12345, 12354 do
    local output = AzureVM.compile(source, { Seed = seed, LuraphVersion = 15 })
    assert(assert(loadstring(output))() == 216, "runtime mismatch at seed " .. seed)
end
print("chained layout: ok")
