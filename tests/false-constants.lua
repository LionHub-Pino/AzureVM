local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path

local code = require("prometheus.azure_vm").compile([[
local false_key = { [false] = "ok" }
local yes = false == false
local no = true == false
return yes, no, false_key[false]
]], { Seed = 12345, LuraphVersion = 14 })
local yes, no, value = assert(loadstring(code))()
assert(yes == true and no == false and value == "ok", "false RK constant corrupted")
print("false constants: ok")
