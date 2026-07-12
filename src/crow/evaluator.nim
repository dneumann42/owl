import std/[strformat, strutils, tables]

import environment
import parser
import syntax
import values

const PreludeSource = staticRead("prelude.nest")

type Evaluator* = object
  env*: Environment

proc eval*(env: Environment, node: SyntaxNode): Value {.raises: [EvaluatorError].}

proc evalBlock(
    env: Environment, body: seq[SyntaxNode]
): Value {.raises: [EvaluatorError].} =
  result = nothing()
  for node in body:
    result = env.eval(node)

proc requireSymbol(
    node: SyntaxNode, role: string
): string {.raises: [EvaluatorError].} =
  if node.kind != Symbol:
    raise newException(EvaluatorError, &"expected {role} to be a symbol")
  node.symbol

proc requireNumber(value: Value): float64 {.raises: [EvaluatorError].} =
  if value.kind != Number:
    raise newException(EvaluatorError, &"expected number, got {value}")
  value.number

proc requireSyntax(value: Value): SyntaxNode {.raises: [EvaluatorError].} =
  if value.kind != Syntax:
    raise newException(EvaluatorError, &"expected syntax, got {value}")
  value.syntax

proc requireList(value: Value): seq[Value] {.raises: [EvaluatorError].} =
  if value.kind != List:
    raise newException(EvaluatorError, &"expected list, got {value}")
  value.items

proc requireText(value: Value): string {.raises: [EvaluatorError].} =
  if value.kind != Text:
    raise newException(EvaluatorError, &"expected text, got {value}")
  value.text

proc defineClosure(
    env: Environment,
    arguments: seq[SyntaxNode],
    body: seq[SyntaxNode],
    evaluatesArguments, acceptsBlock: bool,
): Value {.raises: [EvaluatorError].} =
  if arguments.len == 0:
    raise newException(EvaluatorError, "expected command name")
  let commandName = arguments[0].requireSymbol("command name")
  var parameters: seq[string]
  for argument in arguments[1 .. ^1]:
    parameters.add argument.requireSymbol("parameter")
  result = closureCommand(parameters, body, env, evaluatesArguments, acceptsBlock)
  env.define(commandName, result)

proc commandCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  env.defineClosure(arguments, body, evaluatesArguments = false, acceptsBlock = false)

proc blockCommandCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  env.defineClosure(arguments, body, evaluatesArguments = false, acceptsBlock = true)

proc funCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  env.defineClosure(arguments, body, evaluatesArguments = true, acceptsBlock = false)

proc defineCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard arguments
  discard layout
  result = nothing()
  for node in body:
    if node.kind != Binding:
      raise newException(EvaluatorError, "define body entries must be bindings")
    result = env.eval(node.value)
    env.define(node.bindingSymbol, result)

proc evalCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  result = nothing()
  for argument in arguments:
    let value = env.eval(argument)
    result =
      if value.kind == Syntax:
        env.eval(value.syntax)
      else:
        value

proc printCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  var parts: seq[string]
  result = nothing()
  for argument in arguments:
    result = env.eval(argument)
    parts.add $result
  echo parts.join("")

proc arithmeticCommand(op: string): NativeCommand {.raises: [].} =
  result = proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard layout
    discard body
    if arguments.len == 0:
      raise newException(EvaluatorError, &"{op} expects arguments")
    result = number(env.eval(arguments[0]).requireNumber())
    for argument in arguments[1 .. ^1]:
      let rhs = env.eval(argument).requireNumber()
      case op
      of "+":
        result = number(result.number + rhs)
      of "-":
        result = number(result.number - rhs)
      of "*":
        result = number(result.number * rhs)
      of "/":
        result = number(result.number / rhs)
      else:
        raise newException(EvaluatorError, &"unknown arithmetic operator: {op}")

proc compareCommand(op: string): NativeCommand {.raises: [].} =
  result = proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard layout
    discard body
    if arguments.len != 2:
      raise newException(EvaluatorError, &"{op} expects two arguments")
    let left = env.eval(arguments[0])
    let right = env.eval(arguments[1])
    result =
      case op
      of "=":
        boolean($left == $right)
      of "<":
        boolean(left.requireNumber() < right.requireNumber())
      of "<=":
        boolean(left.requireNumber() <= right.requireNumber())
      of ">":
        boolean(left.requireNumber() > right.requireNumber())
      of ">=":
        boolean(left.requireNumber() >= right.requireNumber())
      else:
        raise newException(EvaluatorError, &"unknown comparison operator: {op}")

