
import unittest
import objects
import evaluation
import libraries

proc s(x: string): Object =
  Object(kind: Symbol, symbol: x)

proc n(x: float64): Object =
  Object(kind: Number, number: x)

proc b(x: bool): Object =
  Object(kind: Boolean, isTrue: x)

proc lst(xs: openArray[Object]): Object =
  Object(kind: List, items: @xs)

proc evaluator(): Evaluator =
  result = Evaluator(root: Env.new())
  result.root.loadCoreLibraries()

suite "Evaluator":
  test "let single binding sets and returns value":
    var ev = evaluator()
    let prog = lst([
      s("do"),
      lst([s("let"), s("x"), n(2)]),
      s("x"),
    ])
    let res = ev.evaluate(prog)
    check res.kind == Number
    check res.number == 2.0

  test "let pair-list binds multiple names and evaluates body":
    var ev = evaluator()
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
    var ev = evaluator()
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
    var ev = evaluator()
    let lam = lst([
      s("lambda"),
      lst([s("x")]),
      s("x"),
    ])
    let res = ev.root.evaluate(lam)
    check res.kind == Function
    check res.function.name == "<lambda>"

  test "do returns last expression":
    var ev = evaluator()
    let prog = lst([
      s("do"),
      b(true),
      b(false),
    ])
    let res = ev.root.evaluate(prog)
    check res.kind == Boolean
    check res.isTrue == false

  test "empty list raises":
    var ev = evaluator()
    let emptyCall = lst([])
    expect(EvalError):
      discard ev.root.evaluate(emptyCall)

  test "quote returns unevaluated list":
    var ev = evaluator()
    let prog = lst([
      s("quote"),
      lst([s("+"), n(1), n(2)]),
    ])
    let res = ev.root.evaluate(prog)
    check res.kind == List
    check res.items.len == 3
    check res.items[0].kind == Symbol
    check res.items[0].symbol == "+"

  test "quote symbol skips lookup":
    var ev = evaluator()
    let prog = lst([
      s("quote"),
      s("missing"),
    ])
    let res = ev.root.evaluate(prog)
    check res.kind == Symbol
    check res.symbol == "missing"

  test "quote nested list preserves structure":
    var ev = evaluator()
    let inner = lst([s("*"), n(2), n(3)])
    let prog = lst([
      s("quote"),
      lst([
        inner,
        s("x"),
      ]),
    ])
    let res = ev.root.evaluate(prog)
    check res.kind == List
    check res.items.len == 2
    check res.items[0] == inner
    check res.items[1].kind == Symbol
    check res.items[1].symbol == "x"

  test "foreign functions receive raw args without double evaluation":
    var ev = evaluator()
    var evalCount = 0
    var capturedLen = 0
    var capturedKind = Nothing
    var capturedNumber = 0.0

    proc bump(env: Env, args: seq[Object]): Object {.gcsafe.} =
      inc evalCount
      Object(kind: Number, number: float64(evalCount))

    proc capture(env: Env, args: seq[Object]): Object {.gcsafe.} =
      capturedLen = args.len
      if args.len > 0:
        capturedKind = args[0].kind
        if capturedKind == Number:
          capturedNumber = args[0].number
      Object(kind: Nothing)

    ev.root.add(s("bump"), ffunc bump)
    ev.root.add(s("capture"), ffunc capture)

    let prog = lst([
      s("capture"),
      lst([s("bump")]),
    ])

    discard ev.root.evaluate(prog)
    check evalCount == 1
    check capturedLen == 1
    check capturedKind == Number
    check capturedNumber == 1.0
