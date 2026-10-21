local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/regression/") or "."
local lines, ticks = {}, 0
local durations = {9, 1, 3} -- ignored warm-up; then two samples whose median is 2
local env = setmetatable({
    arg = {"2"},
    os = { clock = function()
        ticks = ticks + 1
        if ticks % 2 == 1 then return 0 end
        return durations[((ticks / 2 - 1) % 3) + 1]
    end },
    print = function(line) lines[#lines + 1] = line end,
}, { __index = _G })
local benchmark = assert(loadfile(repo .. "/benchmark.lua"))
setfenv(benchmark, env)()
assert(#lines == 9, "unexpected benchmark report length")
for i = 3, #lines do
    assert(lines[i]:match("%s2%.000000%s+1%.000000%s+3%.000000$"),
        "incorrect even-sample median/min/max: " .. lines[i])
end
print("benchmark statistics: ok")