proc whenCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  if arguments.len != 1:
    raise newException(EvaluatorError, "when expects one condition")
  if env.eval(arguments[0]).isTruthy:
    env.evalBlock(body)
  else:
    nothing()

proc pickCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 3:
    raise
      newException(EvaluatorError, "pick expects condition, true value, false value")
  if env.eval(arguments[0]).isTruthy:
    env.eval(arguments[1])
  else:
    env.eval(arguments[2])

proc emptyListCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 0:
    raise newException(EvaluatorError, "list expects no arguments")
  list(@[])

proc emptyDictCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard env
  discard layout
  discard body
  if arguments.len != 0:
    raise newException(EvaluatorError, "dict expects no arguments")
  dictionary(initTable[string, Value]())

proc consCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 2:
    raise newException(EvaluatorError, "cons expects value and list")
  result = list(@[env.eval(arguments[0])])
  result.items.add env.eval(arguments[1]).requireList()

proc firstCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "first expects one list")
  let items = env.eval(arguments[0]).requireList()
  if items.len == 0:
    raise newException(EvaluatorError, "first expects a non-empty list")
  items[0]

proc restCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "rest expects one list")
  let items = env.eval(arguments[0]).requireList()
  if items.len == 0:
    list(@[])
  else:
    list(items[1 .. ^1])

proc emptyCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "empty? expects one list")
  boolean(env.eval(arguments[0]).requireList().len == 0)

proc notCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "not expects one value")
  boolean(not env.eval(arguments[0]).isTruthy)

proc dictPutCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 3:
    raise newException(EvaluatorError, "dict-put expects dict, key, and value")
  let original = env.eval(arguments[0])
  if original.kind != Dictionary:
    raise newException(EvaluatorError, &"expected dictionary, got {original}")
  result = original
  result.entries[env.eval(arguments[1]).requireText()] = env.eval(arguments[2])

proc statementsCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "statements expects script syntax")
  let node = env.eval(arguments[0]).requireSyntax()
  if node.kind != Script:
    raise newException(EvaluatorError, "statements expects script syntax")
  var items: seq[Value]
  for statement in node.statements:
    items.add syntaxValue(statement)
  list(items)

proc bodyOfCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 2:
    raise newException(EvaluatorError, "body-of expects script syntax and tag")
  let node = env.eval(arguments[0]).requireSyntax()
  let tag = env.eval(arguments[1]).requireText()
  if node.kind != Script:
    raise newException(EvaluatorError, "body-of expects script syntax")
  for statement in node.statements:
    if statement.kind == Command and statement.callee.kind == Symbol and
        statement.callee.symbol == tag:
      return syntaxValue(script(statement.body))
  syntaxValue(script(@[]))

proc commandArgCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 2:
    raise newException(EvaluatorError, "command-arg expects command syntax and index")
  let node = env.eval(arguments[0]).requireSyntax()
  let index = env.eval(arguments[1]).requireNumber().int
  if node.kind != Command or index < 0 or index >= node.arguments.len:
    raise newException(EvaluatorError, "command-arg index out of range")
  syntaxValue(node.arguments[index])

proc commandBodyCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "command-body expects command syntax")
  let node = env.eval(arguments[0]).requireSyntax()
  if node.kind != Command:
    raise newException(EvaluatorError, "command-body expects command syntax")
  syntaxValue(script(node.body))

proc bindingSymbolCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "binding-symbol expects binding syntax")
  let node = env.eval(arguments[0]).requireSyntax()
  if node.kind != Binding:
    raise newException(EvaluatorError, "binding-symbol expects binding syntax")
  text(node.bindingSymbol)

proc bindingValueCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "binding-value expects binding syntax")
  let node = env.eval(arguments[0]).requireSyntax()
  if node.kind != Binding:
    raise newException(EvaluatorError, "binding-value expects binding syntax")
  syntaxValue(node.value)

