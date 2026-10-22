-- Bounded bottom-up CFF. Branch bodies retain their own lexical scopes.
local Base=require('prometheus.steps.ControlFlowFlattening')
local Ast=require('prometheus.ast')
local Scope=require('prometheus.scope')
local visitast=require('prometheus.visitast')
local util=require('prometheus.util')
local K=Ast.AstKind
local Deep=Base:extend()
Deep.Name='Deep Control Flow Flattening'
Deep.Description='Lower nested eligible blocks and conditional edges into bounded opaque dispatchers.'
Deep.SettingsDescriptor={}
for k,v in pairs(Base.SettingsDescriptor) do Deep.SettingsDescriptor[k]=v end
Deep.SettingsDescriptor.MaxStates={type='number',default=128,min=4,max=512}
Deep.SettingsDescriptor.OpaqueDispatch={type='boolean',default=true}
function Deep:init()
    Base.init(self)
    if self.MaxStates~=math.floor(self.MaxStates) then error('MaxStates must be an integer',2) end
    self.blocksFlattened,self.branchesLowered=0,0
end
function Deep:flattenBlock(block)
    if #block.statements>self.MaxStates then return false end
    local ids,seen,statements={},{},{}
    local function hoist(id)
        if not seen[id] then ids[#ids+1]=id seen[id]=true end
    end
    for _,stmt in ipairs(block.statements) do
        if stmt.kind==K.LocalVariableDeclaration then
            local lhs={}
            for _,id in ipairs(stmt.ids) do hoist(id) lhs[#lhs+1]=Ast.AssignmentVariable(stmt.scope,id) end
            if #stmt.expressions>0 then statements[#statements+1]=Ast.AssignmentStatement(lhs,stmt.expressions) end
        elseif stmt.kind==K.LocalFunctionDeclaration then
            hoist(stmt.id)
            statements[#statements+1]=Ast.AssignmentStatement({Ast.AssignmentVariable(stmt.scope,stmt.id)},
                {Ast.FunctionLiteralExpression(stmt.args,stmt.body)})
        elseif stmt.kind~=K.NopStatement then statements[#statements+1]=stmt end
    end
    if #statements<self.MinStatements then return false end
    local nodes,lowered={},0
    local function add(stmt,nextId,condition,yes,no)
        nodes[#nodes+1]={stmt=stmt,nextId=nextId,condition=condition,yes=yes,no=no}
        return #nodes
    end
    local entry
    for i=#statements,1,-1 do
        local stmt=statements[i]
        if stmt.kind==K.IfStatement then
            local nextId=entry
            local fallback=nextId
            if stmt.elsebody then fallback=add(Ast.DoStatement(stmt.elsebody),nextId) end
            for j=#stmt.elseifs,1,-1 do
                local branch=stmt.elseifs[j]
                local yes=add(Ast.DoStatement(branch.body),nextId)
                fallback=add(nil,nil,branch.condition,yes,fallback)
            end
            local yes=add(Ast.DoStatement(stmt.body),nextId)
            entry=add(nil,nil,stmt.condition,yes,fallback)
            lowered=lowered+1+#stmt.elseifs
        else entry=add(stmt,entry) end
    end
    if #nodes>self.MaxStates then return false end
    local states,used={},{}
    for i=1,#nodes do
        local n
        repeat n=math.random(1000,99999) until not used[n]
        used[n]=true states[i]=n
    end
    local state=block.scope:addVariable()
    local function variable() return Ast.VariableExpression(block.scope,state) end
    local function transition(target)
        return Ast.AssignmentStatement({Ast.AssignmentVariable(block.scope,state)},
            {target and Ast.NumberExpression(states[target]) or Ast.NilExpression()})
    end
    local whileScope=Scope:new(block.scope)
    local branches={}
    for i,node in ipairs(nodes) do
        local branchScope=Scope:new(whileScope)
        local stmts={}
        if node.condition then
            local yesScope,noScope=Scope:new(branchScope),Scope:new(branchScope)
            stmts[1]=Ast.IfStatement(node.condition,Ast.Block({transition(node.yes)},yesScope),{},
                Ast.Block({transition(node.no)},noScope))
        else
            stmts[1]=node.stmt
            if node.stmt.kind==K.DoStatement then node.stmt.body.scope:setParent(branchScope) end
            if node.stmt.kind~=K.ReturnStatement then stmts[#stmts+1]=transition(node.nextId) end
        end
        local condition=Ast.EqualsExpression(variable(),Ast.NumberExpression(states[i]))
        if self.OpaqueDispatch then
            -- State IDs <=99999: the product is exact and always even in binary64.
            local even=Ast.EqualsExpression(Ast.ModExpression(
                Ast.MulExpression(variable(),Ast.AddExpression(variable(),Ast.NumberExpression(1))),
                Ast.NumberExpression(2)),Ast.NumberExpression(0))
            condition=Ast.AndExpression(condition,even)
        end
        local body=Ast.Block(stmts,branchScope) body.__isCff=true
        branches[#branches+1]={condition=condition,body=body}
    end
    if self.ShuffleStates then branches=util.shuffle(branches) end
    local first=table.remove(branches,1)
    local elseScope=Scope:new(whileScope)
    local otherwise=Ast.Block({transition(nil)},elseScope) otherwise.__isCff=true
    local dispatch=Ast.IfStatement(first.condition,first.body,branches,otherwise)
    local body=Ast.Block({dispatch},whileScope) body.__isCff=true
    local result={}
    if #ids>0 then result[#result+1]=Ast.LocalVariableDeclaration(block.scope,ids,{}) end
    result[#result+1]=Ast.LocalVariableDeclaration(block.scope,{state},{Ast.NumberExpression(states[entry])})
    result[#result+1]=Ast.WhileStatement(body,variable(),block.scope)
    block.statements=result block.__cffApplied=true
    self.blocksFlattened=self.blocksFlattened+1
    self.branchesLowered=self.branchesLowered+lowered
    return true
end
function Deep:apply(ast)
    self.blocksFlattened,self.branchesLowered=0,0
    visitast(ast,nil,function(node)
        if node.kind==K.Block and not node.__isCff and not node.__cffApplied
            and #node.statements>=self.MinStatements and not Base.hasUnenclosedBreak(node)
            and (self.Threshold>=1 or math.random()<=self.Threshold) then
            self:flattenBlock(node)
        end
    end)
    -- Hoisting must not merge repeated local names or capture earlier global reads.
    -- Globally unique alpha-renaming preserves the AST's resolved binding identities.
    local used={}
    local function reserve(scope)
        for _,name in pairs(scope.variables) do used[name]=true end
        for _,child in ipairs(scope.children) do reserve(child) end
    end
    reserve(ast.globalScope)
    local counter=0
    ast.globalScope:renameVariables({Keywords={},generateName=function()
        local name
        repeat counter=counter+1 name="__azcff_local_"..counter until not used[name]
        used[name]=true
        return name
    end})
    return ast
end
return Deep
