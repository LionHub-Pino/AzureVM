--[[
    Prometheus Step: AzureVM
    Bytecode Virtualization Compiler
    Transforms source code into a custom polymorphic bytecode virtual machine.
    Supports Luraph v14.7 Classic and v15.2 Ultra cloaking modes.

    Runtime features:
    - Rolling payload encryption
    - Opaque predicates
    - Configurable decoy opcode density
    - Version-aware anti-debug & anti-tamper
    - Luraph v14.7/v15.2 fingerprint cloaking
]]

local Step = require("prometheus.step")
local AzureVM = require("prometheus.azure_vm")
local Parser = require("prometheus.parser")
local logger = require("logger")

local AzureVMStep = Step:extend()
AzureVMStep.Description = "Compiles code into a custom polymorphic bytecode virtual machine with rolling encryption, runtime integrity checks, and Luraph v14.7/v15.2 cloaking."
AzureVMStep.Name = "AzureVM"

AzureVMStep.SettingsDescriptor = {
    Seed = {
        type = "number",
        default = 0,
        description = "PRNG seed for opcode and keystream scrambling (0 for random)"
    },
    FormatVersion = {
        type = "number",
        default = 1,
        description = "AzureVM payload format version"
    },
    LuraphVersion = {
        type = "number",
        default = 15,
        description = "Luraph cloaking version: 14 for v14.7 Classic, 15 for v15.2 Ultra"
    },
    DecoyDensity = {
        type = "number",
        default = 1.0,
        min = 0.0,
        max = 2.0,
        description = "Multiplier for decoy opcode handler count (1.0 = normal, 2.0 = double)"
    },
    OpaquePredicates = {
        type = "boolean",
        default = true,
        description = "Insert opaque predicates into VM dispatch loop"
    },
    Header = {
        type = "string",
        default = "",
        description = "Custom comment header prefix (e.g. Azure VM)"
    }
}

function AzureVMStep:init()
    -- Step:new() already assigns settings from SettingsDescriptor to self.
    -- Only provide fallback defaults for safety here.
    if self.Seed == nil then self.Seed = 0 end
    if self.FormatVersion == nil then self.FormatVersion = 1 end
    if self.LuraphVersion == nil then self.LuraphVersion = 15 end
    if self.DecoyDensity == nil then self.DecoyDensity = 1.0 end
    if self.OpaquePredicates == nil then self.OpaquePredicates = true end
    if self.Header == nil then self.Header = "" end
end

function AzureVMStep:apply(ast, pipeline)
    local unparser = pipeline.unparser
    local raw_source = unparser:unparse(ast)

    local seed = (self.Seed and self.Seed > 0) and self.Seed or os.time()

    local lph_ver_str = (self.LuraphVersion == 14) and "v14.7 Classic" or "v15.2 Ultra"
    logger:info(string.format("AzureVM [%s] format=%d: compiling with seed=%d, decoy_density=%.1f, opaque_predicates=%s",
        lph_ver_str, self.FormatVersion, seed, self.DecoyDensity, tostring(self.OpaquePredicates)))

    local vm_source = AzureVM.compile(raw_source, {
        Seed = seed,
        FormatVersion = self.FormatVersion,
        LuraphVersion = self.LuraphVersion,
        DecoyDensity = self.DecoyDensity,
        OpaquePredicates = self.OpaquePredicates,
        Header = self.Header,
    })

    pipeline.__azure_vm_result = vm_source
    return ast
end

return AzureVMStep
