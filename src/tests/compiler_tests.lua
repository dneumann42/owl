local Compiler = require("src.compiler")
local read = require("src.reader")
local tester = require("src.tester")

local compiler_test = {}

function compiler_test.to_lua()
  local comp = Compiler:new()
  tester.assert_equal(
    comp:to_lua(
      read([[
        1 + 2
      ]])
    ),
    "local a" ..
    "a = 1 + 2" ..
    "return a"
  )
end

tester.run_tests(compiler_test)
