local log, callbacks = {}, {}
local function probe(n)
    log[#log + 1] = n
    return n % 3 == 0
end
local total = 0
for i = 1, 8 do
    local value
    if i % 2 == 0 then value = i * 11 end
    callbacks[i] = function() return value end
    if probe(i) then
        local captured = i
        local function read() return captured end
        total = total + read()
    elseif probe(i + 1) then
        total = total + 7
    else
        total = total + i
    end
    if i == 7 then break end
end
local function recursive(n)
    if n == 0 then return nil, false, 255, 4294967295 end
    local a, b, c, d = recursive(n - 1)
    return a, b, c, d
end
local a, b, c, d = recursive(4)
local n = 0
repeat
    local limit = 3
    n = n + 1
until n == limit
print(total, table.concat(log, ","), a, b, c, d, n)
for i = 1, 7 do print(i, callbacks[i]()) end

local function shadow()
    local x=10
    local function first() return x end
    local x=20
    return first(),x
end
print(shadow())
