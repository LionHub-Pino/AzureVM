local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path

local Reader = require("prometheus.azure_vm.reader")
local Encoder = require("prometheus.azure_vm.encoder")
local AzureVM = require("prometheus.azure_vm")

local lines, calls = {}, {}
for i = 1, 12 do
    lines[#lines + 1] = ("local f%d = function() return %d end"):format(i, i)
    calls[#calls + 1] = ("f%d()"):format(i)
end
lines[#lines + 1] = "return " .. table.concat(calls, " + ")
local source = table.concat(lines, "\n")

local root = Reader.parse(string.dump(assert(loadstring(source))))
local encoded = Encoder.new(12345):encode_prototype(root)
local seen = {}
local function inspect(node)
    assert(type(node.lm) == "number" and node.lm >= 0 and node.lm <= 2,
        "prototype lacks an instruction layout")
    seen[node.lm] = true
    for _, child in pairs(node.ps) do inspect(child) end
end
inspect(encoded)
local count = 0
for _ in pairs(seen) do count = count + 1 end
assert(count >= 2, "all prototypes share one instruction layout")

for seed = 12345, 12354 do
    local output = AzureVM.compile(source, { Seed = seed, LuraphVersion = 15 })
    assert(assert(loadstring(output))() == 78, "mixed-layout VM changed behavior at seed " .. seed)
end
print("per-prototype layout: ok")
