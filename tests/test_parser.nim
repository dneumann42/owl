import std/unittest

import crow/parser
import crow/syntax

proc symbols(node: SyntaxNode): seq[string] =
  case node.kind
  of Symbol:
    result = @[node.symbol]
  of Command:
    result.add node.callee.symbols
    for argument in node.arguments:
      result.add argument.symbols
  of Binding:
    result.add node.bindingSymbol
    result.add node.value.symbols
  of Script:
    for statement in node.statements:
      result.add statement.symbols
  of String:
    result = @[]

suite "parser":
  test "parses empty input and skips blank/comment lines":
    let tree = parse("""

; comment
  ; indented comment
""")
    check tree.kind == Script
    check tree.statements.len == 0

  test "parses commands, strings, escapes, and comma statements":
    let tree = parse("writeLine \"Hello\\nWorld\" stdout, print \"quote: \\\"\"\n")
    check tree.statements.len == 2
    check tree.statements[0].kind == Command
    check tree.statements[0].callee.symbol == "writeLine"
    check tree.statements[0].arguments[0].stringValue == "Hello\nWorld"
    check tree.statements[0].arguments[1].symbol == "stdout"
    check tree.statements[1].callee.symbol == "print"
    check tree.statements[1].arguments[0].stringValue == "quote: \""

  test "parses all supported string escapes":
    let tree = parse("print \"tab\\treturn\\rslash\\\\\"\n")
    check tree.statements[0].arguments[0].stringValue == "tab\treturn\rslash\\"

  test "parses bindings and keeps numbers as names":
    let tree = parse("""
a = 100
real = -10.03e+2
""")
    check tree.statements.len == 2
    check tree.statements[0].kind == Binding
    check tree.statements[0].bindingSymbol == "a"
    check tree.statements[0].value.callee.symbol == "100"
    check tree.statements[1].value.callee.symbol == "-10.03e+2"

  test "parses explicit blocks":
    let tree = parse("""
define:
  x = 100
  y = (+ x 1)
""")
    let define = tree.statements[0]
    check define.kind == Command
    check define.layout == ColonLayout
    check define.body.len == 2
    check define.body[1].value.callee.symbol == "+"
    check define.body[1].value.arguments[1].symbol == "1"

  test "parses indentation continuations":
    let tree = parse("""
writeLine
  "Hello"
  stdout
""")
    let call = tree.statements[0]
    check call.kind == Command
    check call.layout == ContinuationLayout
    check call.body[0].kind == String
    check call.body[1].callee.symbol == "stdout"

  test "attaches binding layout to the right hand side command":
    let tree = parse("""
pos = Vec3:
  x = 1
  y = 2
""")
    let bound = tree.statements[0]
    check bound.kind == Binding
    check bound.value.kind == Command
    check bound.value.layout == ColonLayout
    check bound.value.body.len == 2

  test "parses grouped calls and equals callee":
    let tree = parse("when (= inp \"hello\"):\n  print \"Hello!\"\n")
    let condition = tree.statements[0].arguments[0]
    check condition.kind == Command
    check condition.callee.symbol == "="
    check condition.arguments[0].symbol == "inp"
    check tree.statements[0].body[0].callee.symbol == "print"

  test "parses grouped callees":
    let tree = parse("(factory maker) arg\n")
    let call = tree.statements[0]
    check call.kind == Command
    check call.callee.kind == Command
    check call.callee.callee.symbol == "factory"
    check call.callee.arguments[0].symbol == "maker"
    check call.arguments[0].symbol == "arg"

  test "parses compound assignment command symbols":
    let tree = parse("+= n 1\n")
    let call = tree.statements[0]
    check call.kind == Command
    check call.callee.symbol == "+="
    check call.arguments[0].symbol == "n"
    check call.arguments[1].symbol == "1"

  test "parses grouped form with layout":
    let tree = parse("""
pos3 = (Vec3:
  x = 1
  y = 2
)
""")
    let value = tree.statements[0].value
    check value.callee.symbol == "Vec3"
    check value.layout == ColonLayout
    check value.body.len == 2

  test "parses dictionary literal command with binding entries":
    let tree = parse("""
config = {}:
  name = "crow"
  answer = (+ 40 2)
""")
    let value = tree.statements[0].value
    check value.kind == Command
    check value.callee.symbol == "{}"
    check value.layout == ColonLayout
    check value.body.len == 2
    check value.body[0].kind == Binding
    check value.body[0].bindingSymbol == "name"
    check value.body[0].value.stringValue == "crow"
    check value.body[1].kind == Binding
    check value.body[1].bindingSymbol == "answer"
    check value.body[1].value.callee.symbol == "+"

  test "parses grouped continuation layout":
    let tree = parse("pos = (Vec3\n  1\n  2\n  3\n)\n")
    let value = tree.statements[0].value
    check value.callee.symbol == "Vec3"
    check value.layout == ContinuationLayout
    check value.body.len == 3

  test "accepts unicode atom characters":
    let tree = parse("π = плюс α β\n")
    check tree.symbols == @["π", "плюс", "α", "β"]

  test "handles crlf, tabs, comments, and final newline insertion":
    let tree = parse("outer:\r\n\tinner ; inline comment\r\nnext")
    check tree.statements.len == 2
    check tree.statements[0].layout == ColonLayout
    check tree.statements[0].body[0].callee.symbol == "inner"
    check tree.statements[1].callee.symbol == "next"

  test "reports explicit parse and lex errors":
    expect ParserError:
      discard parse("\"nope\n")
    expect ParserError:
      discard parse("x = \"\\x\"\n")
    expect ParserError:
      discard parse("a\n  b\n c\n")
    expect ParserError:
      discard parse("\"str\":\n  x\n")
    expect ParserError:
      discard parse("(\"str\":\n  x\n)")
    expect ParserError:
      discard parse("(x\n")
    expect ParserError:
      discard parse("x,\n")
    expect ParserError:
      discard parse("x:\ny\n")

suite "formatter":
  test "formats simple statements and escapes strings":
    let tree = parse("writeLine \"Hello\\nWorld\" stdout\n")
    check $tree == "writeLine \"Hello\\nWorld\" stdout"
    check $parse("print \"tab\\treturn\\rslash\\\\quote\\\"\"\n") ==
      "print \"tab\\treturn\\rslash\\\\quote\\\"\""

  test "formats bindings and grouped command expressions":
    let tree = parse("""
a = 100
y = (+ x 1)
when (= inp "hello"):
  print "Hello!"
""")
    check $tree == "a = 100\ny = (+ x 1)\nwhen (= inp \"hello\"):\n  print \"Hello!\""

  test "formats explicit and continuation blocks":
    check $parse("define:\n  x = 1\n  y = 2\n") == """
define:
  x = 1
  y = 2"""
    check $parse("writeLine\n  \"Hello\"\n  stdout\n") == """
writeLine
  "Hello"
  stdout"""

  test "formats grouped layouts and grouped callees":
    check $parse("pos = (Vec3:\n  x = 1\n  y = 2\n)\n") == """
pos = Vec3:
  x = 1
  y = 2"""
    check $parse("(factory maker) arg\n") == "(factory maker) arg"

  test "formatted output parses back to the same form":
    let source = """
define:
  pos = Vec3:
    x = 1
    y = (+ 1 2)
  when (= inp "hello"):
    print "Hello!"
"""
    let formatted = $parse(source)
    check $parse(formatted) == formatted
