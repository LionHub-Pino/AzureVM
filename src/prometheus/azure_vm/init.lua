--[[
    AzureVM - Custom Lua 5.1 Bytecode Virtual Machine
    Pipeline: source -> string.dump -> Reader -> Encoder -> Generator
    Output: polymorphic VM dispatch with compact output support

    Runtime capabilities:
    - Rolling payload encryption in encoder
    - Polymorphic instruction layout and opcode remapping
    - Opaque predicate support in generator
    - Configurable decoy opcode density
]]

local Reader     = require("prometheus.azure_vm.reader")
local Encoder    = require("prometheus.azure_vm.encoder")
local Generator  = require("prometheus.azure_vm.generator")
local Transpiler = require("prometheus.azure_vm.transpiler")
local Seed       = require("prometheus.azure_vm.seed")

local AzureVM = {}

local function load_source(text)
    -- Lua 5.1's loader also accepts binary chunks. This API accepts source only.
    if text:byte(1) == 27 then
        error("[AzureVM] Binary chunks are not supported; provide Lua source text", 2)
    end
    return loadstring(text, "@chunk")
end

function AzureVM.compile(source_code, options)
    if type(source_code) ~= "string" then
        error("[AzureVM] Source must be a string", 2)
    end
    if options ~= nil and type(options) ~= "table" then
        error("[AzureVM] Options must be a table", 2)
    end
    options = options or {}

    -- Prefer native Lua 5.1 without rewriting literals, newlines, or comments.
    local native_source = source_code
    if native_source:sub(1, 2) == "#!" then
        native_source = native_source:gsub("^#![^\r\n]*", "", 1)
    end
    local chunk_fn, err = load_source(native_source)
    if not chunk_fn then
        -- Limited Luau preprocessing is a fallback, not a full Luau compiler.
        chunk_fn, err = load_source(Transpiler.transpile(native_source))
    end
    if not chunk_fn then
        error("[AzureVM] Syntax error: " .. tostring(err))
    end
    local raw_bytecode = string.dump(chunk_fn)

    -- 3. Parse bytecode into prototype tree
    local root_proto = Reader.parse(raw_bytecode)

    -- 4. Encode with polymorphic opcodes and rolling keystream
    local seed = options.Seed or Seed.random()
    local encoder = Encoder.new(seed)
    local encoded_root = encoder:encode_prototype(root_proto)

    -- 5. Generate compact or formatted AzureVM output (version-aware)
    local vm_script = Generator.emit(encoded_root, encoder, {
        LuraphVersion = options.LuraphVersion or 15,
        DecoyDensity = options.DecoyDensity,
        OpaquePredicates = options.OpaquePredicates,
        Compact = options.Compact,
        RuntimeChecks = options.RuntimeChecks,
        InitializationRetries = options.InitializationRetries,
        Header = options.Header,
    })

    return vm_script
end

return AzureVM
