import std/[strutils, unittest]

import crow
import crow/evaluator
import crow/parser
import crow/values

proc run(source: string): Value =
  var evaluator = Evaluator.init()
  evaluator.exec(parse(source))

proc checkNumber(source: string, expected: float64) =
  let value = run(source)
  check value.kind == Number
  check value.number == expected

proc checkText(source: string, expected: string) =
  let value = run(source)
  check value.kind == Text
  check value.text == expected

proc checkList(source: string, expected: int) =
  let value = run(source)
  check value.kind == List
  check value.items.len == expected

proc checkDict(source: string) =
  let value = run(source)
  check value.kind == Dictionary

proc checkTrue(source: string) =
  check run(source).isTruthy

suite "prelude":
  test "if returns the matching direct branch":
    checkText("""if (= 1 1):
  "good"
else:
  "bad"
""", "good")
    checkText("""if (= 1 2):
  "good"
else:
  "bad"
""", "bad")

  test "if works without else":
    checkText("""if (= 1 1):
  "good"
""", "good")
    checkTrue("""when (not (if false:
  true
)):
  true
""")

  test "if returns a value in an expression":
    checkText("""define:
  result = (do:
    if true:
      "y"
    else:
      "z"
  )
result
""", "y")
    checkText("""define:
  result = (do:
    if false:
      "a"
    else:
      "b"
  )
result
""", "b")

  test "statement if and else share a condition":
    checkText("""define:
  xs = []
if (empty? xs):
  command-define:
    seen = "if"
else:
  command-define:
    seen = "else"
seen
""", "if")
    checkText("""define:
  xs = []:
    "a"
    "b"
if (empty? xs):
  command-define:
    seen = "if"
else:
  command-define:
    seen = "else"
seen
""", "else")

  test "nested statement if and else share the innermost condition":
    checkText("""define:
  xs = []
  ys = []:
    "a"
    "b"
if (empty? xs):
  command-define:
    seen = "outer"
  if (empty? ys):
    command-define:
      seen = "inner"
  else:
    command-define:
      seen = "skipped"
else:
  command-define:
    seen = "outer-else"
seen
""", "skipped")
    checkText("""define:
  xs = []:
    "a"
  ys = []
if (empty? xs):
  command-define:
    seen = "outer"
  if (empty? ys):
    command-define:
      seen = "inner"
  else:
    command-define:
      seen = "skipped"
else:
  command-define:
    seen = "outer-else"
seen
""", "outer-else")
    checkText("""define:
  xs = []
  ys = []
if (empty? xs):
  command-define:
    seen = "outer"
  if (empty? ys):
    command-define:
      seen = "inner"
  else:
    command-define:
      seen = "skipped"
else:
  command-define:
    seen = "outer-else"
seen
""", "inner")

  test "else runs unconditionally":
    checkText("""else:
  "ran"
""", "ran")

  test "statement if without else leaves its condition on the stack":
    checkNumber("""if false:
  command-define:
    x = 1
length condition-results
""", 1)
    checkNumber("""if false:
  command-define:
    x = 1
else:
  command-define:
    x = 2
length condition-results
""", 0)

  test "list-from builds a list from binding syntax":
    checkList("""list-from (statements (parse "1\n2\n3"))
""", 3)
    checkNumber("""+ (length (list-from (statements (parse "1\n2\n3")))) (first (list-from (statements (parse "10"))))
""", 13)

  test "list literal collects statements":
    checkList("""[]:
  1
  (+ 1 1)
  3
""", 3)
    checkNumber("""define:
  values = []:
    10
    20
    30
nth values 1
""", 20)
    checkTrue("""empty? ([])
""")

  test "do evaluates its block":
    checkNumber("""do:
  1
  2
""", 2)
    checkText("""do:
  "a"
  "b"
""", "b")

  test "dict-from builds a dict from binding syntax":
    checkDict("""dict-from (statements (parse "a = 1\nb = 2"))
""")
    checkNumber("""dict-get (dict-from (statements (parse "a = 1\nb = 2"))) "b"
""", 2)

  test "dict literal collects bindings":
    checkDict("""{}:
  name = "crow"
  answer = (+ 40 2)
""")
    checkNumber("""length ({})
""", 0)
    checkNumber("""define:
  config = {}:
    name = "crow"
    answer = 42
+ (length config) (field config "answer")
""", 44)

  test "record-fields lists binding symbols":
    checkNumber("""length (record-fields (statements (parse "x = 1\ny = 2")))
""", 2)
    checkText("""first (record-fields (statements (parse "x = 1\ny = 2")))
""", "x")

  test "record-defaults lists binding values":
    checkNumber("""length (record-defaults (statements (parse "x = 1")))
""", 1)
    checkNumber("""length (record-defaults (statements (parse "")))
""", 0)

  test "record defines a constructor and predicate":
    checkNumber("""record Vec3:
  x = 0
  y = 0
define:
  point = (Vec3 1 2)
+ point.x point.y
""", 3)
    checkTrue("""record Vec3:
  x = 0
define:
  point = (Vec3)
and (Vec3? point) (not (Vec3? (dict-from (statements (parse "a = 1")))))
""")
    checkNumber("""record Vec3:
  x = 10
  y = 20
define:
  point = (Vec3)
+ point.x point.y
""", 30)

  test "unsupported-stream-operation raises":
    expect EvaluatorError:
      discard run("""unsupported-stream-operation
""")

  test "Stream is a record with unsupported field commands":
    checkTrue("""and (Stream? (Stream)) (Stream? (open-string "x")) (not (Stream? (dict-from (statements (parse "a = 1")))))
""")
    expect EvaluatorError:
      discard run("""call (Stream).read
""")

  test "cond-from chooses the first true clause":
    checkText("""cond-from (statements (parse "when false:\n  \"no\"\nwhen T:\n  \"yes\"\n| T:\n  \"never\""))
""", "yes")
    checkText("""cond-from (statements (parse "when false:\n  \"no\"\n| T:\n  \"fallback\""))
""", "fallback")
    let empty = run("""cond-from (statements (parse ""))
""")
    check empty.kind == Nothing
    expect EvaluatorError:
      discard run("""cond-from (statements (parse "bad"))
""")

  test "cond dispatches on when clauses":
    checkText("""define:
  inp = "world"
cond:
  when (= inp "hello"):
    "hello"
  when (= inp "world"):
    "world"
  when T:
    "unknown"
""", "world")
    checkText("""cond:
  when false:
    "no"
  | T:
    "fallback"
""", "fallback")
    expect EvaluatorError:
      discard run("""cond:
  bad
""")

  test "nth indexes into a list":
    checkNumber("""define:
  values = []:
    10
    20
    30
+ (nth values 0) (nth values 2)
""", 40)
    expect EvaluatorError:
      discard run("""nth (list-from (statements (parse "1\n2"))) 5
""")

  test "append-value returns a new list":
    checkNumber("""define:
  xs = []:
    1
    2
  ys = (append-value xs 3)
+ (length ys) (first ys) (first xs)
""", 5)
    checkNumber("""length (append-value ([]) 7)
""", 1)

  test "append mutates the target list":
    checkNumber("""define:
  xs = []:
    1
append xs 2
+ (length xs) (nth xs 1)
""", 4)

  test "drop-front drops the leading values":
    checkNumber("""define:
  xs = []:
    1
    2
    3
+ (length (drop-front xs 2)) (first (drop-front xs 1))
""", 3)
    checkNumber("""length (drop-front ([]) 5)
""", 0)

  test "pop-front mutates the target list":
    checkNumber("""define:
  xs = []:
    1
    2
    3
pop-front xs 2
+ (length xs) (first xs)
""", 4)

  test "close closes a stream":
    checkText("""with (open-string "x") s:
  close s
  "closed"
""", "closed")

  test "read-line reads a line":
    checkText("""with (open-string "ab\ncd") s:
  read-line s
""", "ab")

  test "read reads a single byte":
    checkText("""with (open-string "ab") s:
  read s
""", "a")

  test "read-all reads the rest of the stream":
    checkText("""with (open-string "ab") s:
  read-all s
""", "ab")

  test "write-line writes a line":
    checkText("""with (open-string "") s:
  write-line s "hello"
  read-all s
""", "hello\n")

  test "write writes without a newline":
    checkText("""with (open-string "") s:
  write s "hello"
  write-line s "world"
  read-all s
""", "helloworld\n")

  test "assert passes and raises on failure":
    checkTrue("""assert (= 1 1)
""")
    expect EvaluatorError:
      discard run("""assert (= 1 2)
""")

  test "range iterates up to the stop":
    checkNumber("""define:
  next = (range 1 4)
+ (next) (next) (next)
""", 6)
    checkTrue("""define:
  next = (range 1 4)
  a = (next)
  b = (next)
  c = (next)
  d = (next)
= d nothing
""")

  test "countdown iterates down to the stop":
    checkNumber("""define:
  next = (countdown 3 1)
+ (next) (next)
""", 5)

  test "iter iterates over a list":
    checkNumber("""define:
  next = (iter (list-from (statements (parse "10\n20"))))
+ (next) (next)
""", 30)
    checkTrue("""define:
  next = (iter ([]))
= (next) nothing
""")

  test "once yields a single value":
    checkNumber("""define:
  next = (once 5)
  a = (next)
  b = (next)
when (not (= b nothing)):
  error "once yielded twice"
a
""", 5)

  test "for-each evaluates the body for each item":
    checkNumber("""block-command walk item iterator:
  for-each item (eval iterator) block
walk n (iter (list-from (statements (parse "1\n2\n3")))):
  * n 10
""", 30)
    let empty = run("""block-command walk item iterator:
  for-each item (eval iterator) block
walk n (iter ([])):
  error "should not run"
""")
    check empty.kind == Nothing

  test "for evaluates the iterator expression":
    checkNumber("""for n (range 1 4):
  + n 10
""", 13)
