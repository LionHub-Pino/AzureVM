-- Initialization-only recovery. Never put the user's __EXEC call in this region.
local Runtime={}
function Runtime.validate(options)
    local retries=options.InitializationRetries
    if retries==nil then retries=0 end
    if type(retries)~='number' or retries~=math.floor(retries) or retries<0 or retries>2 then
        error('[AzureVM] InitializationRetries must be an integer from 0 to 2',2)
    end
    if options.RuntimeChecks~=nil and type(options.RuntimeChecks)~='boolean' then
        error('[AzureVM] RuntimeChecks must be a boolean',2)
    end
    return retries
end
local PRELUDE=[=[
local _az_typefn,_az_errorfn,_az_selectfn=type,error,select
local _az_pcallfn,_az_xpcallfn,_az_corolib=pcall,xpcall,coroutine
local _az_stringlib,_az_tablelib,_az_mathlib=string,table,math
local _az_safestring=_az_typefn(string)=="table" and string or {}
local _az_safetable=_az_typefn(table)=="table" and table or {}
local _az_safemath=_az_typefn(math)=="table" and math or {}
local _az_unpackfn=unpack or _az_safetable.unpack
local _az_bytefn,_az_charfn,_az_subfn,_az_gsubfn,_az_findfn=_az_safestring.byte,_az_safestring.char,_az_safestring.sub,_az_safestring.gsub,_az_safestring.find
local _az_concatfn,_az_floorfn,_az_setmetafn=_az_safetable.concat,_az_safemath.floor,setmetatable
local function _az_packvalues(...)return {n=_az_selectfn('#',...),...}end
local function _az_corocall(_az_callback,...)
 if _az_typefn(_az_corolib)~="table" or _az_typefn(_az_corolib.create)~="function" or _az_typefn(_az_corolib.resume)~="function" or _az_typefn(_az_corolib.status)~="function" then
  return false,"AzureVM protected initialization is unavailable"
 end
 local _az_arguments=_az_packvalues(...)
 local _az_thread=_az_corolib.create(function()return _az_callback(_az_unpackfn(_az_arguments,1,_az_arguments.n))end)
 local _az_results=_az_packvalues(_az_corolib.resume(_az_thread))
 if _az_results[1] and _az_corolib.status(_az_thread)~="dead" then return false,"AzureVM initializer must not yield" end
 return _az_unpackfn(_az_results,1,_az_results.n)
end
local pcall=_az_typefn(_az_pcallfn)=="function" and _az_pcallfn or _az_corocall
local function _az_capscheck()
 if not __AZ_CHECKS then return end
 local function _az_failcheck()_az_errorfn("AzureVM runtime integrity check failed",0)end
 if _az_typefn(_az_bytefn)~="function" or _az_typefn(_az_charfn)~="function" or _az_typefn(_az_subfn)~="function" or _az_typefn(_az_gsubfn)~="function" or _az_typefn(_az_findfn)~="function" or _az_typefn(_az_concatfn)~="function" or _az_typefn(_az_floorfn)~="function" or _az_typefn(_az_setmetafn)~="function" or _az_typefn(_az_unpackfn)~="function" then _az_failcheck()end
 if _az_bytefn("AZ",1)~=65 or _az_charfn(65,90)~="AZ" or _az_subfn("aAZb",2,3)~="AZ" or _az_gsubfn("AZ","A","Z")~="ZZ" or _az_concatfn({"A","Z"})~="AZ" or _az_floorfn(1.75)~=1 then _az_failcheck()end
 local _az_canary=_az_setmetafn({},{__index=function(_,key)return key end})
 if _az_canary[719]~=719 then _az_failcheck()end
 if type~=_az_typefn or error~=_az_errorfn or select~=_az_selectfn or string~=_az_stringlib or table~=_az_tablelib or math~=_az_mathlib or string.byte~=_az_bytefn or string.char~=_az_charfn or string.sub~=_az_subfn or string.gsub~=_az_gsubfn or string.find~=_az_findfn or table.concat~=_az_concatfn or math.floor~=_az_floorfn or setmetatable~=_az_setmetafn then _az_failcheck()end
end
local function _az_terminalerror(_az_value)
 if _az_typefn(_az_value)~="string" then return false end
 return _az_value=="AzureVM payload integrity check failed" or _az_value=="AzureVM runtime integrity check failed" or _az_value=="AzureVM initializer must not yield" or _az_value=="AzureVM protected initialization is unavailable"
end
local function _az_retryinit(_az_callback,_az_retries)
 local _az_lastfailure
 for _az_attempt=1,_az_retries+1 do
  local _az_success,_az_value
  if _az_typefn(_az_xpcallfn)=="function" then
   _az_success,_az_value=_az_xpcallfn(_az_callback,function(_az_problem)return _az_problem end)
  else _az_success,_az_value=pcall(_az_callback) end
  if _az_success then return _az_value end
  if _az_terminalerror(_az_value) then _az_errorfn(_az_value,0)end
  _az_lastfailure=_az_value
 end
 _az_errorfn(_az_lastfailure,0)
end
]=]
function Runtime.wrap(decoder,exports,options)
    local retries=Runtime.validate(options)
    local prelude=PRELUDE:gsub('__AZ_CHECKS',options.RuntimeChecks and 'true' or 'false')
    return prelude..'\nlocal _az_initresult=_az_retryinit(function()\n_az_capscheck()\n'..decoder..
        '\n_az_capscheck()\nreturn {'..table.concat(exports,',')..'}\nend,'..retries..')\nlocal '..
        table.concat(exports,',')..'=_az_unpackfn(_az_initresult,1,'..#exports..')\n_az_initresult=nil\n'
end
return Runtime
