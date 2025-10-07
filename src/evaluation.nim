# The OWL virtual machine

## Default to system endianness (typically little endian)

import objects, sugar

type
  Evaluator* = object
    root*: Env

  EvalError* = object of CatchableError

proc evaluateSymbol*(ev: Env, sym: Object): Object {.gcsafe.} =
  assert(sym.kind == Symbol)
  if not ev.has(sym):
    raise EvalError.newException("Undefined symbol '" & sym.symbol & "'")
  return ev.find(sym)

proc evaluate*(ev: Env, o: Object): Object {.gcsafe.}

proc evaluateList*(ev: Env, items: seq[Object]): Object {.gcsafe.} =
  if items.len == 0:
    # TODO: catch this after parsing in a new pass, so its raised before evaluation
    raise EvalError.newException("Unexpected empty list.")
  var first = ev.evaluateSymbol(items[0])

  if first.kind == ForeignFunction:
    let args = collect:
      for x in items[1 ..^ 1]:
        ev.evaluate(x)
    result = first.ffunction(ev, args)
    return

  if first.kind != Function:
    raise EvalError.newException("Expected function to call, but got '" & $first & "'")

proc evaluate*(ev: Env, o: Object): Object {.gcsafe.} =
  case o.kind
  of Nothing, Number, Boolean, Record, Function, ForeignFunction:
    return o
  of Symbol:
    return ev.evaluateSymbol(o)
  of List:
    return ev.evaluateList(o.items)

proc evaluate*(eval: var Evaluator, o: Object): Object {.gcsafe.} =
  result = eval.root.evaluate(o)
