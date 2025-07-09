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
  local stmts = {}

  local call, call_stmts = Compiler:Node_to_lua(node[1])
  for i = 1, #call_stmts do
    insert(stmts, call_stmts[i])
  end

  local args = node[2]
  local params = {}
  for i = 1, #args do
    local a, ae = Compiler:Node_to_lua(args[i])
    for j = 1, #ae do
      insert(stmts, ae[j])
    end
    insert(params, a)
  end

  return fmt("%s(%s)", call, table.concat(params, ", ")), stmts
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

function Compiler:String_to_lua(node)
  return fmt("[[%s]]", node[1]), {}
end

function Compiler:While_to_lua(node)
  assert(node.tag == "While")
  local stmts = {}
  local cond, cond_stmts = Compiler:Node_to_lua(node.cond)
  for i = 1, #cond_stmts do
    insert(stmts, cond_stmts[i])
  end
  local body, body_stmts = Compiler:Node_to_lua(node.body)

  local var = Compiler:next_var()
  insert(stmts, "while " .. cond .. " do")
  for i = 1, #body_stmts do
    insert(stmts, body_stmts[i])
  end
  insert(stmts, var .. " = " .. body)
  insert(stmts, "end")
  return var, stmts
end

function Compiler:Node_to_lua(node)
  local fname = node.tag .. "_to_lua"
  assert(Compiler[fname] ~= nil, "Invalid node tag: " .. node.tag)
  return Compiler[fname](Compiler, node)
end

function Compiler:to_lua(node)
  local expr, stmts = Compiler:Node_to_lua(node)
  table.insert(stmts, "return " .. expr)
  local lua = table.concat(stmts, "\n")
  print(lua)
  return lua
end

return Compiler
