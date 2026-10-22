package.path = './src/?.lua;./src/?/init.lua;' .. package.path
local AzureVM = require('prometheus.azure_vm')
for _, mode in ipairs({14,15}) do
    for _, header in ipairs({'custom', '-- comment\r\nerror("injected")', 'embedded ]=] ]==] delimiters'}) do
        local output = AzureVM.compile('return "a\\nb", false, 17', {
            Seed=12345, LuraphVersion=mode, Compact=true, Header=header
        })
        assert(not output:find('[\r\n]'), 'compact output contains a line break')
        local a,b,c = assert(loadstring(output))()
        assert(a=='a\nb' and b==false and c==17, 'compact output changed values or executed header')
    end
end
print('single-line output: ok')
