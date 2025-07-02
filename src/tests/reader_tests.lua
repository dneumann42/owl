local read = require("src.reader")
local tester = require("src.tester")
local repr = require("src.repr")

local reader_test = {}

local function dot(a, b) return { tag = "Dot", a, b } end
local function call(a, b) return { tag = "Call", a, b } end
local function num(n) return { tag = "Number", n } end
local function sym(s) return { tag = "Symbol", s } end

function reader_test.dot_call()
  local n = read("a.b(1, 2)")[1]
  tester.assert_equal(call(dot(sym("a"), sym("b")), { num(1), num(2) }), n)
end

function reader_test.call_dot()
  local n = read("b(1, 2).a")[1]
  tester.assert_equal(dot(call(sym("b"), { num(1), num(2) }), sym("a")), n)
end

function reader_test.dot_chain()
  local n = read("a.b.c")[1]
  tester.assert_equal(dot(dot(sym "a", sym "b"), sym "c"), n)
end

function reader_test.call_chain()
  local n = read("a()()")[1]
  tester.assert_equal(call(call(sym "a", {}), {}), n)
end

function reader_test.do_block()
  local n = read("do 1 2 3 end")[1]
  tester.assert_equal({ tag = "Do", num(1), num(2), num(3) }, n)
end

tester.run_tests(reader_test)
