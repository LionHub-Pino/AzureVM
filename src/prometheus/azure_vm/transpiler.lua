--[[
    AzureVM - Luau to Lua 5.1 Preprocessor / Transpiler
    Converts Luau-specific syntax to standard Lua 5.1 for full compilation fidelity.
    v14.7 - Fixed: compound operators inside strings are no longer incorrectly transformed
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

    -- 3. Transpile compound operators: +=, -=, *=, /=, %=, ^=, ..=
    -- FIXED: Only transform outside of string literals and comments
    local function expand_compound_safe(line)
        -- Skip lines that are pure comments
        if line:match("^%s*%-%-") then return line end
        
        -- Parse line respecting string boundaries
        local result = {}
        local i = 1
        local len = #line
        while i <= len do
            local ch = line:sub(i, i)
            -- Handle string literals - skip over them entirely
            if ch == '"' or ch == "'" then
                local quote = ch
                local j = i + 1
                while j <= len do
                    local c = line:sub(j, j)
                    if c == '\\' then
                        j = j + 2  -- skip escape sequence
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
                -- Long string literal, find matching close
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
                -- Comment to end of line
                result[#result+1] = line:sub(i)
                i = len + 1
            else
                result[#result+1] = ch
                i = i + 1
            end
        end
        
        local reconstructed = table.concat(result)
        
        -- Now try to match compound operators only on the code portion
        -- We need to check if the compound op is actually in code, not in a string
        local lhs, op, rhs = reconstructed:match("^(%s*[%w_%.%[%]]+)%s*([%+%-%*%/%%%^]%=)%s*(.-)$")
        if lhs and op and rhs then
            -- Verify lhs is a valid assignment target (not inside a string)
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
