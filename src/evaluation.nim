# The OWL virtual machine

## Default to system endianness (typically little endian)

import objects, sugar, sequtils

type
  Evaluator* = object
    root*: Env

  EvalError* = object of CatchableError

proc evaluate*(ev: Env, o: Object): Object {.gcsafe.}
proc evaluate*(ev: Env, fn: Func, params: seq[Object]): Object {.gcsafe.}
proc evaluateLet*(ev: Env, xs: Object): Object {.gcsafe.}
proc evaluateRecDefinition*(ev: Env, xs: Object): Object {.gcsafe.}

proc evaluateSymbol*(ev: Env, sym: Object): Object {.gcsafe.} =
  assert(sym.kind == Symbol)
  if not ev.has(sym):
    raise EvalError.newException("Undefined symbol '" & sym.symbol & "'")
  return ev.find(sym)

proc specialFun*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  if items.len < 4:
    raise EvalError.newException("fun requires a name, params, and body")
  if items[1].kind != Symbol:
    raise EvalError.newException("fun requires a symbol name")
  if items[2].kind != List:
    raise EvalError.newException("fun requires a parameter list")
  let id = items[1]
  let fn = Func(scope: ev.push(), name: $id, params: items[2].items, body: items[3])
  result = ev.add(id, fn)

proc specialLambda*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  if items.len != 3:
    raise EvalError.newException("lambda requires parameters and a body")
  if items[1].kind != List:
    raise EvalError.newException("lambda parameter list must be a list")
  result = Object(
    kind: Function,
    function: Func(scope: ev, name: "<lambda>", params: items[1].items, body: items[2]),
  )

proc specialDo*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  if items.len <= 1:
    return Object(kind: Nothing)
  for i in 1 ..< items.len:
    result = ev.evaluate(items[i])

proc specialQuote*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  if items.len != 2:
    raise EvalError.newException("quote expects a single expression")
  result = items[1]

proc specialList*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  result = Object(
    kind: List,
    items: collect(
      for i in items[1 ..< items.len]:
        ev.evaluate(i)
    ),
  )

proc specialLet*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  result = ev.evaluateLet(Object(kind: List, items: items))

proc specialRecord*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  result = ev.evaluateRecDefinition(Object(kind: List, items: items))

proc specialAnd*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  result = 
    if ev.evaluate(items[1]).toBool.isTrue:
      ev.evaluate(items[2])
    else:
      Object(kind: Nothing)

proc specialOr*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  let a = ev.evaluate(items[1])
  result = 
    if a.toBool.isTrue: a else: ev.evaluate(items[2])

proc specialIf*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  assert(items.len > 0, "If expects condition, consequent and optional alternative")
  {.cast(gcsafe).}:
    echo "IF: ", items
  let cond = items[0]

proc evaluateList*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  if items.len == 0:
    # TODO: catch this after parsing in a new pass, so its raised before evaluation
    raise EvalError.newException("Unexpected empty list.")
  let callable = items[0]
  if ev.specialForms.hasKey($callable):
    return ev.specialForms[$callable](ev, items)
  var first = ev.evaluate(callable)
  let params = collect:
    for x in items[1 ..^ 1]:
      ev.evaluate(x)
  if first.kind == ForeignFunction:
    return first.ffunction(ev, params)
  if first.kind == Function:
    return ev.evaluate(first.function, params)
  raise EvalError.newException("Expected function to call, but got '" & $first & "'")

proc evaluateRecDefinition*(ev: Env, xs: Object): Object {.gcsafe.} =
  result = Object(kind: Record)
  for i in 1 ..< xs.items.len:
    let pair = xs.items[i]
    if pair.kind != List or pair.items[0].kind != Symbol or
        pair.items[0].symbol != "pair":
      raise EvalError.newException("Invalid let binding, expected pair")
    let sym = pair.items[1]
    let value = ev.evaluate(pair.items[2])
    {.cast(gcsafe).}:
      result.rec[sym] = value

proc evaluateLet*(ev: Env, xs: Object): Object {.gcsafe.} =
  if xs.items[1].kind == Symbol:
    let sym = xs.items[1]
    let value = ev.evaluate(xs.items[2])
    ev[sym] = value
    return value
  elif xs.items[1].kind == List:
    let ev = ev.push()
    for pair in xs.items[1].items:
      if pair.kind != List or pair.items[0].kind != Symbol or
          pair.items[0].symbol != "pair":
        raise EvalError.newException("Invalid let binding, expected pair")
      let sym = pair.items[1]
      let value = ev.evaluate(pair.items[2])
      ev[sym] = value
    return ev.evaluate(xs.items[2])
  raise EvalError.newException("Invalid let binding")

proc evaluate*(ev: Env, fn: Func, params: seq[Object]): Object {.gcsafe.} =
  let env = fn.scope
  for i in 0 ..< fn.params.len:
    let key = fn.params[i]
    let value = params[i]
    env.add(key, value)
  result = env.evaluate(fn.body)

proc evaluate*(ev: Env, o: Object): Object {.gcsafe.} =
  case o.kind
  of Nothing, String, Number, Boolean, Record, Function, ForeignFunction:
    return o
  of Symbol:
    return ev.evaluateSymbol(o)
  of List:
    return ev.evaluateList(o.items)

proc evaluate*(eval: var Evaluator, o: Object): Object {.gcsafe.} =
  result = eval.root.evaluate(o)
