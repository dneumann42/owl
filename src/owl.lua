local read = require("src.reader")
local Compiler = require("src.compiler")

local exp = [[
  1 + (3 / 2) * 6
]]

local comp = Compiler:new()
local lua = comp:to_lua(read(exp))

print(lua)
