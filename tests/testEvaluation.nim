
import unittest
import objects
import evaluation

proc s(x: string): Object =
  Object(kind: Symbol, symbol: x)

proc n(x: float64): Object =
  Object(kind: Number, number: x)

proc b(x: bool): Object =
  Object(kind: Boolean, isTrue: x)

proc lst(xs: openArray[Object]): Object =
  Object(kind: List, items: @xs)

suite "Evaluator":
  test "let single binding sets and returns value":
    var ev = Evaluator(root: Env.new())
    let prog = lst([
      s("do"),
      lst([s("let"), s("x"), n(2)]),
      s("x"),
    ])
    let res = ev.evaluate(prog)
    check res.kind == Number
    check res.number == 2.0

  test "let pair-list binds multiple names and evaluates body":
    var ev = Evaluator(root: Env.new())
    let prog = lst([
      s("let"),
      lst([
        lst([s("pair"), s("x"), n(1)]),
        lst([s("pair"), s("y"), n(3)]),
      ]),
      s("y"),
    ])
    let res = ev.root.evaluate(prog)
    check res.kind == Number
    check res.number == 3.0
    check not ev.root.has(s("x"))
    check not ev.root.has(s("y"))

  test "fun defines a named function and calling uses param binding":
    var ev = Evaluator(root: Env.new())
    let defineId = lst([
      s("fun"),
      s("id"),
      lst([s("a")]),
      s("a"),
    ])
    discard ev.root.evaluate(defineId)
    let callId = lst([
      s("id"),
      n(7),
    ])
    let res = ev.root.evaluate(callId)
    check res.kind == Number
    check res.number == 7.0

  test "lambda creates a function value":
    var ev = Evaluator(root: Env.new())
    let lam = lst([
      s("lambda"),
      lst([s("x")]),
      s("x"),
    ])
    let res = ev.root.evaluate(lam)
    check res.kind == Function
    check res.function.name == "<lambda>"

  test "do returns last expression":
    var ev = Evaluator(root: Env.new())
    let prog = lst([
      s("do"),
      b(true),
      b(false),
    ])
    let res = ev.root.evaluate(prog)
    check res.kind == Boolean
    check res.isTrue == false

  test "empty list raises":
    var ev = Evaluator(root: Env.new())
    let emptyCall = lst([])
    expect(EvalError):
      discard ev.root.evaluate(emptyCall)
