-- Demo script with multiple features to stress-test the obfuscator
local function greet(name)
    print("Hello, " .. name .. "! Welcome to Azure Engine.")
end

local function add(a, b)
    return a + b
end

local function factorial(n)
    if n <= 1 then return 1 end
    return n * factorial(n - 1)
end

greet("Azure")
print("2 + 3 = " .. tostring(add(2, 3)))
print("5! = " .. tostring(factorial(5)))

local t = {}
for i = 1, 5 do
    t[i] = i * i
end
print("Squares: " .. table.concat(t, ", "))
print("Done!")
