-- Whole-payload replay for explicitly stateless deployments.
-- "Safe" bounds retries and refreshes VM state; it does not roll back side effects.
local Step=require('prometheus.step')
local Retry=Step:extend()
Retry.Name='Safe Retry Wrapper'
Retry.Description='Replay a fresh VM factory after an error; external side effects are not rolled back.'
Retry.SettingsDescriptor={
    RetryCount={type='number',default=3,min=0,max=100,
        description='Additional payload attempts after the initial execution; 0 disables the wrapper'},
}
local function validate(count)
    if type(count)~='number' or count~=math.floor(count) or count<0 or count>100 then
        error('[AzureVM] RetryCount must be an integer from 0 to 100',2)
    end
end
function Retry:init()validate(self.RetryCount)end
local PREFIX=[=[
return(function(...)
local __az_retry_type,__az_retry_error,__az_retry_select=type,error,select
local __az_retry_unpack=unpack or (table and table.unpack)
local __az_retry_xcall,__az_retry_pcall=xpcall,pcall
if __az_retry_type(__az_retry_unpack)~="function" then __az_retry_error("SafeRetryWrapper requires unpack",0)end
if __az_retry_type(__az_retry_xcall)~="function" and __az_retry_type(__az_retry_pcall)~="function" then
__az_retry_error("SafeRetryWrapper requires pcall or xpcall",0)
end
local function __az_retry_pack(...)return {n=__az_retry_select('#',...),...}end
local __az_retry_args=__az_retry_pack(...)
local function __az_retry_payload(...)
]=]
local SUFFIX=[=[
end
local __az_retry_last
for __az_retry_attempt=1,__AZ_ATTEMPTS do
local function __az_retry_call()
return __az_retry_payload(__az_retry_unpack(__az_retry_args,1,__az_retry_args.n))
end
local __az_retry_values
if __az_retry_type(__az_retry_xcall)=="function" then
__az_retry_values=__az_retry_pack(__az_retry_xcall(__az_retry_call,function(problem)return problem end))
else
__az_retry_values=__az_retry_pack(__az_retry_pcall(__az_retry_call))
end
if __az_retry_values[1] then return __az_retry_unpack(__az_retry_values,2,__az_retry_values.n)end
__az_retry_last=__az_retry_values[2]
end
__az_retry_error(__az_retry_last,0)
end)(...);
]=]
local function singleline(template)
    return (template:gsub('[\r\n]+',' '))
end
function Retry.wrap(source,count)
    if type(source)~='string' then error('[AzureVM] SafeRetryWrapper source must be a string',2)end
    if count==nil then count=3 end
    validate(count)
    if count==0 then return source end
    -- Execute the entire decoder/VM factory again, not just __EXEC on a shared prototype.
    -- This also restores instruction tables erased by root RETURN/TAILCALL handlers.
    local separator=source:find('[\r\n]') and '\n' or ' '
    local suffix=SUFFIX:gsub('__AZ_ATTEMPTS',tostring(count+1))
    return singleline(PREFIX)..source..separator..singleline(suffix)
end
function Retry:apply(ast,pipeline)
    if type(pipeline.__azure_vm_result)~='string' then
        error('[AzureVM] SafeRetryWrapper must run after the AzureVM step',0)
    end
    pipeline.__azure_vm_result=Retry.wrap(pipeline.__azure_vm_result,self.RetryCount)
    return ast
end
return Retry
