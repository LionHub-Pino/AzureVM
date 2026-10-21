-- Compare trusted fixtures with their AzureVM output on the same runtime.
-- Timings include VM initialization/decoding on every call, not Lua source parsing.
local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/scripts/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path
local AzureVM = require("prometheus.azure_vm")
local samples = arg[1] == nil and 5 or tonumber(arg[1])
assert(samples and samples >= 1 and samples <= 100 and samples % 1 == 0,
    "usage: lua5.1 scripts/benchmark-vm.lua [samples: 1..100]")
local fixtures = {
    { name = "arithmetic", source = [[
        local total = 0
        for i = 1, 10000 do total = total + i * 3 end
        return total
    ]] },
    { name = "closures", source = [[
        local function counter(start)
            return function(delta) start = start + delta; return start end
        end
        local nextValue = counter(10)
        local total = 0
        for i = 1, 1000 do total = total + nextValue(i) end
        return total
    ]] },
    { name = "tables_strings", source = [[
        local values = {}
        for i = 1, 1000 do values[i] = "item" .. i end
        local total = 0
        for i, value in ipairs(values) do total = total + i + #value end
        return total
    ]] },
}
local function measure(fn, expected)
    collectgarbage("collect")
    local started = os.clock()
    local actual = fn()
    local elapsed = os.clock() - started
    assert(actual == expected, "benchmark correctness mismatch")
    return elapsed
end
local function median(values)
    table.sort(values)
    local middle = math.floor(#values / 2) + 1
    if #values % 2 == 1 then return values[middle] end
    return (values[middle - 1] + values[middle]) / 2
end
print("runtime,workload,seed,samples,source_bytes,vm_bytes,compile_cpu_s,native_median_cpu_s,vm_median_cpu_s,slowdown")
for _, fixture in ipairs(fixtures) do
    local native = assert(loadstring(fixture.source, "@benchmark_native"))
    local expected = native()
    for _, seed in ipairs({12345, 67890}) do
        collectgarbage("collect")
        local started = os.clock()
        local output = AzureVM.compile(fixture.source, { Seed = seed, LuraphVersion = 14 })
        local compile_time = os.clock() - started
        local vm = assert(loadstring(output, "@benchmark_vm"))
        measure(native, expected) -- warm both paths before sampling
        measure(vm, expected)
        local native_times, vm_times = {}, {}
        for i = 1, samples do
            -- Alternate order to reduce systematic warm-up/order bias.
            if i % 2 == 1 then
                native_times[i] = measure(native, expected)
                vm_times[i] = measure(vm, expected)
            else
                vm_times[i] = measure(vm, expected)
                native_times[i] = measure(native, expected)
            end
        end
        local native_time, vm_time = median(native_times), median(vm_times)
        local ratio = native_time > 0 and string.format("%.3f", vm_time / native_time) or "NA"
        print(string.format("%s,%s,%d,%d,%d,%d,%.6f,%.6f,%.6f,%s",
            _VERSION, fixture.name, seed, samples, #fixture.source, #output,
            compile_time, native_time, vm_time, ratio))
    end
end
