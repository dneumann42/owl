import std/unittest

import owl/[parser, syntax, typing]

proc checkerWithNumbers(): TypeChecker =
  result = TypeChecker.init()
  result.define("+", functionTypeNode("+", TNumber, [TNumber, TNumber]))

proc checkSource(checker: var TypeChecker, source: string): SyntaxNode =
  result = parse(source)
  checker.typeCheck(result)

suite "typing":
  test "boolean literals have Boolean type":
    var checker = TypeChecker.init()
    let ast = checker.checkSource("a = true\nb = F\n")
    check ast.statements[0].typed == @[TBoolean]
    check ast.statements[1].typed == @[TBoolean]

  test "fun defines a callable function type":
    var checker = checkerWithNumbers()
    let ast = checker.checkSource("""
fun add'Number left'Number right'Number:
  + left right
answer = add 20 22
""")

    check ast.statements[0].typed[0].kind == Function
    check ast.statements[0].typed[0].returnType[] == TNumber
    check ast.statements[0].typed[0].parameters == @[TNumber, TNumber]
    check ast.statements[1].typed == @[TNumber]

  test "command defines a callable function type":
    var checker = TypeChecker.init()
    let ast = checker.checkSource("""
command'a identity'a value'a:
  value
answer = identity "owl"
""")

    check ast.statements[0].typed[0].generics == @["a"]
    check ast.statements[1].typed == @[TText]

  test "generic calls specialize each invocation independently":
    var checker = TypeChecker.init()
    let ast = checker.checkSource("""
fun'a identity'a value'a:
  value
number = identity 10
text = identity "owl"
""")

    check ast.statements[1].typed == @[TNumber]
    check ast.statements[2].typed == @[TText]

  test "generic variables unify inside type specifications":
    var checker = TypeChecker.init()
    let generic = symbolTypeNode("a")
    checker.define(
      "first",
      functionTypeNode(
        "first", generic,
        [typeSpecNode(symbolTypeNode("List"), [generic])],
        ["a"],
      ),
    )
    checker.define(
      "numbers", typeSpecNode(symbolTypeNode("List"), [TNumber])
    )
    let ast = checker.checkSource("answer = first numbers\n")

    check ast.statements[0].typed == @[TNumber]

  test "value-of retains a referenced function type":
    var checker = checkerWithNumbers()
    let ast = checker.checkSource("""
plus = value-of +
answer = plus 40 2
""")

    check ast.statements[0].typed[0].kind == Function
    check ast.statements[1].typed == @[TNumber]

  test "records define constructors and typed fields":
    var checker = TypeChecker.init()
    let ast = checker.checkSource("""
record Point:
  x'Number = 0
  y'Number = 0
point = Point 1 2
set point.x 3
value = point.x
""")

    check ast.statements[0].typed[0].kind == Function
    check ast.statements[1].typed[0].kind == TypeSpec
    check ast.statements[2].typed == @[TNothing]
    check ast.statements[3].typed == @[TNumber]

  test "records infer unannotated field types from their defaults":
    var checker = TypeChecker.init()
    let ast = checker.checkSource("""
record Game:
  running = false
game = Game
set game.running true
""")

    check ast.statements[0].typed[0].parameters == @[TBoolean]
    check ast.statements[2].typed == @[TNothing]

  test "generic records specialize their field types":
    var checker = TypeChecker.init()
    let ast = checker.checkSource("""
record't Box:
  value't = 0
box = Box'Text "owl"
text = box.value
""")

    check ast.statements[1].typed[0] ==
      typeSpecNode(symbolTypeNode("Box"), [TText])
    check ast.statements[2].typed == @[TText]

  test "rejects undeclared record type arguments":
    var checker = TypeChecker.init()
    expect TypeCheckError:
      discard checker.checkSource("""
record'x'y V2:
  x'x = cast'x 0
  y'y = cast'y 0
p = V2'Int'Float
""")

  test "set rejects a value that does not match a record field":
    var checker = TypeChecker.init()
    expect TypeCheckError:
      discard checker.checkSource("""
record Point:
  x'Number = 0
point = Point 1
set point.x "wrong"
""")

  test "cast explicitly assigns its callee type":
    var checker = TypeChecker.init()
    let ast = checker.checkSource("value = cast'Number \"42\"\n")

    check ast.statements[0].typed == @[TNumber]

  test "rejects incompatible concrete arguments":
    var checker = checkerWithNumbers()
    expect TypeCheckError:
      discard checker.checkSource("answer = + 1 \"no\"\n")

  test "variadic functions check every argument":
    var checker = TypeChecker.init()
    checker.define("+", variadicFunctionTypeNode("+", TNumber, TNumber))
    let ast = checker.checkSource("answer = + 1 2 3\n")
    check ast.statements[0].typed == @[TNumber]

  test "variadic functions infer one generic type across all arguments":
    var checker = TypeChecker.init()
    let item = symbolTypeNode("a")
    checker.define(
      "pack",
      variadicFunctionTypeNode(
        "pack", typeSpecNode(symbolTypeNode("List"), [item]), item,
        generics = ["a"],
      ),
    )
    let ast = checker.checkSource("values = pack 1 2 3\n")
    check ast.statements[0].typed == @[
      typeSpecNode(symbolTypeNode("List"), [TNumber])
    ]
    expect TypeCheckError:
      discard checker.checkSource("pack 1 \"no\"\n")

  test "rejects conflicting generic arguments":
    var checker = TypeChecker.init()
    expect TypeCheckError:
      discard checker.checkSource("""
fun'a same'a left'a right'a:
  left
same 1 "no"
""")
