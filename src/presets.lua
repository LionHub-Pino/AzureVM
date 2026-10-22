-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- presets.lua
--
-- Predefined obfuscation presets for Prometheus + AzureVM
-- AzureVM presets. Historical Luraph-named keys are compatibility labels.

local presets = {
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
			{ Name = "MixedBooleanArithmetic", Settings = { Threshold = 0.7, MaxTransforms = 32 } },
			{ Name = "OpaquePredicates", Settings = { Threshold = 0.5, MaxPerBlock = 2 } },
			{ Name = "DeepControlFlowFlattening", Settings = { Threshold = 1.0, MinStatements = 3, ShuffleStates = true, OpaqueDispatch = true, MaxStates = 128 } },
			{ Name = "SplitStrings", Settings = {} },
			{ Name = "EncryptStrings", Settings = {} },
			{ Name = "NumbersToExpressions", Settings = { NumberRepresentationMutation = true } },
			{ Name = "AzureVM", Settings = { LuraphVersion = 15, DecoyDensity = 1.5, RuntimeChecks = true, InitializationRetries = 2 } },
			{ Name = "SafeRetryWrapper", Settings = { RetryCount = 3 } },
		},
	},
}
-- Standard and diversified aliases
presets["Clean"] = presets["Minify"]
presets["Lite"] = presets["Minify"]
presets["Basic"] = presets["Weak"]
presets["Life"] = presets["Weak"]
presets["Standard"] = presets["Medium"]
presets["Balanced"] = presets["Medium"]
presets["Solid"] = presets["Strong"]
presets["Shield"] = presets["Strong"]
presets["Classic"] = presets["Luraph"]
presets["Stealth"] = presets["Luraph14"]
presets["Hardcore"] = presets["AzureGod15"]
presets["Armor"] = presets["AzureGod15"]
presets["Immortal"] = presets["AzureGodUltra"]
presets["HardcoreUltra"] = presets["AzureGodUltra"]

-- MONO 22 Album 3 Chapters Aliases:
-- Chương I: Khởi Đầu / Khởi Điệu (Khoidieu -> AzureGod)
-- Chương II: Biến Đổi / Biến Điệu (Biendieu -> AzureGod15)
-- Chương III: Kết Thúc / Đủ Điệu (Dudieu -> AzureGodUltra)
presets["Khoidieu"] = presets["AzureGod"]
presets["khoidieu"] = presets["AzureGod"]
presets["Biendieu"] = presets["AzureGod15"]
presets["biendieu"] = presets["AzureGod15"]
presets["Dudieu"] = presets["AzureGodUltra"]
presets["dudieu"] = presets["AzureGodUltra"]

return presets
