import std/[strformat, tables]

import syntax
import values
export values

proc newEnvironment*(parent: Environment = nil): Environment {.raises: [].} =
  let evaluator =
    if parent == nil:
      nil
    else:
      parent.evaluator
  let commandCaller =
    if parent == nil:
      nil
    else:
      parent.commandCaller
  Environment(
    parent: parent,
    bindings: initTable[string, Value](),
    evaluator: evaluator,
    commandCaller: commandCaller,
  )

proc child*(env: Environment): Environment {.raises: [].} =
  newEnvironment(env)

proc define*(env: Environment, symbol: string, value: Value) {.raises: [].} =
  env.bindings[symbol] = value

proc defineNative*(
    env: Environment, symbol: string, command: NativeCommand
) {.raises: [].} =
  env.define(symbol, nativeCommand(command))

template native*(target: Environment, symbol: string, body: untyped) =
  target.defineNative(symbol, proc(
      env {.inject.}: Environment,
      arguments {.inject.}: seq[SyntaxNode],
      layout {.inject.}: LayoutKind,
      bodyNodes {.inject.}: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    try:
      body
    except EvaluatorError as error:
      raise error
    except CatchableError as error:
      raise newException(EvaluatorError, error.msg)
  )

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

proc eval*(env: Environment, node: SyntaxNode): Value {.raises: [EvaluatorError].} =
  if env.evaluator == nil:
    raise newException(EvaluatorError, "environment has no evaluator")
  env.evaluator(env, node)

proc evalBlock*(
    env: Environment, body: seq[SyntaxNode]
): Value {.raises: [EvaluatorError].} =
  result = nothing()
  for node in body:
    result = env.eval(node)

proc call*(
    env: Environment,
    command: CommandValue,
    arguments: seq[SyntaxNode] = @[],
    layout: LayoutKind = NoLayout,
    body: seq[SyntaxNode] = @[],
): Value {.raises: [EvaluatorError].} =
  if env.commandCaller == nil:
    raise newException(EvaluatorError, "environment cannot call commands")
  env.commandCaller(env, command, arguments, layout, body)
