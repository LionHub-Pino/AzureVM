-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- ControlFlowFlattening.lua
--
-- This Step provides a Control Flow Flattening (CFF) obfuscation step.
-- Transforms sequential basic blocks and function bodies into state machine dispatch loops
-- using: while state do if state == X then ... end end
-- Handles local variable hoisting and preserves Roblox Executor performance.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local logger = require("logger")
local AstKind = Ast.AstKind

local ControlFlowFlattening = Step:extend()
ControlFlowFlattening.Name = "Control Flow Flattening"
ControlFlowFlattening.Description = "Transforms sequential basic blocks into state machine dispatch loops."

ControlFlowFlattening.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The probability (0-1) of applying CFF to an eligible block",
		type = "number",
		default = 1,
		min = 0,
		max = 1,
	},
	MinStatements = {
		name = "MinStatements",
		description = "Minimum number of sequential statements required to flatten a block",
		type = "number",
		default = 3,
		min = 2,
	},
	ShuffleStates = {
		name = "ShuffleStates",
		description = "Whether to randomize the order of state dispatcher branches",
		type = "boolean",
		default = true,
	},
}

function ControlFlowFlattening:init()
	if self.Threshold == nil then self.Threshold = 1 end
	if self.MinStatements == nil then self.MinStatements = 3 end
	if self.ShuffleStates == nil then self.ShuffleStates = true end
end

-- Checks if a node contains a break or continue statement not enclosed by an inner loop.
local function hasUnenclosedBreak(node)
	if not node then return false end

	local kind = node.kind

	if kind == AstKind.BreakStatement or kind == AstKind.ContinueStatement then
		return true
	end

	-- Loops capture break/continue statements within their bodies
	if kind == AstKind.WhileStatement or
	   kind == AstKind.RepeatStatement or
	   kind == AstKind.ForStatement or
	   kind == AstKind.ForInStatement then
		return false
	end

	-- Function boundaries cannot be crossed by break/continue in Lua
	if kind == AstKind.FunctionDeclaration or
	   kind == AstKind.LocalFunctionDeclaration or
	   kind == AstKind.FunctionLiteralExpression then
		return false
	end

	if kind == AstKind.Block then
		for _, stmt in ipairs(node.statements) do
			if hasUnenclosedBreak(stmt) then
				return true
			end
		end
		return false
	end

	if kind == AstKind.IfStatement then
		if hasUnenclosedBreak(node.body) then return true end
		for _, eif in ipairs(node.elseifs or {}) do
			if hasUnenclosedBreak(eif.body) then return true end
		end
		if node.elsebody and hasUnenclosedBreak(node.elsebody) then
			return true
		end
		return false
	end

	if kind == AstKind.DoStatement then
		return hasUnenclosedBreak(node.body)
	end

	return false
end

