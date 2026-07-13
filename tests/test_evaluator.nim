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

  test "define shadows captured symbols and set mutates them":
    let value = run("""
fun probe:
  define:
    current = 1
  fun shadow:
    define:
      current = 10
    current
  fun mutate:
    set current 20
    current
  define:
    shadowed = (shadow)
    afterShadow = current
    mutated = (mutate)
  + shadowed afterShadow mutated current
probe
""")
    check value.kind == Number
    check value.number == 51

  test "compound assignment commands mutate existing symbols":
    let value = run("""
define:
  n = 6
+= n 4
*= n 3
-= n 9
/= n 3
n
""")
    check value.kind == Number
    check value.number == 7

  test "fun defines closures that evaluate arguments":
    let value = run("""
fun inc n:
  + n 1
inc 4
""")
    check value.kind == Number
    check value.number == 5

  test "fn creates anonymous closures":
    let value = run("""
define:
  base = 10
  lam = fn a b c:
    + base a (* b c)
lam 1 2 3
""")
    check value.kind == Number
    check value.number == 17

  test "lambda aliases fn":
    let value = run("""
define:
  lam = lambda a b:
    - a b
lam 9 4
""")
    check value.kind == Number
    check value.number == 5

  test "standard streams are globals":
    let input = run("stdin\n")
    check input.kind == Stream
    check input.stream == InputStream

    let output = run("stdout\n")
    check output.kind == Stream
    check output.stream == OutputStream

  test "write commands take output streams":
    let value = run("write stdout \"\"\n")
    check value.kind == Text
    check value.text == ""

  test "read commands require explicit streams":
    expect EvaluatorError:
      discard run("readline\n")
    expect EvaluatorError:
      discard run("read-line stdout\n")

  test "not negates truthiness":
    let value = run("""
not (= 1 2)
""")
    check value.kind == Boolean
    check value.boolean == true

  test "error raises evaluator errors":
    expect EvaluatorError:
      discard run("error \"boom\"\n")

  test "parse returns syntax evaluated in the caller environment":
    let value = run("""
define:
  x = 40
eval (parse "+ x 2")
""")
    check value.kind == Number
    check value.number == 42

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

  test "prelude cond evaluates clause syntax in the caller environment":
    let value = run("""
fun check line:
  cond:
    when (= line "history"):
      "ok"
    when T:
      "bad"
check "history"
""")
    check value.kind == Text
    check value.text == "ok"

  test "prelude cond rejects invalid clauses":
    expect EvaluatorError:
      discard run("""
cond:
  nope T:
    "bad"
""")

  test "native while loops in the current environment":
    let value = run("""
define:
  n = 0
while (< n 3):
  define:
    n = (+ n 1)
n
""")
    check value.kind == Number
    check value.number == 3

  test "value-of returns a command without calling it":
    let value = run("""
fun answer:
  42
value-of answer
""")
    check value.kind == Command

  test "prelude defines range iterators in crow":
    let value = run("""
define:
  next = (range 1 4)
+ (next) (next) (next)
""")
    check value.kind == Number
    check value.number == 6

  test "prelude defines countdown iterators in crow":
    let value = run("""
define:
  next = (countdown 3 0)
+ (next) (next) (next)
""")
    check value.kind == Number
    check value.number == 6

  test "prelude defines list and once iterators in crow":
    let value = run("""
define:
  items = (iter ([]:
    10
    20
  ))
  single = (once 3)
+ (items) (items) (single)
""")
    check value.kind == Number
    check value.number == 33

  test "prelude defines for over iterators in crow":
    let value = run("""
for n (range 1 4):
  + n 10
""")
    check value.kind == Number
    check value.number == 13
