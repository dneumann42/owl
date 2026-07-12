import std/[tables, unittest]

import crow/evaluator
import crow/parser
import crow/values

proc run(source: string): Value =
  var evaluator = Evaluator.init()
  evaluator.exec(parse(source))

suite "evaluator":
  test "scripts yield the last expression":
    let value = run("""
1
2
""")
    check value.kind == Number
    check value.number == 2

  test "bindings are syntax data":
    let value = run("""
a = 41
""")
    check value.kind == Syntax
    check value.syntax.kind == Binding
    check value.syntax.bindingSymbol == "a"

  test "define binds symbols in the current environment":
    let value = run("""
define:
  a = 41
+ a 1
""")
    check value.kind == Number
    check value.number == 42

  test "fun defines closures that evaluate arguments":
    let value = run("""
fun inc n:
  + n 1
inc 4
""")
    check value.kind == Number
    check value.number == 5

  test "command defines closures that receive raw syntax":
    let value = run("""
command twice x:
  + (eval x) (eval x)
define:
  a = 5
twice a
""")
    check value.kind == Number
    check value.number == 10

  test "block-command receives call body as syntax":
    let value = run("""
block-command run:
  eval block
run:
  define:
    x = 3
  + x 4
""")
    check value.kind == Number
    check value.number == 7

  test "prelude defines list literals in crow":
    let value = run("""
[]:
  1
  + 1 1
  3
""")
    check value.kind == List
    check value.items.len == 3
    check value.items[0].number == 1
    check value.items[1].number == 2
    check value.items[2].number == 3

  test "prelude defines dictionary literals in crow":
    let value = run("""
{}:
  name = "crow"
  answer = (+ 40 2)
""")
    check value.kind == Dictionary
    check value.entries["name"].text == "crow"
    check value.entries["answer"].number == 42

  test "prelude defines if in crow":
    let value = run("""
if (= 1 2):
  then:
    "bad"
  else:
    "good"
""")
    check value.kind == Text
    check value.text == "good"

  test "prelude defines cond in crow":
    let value = run("""
define:
  inp = "world"
cond:
  when (= inp "hello"):
    "hello"
  when (= inp "world"):
    "world"
  when T:
    "unknown"
""")
    check value.kind == Text
    check value.text == "world"

  test "prelude defines for in crow":
    let value = run("""
for n ([]:
  1
  2
  3
):
  + n 10
""")
    check value.kind == Number
    check value.number == 13
