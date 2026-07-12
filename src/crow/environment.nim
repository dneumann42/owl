import std/[strformat, tables]

import values
export values

proc newEnvironment*(parent: Environment = nil): Environment {.raises: [].} =
  Environment(parent: parent, bindings: initTable[string, Value]())

proc child*(env: Environment): Environment {.raises: [].} =
  newEnvironment(env)

proc define*(env: Environment, symbol: string, value: Value) {.raises: [].} =
  env.bindings[symbol] = value

proc find*(env: Environment, symbol: string): Environment {.raises: [].} =
  var current = env
  while current != nil:
    if current.bindings.hasKey(symbol):
      return current
    current = current.parent
  nil

proc contains*(env: Environment, symbol: string): bool {.raises: [].} =
  env.find(symbol) != nil

proc get*(env: Environment, symbol: string): Value {.raises: [EvaluatorError].} =
  let owner = env.find(symbol)
  if owner == nil:
    raise newException(EvaluatorError, &"unknown symbol: {symbol}")
  owner.bindings.getOrDefault(symbol)

proc set*(env: Environment, symbol: string, value: Value) {.raises: [].} =
  let owner = env.find(symbol)
  if owner == nil:
    env.define(symbol, value)
  else:
    owner.bindings[symbol] = value
