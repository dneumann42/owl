local read = require("src.reader")
local repr = require("src.repr")
local tester = require("src.tester")

local reader_test = {}

function reader_test.dot_call()
  local n = read("a.b(1, 2)")[1]
  tester.assert_equal({
    tag = "Call",
    { tag = "Dot",           { tag = "Symbol", "a" }, { tag = "Symbol", "b" }, },
    { { tag = "Number", 1 }, { tag = "Number", 2 } }
  }, n)
end

function reader_test.call_dot()
  local n = read("b(1, 2).a")[1]
  tester.assert_equal({
    tag = "Dot",
    { tag = "Call",   { tag = "Symbol", "b" }, { { tag = "Number", 1 }, { tag = "Number", 2 } } },
    { tag = "Symbol", "a" },
  }, n)
end

tester.run_tests(reader_test)
