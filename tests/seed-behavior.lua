local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path

local AzureVM = require("prometheus.azure_vm")
local Seed = require("prometheus.azure_vm.seed")
local source = "return 42"

local fixed_a = AzureVM.compile(source, { Seed = 12345, LuraphVersion = 14 })
local fixed_b = AzureVM.compile(source, { Seed = 12345, LuraphVersion = 14 })
local different = AzureVM.compile(source, { Seed = 12346, LuraphVersion = 14 })
assert(fixed_a == fixed_b, "fixed seed is not reproducible")
assert(fixed_a ~= different, "distinct seeds generated identical builds")

local seen = {}
for _ = 1, 8 do
    seen[Seed.random()] = true
end
local count = 0
for _ in pairs(seen) do count = count + 1 end
assert(count > 1, "default seed source did not vary")

print("seed behavior: ok")
