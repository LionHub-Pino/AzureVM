-- Portable, bounded MBA identities for Lua 5.1 doubles; no bit library required.
local Step = require('prometheus.step')
local Ast = require('prometheus.ast')
local visitast = require('prometheus.visitast')
local MBA = Step:extend()
MBA.Name = 'Mixed Boolean Arithmetic'
MBA.Description = 'Hide exact 32-bit integer constants using Boolean bit predicates and arithmetic.'
MBA.SettingsDescriptor = {
    Threshold = {type='number', default=0.5, min=0, max=1},
    MaxTransforms = {type='number', default=64, min=0, max=256},
}
function MBA:init()
    if self.MaxTransforms~=math.floor(self.MaxTransforms) then error('MaxTransforms must be an integer',2) end
end
local N = Ast.NumberExpression
local function eligible(n)
    return type(n)=='number' and n~=0 and n==n and math.abs(n)<=4294967295 and n==math.floor(n)
end
function MBA:rewrite(n)
    if not eligible(n) then return N(n) end
    local magnitude = math.abs(n)
    local mask = math.random(1,255)
    local other, weight = magnitude, 1
    -- Compute the build-time XOR operand. Only the low byte is masked.
    for bit=0,7 do
        if math.floor(mask/weight)%2==1 then
            if math.floor(magnitude/weight)%2==1 then other=other-weight else other=other+weight end
        end
        weight=weight*2
    end
    local terms = N(0)
    for bit=0,7 do
        local w = 2^bit
        local function hasBit(value)
            return Ast.GreaterThanOrEqualsExpression(Ast.ModExpression(N(value),N(w*2)),N(w))
        end
        local both = Ast.AndExpression(hasBit(mask),hasBit(other))
        local term = Ast.OrExpression(Ast.AndExpression(both,N(w)),N(0))
        terms = Ast.AddExpression(terms,term)
    end
    -- x XOR y = x + y - 2*(x AND y). All intermediates are exact integers < 2^34.
    local expression = Ast.SubExpression(Ast.AddExpression(N(mask),N(other)),Ast.MulExpression(N(2),terms))
    if n<0 then expression=Ast.NegateExpression(expression) end
    expression.__mba = true
    return expression
end
function MBA:apply(ast)
    self.transformed = 0
    visitast(ast, function(node)
        if node.__mba then return node,true end
    end, function(node)
        if node.kind==Ast.AstKind.NumberExpression and eligible(node.value)
            and self.transformed<self.MaxTransforms and math.random()<=self.Threshold then
            self.transformed=self.transformed+1
            return self:rewrite(node.value)
        end
    end)
    return ast
end
return MBA
