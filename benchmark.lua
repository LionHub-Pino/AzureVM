-- Small, repeatable Lua runtime microbenchmarks. Results are informational;
-- compare on the same machine/runtime and do not treat CI timings as a gate.
local samples = (not arg or arg[1] == nil) and 5 or tonumber(arg[1])
assert(samples and samples >= 1 and samples <= 100 and samples % 1 == 0,
	"usage: lua5.1 benchmark.lua [samples: 1..100]")

local benchmarks = {
	{ "arithmetic loop", 500000, function(n)
		local x = 0; for i = 1, n do x = x + i end; return x
	end },
	{ "function calls", 400000, function(n)
		local function f(a,b,c) return a + b * c end
		local s = 0; for i = 1, n do s = s + f(i, 2, 3) end; return s
	end },
	{ "table create/insert", 400000, function(n)
		local last; for i = 1, n do local t = {i, i*2, i*3}; t[i % 3 + 1] = i; last = t end
		return last and last[1]
	end },
	{ "table iteration", 2000, function(n)
		local t = {}; for i = 1, 1000 do t[i] = i end
		local s = 0; for _ = 1, n do for k,v in pairs(t) do s = s + v - k end end; return s
	end },
	{ "string concat", 4000, function(n)
		local s = ""; for _ = 1, n do s = s .. "a" end; return #s
	end },
	{ "closure creation", 300000, function(n)
		local acc, list = 0, {}; for i = 1, n do local f = function() return i end; acc = acc + f(); list[i % 16] = f end
		return acc
	end },
	{ "metatable index", 1000000, function(n)
		local proxy = {}; setmetatable(proxy, { __index = { value = 123 } })
		local s = 0; for _ = 1, n do s = s + proxy.value end; return s
	end },
}

local sink = 0
local function measure(fn, n)
	collectgarbage("collect")
	local started = os.clock()
	local result = fn(n)
	local elapsed = os.clock() - started
	if type(result) == "number" then sink = sink + result end
	return elapsed
end

print("AzureVM Lua 5.1 microbench (CPU time; informational)")
print(string.format("%-22s %10s %10s %10s %10s", "benchmark", "iterations", "median(s)", "min(s)", "max(s)"))
for _, b in ipairs(benchmarks) do
	measure(b[3], b[2]) -- warm-up
	local times = {}
	for i = 1, samples do times[i] = measure(b[3], b[2]) end
	table.sort(times)
	local middle = math.floor(#times / 2) + 1
	local median = #times % 2 == 1 and times[middle]
		or (times[middle - 1] + times[middle]) / 2
	print(string.format("%-22s %10d %10.6f %10.6f %10.6f", b[1], b[2], median, times[1], times[#times]))
end
if sink == math.huge then print(sink) end -- retain observable benchmark results
