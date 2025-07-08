local Compiler = require("src.compiler")
local read = require("src.reader")
local tester = require("src.tester")

local compiler_test = {}

function compiler_test.grouping()
  local comp = Compiler:new()
  tester.assert_equal(
    comp:to_lua(
      read([[
        1 + 2 / 3 * 4
      ]])
    ),
    "local v1\n" ..
    "v1 = (1 + (2 / (3 * 4)))\n" ..
    "return v1"
  )
  comp = Compiler:new()
  tester.assert_equal(
    comp:to_lua(
      read([[
        (1 + 2) / 3 * 4
      ]])
    ),
    "local v1\n" ..
    "v1 = ((1 + 2) / (3 * 4))\n" ..
    "return v1"
  )
end

function compiler_test.if_expr()
  local comp = Compiler:new()
  tester.assert_equal(
    comp:to_lua(
      read([[
        if 1
        | 2
        | 3
        end
      ]])
    ),
    [[local v1
local v2
if 1 then
v2 = 2
else
v2 = 3
end
v1 = v2
return v1]]
  )
end

function compiler_test.do_expr()
  local comp = Compiler:new()
  tester.assert_equal(
    comp:to_lua(
      read([[
        do
          1 + 2
          3
        end
      ]])
    ),
    [[local v1
local v2
do
v2 = (1 + 2)
v2 = 3
end
v1 = v2
return v1]]
  )
end

function compiler_test.define()
  local comp = Compiler:new()
  tester.assert_equal(
    comp:to_lua(
      read([[
        def x 1 + 3
      ]])
    ),
    "local v1\n" ..
    "local x = (1 + 3)\n" ..
    "v1 = x\n" ..
    "return v1"
  )
end

tester.run_tests(compiler_test)
