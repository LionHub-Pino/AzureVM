-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- OpaquePredicates.lua
--
-- Inserts mathematically invariant opaque branches and dead traps into basic blocks.
-- Generates dead code traps to defeat decompilers and symbolic execution.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitast = require("prometheus.visitast")
local AstKind = Ast.AstKind

local OpaquePredicates = Step:extend()
OpaquePredicates.Description = "Inserts mathematical opaque predicates and dead traps into basic blocks"
OpaquePredicates.Name = "Opaque Predicates"

OpaquePredicates.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "Probability of wrapping an eligible statement in an opaque predicate",
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	},
	MaxPerBlock = {
		name = "MaxPerBlock",
		description = "Maximum opaque predicates per block",
		type = "number",
		default = 2,
		min = 1,
		max = 10,
	},
}

function OpaquePredicates:init(_)
	if self.Threshold == nil then self.Threshold = 0.5 end
	if self.MaxPerBlock == nil then self.MaxPerBlock = 2 end
end

local function make_opaque_condition(scope)
	local mode = math.random(1, 3)
	if mode == 1 then
		-- (r * (r + 1)) % 2 == 0
		local r = math.random(11, 999)
		return Ast.EqualsExpression(
			Ast.ModExpression(
				Ast.MulExpression(
					Ast.NumberExpression(r),
					Ast.NumberExpression(r + 1)
				),
				Ast.NumberExpression(2)
			),
			Ast.NumberExpression(0)
		)
	elseif mode == 2 then
		-- (r + 1337) > r
		local r = math.random(10, 500)
		return Ast.GreaterThanExpression(
			Ast.AddExpression(
				Ast.NumberExpression(r),
				Ast.NumberExpression(1337)
			),
			Ast.NumberExpression(r)
		)
	else
		-- ("lu" .. "ra") == "lura"
		return Ast.EqualsExpression(
			Ast.StrCatExpression(
				Ast.StringExpression("lu"),
				Ast.StringExpression("ra")
			),
			Ast.StringExpression("lura")
		)
	end
end

local function is_eligible(kind)
	return kind == AstKind.AssignmentStatement
		or kind == AstKind.FunctionCallStatement
		or kind == AstKind.PassSelfFunctionCallStatement
		or kind == AstKind.CompoundAddStatement
		or kind == AstKind.CompoundSubStatement
		or kind == AstKind.CompoundMulStatement
		or kind == AstKind.CompoundDivStatement
		or kind == AstKind.CompoundModStatement
		or kind == AstKind.CompoundPowStatement
		or kind == AstKind.CompoundConcatStatement
end

function OpaquePredicates:apply(ast)
	visitast(ast, function(node, _)
		if node.kind ~= AstKind.Block then return end
		local block = node
		if block.__isOpaque or block.__isCff then return end

		local newStmts = {}
		local count = 0
		local max = self.MaxPerBlock or 2

		for _, stmt in ipairs(block.statements) do
			if count < max and is_eligible(stmt.kind) and (self.Threshold >= 1 or math.random() <= self.Threshold) then
				count = count + 1

				local cond = make_opaque_condition(block.scope)
				local trueScope = Scope:new(block.scope)
				local trueBlock = Ast.Block({ stmt }, trueScope)
				trueBlock.__isOpaque = true

				local deadScope = Scope:new(block.scope)
				local deadVarId = deadScope:addVariable()
				local deadStmt = Ast.LocalVariableDeclaration(
					deadScope,
					{ deadVarId },
					{ Ast.NumberExpression(math.random(1000, 99999)) }
				)
				local deadBlock = Ast.Block({ deadStmt }, deadScope)
				deadBlock.__isOpaque = true

				local ifStmt = Ast.IfStatement(cond, trueBlock, {}, deadBlock)
				ifStmt.__isOpaque = true
				newStmts[#newStmts + 1] = ifStmt
			else
				newStmts[#newStmts + 1] = stmt
			end
		end

		block.statements = newStmts
		block.__isOpaque = true
	end)
end

return OpaquePredicates
