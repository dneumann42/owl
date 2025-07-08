local fmt        = string.format
local repr       = require("src.repr")
local insert     = table.insert

Compiler         = { var_index = 0 }
Compiler.__index = Compiler -- Set __index to allow method lookup

function Compiler:next_var()
  self.var_index = self.var_index + 1
  return fmt("v%d", self.var_index)
end

function Compiler:new()
  self.var_index = 0
  return setmetatable({}, self)
end

function Compiler:Symbol_to_lua(node)
  assert(node.tag == 'Symbol')
  return node[1], {}
end

function Compiler:Number_to_lua(node)
  assert(node.tag == 'Number')
  return node[1], {}
end

function Compiler:BinExpr_to_lua(node)
  assert(node.tag == 'BinExpr')
  local a, a_stmts = Compiler:Node_to_lua(node[1])
  local b, b_stmts = Compiler:Node_to_lua(node[3])
  local stmts = {}
  for i = 1, #a_stmts do table.insert(stmts, a_stmts[i]) end
  for i = 1, #b_stmts do table.insert(stmts, b_stmts[i]) end
  return fmt("(%s %s %s)", a, node[2][1], b), stmts
end

function Compiler:Script_to_lua(node)
  assert(node.tag == 'Script')
  local var = self:next_var()
  local stmts = { "local " .. var }
  for i = 1, #node do
    local child, child_stmts = Compiler:Node_to_lua(node[i])
    for j = 1, #child_stmts do
      table.insert(stmts, child_stmts[j])
    end
    table.insert(stmts, var .. " = " .. child)
  end
  return var, stmts
end

function Compiler:Call_to_lua(node)
  assert(node.tag == 'Call')
end

function Compiler:Dot_to_lua(node)
  assert(node.tag == 'Dot')
end

function Compiler:Do_to_lua(node)
  assert(node.tag == 'Do')
  local result = Compiler:next_var()
  local stmts = { "local " .. result, "do" }
  for i = 1, #node do
    local expr, expr_stmts = Compiler:Node_to_lua(node[i])
    for j = 1, #expr_stmts do
      insert(stmts, expr_stmts[j])
    end
    insert(stmts, result .. " = " .. expr)
  end
  insert(stmts, "end")
  return result, stmts
end

function Compiler:If_to_lua(node)
  assert(node.tag == 'If')

  local var = self:next_var()
  local stmts = {}
  local cond, cond_exprs = Compiler:Node_to_lua(node.cond)
  for i = 1, #cond_exprs do
    table.insert(stmts, cond_exprs[i])
  end

  local ifTrue, ifTrue_exprs = Compiler:Node_to_lua(node.ifTrue)

  insert(stmts, "local " .. var)
  insert(stmts, fmt("if %s then", cond))
  if #ifTrue_exprs > 0 then
    insert(stmts, table.concat(ifTrue_exprs, "\n"))
  end
  insert(stmts, var .. " = " .. ifTrue)

  if node.ifFalse then
    local ifFalse, ifFalse_exprs = Compiler:Node_to_lua(node.ifFalse)
    insert(stmts, "else")
    if #ifFalse_exprs > 0 then
      insert(stmts, table.concat(ifFalse_exprs, "\n"))
    end
    insert(stmts, var .. " = " .. ifFalse)
    insert(stmts, "end")
  else
    insert(stmts, "end")
  end
  return var, stmts
end

function Compiler:Define_to_lua(node)
  assert(node.tag == 'Define')

  local stmts = {}
  local name, name_stmts = Compiler:Node_to_lua(node.name)
  for i = 1, #name_stmts do
    table.insert(stmts, name_stmts[i])
  end

  local expr, expr_stmts = Compiler:Node_to_lua(node.value)
  for i = 1, #expr_stmts do
    table.insert(stmts, expr_stmts[i])
  end
  table.insert(stmts, fmt("local %s = %s", name, expr))

  return name, stmts
end

function Compiler:Lambda_to_lua(node)
  assert(node.tag == 'Lambda')
end

function Compiler:Node_to_lua(node)
  return Compiler[node.tag .. "_to_lua"](Compiler, node)
end

function Compiler:to_lua(node)
  local expr, stmts = Compiler:Node_to_lua(node)
  table.insert(stmts, "return " .. expr)
  return table.concat(stmts, "\n")
end

return Compiler
