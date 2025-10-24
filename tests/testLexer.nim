import unittest
import std/sequtils

import owl

proc assertNumber(t: Token, v: float64) =
  check t.kind == Number
  check t.number == v

proc assertSymbol(t: Token, s: string) =
  check t.kind == Symbol
  check t.symbol == s

proc assertString(t: Token, s: string) =
  check t.kind == String
  check t.str == s

proc assertOp(t: Token, s: string) =
  check t.kind == Op
  check t.operator == s

proc assertEof(t: Token) =
  check t.kind == Eof

proc L(src: string): Lexer =
  Lexer.init(src)

proc E(src: string): Object =
  var lx = L(src)
  expr(lx)

proc R(src: string): Object =
  var lx = L(src)
  let (e, m) = rec(lx)
  doAssert m
  e

proc B(src: string): Object =
  var lx = L(src)
  let (e, m) = codeBlock(lx)
  doAssert m
  e

template list(xs: varargs[Object]): Object =
  Object(kind: List, items: @xs)

proc bin(op: string, a, b: Object): Object =
  list(sym op, a, b)

proc dot(a, b: Object): Object =
  list(sym".", a, b)

proc call(name: string, args: varargs[Object]): Object =
  node(name, @args)

proc params(xs: varargs[Object]): Object =
  list(xs)

proc recPairs(ps: openArray[Object]): Object =
  node("record", @ps)

proc pair(k, v: Object): Object =
  node("pair", @[k, v])

proc chainDot(xs: openArray[Object]): Object =
  doAssert xs.len >= 2
  var acc = dot(xs[0], xs[1])
  for i in 2 ..< xs.len:
    acc = dot(acc, xs[i])
  acc

proc strObj(s: string): Object =
  Object(kind: String, str: s)

suite "Lexer":
  test "basic tokens":
    var lx = L("100 + hello")
    check lx.tokens.len == 3
    assertNumber(lx[0], 100)
    assertOp(lx[1], "+")
    assertSymbol(lx[2], "hello")
    assertEof(lx[3])

  test "whitespace and sequencing":
    let lx = L("  a * b   +  23   -c ")
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
    var lx = L("foo + bar")
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
    let lx = L("0 007 42 9001")
    check lx.tokens.len == 4
    assertNumber(lx[0], 0)
    assertNumber(lx[1], 7)
    assertNumber(lx[2], 42)
    assertNumber(lx[3], 9001)

  test "strings":
    let lx = L("\"hello world\"")
    check lx.tokens.len == 1
    assertString(lx[0], "hello world")
    assertEof(lx[1])

  test "index out of range gives Eof":
    let lx = L("x")
    assertSymbol(lx[0], "x")
    assertEof(lx[1])
    assertEof(lx[100])

suite "record parsing":
  test "empty record":
    let e = R("@{ }")
    check e == list(sym"record")

  test "single pair symbol key":
    let e = R("@{ a = 1 }")
    check e == recPairs(@[pair(sym"a", num 1)])

  test "single pair numeric key":
    let e = R("@{ 1 = 2 }")
    check e == recPairs(@[pair(num 1, num 2)])

  test "multiple pairs with commas":
    let e = R("@{ a=1, b=2, c=3 }")
    check e == recPairs(
      @[pair(sym"a", num 1), pair(sym"b", num 2), pair(sym"c", num 3)]
    )

  test "expression values respect precedence":
    let e = R("@{ a=1+2, b=3*4, c=5+6*7 }")
    check e ==
      recPairs(
        @[
          pair(sym"a", bin("+", num 1, num 2)),
          pair(sym"b", bin("*", num 3, num 4)),
          pair(sym"c", bin("+", num 5, bin("*", num 6, num 7))),
        ]
      )

  test "record with list and booleans":
    let e = R("@{ xs=[1,2,3], t=#t, f=#f, n=none }")
    check e.items.len == 1 + 4
    check e.items[0] == sym"record"
    check e.items[1] == pair(sym"xs", list(sym"quote", list(num 1, num 2, num 3)))
    check e.items[2] == pair(sym"t", True)
    check e.items[3] == pair(sym"f", False)
    check e.items[4] == pair(sym"n", None)

suite "code block parsing":
  test "empty block":
    check B("{}") == node("do", @[])

  test "numbers sequence":
    check B("{ 1 2 3 }") == node("do", @[num 1, num 2, num 3])

  test "mixed expressions and list":
    let e = B("{ 1 2+3 [4,5] }")
    check e.items.len == 1 + 3
    check e.items[0] == sym"do"
    check e.items[1] == num 1
    check e.items[2] == bin("+", num 2, num 3)
    check e.items[3] == list(sym"quote", list(num 4, num 5))

  test "nested record inside block":
    let e = B("{ @{a=1, b=2} }")
    check e.items.len == 2
    check e.items[0] == sym"do"
    check e.items[1] == recPairs(@[pair(sym"a", num 1), pair(sym"b", num 2)])

  test "block respects operator precedence":
    check B("{ 1+2*3 }") == node("do", @[bin("+", num 1, bin("*", num 2, num 3))])

  test "block with booleans and none":
    check B("{ #t #f none }") == node("do", @[True, False, None])