proc evalWithCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 3:
    raise newException(EvaluatorError, "eval-with expects symbol, value, and body")
  let symbolNode = env.eval(arguments[0]).requireSyntax()
  let value = env.eval(arguments[1])
  let bodyNode = env.eval(arguments[2]).requireSyntax()
  let local = env.child()
  local.define(symbolNode.requireSymbol("binding symbol"), value)
  if bodyNode.kind == Script:
    local.evalBlock(bodyNode.statements)
  else:
    local.eval(bodyNode)

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
        syntaxValue(arguments[index])
    local.define(parameter, value)
  local.define("block", syntaxValue(script(body)))
  local.define("layout", text($layout))
  local.evalBlock(command.body)

proc evalCommandNode(
    env: Environment, node: SyntaxNode
): Value {.raises: [EvaluatorError].} =
  if node.callee.kind == Symbol and node.arguments.len == 0 and node.layout == NoLayout:
    let parsed = parseNumber(node.callee.symbol)
    if parsed.ok:
      return parsed.value
    if node.callee.symbol == "true" or node.callee.symbol == "T":
      return boolean(true)
    if node.callee.symbol == "false" or node.callee.symbol == "F":
      return boolean(false)
    if env.contains(node.callee.symbol):
      let value = env.get(node.callee.symbol)
      if value.kind != Command:
        return value

  let callee = env.eval(node.callee)
  if callee.kind != Command:
    raise newException(EvaluatorError, &"callee is not a command: {callee}")

  case callee.command.kind
  of NativeCommandKind:
    callee.command.native(env, node.arguments, node.layout, node.body)
  of ClosureCommandKind:
    env.callClosure(callee.command, node.arguments, node.layout, node.body)

proc eval*(env: Environment, node: SyntaxNode): Value {.raises: [EvaluatorError].} =
  case node.kind
  of Script:
    result = env.evalBlock(node.statements)
  of Binding:
    result = syntaxValue(node)
  of Command:
    result = env.evalCommandNode(node)
  of Symbol:
    let parsed = parseNumber(node.symbol)
    if parsed.ok:
      result = parsed.value
    elif node.symbol == "true" or node.symbol == "T":
      result = boolean(true)
    elif node.symbol == "false" or node.symbol == "F":
      result = boolean(false)
    else:
      result = env.get(node.symbol)
  of String:
    result = text(node.stringValue)

proc addBuiltins(env: Environment) {.raises: [].} =
  env.define("command", nativeCommand(commandCommand))
  env.define("block-command", nativeCommand(blockCommandCommand))
  env.define("fun", nativeCommand(funCommand))
  env.define("define", nativeCommand(defineCommand))
  env.define("eval", nativeCommand(evalCommand))
  env.define("print", nativeCommand(printCommand))
  env.define("when", nativeCommand(whenCommand))
  env.define("nothing", nothing())
  env.define("pick", nativeCommand(pickCommand))
  env.define("list", nativeCommand(emptyListCommand))
  env.define("dict", nativeCommand(emptyDictCommand))
  env.define("cons", nativeCommand(consCommand))
  env.define("first", nativeCommand(firstCommand))
  env.define("rest", nativeCommand(restCommand))
  env.define("empty?", nativeCommand(emptyCommand))
  env.define("not", nativeCommand(notCommand))
  env.define("dict-put", nativeCommand(dictPutCommand))
  env.define("statements", nativeCommand(statementsCommand))
  env.define("body-of", nativeCommand(bodyOfCommand))
  env.define("command-arg", nativeCommand(commandArgCommand))
  env.define("command-body", nativeCommand(commandBodyCommand))
  env.define("binding-symbol", nativeCommand(bindingSymbolCommand))
  env.define("binding-value", nativeCommand(bindingValueCommand))
  env.define("eval-with", nativeCommand(evalWithCommand))
  for op in ["+", "-", "*", "/"]:
    env.define(op, nativeCommand(arithmeticCommand(op)))
  for op in ["=", "<", "<=", ">", ">="]:
    env.define(op, nativeCommand(compareCommand(op)))

proc loadPrelude(env: Environment) {.raises: [EvaluatorError].} =
  try:
    discard env.eval(parse(PreludeSource))
  except CatchableError as error:
    raise newException(EvaluatorError, "invalid prelude: " & error.msg)

proc init*(T: typedesc[Evaluator]): T {.raises: [EvaluatorError].} =
  result = T(env: newEnvironment())
  result.env.addBuiltins()
  result.env.loadPrelude()

proc exec*(
    evaluator: var Evaluator, node: SyntaxNode
): Value {.raises: [EvaluatorError].} =
  evaluator.env.eval(node)
