package.path='./src/?.lua;./src/?/init.lua;'..package.path
local AzureVM=require('prometheus.azure_vm')
for _,mode in ipairs({14,15}) do
 local output=AzureVM.compile('entered(); return 19',{Seed=12345,LuraphVersion=mode,RuntimeChecks=true,InitializationRetries=2,Compact=true})
 local probes,entered=0,0
 local strings={} for k,v in pairs(string) do strings[k]=v end
 local env=setmetatable({string=strings,entered=function()entered=entered+1 end},{__index=_G})
 strings.gsub=function(s,...)
  if s=='AZ' then probes=probes+1 end
  -- A wrapper installed during initialization, even with equivalent behavior.
  strings.byte=function(...)return string.byte(...)end
  return string.gsub(s,...)
 end
 local fn=assert(loadstring(output)) setfenv(fn,env)
 local ok,err=pcall(fn)
 assert(not ok and err=='AzureVM runtime integrity check failed' and entered==0 and probes==1,
  'library replacement was not terminal before user code')
 strings={} for k,v in pairs(string) do strings[k]=v end
 env.string=strings
 strings.gsub=function(s,...)
  if s=='AZ' then probes=probes+1 end
  return string.gsub(s,...)
 end
 probes=0
 local _,endpos=output:find('%[(=*)%[LPH>')
 local start=assert(endpos)+1
 local byte=output:sub(start,start)
 local corrupted=output:sub(1,start-1)..(byte=='!' and '"' or '!')..output:sub(start+1)
 fn=assert(loadstring(corrupted)) setfenv(fn,env)
 ok,err=pcall(fn)
 assert(not ok and err=='AzureVM payload integrity check failed' and entered==0 and probes==1,
  'corrupt payload was retried or executed')
 -- Missing/semantically broken primitives must fail clearly without entering user code.
 strings.find=17
 fn=assert(loadstring(output)) setfenv(fn,env)
 ok,err=pcall(fn)
 assert(not ok and err=='AzureVM runtime integrity check failed' and entered==0)
 -- Interpreting the encoded payload does not require dumping or loading native user code.
 local narrowString={} for k,v in pairs(string) do narrowString[k]=v end
 narrowString.dump=false
 local narrow=setmetatable({string=narrowString,debug=false,loadstring=false,load=false,
  entered=function()entered=entered+1 end},{__index=_G})
 fn=assert(loadstring(output)) setfenv(fn,narrow)
 assert(fn()==19,'runtime unexpectedly required native dump/load/debug facilities')
 -- An installed debugger/profiler hook must remain installed and usable.
 local count=0
 local function hook()count=count+1 end
 local old,mask,instructions=debug.gethook()
 debug.sethook(hook,'',100)
 ok,err=pcall(function()
  local clean=assert(loadstring(output))
  local normal=setmetatable({entered=function()entered=entered+1 end},{__index=_G})
  setfenv(clean,normal)
  assert(clean()==19)
  local h,m,c=debug.gethook()
  assert(h==hook and m=='' and c==100 and count>0,'host hook modified')
 end)
 debug.sethook(old,mask,instructions)
 assert(ok,err)
end
print('runtime integrity fail-closed checks and host hook preservation: ok')
