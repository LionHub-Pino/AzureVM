local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/regression/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path
local Numbers = require("prometheus.steps.NumbersToExpressions")
local step = Numbers:new({ NumberRepresentationMutation = true,
    AllowedNumberRepresentations = {"hex"}, InternalThreshold = 0 })
local original_format = string.format
local ok, err = pcall(function()
    string.format = function(format, value, ...)
        if format == "0x%X" then
            assert(value >= 0 and value <= 4294967295, "unsafe integer conversion reached hex formatter")
        end
        return original_format(format, value, ...)
    end
    for _, value in ipairs({4294967296, 2^53, 1e100, 1.7976931348623157e308}) do
        local node = step:CreateNumberExpression(value, 1)
        assert(node.value == value, "out-of-range hex did not preserve original number")
    end
    local boundary = step:CreateNumberExpression(4294967295, 1)
    assert(tonumber(boundary.value) == 4294967295, "portable hex boundary changed")
end)
string.format = original_format
assert(ok, err)
print("numeric hex range: ok")
