#!/usr/bin/env lua
--[[
    AzureObf - Lua 5.1 VM-based obfuscator
    Built on Prometheus; preset names are AzureVM compatibility labels.
    Developed for Chủ Nhân Azure.
]]

local function script_path()
    local str = debug.getinfo(1, "S").source:sub(2)
    return str:match("(.*[/%\\])") or "./"
end

local base_dir = script_path()
package.path = base_dir .. "src/?.lua;" .. base_dir .. "src/?/init.lua;" .. base_dir .. "prometheus/src/?.lua;" .. base_dir .. "prometheus/src/?/init.lua;" .. package.path

local AzureVM = require("prometheus.azure_vm")
local Pipeline = require("prometheus.pipeline")

local BANNER = [[
================================================================================
       ___                             ____  __      ____  
      /   | ____  __  __________      / __ \/ /_    / __/  
     / /| |/_  / / / / / ___/ _ \    / / / / __ \  / /_    
    / ___ | / /_/ /_/ / /  /  __/   / /_/ / /_/ / / __/    
   /_/  |_|/___/\__,_/_/   \___/    \____/_.___(_)_/       
                                                           
   Lua 5.1 VM-based obfuscator
   Custom opcode mapping - rolling encoding - optional AST transforms
================================================================================
]]

local function print_help()
    print(BANNER)
    print("Usage: lua azure_obf.lua <input.lua> [options]")
    print("")
    print("Options:")
    print("  -o, --out <file>       Output destination (default: <input>_protected.lua)")
    print("  --preset <name>        Protection profile:")
    print("                           Luraph     : AzureVM baseline (default; not Luraph)")
    print("                           Luraph14   : AzureVM with string and number transforms")
    print("                           Luraph15   : Same transforms, more decoy handlers")
    print("                           AzureGod   : String and number transforms, 1.5x decoys (alias: Khoidieu)")
    print("                           AzureGod15 : Same transforms, template mode 15 (alias: Biendieu, Hardcore)")
    print("                           AzureGodUltra : Deep CFF, MBA, guards and payload retry (alias: Dudieu, Immortal)")
    print("                           Khoidieu      : Chương 1 MONO (AST transforms, 1.5x decoys)")
    print("                           Biendieu      : Chương 2 MONO (Template mode 15, high hardening)")
    print("                           Dudieu        : Chương 3 MONO (Deep CFF, MBA, Guards, Retry)")
    print("                           Hardcore      : Alias for AzureGod15")
    print("                           Life          : Alias for Weak")
    print("  --header <text>        Custom comment header (default: AzureVM template mode)")
    print("  --compact             Emit a single physical line, including header")
    print("  --retry-count <N>     Payload retries 0..100; also --retry-count=N (Ultra: 3)")
    print("  --seed <number>        Integer 1..2147483647 for deterministic compilation")
    print("  -v, --version          Show version info")
    print("  -h, --help             Show this help menu")
    print("")
    print("Examples:")
    print("  lua azure_obf.lua main.lua -o main_obf.lua")
    print("  lua azure_obf.lua script.lua --preset Luraph -o out.lua")
    print("  lua azure_obf.lua script.lua --preset Luraph14 -o out.lua")
    print("  lua azure_obf.lua game.lua --preset Luraph15 -o out.lua")
    print("  lua azure_obf.lua game.lua --preset AzureGod15 --seed 99999")
end

local args = { ... }
if #args == 0 then
    print_help()
    os.exit(0)
end

local input_file = nil
local output_file = nil
local preset = "Luraph"
local seed = require("prometheus.azure_vm.seed").random()
local header_text = nil
local compact = false
local retry_count = nil

local function fail(message)
    io.stderr:write("[-] Error: " .. message .. "\n")
    os.exit(1)
end

local function option_value(index, option)
    local value = args[index + 1]
    if not value or value:match("^%-%-") then
        fail("Missing value for " .. option)
    end
    return value
end

local function parse_retry_count(value)
    local count = tonumber(value)
    if not count or count < 0 or count > 100 or count % 1 ~= 0 then
        fail("Retry count must be an integer between 0 and 100")
    end
    return count
end

