local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/regression/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path
local Pipeline = require("prometheus.pipeline")
local presets = require("presets")
local logger = require("logger")
logger.logLevel = logger.LogLevel.Error
local file = assert(io.open(repo .. "/tests/numeric-literals.lua", "rb"))
local source = file:read("*a")
file:close()

-- Capture trusted fixture output; this environment is not a security sandbox.
local function capture(code)
    local lines = {}
    local env = setmetatable({ print = function(...)
        local values = {}
        for i = 1, select("#", ...) do values[i] = tostring(select(i, ...)) end
        lines[#lines + 1] = table.concat(values, "\t")
    end }, { __index = _G })
    local fn = assert(loadstring(code))
    setfenv(fn, env)()
    return table.concat(lines, "\n")
end
local expected = capture(source)
local checks = 0
for _, preset in ipairs({"Luraph", "Luraph14", "Luraph15", "AzureGod", "AzureGod15", "AzureGodUltra"}) do
    for _, seed in ipairs({1, 12345, 67890}) do
        local pipeline = Pipeline:fromConfig(presets[preset])
        pipeline.Seed, pipeline.seed = seed, seed
        local output = pipeline:apply(source)
        assert(capture(output) == expected, "numeric precision changed for " .. preset .. " seed " .. seed)
        checks = checks + 1
        collectgarbage("collect")
    end
end
print("numeric pipeline: ok (" .. checks .. " preset/seed combinations)")