function ControlFlowFlattening:flattenBlock(block)
	local hoistedVarIds = {}
	local hoistedVarSet = {}
	local executableStatements = {}

	for _, stmt in ipairs(block.statements) do
		if stmt.kind == AstKind.LocalVariableDeclaration then
			for _, varId in ipairs(stmt.ids) do
				if not hoistedVarSet[varId] then
					hoistedVarSet[varId] = true
					table.insert(hoistedVarIds, varId)
				end
			end
			if #stmt.expressions > 0 then
				local lhs = {}
				for _, varId in ipairs(stmt.ids) do
					table.insert(lhs, Ast.AssignmentVariable(stmt.scope, varId))
				end
				table.insert(executableStatements, Ast.AssignmentStatement(lhs, stmt.expressions))
			end
		elseif stmt.kind == AstKind.LocalFunctionDeclaration then
			local varId = stmt.id
			if not hoistedVarSet[varId] then
				hoistedVarSet[varId] = true
				table.insert(hoistedVarIds, varId)
			end
			local lhs = { Ast.AssignmentVariable(stmt.scope, stmt.id) }
			local rhs = { Ast.FunctionLiteralExpression(stmt.args, stmt.body) }
			table.insert(executableStatements, Ast.AssignmentStatement(lhs, rhs))
		elseif stmt.kind == AstKind.NopStatement then
			-- Skip NopStatement
		else
			table.insert(executableStatements, stmt)
		end
	end

	local numStatements = #executableStatements
	if numStatements < self.MinStatements then
		return false
	end

	-- Generate unique positive integer state IDs
	local stateIds = {}
	local usedStateIds = {}
	for i = 1, numStatements do
		local id
		repeat
			id = math.random(1000, 99999)
		until not usedStateIds[id]
		usedStateIds[id] = true
		table.insert(stateIds, id)
	end

	-- Create state variable in block scope
	local stateVarId = block.scope:addVariable()

	-- Build branch for each state
	local branches = {}
	for i = 1, numStatements do
		local stmt = executableStatements[i]
		local currId = stateIds[i]
		local isLast = (i == numStatements)
		local isReturn = (stmt.kind == AstKind.ReturnStatement)

		local branchStmts = { stmt }
		if not isReturn then
			local nextExpr
			if isLast then
				nextExpr = Ast.NilExpression()
			else
				nextExpr = Ast.NumberExpression(stateIds[i + 1])
			end
			local stateTransition = Ast.AssignmentStatement(
				{ Ast.AssignmentVariable(block.scope, stateVarId) },
				{ nextExpr }
			)
			table.insert(branchStmts, stateTransition)
		end

		table.insert(branches, {
			stateId = currId,
			statements = branchStmts,
		})
	end

	-- Shuffle states to flatten control flow
	if self.ShuffleStates then
		branches = util.shuffle(branches)
	end

	-- Construct state machine while loop
	local whileScope = Scope:new(block.scope)

	local branch1 = branches[1]
	local ifScope1 = Scope:new(whileScope)
	local cond1 = Ast.EqualsExpression(
		Ast.VariableExpression(block.scope, stateVarId),
		Ast.NumberExpression(branch1.stateId)
	)
	local body1 = Ast.Block(branch1.statements, ifScope1)
	body1.__isCff = true

	local elseifs = {}
	for i = 2, #branches do
		local b = branches[i]
		local ifScopeK = Scope:new(whileScope)
		local condK = Ast.EqualsExpression(
			Ast.VariableExpression(block.scope, stateVarId),
			Ast.NumberExpression(b.stateId)
		)
		local bodyK = Ast.Block(b.statements, ifScopeK)
		bodyK.__isCff = true
		table.insert(elseifs, {
			condition = condK,
			body = bodyK,
		})
	end

	-- Fallback safety else branch to prevent executor hang if state is tampered/invalid
	local elseScope = Scope:new(whileScope)
	local elseBlock = Ast.Block({
		Ast.AssignmentStatement(
			{ Ast.AssignmentVariable(block.scope, stateVarId) },
			{ Ast.NilExpression() }
		)
	}, elseScope)
	elseBlock.__isCff = true

	local ifStmt = Ast.IfStatement(cond1, body1, elseifs, elseBlock)

	local whileBody = Ast.Block({ ifStmt }, whileScope)
	whileBody.__isCff = true

	local whileStmt = Ast.WhileStatement(
		whileBody,
		Ast.VariableExpression(block.scope, stateVarId),
		block.scope
	)
	whileStmt.__isCff = true

	local newBlockStatements = {}
	if #hoistedVarIds > 0 then
		table.insert(newBlockStatements, Ast.LocalVariableDeclaration(block.scope, hoistedVarIds, {}))
	end
	table.insert(newBlockStatements, Ast.LocalVariableDeclaration(
		block.scope,
		{ stateVarId },
		{ Ast.NumberExpression(stateIds[1]) }
	))
	table.insert(newBlockStatements, whileStmt)

	block.statements = newBlockStatements
	block.__cffApplied = true
	return true
end

function ControlFlowFlattening:apply(ast, pipeline)
	visitast(ast, function(node, data)
		if node.kind ~= AstKind.Block then
			return
		end

		local block = node
		if block.__isCff or block.__cffApplied then
			return
		end

		if #block.statements < self.MinStatements then
			return
		end

		if hasUnenclosedBreak(block) then
			return
		end

		if self.Threshold < 1 and math.random() > self.Threshold then
			return
		end

		self:flattenBlock(block)
	end)

	return ast
end

return ControlFlowFlattening
