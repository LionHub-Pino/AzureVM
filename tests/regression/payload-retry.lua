package.path='./src/?.lua;./src/?/init.lua;'..package.path
local AzureVM=require('prometheus.azure_vm')
local Retry=require('prometheus.steps.SafeRetryWrapper')
local Pipeline=require('prometheus.pipeline')
local logger=require('logger')
logger.logLevel=logger.LogLevel.Error
local function pack(...)return {n=select('#',...),...}end
for _,mode in ipairs({14,15}) do
 for _,protection in ipairs({'xpcall','pcall'}) do
  local seen,calls={},0
  local token={}
  local env=setmetatable({
   observe=function(x)seen[#seen+1]=x end,
   flaky=function(x)
    calls=calls+1
    if calls<=3 then error(token,0)end
    return nil,false,x,'done'
   end,
  },{__index=_G})
  if protection=='pcall' then env.xpcall=false end
  -- TAILCALL clears root instructions before the host function can fail.
  local source='local x=0; x=x+1; observe(x); return flaky(x)'
  local vm=AzureVM.compile(source,{Seed=12345,LuraphVersion=mode,Compact=true})
  local wrapped=Retry.wrap(vm,3)
  assert(not wrapped:find('[\r\n]'),'wrapper broke compact output')
  local fn=assert(loadstring(wrapped)) setfenv(fn,env)
  local result=pack(fn())
  assert(calls==4 and #seen==4,'retry count did not mean 3 retries plus initial attempt')
  for _,x in ipairs(seen)do assert(x==1,'register or stack state leaked between attempts')end
  assert(result.n==4 and result[1]==nil and result[2]==false and result[3]==1 and result[4]=='done')
  calls=0
  env.flaky=function()calls=calls+1 error(token,0)end
  fn=assert(loadstring(wrapped)) setfenv(fn,env)
  local ok,err=pcall(fn)
  assert(not ok and err==token and calls==4,'last error object/count changed')
 end
end
local output=AzureVM.compile('return ...',{Seed=12345,Compact=true})
local result=pack(assert(loadstring(Retry.wrap(output,3)))(nil,false,9,nil))
assert(result.n==4 and result[2]==false and result[3]==9)
assert(Retry.wrap(output,0)==output,'zero retries must disable wrapping')
for _,value in ipairs({-1,101,0.5,'3',false,math.huge,0/0})do
 assert(not pcall(Retry.wrap,output,value),'invalid retry count accepted')
end
local pipeline=Pipeline:fromConfig({LuaVersion='Lua51',Seed=12345,Steps={
 {Name='AzureVM',Settings={Compact=true}},
 {Name='SafeRetryWrapper',Settings={RetryCount=3}},
}})
pipeline.seed=12345
local compiled=pipeline:apply('attempts=attempts+1; if attempts<4 then error("again",0) end; return attempts')
local env=setmetatable({attempts=0},{__index=_G})
local fn=assert(loadstring(compiled)) setfenv(fn,env)
assert(fn()==4 and env.attempts==4,'pipeline step did not replay external side effects')

assert(not pcall(Retry.wrap,nil,3),'invalid source accepted')
assert(not pcall(function() Retry:new({RetryCount=3}):apply({}, {}) end),'invalid step ordering accepted')
local blockedEnv=setmetatable({pcall=false,xpcall=false},{__index=_G})
local blocked=assert(loadstring(Retry.wrap(output,3))) setfenv(blocked,blockedEnv)
local ok,err=pcall(blocked)
assert(not ok and err=='SafeRetryWrapper requires pcall or xpcall')
local function checkError(value)
 local calls=0
 local vm=AzureVM.compile('fail()',{Seed=12345,Compact=true})
 local env=setmetatable({fail=function()calls=calls+1 error(value,0)end},{__index=_G})
 local fn=assert(loadstring(Retry.wrap(vm,3))) setfenv(fn,env)
 local success,problem=pcall(fn)
 assert(not success and problem==value and calls==4,'nil/false error object was altered')
end
checkError(nil)
checkError(false)
-- Outer replay deliberately retries even initialization integrity rejection.
local protected=AzureVM.compile('entered()',{Seed=12345,RuntimeChecks=true,Compact=true})
local _,last=protected:find('%[(=*)%[LPH>')
local start=assert(last)+1
local byte=protected:sub(start,start)
local corrupt=protected:sub(1,start-1)..(byte=='!' and '"' or '!')..protected:sub(start+1)
local strings={} for k,v in pairs(string)do strings[k]=v end
local probes,entered=0,0
strings.gsub=function(value,...)
 if value=='AZ' then probes=probes+1 end
 return string.gsub(value,...)
end
local env=setmetatable({string=strings,entered=function()entered=entered+1 end},{__index=_G})
local fn=assert(loadstring(Retry.wrap(corrupt,3))) setfenv(fn,env)
ok,err=pcall(fn)
assert(not ok and err=='AzureVM payload integrity check failed' and probes==4 and entered==0,
 'whole-factory retry budget or integrity rejection changed')
print('payload retry: fresh VM, tailcall cleanup, side effects, errors, tuples and limits: ok')
