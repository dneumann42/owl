import std/[strformat]

import commands
import environment
import parser
import syntax
import values
export environment

const PreludeSource = staticRead("prelude.nest")

type Evaluator* = object
  env*: Environment

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
  local.define("block", syntaxValue(script(body), env))
  local.define("layout", text($layout))
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
    if env.contains(node.callee.symbol):
      let value = env.get(node.callee.symbol)
      if value.kind != Command:
        return value

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

proc evalCore(env: Environment, node: SyntaxNode): Value {.raises: [EvaluatorError].} =
  case node.kind
  of Script:
    result = env.evalBlock(node.statements)
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

proc loadPrelude(env: Environment) {.raises: [EvaluatorError].} =
  try:
    discard env.eval(parse(PreludeSource, "crow/prelude.nest"))
  except CatchableError as error:
    raise newException(EvaluatorError, "invalid prelude: " & error.msg)

proc init*(T: typedesc[Evaluator]): T {.raises: [EvaluatorError].} =
  result = T(env: newEnvironment())
  result.env.evaluator = evalCore
  result.env.commandCaller = callCommandValue
  result.env.addStandardCommands()
  result.env.loadPrelude()

proc exec*(
    evaluator: var Evaluator, node: SyntaxNode
): Value {.raises: [EvaluatorError].} =
  evaluator.env.eval(node)

proc defineNative*(
    evaluator: var Evaluator, symbol: string, command: NativeCommand
) {.raises: [].} =
  evaluator.env.defineNative(symbol, command)

template native*(evaluator: var Evaluator, symbol: string, body: untyped) =
  evaluator.defineNative(symbol, proc(
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
