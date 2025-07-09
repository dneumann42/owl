local read = require("src.reader")
local Compiler = require("src.compiler")

local fmt = string.format

local function eval(code)
  local Env = {
    echo = print,
    type = type,
  }

  local comp = Compiler:new()
  local node = read(code)
  local lua = comp:to_lua(node)

  return pcall(function()
    return load(lua, "owl-eval", "bt", Env)()
  end)
end

local function read_file(path)
  local file = io.open(path)
  if not file then
    error("File does not exist '" .. path .. "'")
  end
  local content = file:read("a")
  file:close()
  return content
end

local function repl()
  local code = read_file("scripts/repl.owl")
  local ok, value = eval(code)
  print(ok, value)
end

if #arg == 0 then
  repl()
  return
end

local i = 1
while i <= #arg do
  if arg[i] == "-e" then
    local ok, value = eval(arg[i + 1])
    print(ok, value)
    i = i + 1
  else
    local ok, value = eval(read_file(arg[i]))
    print(ok, value)
    i = i + 1
  end
  i = i + 1
end
