import std/[strformat, tables]

import commands, environment, parser, syntax, values

const PreludeSource = staticRead("prelude.owl")

type Evaluator* = object
  env*: Environment

let
  emptyScript = script(@[])
  layoutNames = [
    NoLayout: text("NoLayout"),
    ColonLayout: text("ColonLayout"),
    ContinuationLayout: text("ContinuationLayout"),
  ]

proc callClosure(
    env: Environment,
    command: CommandValue,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  if command.parameters.len != arguments.len:
    raise newException(
      EvaluatorError,
      &"expected {command.parameters.len} arguments, got {arguments.len}",
    )
  if body.len > 0 and not command.acceptsBlock:
    raise newException(EvaluatorError, "command does not accept a block")

  let parent = if command.evaluatesArguments: command.captured else: env
  let local = parent.child()
  for index, parameter in command.parameters:
    let value =
      if command.evaluatesArguments:
        env.eval(arguments[index])
      else:
        syntaxValue(arguments[index], env)
    local.define(parameter, value)
  # Binding these costs an allocation each, and almost no closure reads them,
  # so `closureCommand` works out up front whether the body mentions them.
  if command.usesBlock:
    local.define("block", syntaxValue(
      if body.len == 0: emptyScript else: script(body), env))
  if command.usesLayout:
    local.define("layout", layoutNames[layout])
  local.evalBlock(command.body)

proc literalValue(symbol: string): tuple[ok: bool, value: Value] {.raises: [].} =
  let parsed = parseNumber(symbol)
  if parsed.ok:
    (true, parsed.value)
  elif symbol == "true" or symbol == "T":
    (true, boolean(true))
  elif symbol == "false" or symbol == "F":
    (true, boolean(false))
  else:
    (false, nothing())

proc evalCommandNode(
    env: Environment, node: SyntaxNode
): Value {.raises: [EvaluatorError].} =
  if node.callee.kind == Symbol and node.arguments.len == 0 and node.layout == NoLayout:
    let literal = literalValue(node.callee.symbol)
    if literal.ok:
      return literal.value
    let owner = env.find(node.callee.symbol)
    if owner != nil:
      let value = owner.bindings.getOrDefault(node.callee.symbol)
      if value.kind != Command:
        return value
      return env.call(value.command, node.arguments, node.layout, node.body)

  let callee = env.eval(node.callee)
  if callee.kind != Command:
    raise newException(EvaluatorError, &"callee is not a command: {callee}")

  env.call(callee.command, node.arguments, node.layout, node.body)

proc callCommandValue(
    env: Environment,
    command: CommandValue,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  case command.kind
  of NativeCommandKind:
    command.native(env, arguments, layout, body)
  of ClosureCommandKind:
    env.callClosure(command, arguments, layout, body)

proc evalNode(env: Environment, node: SyntaxNode): Value {.raises: [EvaluatorError].} =
  try:
    case node.kind
    of Script:
      result = nothing()
      for statement in node.statements:
        result = env.eval(statement)
    of Binding:
      result = syntaxValue(node, env)
    of Command:
      result = env.evalCommandNode(node)
    of Symbol:
      let literal = literalValue(node.symbol)
      if literal.ok:
        result = literal.value
      else:
        result = env.get(node.symbol)
    of String:
      result = text(node.stringValue)
  except EvaluatorError as error:
    if not node.isNil and node.kind != Script:
      let label =
        case node.kind
        of Command:
          $node.callee
        of Binding:
          node.bindingSymbol
        of Symbol:
          node.symbol
        of String:
          "string"
        of Script:
          ""
      error.addFrame(node.pos, label)
    raise error

proc evalTopLevelNode(env: Environment, node: SyntaxNode): Value {.raises: [EvaluatorError].} =
  if node.kind != Script:
    return env.eval(node)

  result = nothing()
  for statement in node.statements:
    if statement.kind != Binding:
      result = env.eval(statement)
      continue
    if env.bindings.hasKey(statement.bindingSymbol):
      raise newException(
        EvaluatorError, &"symbol already defined: {statement.bindingSymbol}"
      )
    result = env.eval(statement.value)
    env.define(statement.bindingSymbol, result)

proc loadPrelude(env: Environment) {.raises: [EvaluatorError].} =
  try:
    discard env.eval(parse(PreludeSource, "owl/prelude.owl"))
  except CatchableError as error:
    raise newException(EvaluatorError, "invalid prelude: " & error.msg)

proc init*(T: typedesc[Evaluator]): T {.raises: [EvaluatorError].} =
  result = T(env: newEnvironment())
  result.env.evaluator = evalNode
  result.env.topLevelEvaluator = evalTopLevelNode
  result.env.commandCaller = callCommandValue
  result.env.addStandardCommands()
  result.env.loadPrelude()

proc exec*(
    evaluator: var Evaluator, node: SyntaxNode
): Value {.raises: [EvaluatorError].} =
  evaluator.env.evalTopLevel(node)

proc defineNative*(
    evaluator: var Evaluator, symbol: string, command: NativeCommand
) {.raises: [].} =
  evaluator.env.defineNative(symbol, command)

proc registerModule*(
    evaluator: var Evaluator, name: string, exports: Value
) {.raises: [EvaluatorError].} =
  evaluator.env.registerModule(name, exports)

proc registerModule*(evaluator: var Evaluator, module: NativeModule) {.raises: [].} =
  evaluator.env.registerModule(module)
