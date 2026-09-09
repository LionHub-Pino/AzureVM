-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- presets.lua
--
-- Predefined obfuscation presets for Prometheus + AzureVM
-- High-fidelity Luraph v14.7 Classic & v15.2 Ultra Cloaking

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
	-- Luraph: Standalone Luraph v14.7 Classic Virtual Machine (Default)
	-- Fingerprint: LPH_JIT_MAX, debug.getinfo(1)
	-- Pure polymorphic bytecode dispatch + rolling keystream
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
	-- Luraph14: Full Pipeline Luraph v14.7 Classic
	-- AST Pre-Mutation: SplitStrings + EncryptStrings + NumbersToExpressions
	-- Virtualization: AzureVM v14.7 Classic polymorphic VM
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
	-- Luraph15: Full Pipeline Luraph v15.2 Ultra
	-- AST Pre-Mutation: SplitStrings + EncryptStrings + NumbersToExpressions
	-- Virtualization: AzureVM v15.2 Ultra polymorphic VM
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
	-- AzureGod: Maximum Protection with Luraph v14.7 Cloaking
	-- Heavy AST Pre-Mutation + Dense Decoy Handlers + AzureVM v14.7
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
	-- AzureGod15: Maximum Protection with Luraph v15.2 Ultra Cloaking
	-- Heavy AST Pre-Mutation + Dense Decoy Handlers + AzureVM v15.2 Ultra
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
	-- AzureGodUltra: Ultimate Protection with CFF + Luraph v15.2 Ultra Cloaking
	-- Control Flow Flattening + SplitStrings + EncryptStrings + NumbersToExpressions + AzureVM v15.2 Ultra
	-- =====================================================================
	["AzureGodUltra"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "ControlFlowFlattening", Settings = { Threshold = 1.0, MinStatements = 3, ShuffleStates = true } },
			{ Name = "SplitStrings", Settings = {} },
			{ Name = "EncryptStrings", Settings = {} },
			{ Name = "NumbersToExpressions", Settings = { NumberRepresentationMutation = true } },
			{ Name = "AzureVM", Settings = { LuraphVersion = 15, DecoyDensity = 1.5 } },
		},
	},
}
