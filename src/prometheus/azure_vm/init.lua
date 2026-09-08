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

local AzureVM = {}

function AzureVM.compile(source_code, options)
    options = options or {}

    -- 1. Transpile Luau → Lua 5.1 with string-safe compound op expansion
    local clean_code = Transpiler.transpile(source_code)

    -- 2. Compile to bytecode
    local chunk_fn, err = loadstring(clean_code, "@chunk")
    if not chunk_fn then
        error("[AzureVM] Syntax error: " .. tostring(err))
    end
    local raw_bytecode = string.dump(chunk_fn)

    -- 3. Parse bytecode into prototype tree
    local root_proto = Reader.parse(raw_bytecode)

    -- 4. Encode with polymorphic opcodes and rolling keystream
    local seed = options.Seed or os.time()
    local encoder = Encoder.new(seed)
    local encoded_root = encoder:encode_prototype(root_proto)

    -- 5. Generate compact or formatted AzureVM output (version-aware)
    local vm_script = Generator.emit(encoded_root, encoder, {
        LuraphVersion = options.LuraphVersion or 15,
        DecoyDensity = options.DecoyDensity,
        OpaquePredicates = options.OpaquePredicates,
        Compact = options.Compact,
        Header = options.Header,
    })

    return vm_script
end

return AzureVM
