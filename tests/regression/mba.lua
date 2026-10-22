package.path='./src/?.lua;./src/?/init.lua;'..package.path
local MBA=require('prometheus.steps.MixedBooleanArithmetic')
local Unparser=require('prometheus.unparser')
local unparser=Unparser:new({LuaVersion='Lua51',PrettyPrint=false})
local values={0,-0,0.5,-0.25,1,2,255,256,65535,2147483647,4294967295,-4294967295,4294967296,math.huge,-math.huge,0/0}
for i=1,100 do values[#values+1]=i*40499 end
local step=MBA:new({Threshold=1,MaxTransforms=200})
for seed=1,10 do
 math.randomseed(seed)
 for _,n in ipairs(values) do
  local expression=step:rewrite(n)
  local result=assert(loadstring('return '..unparser:unparseExpression(expression)))()
  assert((n~=n and result~=result) or n==result,'MBA value changed')
  if n==0 then assert(1/n==1/result,'MBA zero sign changed') end
 end
end
print('MBA identities and numeric boundaries: ok')

local Parser=require('prometheus.parser')
local Numbers=require('prometheus.steps.NumbersToExpressions')
local visit=require('prometheus.visitast')
local ast=Parser:new({LuaVersion='Lua51'}):parse('return 11,22,33,44,55')
local budget=MBA:new({Threshold=1,MaxTransforms=2})
budget:apply(ast)
assert(budget.transformed==2,'MBA transform budget was not honored')
local before=unparser:unparse(ast)
Numbers:new({Threshold=1}):apply(ast)
local marked=0
visit(ast,function(node)
 if node.__mba then
  marked=marked+1
  assert(node.lhs.kind=='AddExpression','arithmetic pass rewrote an MBA root')
  return node,true
 end
end)
assert(marked==2,'MBA markers or identity preservation lost')
local result={assert(loadstring(unparser:unparse(ast)))()}
assert(table.concat(result,',')=='11,22,33,44,55')
print('MBA transform budget and pipeline preservation: ok')
