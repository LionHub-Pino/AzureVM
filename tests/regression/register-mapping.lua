package.path = './src/?.lua;./src/?/init.lua;' .. package.path
local AzureVM = require('prometheus.azure_vm')
local source = [[
local x=false
local function swap(v) local old=x x=v return old end
local function values(...) return select('#',...), ... end
local n,a,b,c=values(nil,false,9)
assert(n==3 and a==nil and b==false and c==9)
assert(swap(41)==false)
assert(swap(42)==41)
return function() return x end
]]
for _,mode in ipairs({14,15}) do
    for _,seed in ipairs({12345,67890}) do
        local mappings={}
        local output=AzureVM.compile(source,{Seed=seed,LuraphVersion=mode})
        local env=setmetatable({}, {__index=_G})
        env.setmetatable=function(t, mt)
            if type(mt.__index)=='function' and type(mt.__newindex)=='function' then
                mappings[#mappings+1]=t
            end
            return setmetatable(t,mt)
        end
        local chunk=assert(loadstring(output))
        setfenv(chunk,env)
        local closure=chunk()
        assert(closure()==42 and closure()==42, 'virtual register/upvalue semantics changed')
        assert(#mappings>0, 'register storage was not virtualized')
        for _,proxy in ipairs(mappings) do
            assert(next(proxy)==nil, 'logical register values leaked into proxy keys')
        end
    end
end
print('virtual register mapping: ok')
