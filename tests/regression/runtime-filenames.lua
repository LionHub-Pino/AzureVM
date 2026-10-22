local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/regression/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path
local AzureVM = require("prometheus.azure_vm")
local source = "local total=0; for i=1,40 do total=total+i end; return total"
local checks = 0
for _, mode in ipairs({14, 15}) do
    for _, seed in ipairs({12345, 67890}) do
        local output = AzureVM.compile(source, { Seed = seed, LuraphVersion = mode })
        for _, filename in ipairs({"ordinary.lua", "hook_config.lua", "dump_report.lua", "profiler_config.lua", "extractor_example.lua"}) do
            local fn = assert(loadstring(output, "@" .. filename))
            local ok, result = pcall(fn)
            assert(ok and result == 820, "filename changed VM behavior: " .. filename .. ": " .. tostring(result))
            checks = checks + 1
        end
    end
end
local old_hook, old_mask, old_count = debug.gethook()
local calls = 0
local hook = function() calls = calls + 1 end
debug.sethook(hook, "", 1000)
local ok, err = pcall(function()
    local output = AzureVM.compile(source, { Seed = 12345, LuraphVersion = 15 })
    assert(assert(loadstring(output, "@profiler_config.lua"))() == 820)
    local current, mask, count = debug.gethook()
    assert(current == hook and mask == "" and count == 1000, "VM modified the host debug hook")
    assert(calls > 0, "host debug hook did not run")
end)
if old_hook then debug.sethook(old_hook, old_mask, old_count) else debug.sethook() end
assert(ok, err)
print("runtime filenames: ok (" .. checks .. " contexts, host hook preserved)")
