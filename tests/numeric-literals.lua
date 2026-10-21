-- Compare exact formatting and zero signs after AST transforms + VM encoding.
local values = {
    1.0000000000000002, 0.9999999999999999, 9007199254740991,
    1.2345678901234567, 2.2250738585072014e-308,
    2.2250738585072009e-308, 4.9406564584124654e-324,
    -4.9406564584124654e-324, 1.7976931348623157e308,
    -1.7976931348623157e308, 1e309, -1e309, -0.0,
}
for i, value in ipairs(values) do
    print(i, string.format("%.17g", value), string.format("%.17g", 1/value))
end
