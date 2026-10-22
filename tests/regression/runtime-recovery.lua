package.path='./src/?.lua;./src/?/init.lua;'..package.path
local AzureVM=require('prometheus.azure_vm')
local function pack(...) return {n=select('#',...),...} end
local function environment(faults)
 local strings={} for k,v in pairs(string) do strings[k]=v end
 local state={faults=0,entered=0}
 local env=setmetatable({string=strings,entered=function() state.entered=state.entered+1 end},{__index=_G})
 strings.gsub=function(...)
  state.faults=state.faults+1
  if state.faults<=faults then error('injected transient initialization failure',0) end
  return string.gsub(...)
 end
 return env,state
end
for _,mode in ipairs({14,15}) do
 local output=AzureVM.compile('entered(); return nil,false,7,...',{
  Seed=12345,LuraphVersion=mode,RuntimeChecks=true,InitializationRetries=2,Compact=true})
 assert(not output:find('[\r\n]'))
 for _,protection in ipairs({'xpcall','pcall','coroutine'}) do
  local env,state=environment(1)
  if protection~='xpcall' then env.xpcall=false end
  if protection=='coroutine' then env.pcall=false end
  local fn=assert(loadstring(output)) setfenv(fn,env)
  local ok,result=pcall(function() return pack(fn('argument',nil,11)) end)
  assert(ok,'initialization did not recover with '..protection..': '..tostring(result))
  assert(state.entered==1 and result.n==6 and result[1]==nil and result[2]==false
   and result[3]==7 and result[4]=='argument' and result[5]==nil and result[6]==11)
 end
 local env,state=environment(100)
 local fn=assert(loadstring(output)) setfenv(fn,env)
 local ok,err=pcall(fn)
 assert(not ok and state.entered==0 and state.faults==3,'initialization retry bound violated')
 local failing=AzureVM.compile('entered(); error("user failure",0)',{
  Seed=12345,LuraphVersion=mode,RuntimeChecks=true,InitializationRetries=2})
 env,state=environment(0) fn=assert(loadstring(failing)) setfenv(fn,env)
 ok,err=pcall(fn)
 assert(not ok and err=='user failure' and state.entered==1,'user code retried or its error changed')
 local errorToken={}
 local tableFailure=AzureVM.compile('entered(); error(token,0)',{
  Seed=12345,LuraphVersion=mode,RuntimeChecks=true,InitializationRetries=2})
 local tableEnv,tableState=environment(0) tableEnv.token=errorToken
 local tableFn=assert(loadstring(tableFailure)) setfenv(tableFn,tableEnv)
 local tableOk,tableErr=pcall(tableFn)
 assert(not tableOk and tableErr==errorToken and tableState.entered==1,'user error object lost')
 local yieldingUser=AzureVM.compile('entered(); local x=coroutine.yield("ready"); return x',{
  Seed=12345,LuraphVersion=mode,RuntimeChecks=true,InitializationRetries=2})
 local yieldEnv,yieldState=environment(0)
 local yieldFn=assert(loadstring(yieldingUser)) setfenv(yieldFn,yieldEnv)
 local thread=coroutine.create(yieldFn)
 local resumed,value=coroutine.resume(thread)
 assert(resumed and value=='ready' and yieldState.entered==1,'user yield wrapped in protected initialization')
 resumed,value=coroutine.resume(thread,42)
 assert(resumed and value==42 and yieldState.entered==1)
 local yielding,ys=environment(0)
 yielding.xpcall=false yielding.pcall=false
 yielding.string.gsub=function() ys.faults=ys.faults+1 coroutine.yield('not allowed') end
 fn=assert(loadstring(output)) setfenv(fn,yielding)
 ok,err=pcall(fn)
 assert(not ok and err=='AzureVM initializer must not yield' and ys.faults==1 and ys.entered==0)
 local unavailable,us=environment(0)
 unavailable.xpcall=false unavailable.pcall=false unavailable.coroutine=false
 fn=assert(loadstring(output)) setfenv(fn,unavailable)
 ok,err=pcall(fn)
 assert(not ok and err=='AzureVM protected initialization is unavailable' and us.entered==0)
end
for _,value in ipairs({-1,3,0.5,'2',false}) do
 assert(not pcall(AzureVM.compile,'return 1',{InitializationRetries=value}),'invalid retry option accepted')
end
assert(not pcall(AzureVM.compile,'return 1',{RuntimeChecks='true'}),'invalid runtime check option accepted')
print('bounded initialization recovery, fallbacks, and user side effects: ok')
