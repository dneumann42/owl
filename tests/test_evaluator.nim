import std/[os, strutils, tables, unittest]

import crow
import crow/evaluator
import crow/parser
import crow/values

type ProbeNative = ref object of NativeValue
  label: string

proc run(source: string): Value =
  var evaluator = Evaluator.init()
  evaluator.exec(parse(source))

suite "evaluator":
  test "scripts yield the last expression":
    let value = run(
      """
1
2
"""
    )
    check value.kind == Number
    check value.number == 2

  test "bindings are syntax data":
    let value = run(
      """
a = 41
"""
    )
    check value.kind == Syntax
    check value.syntax.kind == Binding
    check value.syntax.bindingSymbol == "a"

  test "define binds symbols in the current environment":
    let value = run(
      """
define:
  a = 41
+ a 1
"""
    )
    check value.kind == Number
    check value.number == 42

  test "define shadows captured symbols and set mutates them":
    let value = run(
      """
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
"""
    )
    check value.kind == Number
    check value.number == 51

  test "compound assignment commands mutate existing symbols":
    let value = run(
      """
define:
  n = 6
+= n 4
*= n 3
-= n 9
/= n 3
n
"""
    )
    check value.kind == Number
    check value.number == 7

  test "fun defines closures that evaluate arguments":
    let value = run(
      """
fun inc n:
  + n 1
inc 4
"""
    )
    check value.kind == Number
    check value.number == 5

  test "indentation groups call arguments":
    let value = run(
      """
command third a b c:
  eval c
third
  (+ 1 2 3)
  "test"
  T
"""
    )
    check value.kind == Boolean
    check value.boolean == true

  test "indentation supplies evaluated closure arguments":
    let value = run(
      """
fun total a b c:
  + a b c
total
  (+ 1 2 3)
  4
  5
"""
    )
    check value.kind == Number
    check value.number == 15

  test "fn creates anonymous closures":
    let value = run(
      """
define:
  base = 10
  lam = fn a b c:
    + base a (* b c)
lam 1 2 3
"""
    )
    check value.kind == Number
    check value.number == 17

  test "lambda aliases fn":
    let value = run(
      """
define:
  lam = lambda a b:
    - a b
lam 9 4
"""
    )
    check value.kind == Number
    check value.number == 5

  test "standard streams are globals":
    let input = run("stdin\n")
    check input.kind == Record
    check input.recordName == "Stream"
    check input.recordEntries.hasKey("read")
    check input.recordEntries.hasKey("read-line")
    check input.recordEntries.hasKey("read-all")
    check input.recordEntries.hasKey("open")
    check input.recordEntries.hasKey("close")

    let output = run("stdout\n")
    check output.kind == Record
    check output.recordName == "Stream"
    check output.recordEntries.hasKey("write")
    check output.recordEntries.hasKey("write-line")
    check output.recordEntries.hasKey("open")
    check output.recordEntries.hasKey("close")

  test "stream predicate recognizes host streams":
    let value =
      run("and (Stream? stdin) (Stream? stdout) (Stream? (open-string \"x\"))\n")
    check value.kind == Boolean
    check value.boolean

  test "write commands take output streams":
    let value = run("write stdout \"\"\n")
    check value.kind == Text
    check value.text == ""

  test "read commands require explicit streams":
    expect EvaluatorError:
      discard run("readline\n")
    expect EvaluatorError:
      discard run("read-line stdout\n")

  test "read reads one byte and read-all drains remaining input":
    let value = run(
      """
with (open-string "abc") stream:
  concat (read stream) (read-all stream)
"""
    )
    check value.kind == Text
    check value.text == "abc"

  test "append mutates named lists and nth reads by index":
    let value = run(
      """
define:
  values = (list)
append values "a"
append values "b"
nth values 1
"""
    )
    check value.kind == Text
    check value.text == "b"

  test "pop-front mutates named lists by dropping leading items":
    let value = run(
      """
define:
  values = []:
    "a"
    "b"
    "c"
    "d"
pop-front values 2
nth values 0
"""
    )
    check value.kind == Text
    check value.text == "c"

    let empty = run(
      """
define:
  values = []:
    "a"
pop-front values 3
empty? values
"""
    )
    check empty.kind == Boolean
    check empty.boolean == true

  test "length returns list dictionary and string sizes":
    let value = run(
      """
define:
  values = []:
    1
    2
    3
  config = {}:
    name = "crow"
    answer = 42
+ (length values) (length config) (length "crow")
"""
    )
    check value.kind == Number
    check value.number == 9

    expect EvaluatorError:
      discard run("length 42\n")

  test "to-string pretty prints values as owl source":
    let plain = run("to-string \"hello\"\n")
    check plain.kind == Text
    check plain.text == "\"hello\""

    let structured = run(
      """
to-string []:
  1
  "two"
  false
"""
    )
    check structured.kind == Text
    check structured.text == "[]:\n  1, \"two\", false"

  test "value strings round-trip as owl source":
    let source = $dictionary({
      "plain": text("a\nb"),
      "space key": number(42)
    }.toTable())

    let value = run(source)
    check value.kind == Dictionary
    check value.entries["plain"].text == "a\nb"
    check value.entries["space key"].number == 42

    let compact = $dictionary({
      "answer": number(42),
      "name": text("crow")
    }.toTable())
    check compact == "{}:\n  answer = 42, name = \"crow\""

  test "assert raises when condition is false":
    discard run("assert (= 1 1)\n")
    expect EvaluatorError:
      discard run("assert (= 1 2)\n")

  test "with opens and closes string streams":
    let value = run(
      """
define:
  lines = (list)
with (open-string "a\nb\n") stream:
  append lines (read-line stream)
  append lines (read-line stream)
= (nth lines 0) (nth lines 1)
"""
    )
    check value.kind == Boolean
    check value.boolean == false

  test "not negates truthiness":
    let value = run(
      """
not (= 1 2)
"""
    )
    check value.kind == Boolean
    check value.boolean == true

  test "and short-circuits and returns the decisive value":
    check run("and\n").boolean == true
    check run("and true 7\n").number == 7
    check run("and true false (error \"unreachable\")\n").boolean == false
    expect EvaluatorError:
      discard run("and true (error \"reachable\")\n")

  test "or short-circuits and returns the decisive value":
    check run("or\n").boolean == false
    check run("or false 7\n").number == 7
    check run("or true (error \"unreachable\")\n").boolean == true
    expect EvaluatorError:
      discard run("or false (error \"reachable\")\n")

  test "error raises evaluator errors":
    expect EvaluatorError:
      discard run("error \"boom\"\n")

  test "evaluator errors include source preview and stack trace":
    var evaluator = Evaluator.init()
    try:
      discard evaluator.exec(
        parse(
          """
fun explode:
  error "boom"
explode
""", "/tmp/stack.nest",
        )
      )
      fail()
    except EvaluatorError as error:
      let output = report(error)
      check output.contains("/tmp/stack.nest:2:3: error: \"boom\"")
      check output.contains("  error \"boom\"")
      check output.contains("Stack trace:")
      check output.contains("/tmp/stack.nest:3:1 in explode")

  test "parse returns syntax evaluated in the caller environment":
    let value = run(
      """
define:
  x = 40
eval (parse "+ x 2")
"""
    )
    check value.kind == Number
    check value.number == 42

  test "import evaluates another source file in the caller environment":
    let dir = getTempDir() / "crow-import-test"
    createDir(dir)
    writeFile(
      dir / "defs.nest",
      """
define:
  imported = 40
""",
    )

    var evaluator = Evaluator.init()
    let value = evaluator.exec(
      parse(
        """
import "defs.nest"
+ imported 2
""",
        dir / "main.nest",
      )
    )
    check value.kind == Number
    check value.number == 42

  test "use evaluates another source file as a module dictionary":
    let dir = getTempDir() / "crow-use-test"
    createDir(dir)
    writeFile(
      dir / "mathish.nest",
      """
define:
  imported = 40
fun inc n:
  + n 1
""",
    )

    var evaluator = Evaluator.init()
    let value = evaluator.exec(
      parse(
        """
use mathish
mathish.inc mathish.imported
""",
        dir / "main.nest",
      )
    )
    check value.kind == Number
    check value.number == 41

    expect EvaluatorError:
      discard evaluator.exec(parse("imported\n"))

  test "use imports included module symbols into the script namespace":
    let dir = getTempDir() / "crow-use-filter-test"
    createDir(dir)
    writeFile(
      dir / "mathish.nest",
      """
define:
  imported = 40
  hidden = 99
fun inc n:
  + n 1
""",
    )

    var evaluator = Evaluator.init()
    let value = evaluator.exec(
      parse(
        """
use mathish:
  include imported inc
  exclude hidden
inc imported
""",
        dir / "main.nest",
      )
    )
    check value.kind == Number
    check value.number == 41
    expect EvaluatorError:
      discard evaluator.exec(parse("hidden\n"))

  test "use excludes selected module symbols from the script namespace":
    let dir = getTempDir() / "crow-use-exclude-test"
    createDir(dir)
    writeFile(
      dir / "mathish.nest",
      """
define:
  imported = 40
  hidden = 99
""",
    )

    var evaluator = Evaluator.init()
    let value = evaluator.exec(
      parse(
        """
use mathish:
  exclude hidden
imported
""",
        dir / "main.nest",
      )
    )
    check value.kind == Number
    check value.number == 40
    expect EvaluatorError:
      discard evaluator.exec(parse("hidden\n"))

  test "command defines closures that receive raw syntax":
    let value = run(
      """
command twice x:
  + (eval x) (eval x)
define:
  a = 5
twice a
"""
    )
    check value.kind == Number
    check value.number == 10

  test "block-command receives call body as syntax":
    let value = run(
      """
block-command run:
  eval block
run:
  define:
    x = 3
  + x 4
"""
    )
    check value.kind == Number
    check value.number == 7

  test "prelude defines list literals in crow":
    let value = run(
      """
[]:
  1
  + 1 1
  3
"""
    )
    check value.kind == List
    check value.items.len == 3
    check value.items[0].number == 1
    check value.items[1].number == 2
    check value.items[2].number == 3

  test "prelude defines dictionary literals in crow":
    let value = run(
      """
{}:
  name = "crow"
  answer = (+ 40 2)
"""
    )
    check value.kind == Dictionary
    check value.entries["name"].text == "crow"
    check value.entries["answer"].number == 42

  test "dictionary entries can be read with dict-get and field":
    let value = run(
      """
define:
  config = {}:
    name = "crow"
    answer = (+ 40 2)
+ (dict-get config "answer") (field config "answer")
"""
    )
    check value.kind == Number
    check value.number == 84

  test "dictionary entries can be set by assigning dict-put result":
    let value = run(
      """
define:
  config = (dict)
set config (dict-put config "name" "crow")
set config (dict-put config "answer" (+ 40 2))
dict-get config "answer"
"""
    )
    check value.kind == Number
    check value.number == 42

  test "dot and bracket selectors read values":
    let value = run(
      """
define:
  values = []:
    10
    20
  config = {}:
    nested = {}:
      answer = 42
+ values.[0] values.[1] config.nested.answer
"""
    )
    check value.kind == Number
    check value.number == 72

  test "set updates selector targets":
    let value = run(
      """
define:
  values = []:
    10
    20
  config = (dict)
set values.[1] 30
set config.["name"] "crow"
set config.answer 12
+ values.[1] config.answer
"""
    )
    check value.kind == Number
    check value.number == 42

  test "{} block command evaluates binding values in caller scope":
    let value = run(
      """
define:
  base = 40
  config = {}:
    answer = (+ base 2)
dict-get config "answer"
"""
    )
    check value.kind == Number
    check value.number == 42

  test "record constructors create fixed-field values":
    let value = run(
      """
record Vec3:
  x = 0
  y = 0
  z = 0
define:
  a = (Vec3 1 2 3)
  b = Vec3 1 2:
    z = 4
  c = Vec3
    5
    6
    7
+ a.x b.z c.y
"""
    )
    check value.kind == Number
    check value.number == 11

  test "record command defines a type predicate":
    let value = run(
      """
record Vec3:
  x = 0
record Color:
  x = 0
define:
  point = (Vec3)
  color = (Color)
and (Vec3? point) (not (Vec3? color)) (not (Vec3? (dict))) (not (Vec3? 1))
"""
    )
    check value.kind == Boolean
    check value.boolean == true

  test "record fields can be set but not added":
    let value = run(
      """
record Vec3:
  x = 0
  y = 0
define:
  point = (Vec3)
set point.x 10
point.x
"""
    )
    check value.kind == Number
    check value.number == 10

    expect EvaluatorError:
      discard run(
        """
record Vec3:
  x = 0
define:
  point = (Vec3)
set point.y 10
"""
      )

    expect EvaluatorError:
      discard run(
        """
record Vec3:
  x = 0
Vec3:
  y = 10
"""
      )

  test "native commands receive raw syntax and choose evaluation":
    var evaluator = Evaluator.init()
    evaluator.native "capture":
      doAssert arguments.len == 2
      doAssert arguments[0].kind == Symbol
      doAssert arguments[0].symbol == "x"
      doAssert bodyNodes.len == 1
      let evaluated = env.eval(arguments[1])
      text(arguments[0].symbol & ":" & $evaluated & ":" & $layout)

    let value = evaluator.exec(
      parse(
        """
capture x (+ 20 22):
  ignored
"""
      )
    )

    check value.kind == Text
    check value.text == "x:42:ColonLayout"

  test "native values can be returned by extensions":
    var evaluator = Evaluator.init()
    evaluator.native "probe":
      discard env
      discard arguments
      discard layout
      discard bodyNodes
      nativeValue(ProbeNative(label: "from-native"))

    let value = evaluator.exec(parse("probe\n"))

    check value.kind == Native
    check ProbeNative(value.native).label == "from-native"

  test "prelude defines if in crow":
    let value = run(
      """
if (= 1 2):
  then:
    "bad"
  else:
    "good"
"""
    )
    check value.kind == Text
    check value.text == "good"

  test "prelude defines cond in crow":
    let value = run(
      """
define:
  inp = "world"
cond:
  when (= inp "hello"):
    "hello"
  when (= inp "world"):
    "world"
  when T:
    "unknown"
"""
    )
    check value.kind == Text
    check value.text == "world"

  test "prelude cond evaluates clause syntax in the caller environment":
    let value = run(
      """
fun check line:
  cond:
    when (= line "history"):
      "ok"
    when T:
      "bad"
check "history"
"""
    )
    check value.kind == Text
    check value.text == "ok"

  test "prelude cond rejects invalid clauses":
    expect EvaluatorError:
      discard run(
        """
cond:
  nope T:
    "bad"
"""
      )

  test "native while loops in the current environment":
    let value = run(
      """
define:
  n = 0
while (< n 3):
  define:
    n = (+ n 1)
n
"""
    )
    check value.kind == Number
    check value.number == 3

  test "value-of returns a command without calling it":
    let value = run(
      """
fun answer:
  42
value-of answer
"""
    )
    check value.kind == Command

  test "prelude defines range iterators in crow":
    let value = run(
      """
define:
  next = (range 1 4)
+ (next) (next) (next)
"""
    )
    check value.kind == Number
    check value.number == 6

  test "prelude defines countdown iterators in crow":
    let value = run(
      """
define:
  next = (countdown 3 0)
+ (next) (next) (next)
"""
    )
    check value.kind == Number
    check value.number == 6

  test "prelude defines list and once iterators in crow":
    let value = run(
      """
define:
  items = (iter ([]:
    10
    20
  ))
  single = (once 3)
+ (items) (items) (single)
"""
    )
    check value.kind == Number
    check value.number == 33

  test "prelude defines for over iterators in crow":
    let value = run(
      """
for n (range 1 4):
  + n 10
"""
    )
    check value.kind == Number
    check value.number == 13

  test "command environments participate in regular lookup":
    let value = run(
      """
command-define:
  flag = true
flag
"""
    )
    check value.kind == Boolean
    check value.boolean

    let visible = run(
      """
command-define:
  hidden = 1
hidden
"""
    )
    check visible.kind == Number
    check visible.number == 1

  test "command-define evaluates values in the caller environment":
    let value = run(
      """
define:
  base = 40
command-define:
  answer = (+ base 2)
+ answer answer
"""
    )
    check value.kind == Number
    check value.number == 84

  test "set mutates command environment state":
    let value = run(
      """
command-define:
  count = 1
set count 2
count
"""
    )
    check value.kind == Number
    check value.number == 2

    expect EvaluatorError:
      discard run(
        """
set missing 1
"""
      )

  test "prelude if and else share their condition state":
    let trueBranch = run(
      """
define:
  xs = []
if (empty? xs):
  command-define:
    seen = "if"
else:
  command-define:
    seen = "else"
seen
"""
    )
    check trueBranch.kind == Text
    check trueBranch.text == "if"

    let falseBranch = run(
      """
define:
  xs = []:
    1
if (empty? xs):
  command-define:
    seen = "if"
else:
  command-define:
    seen = "else"
seen
"""
    )
    check falseBranch.kind == Text
    check falseBranch.text == "else"

  test "prelude if and else nest without clobbering outer conditions":
    let innerFalse = run(
      """
define:
  xs = []
  ys = []:
    1
if (empty? xs):
  if (empty? ys):
    command-define:
      seen = "inner-if"
  else:
    command-define:
      seen = "inner-else"
else:
  command-define:
    seen = "outer-else"
seen
"""
    )
    check innerFalse.kind == Text
    check innerFalse.text == "inner-else"

    let outerFalse = run(
      """
define:
  xs = []:
    1
  ys = []
if (empty? xs):
  if (empty? ys):
    command-define:
      seen = "inner-if"
  else:
    command-define:
      seen = "inner-else"
else:
  command-define:
    seen = "outer-else"
seen
"""
    )
    check outerFalse.kind == Text
    check outerFalse.text == "outer-else"

    let allTrue = run(
      """
define:
  xs = []
  ys = []
  zs = []
if (empty? xs):
  if (empty? ys):
    if (empty? zs):
      command-define:
        seen = "deep"
    else:
      command-define:
        seen = "shallow"
  else:
    command-define:
      seen = "middle"
else:
  command-define:
    seen = "outer"
seen
"""
    )
    check allTrue.kind == Text
    check allTrue.text == "deep"

  test "prelude if tagged form coexists with standalone else":
    let tagged = run(
      """
if (= 1 2):
  then:
    "bad"
  else:
    "good"
"""
    )
    check tagged.kind == Text
    check tagged.text == "good"

    let nestedTagged = run(
      """
define:
  xs = []
if (empty? xs):
  if (= 1 2):
    then:
      command-define:
        seen = "clause-then"
    else:
      command-define:
        seen = "clause-else"
else:
  command-define:
    seen = "outer-else"
seen
"""
    )
    check nestedTagged.kind == Text
    check nestedTagged.text == "clause-else"
