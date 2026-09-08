import std/[strformat, tables]

import syntax
import values
export values

type NativeModule* = object
  name*: string
  exports*: Table[string, Value]
  ## Static signatures are deliberately kept beside their runtime exports so a
  ## host can opt a native module into checked Owl without changing its runtime
  ## implementation.
  types*: Table[string, TypeSyntaxNode]

proc newEnvironment*(
    parent: Environment = nil, fallback: Environment = nil
): Environment {.raises: [].} =
  let nativeModules =
    if parent != nil:
      parent.nativeModules
    elif fallback != nil:
      fallback.nativeModules
    else:
      new Table[string, Value]
  # `bindings` is left default so it allocates on first use. Most call frames
  # bind only a parameter or two, and many bind nothing at all.
  result = Environment(
    parent: parent,
    fallback: fallback,
    nativeModules: nativeModules,
  )
  if parent != nil:
    result.evaluator = parent.evaluator
    result.topLevelEvaluator = parent.topLevelEvaluator
    result.typedModuleRegistrar = parent.typedModuleRegistrar
    result.commandCaller = parent.commandCaller

proc child*(env: Environment): Environment {.raises: [].} =
  newEnvironment(env, env.fallback)

proc define*(env: Environment, symbol: string, value: Value) {.raises: [].} =
  env.bindings[symbol] = value

proc defineNative*(
    env: Environment, symbol: string, command: NativeCommand
) {.raises: [].} =
  env.define(symbol, nativeCommand(command))

proc nativeModule*(name: string): NativeModule {.raises: [].} =
  NativeModule(
    name: name,
    exports: initTable[string, Value](),
    types: initTable[string, TypeSyntaxNode](),
  )

proc define*(module: var NativeModule, symbol: string, value: Value) {.raises: [].} =
  module.exports[symbol] = value

proc define*(
    module: var NativeModule, symbol: string, value: Value,
    typeDef: TypeSyntaxNode,
) {.raises: [].} =
  module.define(symbol, value)
  module.types[symbol] = typeDef

proc defineNative*(
    module: var NativeModule, symbol: string, command: NativeCommand
) {.raises: [].} =
  module.define(symbol, nativeCommand(command))

proc defineNative*(
    module: var NativeModule, symbol: string, command: NativeCommand,
    typeDef: TypeSyntaxNode,
) {.raises: [].} =
  module.define(symbol, nativeCommand(command), typeDef)

proc moduleValue*(module: NativeModule): Value {.raises: [].} =
  record(module.exports)

proc registerModule*(
    env: Environment, name: string, exports: Value
) {.raises: [EvaluatorError].} =
  if exports.kind != Record:
    raise newException(EvaluatorError, "native module exports must be a dictionary")
  env.nativeModules[][name] = exports

proc registerModule*(env: Environment, module: NativeModule) {.raises: [].} =
  env.nativeModules[][module.name] = module.moduleValue()

proc hasNativeModule*(env: Environment, name: string): bool {.raises: [].} =
  not env.nativeModules.isNil and env.nativeModules[].hasKey(name)

proc getNativeModule*(
    env: Environment, name: string
): Value {.raises: [EvaluatorError].} =
  if not env.hasNativeModule(name):
    raise newException(EvaluatorError, &"unknown native module: {name}")
  env.nativeModules[].getOrDefault(name)

template native*(target: untyped, symbol: string, body: untyped) =
  ## Define a native command on an environment, a `NativeModule`, or anything
  ## else with a `defineNative`. The body sees `env`, `arguments`, `layout`,
  ## and `bodyNodes`; any other exception it raises becomes an
  ## `EvaluatorError`.
  mixin defineNative
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
  if env.fallback != nil:
    return env.fallback.find(symbol)
  result = nil

proc contains*(env: Environment, symbol: string): bool {.raises: [].} =
  env.find(symbol) != nil

proc get*(env: Environment, symbol: string): Value {.raises: [EvaluatorError].} =
  let owner = env.find(symbol)
  if owner == nil:
    raise newException(EvaluatorError, &"unknown symbol: {symbol}")
  result = owner.bindings.getOrDefault(symbol)

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
  env.eval(script(body))

proc evalTopLevel*(
    env: Environment, node: SyntaxNode
): Value {.raises: [EvaluatorError].} =
  if env.topLevelEvaluator == nil:
    raise newException(EvaluatorError, "environment has no top-level evaluator")
  env.topLevelEvaluator(env, node)

proc registerTypedModule*(
    env: Environment, name: string, exports: seq[string]
) {.raises: [].} =
  if env.typedModuleRegistrar != nil:
    env.typedModuleRegistrar(name, exports)

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
