local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/regression/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path
local AzureVM = require("prometheus.azure_vm")
local cases = {
    [==[return [=[first

value += 7
\u{41}
last]=]]==],
    [==[return "\\u{41} and \\u{1F600}"]==],
    [==[return "\u{41}"]==],
    [==[return "first\
\
last"]==],
    "return [=[first\r\n\r\nlast]=]",
}
local checks = 0
for _, source in ipairs(cases) do
    local expected = assert(loadstring(source))()
    for _, mode in ipairs({14, 15}) do
        local output = AzureVM.compile(source, { Seed = 12345, LuraphVersion = mode })
        assert(assert(loadstring(output))() == expected, "native Lua source changed in template " .. mode)
        checks = checks + 1
    end
end
local luau = "local x = 1\nx += 2\nreturn x"
local output = AzureVM.compile(luau, { Seed = 12345 })
assert(assert(loadstring(output))() == 3, "limited compound-assignment fallback stopped working")
local shebang = "#!/usr/bin/env lua\r\nreturn [=[first\n\nlast]=]"
output = AzureVM.compile(shebang, { Seed = 12345 })
assert(assert(loadstring(output))() == "first\n\nlast", "shebang handling changed a literal")
local native_load = loadstring
local binary = string.dump(function() return 1 end)
local loader_called = false
loadstring = function() loader_called = true; error("binary reached native loader") end
local ok, err = pcall(AzureVM.compile, binary)
loadstring = native_load
assert(not ok and tostring(err):find("Binary chunks", 1, true), "binary chunk was not explicitly rejected")
assert(not loader_called, "binary validation ran after the native loader")
for _, value in ipairs({false, 42, {}}) do
    ok, err = pcall(AzureVM.compile, value)
    assert(not ok and tostring(err):find("Source must be a string", 1, true), "source type was not validated")
end
ok, err = pcall(AzureVM.compile, nil)
assert(not ok and tostring(err):find("Source must be a string", 1, true), "nil source was not validated")
ok, err = pcall(AzureVM.compile, "return 1", false)
assert(not ok and tostring(err):find("Options must be a table", 1, true), "options type was not validated")
ok, err = pcall(AzureVM.compile, "return )")
assert(not ok and tostring(err):find("Syntax error", 1, true), "invalid text did not return a syntax error")
print("source preservation: ok (" .. checks .. " native source roundtrips)")
