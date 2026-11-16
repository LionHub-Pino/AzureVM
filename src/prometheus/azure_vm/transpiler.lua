--[[
    AzureVM - Advanced Luau-to-Lua 5.1 Preprocessor (v1.5.2).
    Pre-pipeline transpiler converting modern Luau Roblox constructs into standard
    Lua 5.1 code for bytecode compilation.
    
    Supported Luau Features:
    - Shebang removal
    - Unicode escapes (\u{XXXX})
    - Binary numbers (0b[01]+)
    - Numeric underscores (1_000_000, 0x1F_2A)
    - Multiline and single-line type statements (type T = { ... }, export type ...)
    - Function parameter and return type annotations
    - Local variable type annotations (local x: number = 10)
    - Type casts (:: type)
    - String interpolation (`Hello {name}!`)
    - If-else ternary expressions (if a then b else c)
    - Compound operators (+=, -=, *=, /=, %=, ^=, ..=)
]]

local Transpiler = {}

function Transpiler.transpile(code)
    -- 1. Remove shebang if present
    code = code:gsub("^#![^\n]*\n", "")

    -- 2. Transpile unicode escapes: \u{XXXX} -> decimal byte sequence
    code = code:gsub("\\u%{([0-9a-fA-F]+)%}", function(hex)
        local val = tonumber(hex, 16)
        if not val then return "" end
        if val < 128 then
            return string.format("\\%03d", val)
        elseif val < 2048 then
            local b1 = 192 + math.floor(val / 64)
            local b2 = 128 + (val % 64)
            return string.format("\\%03d\\%03d", b1, b2)
        elseif val < 65536 then
            local b1 = 224 + math.floor(val / 4096)
            local b2 = 128 + (math.floor(val / 64) % 64)
            local b3 = 128 + (val % 64)
            return string.format("\\%03d\\%03d\\%03d", b1, b2, b3)
        else
            local b1 = 240 + math.floor(val / 262144)
            local b2 = 128 + (math.floor(val / 4096) % 64)
            local b3 = 128 + (math.floor(val / 64) % 64)
            local b4 = 128 + (val % 64)
            return string.format("\\%03d\\%03d\\%03d\\%03d", b1, b2, b3, b4)
        end
    end)

    -- 3. Transpile binary literals: 0b1011 -> 11
    code = code:gsub("%f[%w]0b([01]+)%f[%W]", function(bin)
        local num = 0
        for i = 1, #bin do
            num = num * 2 + (bin:sub(i, i) == "1" and 1 or 0)
        end
        return tostring(num)
    end)

    -- 4. Transpile numeric underscores: 1_000_000 -> 1000000
    code = code:gsub("(%f[%w]%d+)_([%d_]+)%f[%W]", function(head, tail)
        return head .. tail:gsub("_", "")
    end)
    code = code:gsub("(%f[%w]0x[%da-fA-F]+)_([%da-fA-F_]+)%f[%W]", function(head, tail)
        return head .. tail:gsub("_", "")
    end)

    -- 5. Strip multiline and single-line Luau type statements
    code = code:gsub("(%f[%w]export[ \t]+type[ \t]+[%w_]+[ \t]*=[ \t]*%b{})", "")
    code = code:gsub("(%f[%w]type[ \t]+[%w_]+[ \t]*=[ \t]*%b{})", "")
    code = code:gsub("([\r\n]%s*)export[ \t]+type[ \t]+[%w_]+[ \t]*=[ \t]*[^\r\n]+", "%1")
    code = code:gsub("([\r\n]%s*)type[ \t]+[%w_]+[ \t]*=[ \t]*[^\r\n]+", "%1")
    code = code:gsub("^%s*export[ \t]+type[ \t]+[%w_]+[ \t]*=[ \t]*[^\r\n]+", "")
    code = code:gsub("^%s*type[ \t]+[%w_]+[ \t]*=[ \t]*[^\r\n]+", "")

    -- 6. Strip Luau type casts: expr :: any -> (expr)
    code = code:gsub("::[ \t]*[%w_%.%[%]%<%>%?%|%& \t]+", "")

    -- 7. Strip variable and function type annotations
    code = code:gsub("(local[ \t]+)([%w_]+)[ \t]*:[ \t]*[%w_%.%[%]%<%>%?%|%& \t]+[ \t]*=", function(pfx, varname)
        if varname == "function" then return nil end
        return pfx .. varname .. " ="
    end)
    code = code:gsub("(function[ \t]*[%w_%.%:]*[ \t]*%b())[ \t]*:[ \t]*[%w_%.%[%]%<%>%?%|%& \t]+", "%1")
    code = code:gsub("(function[ \t]*[%w_%.%:]*[ \t]*)(%b())", function(decl, params)
        local inner = params:sub(2, -2)
        inner = inner:gsub("([%w_]+)[ \t]*:[ \t]*[%w_%.%[%]%<%>%?%|%& \t]+", "%1")
        return decl .. "(" .. inner .. ")"
    end)

    -- 8. Transpile String Interpolation: `Count: {x}!` -> ("Count: " .. tostring(x) .. "!")
    code = code:gsub("`([^`]*)`", function(content)
        local parts = {}
        local last_idx = 1
        local len = #content
        while last_idx <= len do
            local start_b, end_b = content:find("{.-}", last_idx)
            if start_b then
                if start_b > last_idx then
                    local text = content:sub(last_idx, start_b - 1)
                    table.insert(parts, string.format("%q", text))
                end
                local expr = content:sub(start_b + 1, end_b - 1)
                table.insert(parts, string.format("tostring(%s)", expr))
                last_idx = end_b + 1
            else
                local text = content:sub(last_idx)
                table.insert(parts, string.format("%q", text))
                break
            end
        end
        if #parts == 0 then
            return '""'
        elseif #parts == 1 then
            return parts[1]
        else
            return "(" .. table.concat(parts, " .. ") .. ")"
        end
    end)

    -- 9. Transpile Luau if-else expressions
    code = code:gsub("(%f[%w]local%s+[%w_]+%s*=%s*)if%s+(.-)%s+then%s+(.-)%s+else%s+([^\r\n;]+)", function(pfx, c, t, f)
        f = f:match("^%s*(.-)%s*$")
        return string.format("%s((%s) and (%s) or (%s))", pfx, c, t, f)
    end)
    code = code:gsub("(%f[%w][%w_%.%[%]]+%s*=%s*)if%s+(.-)%s+then%s+(.-)%s+else%s+([^\r\n;]+)", function(pfx, c, t, f)
        if pfx:find("^%s*if%s+") then return nil end
        f = f:match("^%s*(.-)%s*$")
        return string.format("%s((%s) and (%s) or (%s))", pfx, c, t, f)
    end)
    code = code:gsub("(%f[%w]return%s+)if%s+(.-)%s+then%s+(.-)%s+else%s+([^\r\n;]+)", function(pfx, c, t, f)
        f = f:match("^%s*(.-)%s*$")
        return string.format("%s((%s) and (%s) or (%s))", pfx, c, t, f)
    end)

    -- 10. Transpile compound operators outside strings and comments
    local function expand_compound_safe(line)
        -- Skip lines that are pure comments
        if line:match("^%s*%-%-") then return line end
        
        -- Parse line respecting string boundaries
        local result = {}
        local i = 1
        local len = #line
        while i <= len do
            local ch = line:sub(i, i)
            if ch == '"' or ch == "'" then
                local quote = ch
                local j = i + 1
                while j <= len do
                    local c = line:sub(j, j)
                    if c == '\\' then
                        j = j + 2
                    elseif c == quote then
                        j = j + 1
                        break
                    else
                        j = j + 1
                    end
                end
                result[#result+1] = line:sub(i, j - 1)
                i = j
            elseif ch == '[' and (line:sub(i, i+1) == '[[' or line:sub(i, i+1) == '[=') then
                local eq = line:match('^%[(=*)%[', i)
                if eq then
                    local close = ']' .. eq .. ']'
                    local j = line:find(close, i + 2 + #eq, true)
                    if j then
                        j = j + #close
                        result[#result+1] = line:sub(i, j - 1)
                        i = j
                    else
                        result[#result+1] = line:sub(i)
                        i = len + 1
                    end
                else
                    result[#result+1] = ch
                    i = i + 1
                end
            elseif line:sub(i, i+1) == '--' then
                result[#result+1] = line:sub(i)
                i = len + 1
            else
                result[#result+1] = ch
                i = i + 1
            end
        end
        
        local reconstructed = table.concat(result)
        
        local lhs, op, rhs = reconstructed:match("^(%s*[%w_%.%[%]]+)%s*([%+%-%*%/%%%^]%=)%s*(.-)$")
        if lhs and op and rhs then
            local pure_op = op:sub(1, 1)
            lhs = lhs:match("^%s*(.-)%s*$")
            return string.format("%s = %s %s (%s)", lhs, lhs, pure_op, rhs)
        end
        local lhs_c, op_c, rhs_c = reconstructed:match("^(%s*[%w_%.%[%]]+)%s*(%.%.%=)%s*(.-)$")
        if lhs_c and op_c and rhs_c then
            lhs_c = lhs_c:match("^%s*(.-)%s*$")
            return string.format("%s = %s .. (%s)", lhs_c, lhs_c, rhs_c)
        end
        return line
    end

    local lines = {}
    for line in code:gmatch("[^\r\n]+") do
        table.insert(lines, expand_compound_safe(line))
    end
    code = table.concat(lines, "\n")

    return code
end

return Transpiler
