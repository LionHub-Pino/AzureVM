local raw = [=[first

value += 7
\u{41}
last]=]
local escaped = "\\u{41} and \\u{1F600}"
local continued = "first\
\
last"
print(string.format("%q", raw))
print(string.format("%q", escaped))
print(string.format("%q", continued))
