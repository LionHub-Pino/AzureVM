local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/regression/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path
local Reader = require("prometheus.azure_vm.reader")
local chunk = string.dump(function(a)
    local s = "reader fixture"
    return function(b) return a + b, s, false end
end)
local proto = Reader.parse(chunk)
assert(proto.numParams == 1 and proto.prototypes[0])
local function rejects(input)
    local ok, err = pcall(Reader.parse, input)
    assert(not ok, "reader accepted malformed bytecode")
    assert(tostring(err):match("bytecode"), "uncontrolled reader error: " .. tostring(err))
end
for n = 0, #chunk - 1 do rejects(chunk:sub(1, n)) end
rejects(chunk .. "trailing bytes")
rejects(false)
if chunk:byte(9) == 8 then
    -- The high half of the first size_t must not be silently ignored.
    rejects(chunk:sub(1, 16) .. "\1" .. chunk:sub(18))
end
local width = chunk:byte(9)
local n = chunk:byte(13) + chunk:byte(14) * 256 + chunk:byte(15) * 65536 + chunk:byte(16) * 16777216
local terminator = 12 + width + n
rejects(chunk:sub(1, terminator - 1) .. "X" .. chunk:sub(terminator + 1))
local instructions = terminator + 13
rejects(chunk:sub(1, instructions - 1) .. "\255\255\255\255" .. chunk:sub(instructions + 4))
-- Synthetic prototype records exercise the nesting boundary without asking
-- Lua's source parser to compile a deeply nested function.
local zero = string.rep("\0", 4)
local prefix = string.rep("\0", width) .. zero .. zero .. string.char(0, 0, 0, 2) .. zero .. zero
local function tree(depth)
    if depth == 1 then return prefix .. zero .. zero .. zero .. zero end
    return prefix .. string.char(1, 0, 0, 0) .. tree(depth - 1) .. zero .. zero .. zero
end
assert(Reader.parse(chunk:sub(1, 12) .. tree(200)))
rejects(chunk:sub(1, 12) .. tree(201))
print("reader validation: ok (" .. #chunk .. " truncations)")
