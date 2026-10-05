-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- presets.lua
--
-- Predefined obfuscation presets for Prometheus + AzureVM
-- AzureVM presets. Historical Luraph-named keys are compatibility labels.

return {
	-- Minifies your code. Does not obfuscate it. No performance loss.
	["Minify"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {},
	},

	-- Weak obfuscation. Very readable, low performance loss.
	["Weak"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = {} },
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
		},
	},

	-- Vmify-only preset for testing
	["Vmify"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = {} },
		},
	},

	-- Medium obfuscation. Moderate obfuscation, moderate performance loss.
	["Medium"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "EncryptStrings", Settings = {} },
			{ Name = "Vmify", Settings = {} },
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperThreshold = 0,
				},
			},
			{ Name = "NumbersToExpressions", Settings = {} },
			{ Name = "WrapInFunction", Settings = {} },
		},
	},

	-- Strong obfuscation, high performance loss.
	["Strong"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = {} },
			{ Name = "EncryptStrings", Settings = {} },
			{ Name = "Vmify", Settings = {} },
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperThreshold = 0
				},
			},
			{
				Name = "NumbersToExpressions",
				Settings = {
					NumberRepresentationMutation = true
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
		},
	},

	-- =====================================================================
    -- Luraph: AzureVM baseline template mode 14 (default)
	-- Fingerprint: LPH_JIT_MAX, debug.getinfo(1)
    -- Opcode mapping and rolling instruction encoding
	-- =====================================================================
	["Luraph"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "AzureVM", Settings = { LuraphVersion = 14 } },
		},
	},

	-- =====================================================================
    -- Luraph14: AzureVM template mode 14 with AST pre-transforms
	-- AST Pre-Mutation: SplitStrings + EncryptStrings + NumbersToExpressions
    -- Virtualization: AzureVM template mode 14
	-- =====================================================================
	["Luraph14"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "SplitStrings", Settings = {} },
			{ Name = "EncryptStrings", Settings = {} },
			{ Name = "NumbersToExpressions", Settings = { NumberRepresentationMutation = true } },
			{ Name = "AzureVM", Settings = { LuraphVersion = 14, DecoyDensity = 1.0 } },
		},
	},

	-- =====================================================================
    -- Luraph15: AzureVM template mode 15 with AST pre-transforms
	-- AST Pre-Mutation: SplitStrings + EncryptStrings + NumbersToExpressions
    -- Virtualization: AzureVM template mode 15
	-- Fingerprint: LPH_JIT_ULTRA + pcall(debug.getinfo, 2, "f") + getupvalue checks
	-- =====================================================================
	["Luraph15"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "SplitStrings", Settings = {} },
			{ Name = "EncryptStrings", Settings = {} },
			{ Name = "NumbersToExpressions", Settings = { NumberRepresentationMutation = true } },
			{ Name = "AzureVM", Settings = { LuraphVersion = 15, DecoyDensity = 1.2 } },
		},
	},

	-- =====================================================================
    -- AzureGod: AST pre-transforms + 1.5x decoy density + template mode 14
	-- =====================================================================
	["AzureGod"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "SplitStrings", Settings = {} },
			{ Name = "EncryptStrings", Settings = {} },
			{ Name = "NumbersToExpressions", Settings = { NumberRepresentationMutation = true } },
			{ Name = "AzureVM", Settings = { LuraphVersion = 14, DecoyDensity = 1.5 } },
		},
	},

	-- =====================================================================
    -- AzureGod15: AST pre-transforms + 1.5x decoy density + template mode 15
	-- =====================================================================
	["AzureGod15"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "SplitStrings", Settings = {} },
			{ Name = "EncryptStrings", Settings = {} },
			{ Name = "NumbersToExpressions", Settings = { NumberRepresentationMutation = true } },
			{ Name = "AzureVM", Settings = { LuraphVersion = 15, DecoyDensity = 1.5 } },
		},
	},

	-- =====================================================================
    -- AzureGodUltra: CFF and opaque predicates in addition to AST pre-transforms
    -- and AzureVM template mode 15. This is not a measured security ranking.
	-- =====================================================================
	["AzureGodUltra"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "OpaquePredicates", Settings = { Threshold = 0.5, MaxPerBlock = 2 } },
			{ Name = "ControlFlowFlattening", Settings = { Threshold = 1.0, MinStatements = 3, ShuffleStates = true } },
			{ Name = "SplitStrings", Settings = {} },
			{ Name = "EncryptStrings", Settings = {} },
			{ Name = "NumbersToExpressions", Settings = { NumberRepresentationMutation = true } },
			{ Name = "AzureVM", Settings = { LuraphVersion = 15, DecoyDensity = 1.5 } },
		},
	},
}
