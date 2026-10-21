local repo = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/regression/") or "."
package.path = repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. package.path
local Reader = require("prometheus.azure_vm.reader")
local Encoder = require("prometheus.azure_vm.encoder")
local Generator = require("prometheus.azure_vm.generator")
local values = {
    0, -1 / math.huge, 1, -1, 0.1, 1 / 3,
    2^53 - 1, 2^53, 1 + 2^-52, 1 - 2^-53,
    2^-1022, 2^-1022 - 2^-1074, 2^-1022 + 2^-1074,
    2^-1074, -(2^-1074), 2^1023,
    1.7976931348623157e308, -1.7976931348623157e308,
    math.huge, -math.huge, 0/0,
}
for _, exponent in ipairs({-1073, -1022, -1000, -100, -1, 0, 1, 100, 1000, 1023}) do
    values[#values + 1] = math.ldexp(0.75, exponent)
    values[#values + 1] = -math.ldexp(0.75, exponent)
end
local checks = 0
for _, value in ipairs(values) do
  for _, mode in ipairs({14, 15}) do
    local proto = Reader.parse(string.dump(function() return 1 end))
    proto.constants[0] = { type = 3, value = value }
    for _, seed in ipairs({12345, 67890}) do
        local encoder = Encoder.new(seed)
        local output = Generator.emit(encoder:encode_prototype(proto), encoder, { LuraphVersion = mode })
        local actual = assert(loadstring(output))()
        checks = checks + 1
        if value ~= value then
            assert(actual ~= actual, "NaN constant was changed")
        else
            assert(actual == value, "numeric roundtrip changed " .. tostring(value) .. " to " .. tostring(actual))
            if value == 0 then assert(1/actual == 1/value, "signed zero was changed") end
        end
    end
  end
end
print("numeric constants: ok (" .. checks .. " roundtrips)")
