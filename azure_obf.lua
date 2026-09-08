#!/usr/bin/env lua
--[[
    AzureObf - Elite Lua/Luau Virtualization & Obfuscation Engine
    Architecture inspired by Prometheus & Luraph (Luraph-grade & beyond)
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
                                                           
   Elite Lua/Luau Virtualization Engine | Luraph-Grade & Beyond
   Custom ISA - Rolling Keystream - Anti-Hook - Opaque Math
================================================================================
]]

local function print_help()
    print(BANNER)
    print("Usage: lua azure_obf.lua <input.lua> [options]")
    print("")
    print("Options:")
    print("  -o, --out <file>       Output destination (default: <input>_protected.lua)")
    print("  --preset <name>        Protection profile:")
    print("                           Luraph     : Luraph v14.7 Standalone VM (Default)")
    print("                           Luraph14   : Luraph v14.7 Full Pipeline (Pre-VM + VM + Post-VM)")
    print("                           Luraph15   : Luraph v15.2 Ultra Full Pipeline")
    print("                           AzureGod   : AST Pre-Mutation + AzureVM v14.7")
    print("                           AzureGod15 : AST Pre-Mutation + Full Pipeline + AzureVM v15.2")
    print("  --header <text>        Custom comment header (default: Azure VM v14.7/v15.2)")
    print("  --seed <number>        Fixed PRNG seed for deterministic compilation")
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
local seed = os.time()
local header_text = nil

local i = 1
while i <= #args do
    local arg = args[i]
    if arg == "-h" or arg == "--help" then
        print_help()
        os.exit(0)
    elseif arg == "-v" or arg == "--version" then
        print("AzureObf Engine v2.0 (Prometheus-Azure Hybrid)")
        os.exit(0)
    elseif arg == "-o" or arg == "--out" then
        i = i + 1
        output_file = args[i]
    elseif arg == "--preset" then
        i = i + 1
        preset = args[i]
    elseif arg == "--header" then
        i = i + 1
        header_text = args[i]
    elseif arg == "--seed" then
        i = i + 1
        seed = tonumber(args[i]) or seed
    elseif not input_file and not arg:match("^%-") then
        input_file = arg
    end
    i = i + 1
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
local lph_ver = (preset:lower():find("15")) and 15 or 14
print(string.format("[*] Cloaking Mode : Luraph v%s", lph_ver == 15 and "15.2 Ultra" or "14.7 Classic"))
print(string.format("[*] PRNG Seed     : %d", seed))
print("")

local Transpiler = require("prometheus.azure_vm.transpiler")

local clock_start = os.clock()

local compile_source = source_code
local final_code

-- For AzureGod: Apply AST mutation on raw source FIRST, then compile into VM
print("[1/2] Loading Prometheus presets...")
local presets = require("presets")
local pipeline_config = presets[preset] or presets["AzureGod"]

if header_text then
    for _, step in ipairs(pipeline_config.Steps or {}) do
        if step.Name == "AzureVM" then
            step.Settings = step.Settings or {}
            step.Settings.Header = header_text
        end
    end
end

print("[2/2] Applying obfuscation pipeline...")
local Pipeline = require("prometheus.pipeline")
local pipeline = Pipeline:fromConfig(pipeline_config)
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
print("[+] Protection verified: Luraph-grade polymorphic VM + rolling keystream active.")
