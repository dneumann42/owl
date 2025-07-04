local fmt = string.format

Compiler = {}
Compiler.__index = Compiler -- Set __index to allow method lookup

function Compiler:new()
  local obj = setmetatable({}, self)
  return obj
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
  local stmts = {
    "local result"
  }
  for i = 1, #node do
    local child, child_stmts = Compiler:Node_to_lua(node[i])
    for j = 1, #child_stmts do
      table.insert(stmts, child_stmts[j])
    end
    table.insert(stmts, "result = " .. child)
  end
  return "result", stmts
end

function Compiler:Call_to_lua(node)
  assert(node.tag == 'Call')
end

function Compiler:Dot_to_lua(node)
  assert(node.tag == 'Dot')
end

function Compiler:Do_to_lua(node)
  assert(node.tag == 'Do')
end

function Compiler:If_to_lua(node)
  assert(node.tag == 'If')
end

function Compiler:Define_to_lua(node)
  assert(node.tag == 'Define')
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
