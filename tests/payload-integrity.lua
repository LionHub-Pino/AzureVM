local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path

local AzureVM = require("prometheus.azure_vm")
local output = AzureVM.compile("return 500500", { Seed = 12345, LuraphVersion = 14 })
local run = assert(loadstring(output))
assert(run() == 500500, "untampered output changed behavior")

local _, opening_end, equals = output:find("%[(=*)%[LPH>")
local start = assert(opening_end, "payload marker missing") + 1
local stop = assert(output:find("]" .. equals .. "]", start, true), "payload end missing")
local prefix, blob, suffix = output:sub(1, start - 1), output:sub(start, stop - 1), output:sub(stop)
assert(#blob > 10, "payload is empty")
local first = blob:sub(1, 1)
local replacement = first == "!" and '"' or "!"
local tampered = prefix .. replacement .. blob:sub(2) .. suffix
local ok, err = pcall(assert(loadstring(tampered)))
assert(not ok and tostring(err):find("AzureVM payload integrity check failed", 1, true),
    "tampered payload was not rejected by integrity check: " .. tostring(err))

print("payload integrity: ok")
