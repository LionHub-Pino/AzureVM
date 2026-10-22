package.path = './src/?.lua;./src/?/init.lua;' .. package.path
local AzureVM = require('prometheus.azure_vm')
local secret = 'lazy-secret-unchanged-value'
for _, mode in ipairs({14, 15}) do
    local output = AzureVM.compile('return function() return "' .. secret .. '" end', {Seed=12345, LuraphVersion=mode})
    assert(not output:find(secret, 1, true), 'plaintext literal embedded in output')
    local concat, count = table.concat, 0
    table.concat = function(t, sep, first, last)
        local value = concat(t, sep, first, last)
        if value == secret then count = count + 1 end
        return value
    end
    local ok, err = pcall(function()
        local closure = assert(loadstring(output))()
        assert(count == 0, 'unused string decrypted during initialization')
        assert(closure() == secret and count == 1, 'first string access did not decode')
        assert(closure() == secret and count == 2, 'plaintext cached between string accesses')
    end)
    table.concat = concat
    assert(ok, err)
end
print('lazy string decoding: ok')
