import unittest

import owl

proc assertNumber(t: Token, v: float64) =
  check t.kind == Number
  check t.number == v

proc assertSymbol(t: Token, s: string) =
  check t.kind == Symbol
  check t.symbol == s

proc assertOp(t: Token, s: string) =
  check t.kind == Op
  check t.operator == s

proc assertEof(t: Token) =
  check t.kind == Eof

suite "Lexer":
  test "basic tokens":
    var lx = Lexer.init("100 + hello")
    check lx.tokens.len == 3
    assertNumber(lx[0], 100)
    assertOp(lx[1], "+")
    assertSymbol(lx[2], "hello")
    assertEof(lx[3])

  test "whitespace and sequencing":
    let lx = Lexer.init("  a*b   +  23   -c ")
    check lx.tokens.len == 7
    assertSymbol(lx[0], "a")
    assertOp(lx[1], "*")
    assertSymbol(lx[2], "b")
    assertOp(lx[3], "+")
    assertNumber(lx[4], 23)
    assertOp(lx[5], "-")
    assertSymbol(lx[6], "c")
    assertEof(lx[7])

  test "peek/next flow":
    var lx = Lexer.init("foo + bar")
    var t = lx.next()
    assertSymbol(t, "foo")
    t = lx.peek()
    assertOp(t, "+")
    discard lx.next()
    t = lx.next()
    assertSymbol(t, "bar")
    t = lx.peek()
    assertEof(t)
    t = lx.next()
    assertEof(t)
    t = lx.next()
    assertEof(t)

  test "numbers":
    let lx = Lexer.init("0 007 42 9001")
    check lx.tokens.len == 4
    assertNumber(lx[0], 0)
    assertNumber(lx[1], 7)
    assertNumber(lx[2], 42)
    assertNumber(lx[3], 9001)

  test "index out of range gives Eof":
    let lx = Lexer.init("x")
    assertSymbol(lx[0], "x")
    assertEof(lx[1])
    assertEof(lx[100])

  test "invalid character raises":
    expect Exception:
      discard Lexer.init("@")

proc parseRec(src: string): Exp =
  var lex = Lexer.init(src)
  let (e, m) = rec(lex)
  doAssert m
  e

proc parseBlock(src: string): Exp =
  var lex = Lexer.init(src)
  let (e, m) = codeBlock(lex)
  doAssert m
  e

suite "record parsing":
  test "empty record":
    let e = parseRec("@{ }")
    check e == node("record", @[])

  test "single pair symbol key":
    let e = parseRec("@{ a = 1 }")
    check e == node("record", @[node("pair", @[sym("a"), num(1)])])

  test "single pair numeric key":
    let e = parseRec("@{ 1 = 2 }")
    check e == node("record", @[node("pair", @[num(1), num(2)])])

  test "multiple pairs with commas":
    let e = parseRec("@{ a=1, b=2, c=3 }")
    check e == node("record", @[
      node("pair", @[sym("a"), num(1)]),
      node("pair", @[sym("b"), num(2)]),
      node("pair", @[sym("c"), num(3)]),
    ])

  test "expression values respect precedence":
    let e = parseRec("@{ a=1+2, b=3*4, c=5+6*7 }")
    check e == node("record", @[
      node("pair", @[sym("a"), Exp(kind: List, items: @[sym("+"), num(1), num(2)])]),
      node("pair", @[sym("b"), Exp(kind: List, items: @[sym("*"), num(3), num(4)])]),
      node("pair", @[sym("c"), Exp(kind: List, items: @[sym("+"), num(5), Exp(kind: List, items: @[sym("*"), num(6), num(7)])])]),
    ])

  test "record with list and booleans":
    let e = parseRec("@{ xs=[1,2,3], t=#t, f=#f, n=none }")
    check e.items.len == 1 + 4
    check e.items[0] == sym("record")
    check e.items[1] == node("pair", @[sym("xs"), Exp(kind: List, items: @[num(1), num(2), num(3)])])
    check e.items[2] == node("pair", @[sym("t"), True])
    check e.items[3] == node("pair", @[sym("f"), False])
    check e.items[4] == node("pair", @[sym("n"), None])

suite "code block parsing":
  test "empty block":
    let e = parseBlock("{}")
    check e == node("do", @[])

  test "numbers sequence":
    let e = parseBlock("{ 1 2 3 }")
    check e == node("do", @[num(1), num(2), num(3)])

  test "mixed expressions and list":
    let e = parseBlock("{ 1 2+3 [4,5] }")
    check e.items.len == 1 + 3
    check e.items[0] == sym("do")
    check e.items[1] == num(1)
    check e.items[2] == Exp(kind: List, items: @[sym("+"), num(2), num(3)])
    check e.items[3] == Exp(kind: List, items: @[num(4), num(5)])

  test "nested record inside block":
    let e = parseBlock("{ @{a=1, b=2} }")
    check e.items.len == 2
    check e.items[0] == sym("do")
    check e.items[1] == node("record", @[
      node("pair", @[sym("a"), num(1)]),
      node("pair", @[sym("b"), num(2)])
    ])

  test "block respects operator precedence":
    let e = parseBlock("{ 1+2*3 }")
    check e == node("do", @[
      Exp(kind: List, items: @[
        sym("+"),
        num(1),
        Exp(kind: List, items: @[sym("*"), num(2), num(3)])
      ])
    ])

  test "block with booleans and none":
    let e = parseBlock("{ #t #f none }")
    check e == node("do", @[True, False, None])