local i = 1
while i <= #args do
    local arg = args[i]
    if arg == "-h" or arg == "--help" then
        print_help()
        os.exit(0)
    elseif arg == "-v" or arg == "--version" then
        print("AzureVM v2.0.0")
        os.exit(0)
    elseif arg == "-o" or arg == "--out" then
        output_file = option_value(i, arg)
        i = i + 1
    elseif arg == "--preset" then
        preset = option_value(i, arg)
        i = i + 1
    elseif arg == "--compact" then
        compact = true
    elseif arg == "--retry-count" then
        retry_count = parse_retry_count(option_value(i, arg))
        i = i + 1
    elseif arg:match("^%-%-retry%-count=") then
        retry_count = parse_retry_count(arg:match("=(.*)$"))
    elseif arg == "--header" then
        header_text = option_value(i, arg)
        i = i + 1
    elseif arg == "--seed" then
        local value = option_value(i, arg)
        seed = tonumber(value)
        if not seed or seed < 1 or seed > 2147483647 or seed % 1 ~= 0 then
            fail("Seed must be an integer between 1 and 2147483647")
        end
        i = i + 1
    elseif not input_file and not arg:match("^%-") then
        input_file = arg
    else
        fail("Unexpected argument: " .. arg)
    end
    i = i + 1
end

local presets = require("presets")
local pipeline_config = presets[preset]
if not pipeline_config then
    fail("Unknown preset: " .. preset)
end

if retry_count ~= nil then
    local found = false
    for _, step in ipairs(pipeline_config.Steps or {}) do
        if step.Name == "SafeRetryWrapper" then
            step.Settings = step.Settings or {}
            step.Settings.RetryCount = retry_count
            found = true
        end
    end
    if not found and retry_count > 0 then
        local vm_index
        for index, step in ipairs(pipeline_config.Steps or {}) do
            if step.Name == "AzureVM" then vm_index = index end
        end
        if not vm_index then fail("--retry-count requires an AzureVM preset") end
        table.insert(pipeline_config.Steps, vm_index + 1, {
            Name = "SafeRetryWrapper", Settings = { RetryCount = retry_count }
        })
    end
end

if not input_file then
    io.stderr:write("[-] Error: No input file specified.\n")
    os.exit(1)
end

if not output_file then
    output_file = input_file:gsub("%.lua$", "") .. "_protected.lua"
    if output_file == input_file then
        output_file = input_file .. ".protected.lua"
    end
end

-- Read source file
local f_in = io.open(input_file, "r")
if not f_in then
    io.stderr:write("[-] Error: Cannot open input file: " .. input_file .. "\n")
    os.exit(1)
end
local source_code = f_in:read("*a")
f_in:close()

print(BANNER)
print(string.format("[*] Target Script : %s (%d bytes)", input_file, #source_code))
print(string.format("[*] Preset        : %s", preset))
local lph_ver = (preset:lower():find("15") or preset:lower():find("ultra")) and 15 or 14
print(string.format("[*] Template Mode : AzureVM %d", lph_ver))
print(string.format("[*] PRNG Seed     : %d", seed))
print("")

local Transpiler = require("prometheus.azure_vm.transpiler")

local clock_start = os.clock()

local compile_source = source_code
local final_code

-- For AzureGod: Apply AST mutation on raw source FIRST, then compile into VM
print("[1/2] Loading Prometheus presets...")

if header_text or compact then
    for _, step in ipairs(pipeline_config.Steps or {}) do
        if step.Name == "AzureVM" then
            step.Settings = step.Settings or {}
            if header_text then step.Settings.Header = header_text end
            if compact then step.Settings.Compact = true end
        end
    end
end

print("[2/2] Applying obfuscation pipeline...")
local Pipeline = require("prometheus.pipeline")
local pipeline = Pipeline:fromConfig(pipeline_config)
pipeline.Seed = seed
pipeline.seed = seed
final_code = pipeline:apply(source_code)


local elapsed = os.clock() - clock_start

-- Write output
local f_out = io.open(output_file, "w")
if not f_out then
    io.stderr:write("[-] Error: Cannot write to output file: " .. output_file .. "\n")
    os.exit(1)
end
f_out:write(final_code)
f_out:close()

print("")
print(string.format("[+] Obfuscation successfully completed in %.2f seconds!", elapsed))
print(string.format("[+] Output File: %s (%d bytes)", output_file, #final_code))
print("[+] AzureVM output generated. Run tests before deploying to your target runtime.")
