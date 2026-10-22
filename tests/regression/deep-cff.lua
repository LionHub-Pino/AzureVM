package.path='./src/?.lua;./src/?/init.lua;'..package.path
local logger=require('logger')
logger.logLevel=logger.LogLevel.Error
local Parser=require('prometheus.parser')
local Unparser=require('prometheus.unparser')
local Deep=require('prometheus.steps.DeepControlFlowFlattening')
local source=[[
local calls={}
local function test(x) calls[#calls+1]=x return x==2 end
local sum=0
for i=1,6 do
 local localValue=i*3
 if test(i) then
  local captured=localValue
  local f=function() return captured end
  sum=sum+f()
 elseif test(i+1) then
  sum=sum+10
 else
  sum=sum+localValue
 end
 if i==5 then break end
end
local function recur(n)
 if n==0 then return nil,false,7 end
 local a,b,c=recur(n-1)
 return a,b,c
end
local a,b,c=recur(3)
return sum,table.concat(calls,','),a,b,c
]]
local function pack(...) return {n=select('#',...),...} end
local expected=pack(assert(loadstring(source))())
for _,seed in ipairs({1,12345,67890}) do
 math.randomseed(seed)
 local ast=Parser:new({LuaVersion='Lua51'}):parse(source)
 local step=Deep:new({Threshold=1,MinStatements=2,MaxStates=128})
 step:apply(ast)
 assert(step.blocksFlattened>1 and step.branchesLowered>0,'deep dispatcher did not lower nested branches')
 local output=Unparser:new({LuaVersion='Lua51',PrettyPrint=false}):unparse(ast)
 local actual=pack(assert(loadstring(output))())
 assert(actual.n==expected.n)
 for i=1,actual.n do assert(actual[i]==expected[i],'deep CFF changed result '..i) end
end
print('deep CFF nested branches and scope semantics: ok')

local shadowing = 'local x=10; local function read() return x end; local x=20; return read(),x'
local shadowAst=Parser:new({LuaVersion='Lua51'}):parse(shadowing)
local shadowStep=Deep:new({Threshold=1,MinStatements=2})
shadowStep:apply(shadowAst)
local shadowCode=Unparser:new({LuaVersion='Lua51'}):unparse(shadowAst)
local first,second=assert(loadstring(shadowCode))()
assert(first==10 and second==20,'hoisted shadowed local bindings merged')

local forward = 'local function read() return x end; local x=x; return read(),x'
local ast=Parser:new({LuaVersion='Lua51'}):parse(forward)
Deep:new({Threshold=1,MinStatements=2}):apply(ast)
local code=Unparser:new({LuaVersion='Lua51'}):unparse(ast)
local fn=assert(loadstring(code))
setfenv(fn,setmetatable({x=55},{__index=_G}))
local a,b=fn()
assert(a==55 and b==55,'hoisting captured a global or initializer read')
print('deep CFF hoisted binding identities: ok')