suite "call and dot":
  test "simple call":
    let got = E("echo(2)")
    let want = call("echo", num 2)
    check got == want

  test "multi-arg call":
    let got = E("sum(1, 2, 3)")
    let want = call("sum", num 1, num 2, num 3)
    check got == want

  test "string literal expression":
    let got = E("\"hi\"")
    let want = strObj("hi")
    check got == want

  test "call with string literal":
    let got = E("echo(\"hi\")")
    let want = call("echo", strObj("hi"))
    check got == want

  test "nested calls":
    let got = E("f(g(1), h(2,3))")
    let want = call("f", call("g", num 1), call("h", num 2, num 3))
    check got == want

  test "quote shorthand expression":
    let got = E("'foo")
    let want = node("quote", @[sym"foo"])
    check got == want

  test "dot chains left-assoc":
    let got = E("a.b.c")
    let want = chainDot([sym"a", sym"b", sym"c"])
    check got == want

  test "dot binds tighter than +":
    let got = E("a.b + c.d")
    let want = bin("+", dot(sym"a", sym"b"), dot(sym"c", sym"d"))
    check got == want

  test "call then dot with call":
    let got = E("foo(1).bar(2)")
    let want = dot(call("foo", num 1), call("bar", num 2))
    check got == want

  test "mixed chain with calls":
    let got = E("f(1).g.h(2,3).k")
    let want = dot(dot(dot(call("f", num 1), sym"g"), call("h", num 2, num 3)), sym"k")
    check got == want

suite "Lexer (comparisons)":
  test "multi-char and single-char operators":
    let lx = L("== != <= >= < >")
    check lx.tokens.len == 6
    assertOp(lx[0], "==")
    assertOp(lx[1], "!=")
    assertOp(lx[2], "<=")
    assertOp(lx[3], ">=")
    assertOp(lx[4], "<")
    assertOp(lx[5], ">")
    assertEof(lx[6])

suite "comparison parsing":
  test "relational looser than dot and * and + chain":
    let got = E("1 + 2 * 3 == 7")
    let want = bin("==", bin("+", num 1, bin("*", num 2, num 3)), num 7)
    check got == want

  test "equality lowest: 1 < 2 == #t":
    let got = E("1 < 2 == #t")
    let want = bin("==", bin("<", num 1, num 2), True)
    check got == want

  test "relational lower than +":
    let got = E("1 + 2 < 4")
    let want = bin("<", bin("+", num 1, num 2), num 4)
    check got == want

  test "all relational variants":
    for (src, op) in [
      ("1 < 2", "<"), ("1 <= 2", "<="), ("2 > 1", ">"), ("2 >= 1", ">=")
    ]:
      let g = E(src)
      check g.items.len == 3
      check g.items[0] == sym(op)

  test "equality forms":
    for (src, op) in [("1 == 1", "=="), ("1 != 2", "!=")]:
      let g = E(src)
      check g.items.len == 3
      check g.items[0] == sym(op)

  test "dot binds tighter than equality":
    let got = E("a.b == c.d")
    let want = bin("==", dot(sym"a", sym"b"), dot(sym"c", sym"d"))
    check got == want

  test "left-assoc equality chain":
    let got = E("1 == 2 == 3")
    let want = bin("==", bin("==", num 1, num 2), num 3)
    check got == want

suite "record parsing (comparisons)":
  test "record values with comparisons respect precedence":
    let e = R("@{ a=1<2, b=1+2<4, c=a.b==c.d }")
    check e ==
      recPairs(
        @[
          pair(sym"a", bin("<", num 1, num 2)),
          pair(sym"b", bin("<", bin("+", num 1, num 2), num 4)),
          pair(sym"c", bin("==", dot(sym"a", sym"b"), dot(sym"c", sym"d"))),
        ]
      )

suite "code block parsing (comparisons)":
  test "block equality lowest":
    check B("{ 1 < 2 == #t }") == node("do", @[bin("==", bin("<", num 1, num 2), True)])

suite "functions and lambdas":
  test "lambda: empty params, simple body":
    let got = E("fun() 42")
    let want = node("lambda", @[params(), num 42])
    check got == want

  test "lambda: single param, identifier body":
    let got = E("fun(x) x")
    let want = node("lambda", @[params(sym"x"), sym"x"])
    check got == want

  test "lambda: multi-params, body respects precedence":
    let got = E("fun(x, y) x + y * 2")
    let want = node(
      "lambda", @[params(sym"x", sym"y"), bin("+", sym"x", bin("*", sym"y", num 2))]
    )
    check got == want

  test "fun def: empty params, single expr block":
    let got = E("fun id() { 1 }")
    let want = node("fun", @[sym"id", params(), node("do", @[num 1])])
    check got == want

  test "fun def: one param, simple body":
    let got = E("fun inc(x) { x + 1 }")
    let want =
      node("fun", @[sym"inc", params(sym"x"), node("do", @[bin("+", sym"x", num 1)])])
    check got == want

  test "fun def: two params, binary in body":
    let got = E("fun add(a, b) { a + b }")
    let want = node(
      "fun",
      @[sym"add", params(sym"a", sym"b"), node("do", @[bin("+", sym"a", sym"b")])],
    )
    check got == want

  test "fun def: record in body":
    let got = E("fun make(x, y) { @{a=x, b=y} }")
    let want = node(
      "fun",
      @[
        sym"make",
        params(sym"x", sym"y"),
        node("do", @[recPairs(@[pair(sym"a", sym"x"), pair(sym"b", sym"y")])]),
      ],
    )
    check got == want

  test "lambda nested in expression context":
    let got = E("[fun(x) x, fun() 0]")
    let want = list(
      sym"quote",
      list(
        node("lambda", @[params(sym"x"), sym"x"]), node("lambda", @[params(), num 0])
      ),
    )
    check got == want
