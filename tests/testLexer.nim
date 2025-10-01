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
