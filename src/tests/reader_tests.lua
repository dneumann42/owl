local read = require("src.reader")
local tester = require("src.tester")
local repr = require("src.repr")

local reader_test = {}

local function dot(a, b) return { tag = "Dot", a, b } end
local function call(a, b) return { tag = "Call", a, b } end
local function num(n) return { tag = "Number", n } end
local function sym(s) return { tag = "Symbol", s } end
local function str(s) return { tag = "String", s } end

function reader_test.call()
  local n = read("a(1, 2)")[1]
  tester.assert_equal(call(sym("a"), { num(1), num(2) }), n)
end

function reader_test.hello_world()
  local n = read('print("Hello, World!")')[1]
  tester.assert_equal(call(sym("print"), { str("Hello, World!") }), n)
end

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

function reader_test.if_block()
  local n = read([[
    if 1
    | 2
    | 3
    end
  ]])[1]
  tester.assert_equal({ tag = "If", cond = num(1), ifTrue = num(2), ifFalse = num(3) }, n)
  local n1 = read([[
    if 1
    | 2
    end
  ]])[1]
  tester.assert_equal({ tag = "If", cond = num(1), ifTrue = num(2), ifFalse = nil }, n1)
end

function reader_test.define()
  local n = read("def hello 100")[1]
  tester.assert_equal({ tag = "Define", name = sym "hello", value = num(100) }, n)
end

function reader_test.lambda()
  local n = read("fn(a, b) a + b")[1]
  tester.assert_equal(
    { tag = "Lambda", params = { sym "a", sym "b", tag = "Parameters" }, body = { tag = "BinExpr", sym "a", sym "+", sym "b" } },
    n)

  local n2 = read([[
    fn(a, b) do
      a + b
    end
  ]])[1]
  tester.assert_equal(
    {
      tag = "Lambda",
      params = {
        tag = "Parameters",
        sym "a",
        sym "b"
      },
      body = {
        tag = "Do",
        {
          tag = "BinExpr",
          sym "a",
          sym "+",
          sym "b"
        }
      },
    },
    n2
  )
end

function reader_test.do_expr()
  local n = read([[
    do
      1 + 2
      3
    end
  ]])[1]
  tester.assert_equal(n, {
    tag = "Do",
    { tag = "BinExpr", num(1), sym '+', num(2) },
    num(3),
  })
end

function reader_test.strings()
  local r = read [[
    "Hello, World"
  ]]
  tester.assert_equal({ tag = "String", "Hello, World" }, r[1])
end

tester.run_tests(reader_test)
