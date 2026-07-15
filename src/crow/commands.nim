import std/[macros, os, rdstdin, strformat, strutils, tables]

import environment
import parser
import syntax
import values

type CommandRegistration = object
  name: string
  command: NativeCommand

var commandRegistry: seq[CommandRegistration]

macro stdCommand*(name: static[string], node: untyped): untyped =
  let procName = node[0]
  result = newStmtList(
    node,
    quote do:
      commandRegistry.add CommandRegistration(name: `name`, command: `procName`)
    ,
  )

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

proc syntaxEnvironment(
    value: Value, fallback: Environment
): Environment {.raises: [].} =
  if value.kind == Syntax and value.syntaxEnv != nil: value.syntaxEnv else: fallback

proc requireList(value: Value): seq[Value] {.raises: [EvaluatorError].} =
  if value.kind != List:
    raise newException(EvaluatorError, &"expected list, got {value}")
  value.items

proc requireDictionary(value: Value): Table[string, Value] {.raises: [EvaluatorError].} =
  if value.kind != Dictionary:
    raise newException(EvaluatorError, &"expected dictionary, got {value}")
  value.entries

proc requireText(value: Value): string {.raises: [EvaluatorError].} =
  if value.kind != Text:
    raise newException(EvaluatorError, &"expected text, got {value}")
  value.text

proc field(value: Value, name: string): Value {.raises: [EvaluatorError].} =
  let entries = value.requireDictionary()
  if not entries.hasKey(name):
    raise newException(EvaluatorError, &"missing field: {name}")
  entries.getOrDefault(name)

proc optionalField(value: Value, name: string): Value {.raises: [].} =
  if value.kind == Dictionary and value.entries.hasKey(name):
    value.entries.getOrDefault(name)
  else:
    nothing()

proc callOptionalField(
    env: Environment,
    receiver: Value,
    name: string,
): Value {.raises: [EvaluatorError].} =
  let fieldValue = receiver.optionalField(name)
  if fieldValue.kind == Nothing:
    return receiver
  if fieldValue.kind != Command:
    raise newException(EvaluatorError, &"field is not a command: {name}")
  let value = env.call(fieldValue.command)
  if value.kind == Nothing:
    receiver
  else:
    value

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

proc setSymbol(
    env: Environment, symbol: string, value: Value
) {.raises: [EvaluatorError].} =
  if not env.contains(symbol):
    raise newException(EvaluatorError, &"cannot set unknown symbol: {symbol}")
  env.set(symbol, value)

proc setTarget(
    env: Environment, target: SyntaxNode, value: Value
) {.raises: [EvaluatorError].} =
  if target.kind == Symbol:
    env.setSymbol(target.symbol, value)
    return

  let targetValue = env.eval(target)
  let targetNode = targetValue.requireSyntax()
  let targetEnv = targetValue.syntaxEnvironment(env)
  targetEnv.setSymbol(targetNode.requireSymbol("set target"), value)

proc commandCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "command", raises: [EvaluatorError].} =
  discard layout
  env.defineClosure(arguments, body, evaluatesArguments = false, acceptsBlock = false)

proc blockCommandCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "block-command", raises: [EvaluatorError].} =
  discard layout
  env.defineClosure(arguments, body, evaluatesArguments = false, acceptsBlock = true)

proc funCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "fun", raises: [EvaluatorError].} =
  discard layout
  env.defineClosure(arguments, body, evaluatesArguments = true, acceptsBlock = false)

proc fnCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "fn", raises: [EvaluatorError].} =
  discard layout
  var parameters: seq[string]
  for argument in arguments:
    parameters.add argument.requireSymbol("parameter")
  closureCommand(parameters, body, env, evaluatesArguments = true, acceptsBlock = false)

proc lambdaCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "lambda", raises: [EvaluatorError].} =
  fnCommand(env, arguments, layout, body)

proc defineCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "define", raises: [EvaluatorError].} =
  discard arguments
  discard layout
  result = nothing()
  for node in body:
    if node.kind != Binding:
      raise newException(EvaluatorError, "define body entries must be bindings")
    result = env.eval(node.value)
    env.define(node.bindingSymbol, result)

proc setCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "set", raises: [EvaluatorError].} =
  discard layout
  if arguments.len == 2 and body.len == 0:
    result = env.eval(arguments[1])
    env.setTarget(arguments[0], result)
    return

  if arguments.len != 0:
    raise newException(EvaluatorError, "set expects a symbol/value pair or a block")

  result = nothing()
  for node in body:
    if node.kind != Binding:
      raise newException(EvaluatorError, "set body entries must be bindings")
    result = env.eval(node.value)
    env.setSymbol(node.bindingSymbol, result)

proc evalCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "eval", raises: [EvaluatorError].} =
  discard layout
  discard body
  result = nothing()
  for argument in arguments:
    let value = env.eval(argument)
    result =
      if value.kind == Syntax:
        value.syntaxEnvironment(env).eval(value.syntax)
      else:
        value

proc parseCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "parse", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "parse expects one text value")
  try:
    syntaxValue(parse(env.eval(arguments[0]).requireText()), env)
  except ParserError as error:
    raise newException(EvaluatorError, error.msg)

proc valueOfCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "value-of", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "value-of expects one symbol")
  env.get(arguments[0].requireSymbol("value name"))

proc callCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "call", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len == 0:
    raise newException(EvaluatorError, "call expects a command")
  let command = env.eval(arguments[0])
  if command.kind != Command:
    raise newException(EvaluatorError, &"call expected command, got {command}")
  env.call(command.command, arguments[1 .. ^1])

proc printCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "print", raises: [EvaluatorError].} =
  discard layout
  discard body
  var parts: seq[string]
  result = nothing()
  for argument in arguments:
    result = env.eval(argument)
    parts.add $result
  echo parts.join("")

proc errorCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "error", raises: [EvaluatorError].} =
  discard layout
  discard body
  var message = ""
  for argument in arguments:
    message.add $env.eval(argument)
  raise newException(EvaluatorError, message)

proc stdinStream(): Value {.raises: [].} =
  var entries = initTable[string, Value]()
  entries["read-line"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "stdin read-line expects no arguments")
    var line: string
    if readLineFromStdin("", line):
      text(line)
    else:
      nothing()
  )
  entries["open"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "stdin open expects no arguments")
    nothing()
  )
  entries["close"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "stdin close expects no arguments")
    nothing()
  )
  dictionary(entries)

proc stdoutStream(): Value {.raises: [].} =
  var entries = initTable[string, Value]()
  entries["write"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard layout
    discard body
    result = nothing()
    for argument in arguments:
      result = env.eval(argument)
      try:
        stdout.write($result)
      except IOError as error:
        raise newException(EvaluatorError, error.msg)
  )
  entries["write-line"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard layout
    discard body
    result = nothing()
    for argument in arguments:
      result = env.eval(argument)
      try:
        stdout.write($result)
      except IOError as error:
        raise newException(EvaluatorError, error.msg)
    try:
      stdout.write("\n")
    except IOError as error:
      raise newException(EvaluatorError, error.msg)
  )
  entries["open"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "stdout open expects no arguments")
    nothing()
  )
  entries["close"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "stdout close expects no arguments")
    nothing()
  )
  dictionary(entries)

proc fileMode(mode: string): FileMode {.raises: [EvaluatorError].} =
  case mode
  of "r", "rb":
    fmRead
  of "w", "wb":
    fmWrite
  of "a", "ab":
    fmAppend
  else:
    raise newException(EvaluatorError, &"unsupported file mode: {mode}")

proc openFileStream(path, mode: string): Value {.raises: [].} =
  var entries = initTable[string, Value]()
  var file: File
  var opened = false

  entries["open"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "file open expects no arguments")
    if not opened:
      try:
        if not open(file, path, fileMode(mode)):
          raise newException(EvaluatorError, &"could not open file: {path}")
        opened = true
      except IOError as error:
        raise newException(EvaluatorError, error.msg)
    nothing()
  )
  entries["close"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "file close expects no arguments")
    if opened:
      close(file)
      opened = false
    nothing()
  )
  entries["read-line"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "file read-line expects no arguments")
    if not opened:
      raise newException(EvaluatorError, "file is not open")
    try:
      if file.endOfFile:
        return nothing()
      text(file.readLine())
    except IOError as error:
      raise newException(EvaluatorError, error.msg)
  )
  entries["write"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard layout
    discard body
    if not opened:
      raise newException(EvaluatorError, "file is not open")
    result = nothing()
    for argument in arguments:
      result = env.eval(argument)
      try:
        file.write($result)
      except IOError as error:
        raise newException(EvaluatorError, error.msg)
  )
  entries["write-line"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard layout
    discard body
    if not opened:
      raise newException(EvaluatorError, "file is not open")
    result = nothing()
    for argument in arguments:
      result = env.eval(argument)
      try:
        file.write($result)
      except IOError as error:
        raise newException(EvaluatorError, error.msg)
    try:
      file.write("\n")
    except IOError as error:
      raise newException(EvaluatorError, error.msg)
  )
  dictionary(entries)

proc openStringStream(content: string): Value {.raises: [].} =
  var entries = initTable[string, Value]()
  var buffer = content
  var position = 0
  var opened = false

  entries["open"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "string open expects no arguments")
    position = 0
    opened = true
    nothing()
  )
  entries["close"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "string close expects no arguments")
    opened = false
    nothing()
  )
  entries["read-line"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard env
    discard layout
    discard body
    if arguments.len != 0:
      raise newException(EvaluatorError, "string read-line expects no arguments")
    if not opened:
      raise newException(EvaluatorError, "string stream is not open")
    if position >= buffer.len:
      return nothing()
    let start = position
    while position < buffer.len and buffer[position] notin {'\n', '\r'}:
      inc position
    result = text(buffer[start ..< position])
    if position < buffer.len and buffer[position] == '\r':
      inc position
      if position < buffer.len and buffer[position] == '\n':
        inc position
    elif position < buffer.len and buffer[position] == '\n':
      inc position
  )
  entries["write"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard layout
    discard body
    result = nothing()
    for argument in arguments:
      result = env.eval(argument)
      buffer.add $result
  )
  entries["write-line"] = nativeCommand(proc(
      env: Environment,
      arguments: seq[SyntaxNode],
      layout: LayoutKind,
      body: seq[SyntaxNode],
  ): Value {.raises: [EvaluatorError].} =
    discard layout
    discard body
    result = nothing()
    for argument in arguments:
      result = env.eval(argument)
      buffer.add $result
    buffer.add "\n"
  )
  dictionary(entries)

proc openFileCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "open-file", raises: [EvaluatorError].} =
  discard layout
  discard body
  case arguments.len
  of 1:
    let mode = env.eval(arguments[0]).requireText()
    openFileStream(getTempDir() / "crow-example-stream.txt", mode)
  of 2:
    let path = env.eval(arguments[0]).requireText()
    let mode = env.eval(arguments[1]).requireText()
    openFileStream(path, mode)
  else:
    raise newException(EvaluatorError, "open-file expects mode or path and mode")

proc openStringCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "open-string", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "open-string expects one text value")
  openStringStream(env.eval(arguments[0]).requireText())

proc withCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "with", raises: [EvaluatorError].} =
  discard layout
  if arguments.len != 2:
    raise newException(EvaluatorError, "with expects resource and binding name")
  let binding = arguments[1].requireSymbol("with binding")
  var resource = env.eval(arguments[0])
  resource = env.callOptionalField(resource, "open")
  let local = env.child()
  local.define(binding, resource)
  try:
    result = local.evalBlock(body)
  finally:
    discard local.callOptionalField(resource, "close")

proc arithmeticCommand(
    env: Environment, arguments: seq[SyntaxNode], op: string
): Value {.raises: [EvaluatorError].} =
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

proc plusCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "+", raises: [EvaluatorError].} =
  discard layout
  discard body
  arithmeticCommand(env, arguments, "+")

proc minusCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "-", raises: [EvaluatorError].} =
  discard layout
  discard body
  arithmeticCommand(env, arguments, "-")

proc multiplyCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "*", raises: [EvaluatorError].} =
  discard layout
  discard body
  arithmeticCommand(env, arguments, "*")

proc divideCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "/", raises: [EvaluatorError].} =
  discard layout
  discard body
  arithmeticCommand(env, arguments, "/")

proc arithmeticAssignCommand(
    env: Environment, arguments: seq[SyntaxNode], op: string
): Value {.raises: [EvaluatorError].} =
  if arguments.len != 2:
    raise newException(EvaluatorError, &"{op}= expects symbol and value")
  let symbol = arguments[0].requireSymbol("assignment target")
  let left = env.get(symbol).requireNumber()
  let right = env.eval(arguments[1]).requireNumber()
  result =
    case op
    of "+":
      number(left + right)
    of "-":
      number(left - right)
    of "*":
      number(left * right)
    of "/":
      number(left / right)
    else:
      raise newException(EvaluatorError, &"unknown assignment operator: {op}=")
  env.setSymbol(symbol, result)

proc plusAssignCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "+=", raises: [EvaluatorError].} =
  discard layout
  discard body
  arithmeticAssignCommand(env, arguments, "+")

proc minusAssignCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "-=", raises: [EvaluatorError].} =
  discard layout
  discard body
  arithmeticAssignCommand(env, arguments, "-")

proc multiplyAssignCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "*=", raises: [EvaluatorError].} =
  discard layout
  discard body
  arithmeticAssignCommand(env, arguments, "*")

proc divideAssignCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "/=", raises: [EvaluatorError].} =
  discard layout
  discard body
  arithmeticAssignCommand(env, arguments, "/")

proc compareCommand(
    env: Environment, arguments: seq[SyntaxNode], op: string
): Value {.raises: [EvaluatorError].} =
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

proc equalCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "=", raises: [EvaluatorError].} =
  discard layout
  discard body
  compareCommand(env, arguments, "=")

proc lessThanCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "<", raises: [EvaluatorError].} =
  discard layout
  discard body
  compareCommand(env, arguments, "<")

proc lessOrEqualCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "<=", raises: [EvaluatorError].} =
  discard layout
  discard body
  compareCommand(env, arguments, "<=")

proc greaterThanCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: ">", raises: [EvaluatorError].} =
  discard layout
  discard body
  compareCommand(env, arguments, ">")

proc greaterOrEqualCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: ">=", raises: [EvaluatorError].} =
  discard layout
  discard body
  compareCommand(env, arguments, ">=")

proc whenCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "when", raises: [EvaluatorError].} =
  discard layout
  if arguments.len != 1:
    raise newException(EvaluatorError, "when expects one condition")
  if env.eval(arguments[0]).isTruthy:
    env.evalBlock(body)
  else:
    nothing()

proc whileCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "while", raises: [EvaluatorError].} =
  discard layout
  if arguments.len != 1:
    raise newException(EvaluatorError, "while expects one condition")
  result = nothing()
  while env.eval(arguments[0]).isTruthy:
    result = env.evalBlock(body)

proc pickCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "pick", raises: [EvaluatorError].} =
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
): Value {.stdCommand: "list", raises: [EvaluatorError].} =
  discard env
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
): Value {.stdCommand: "dict", raises: [EvaluatorError].} =
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
): Value {.stdCommand: "cons", raises: [EvaluatorError].} =
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
): Value {.stdCommand: "first", raises: [EvaluatorError].} =
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
): Value {.stdCommand: "rest", raises: [EvaluatorError].} =
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
): Value {.stdCommand: "empty?", raises: [EvaluatorError].} =
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
): Value {.stdCommand: "not", raises: [EvaluatorError].} =
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
): Value {.stdCommand: "dict-put", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 3:
    raise newException(EvaluatorError, "dict-put expects dict, key, and value")
  let original = env.eval(arguments[0])
  if original.kind != Dictionary:
    raise newException(EvaluatorError, &"expected dictionary, got {original}")
  result = original
  result.entries[env.eval(arguments[1]).requireText()] = env.eval(arguments[2])

proc dictGetCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "dict-get", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 2:
    raise newException(EvaluatorError, "dict-get expects dict and key")
  let original = env.eval(arguments[0])
  original.field(env.eval(arguments[1]).requireText())

proc fieldCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "field", raises: [EvaluatorError].} =
  dictGetCommand(env, arguments, layout, body)

proc statementsCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "statements", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "statements expects script syntax")
  let syntax = env.eval(arguments[0])
  let node = syntax.requireSyntax()
  let sourceEnv = syntax.syntaxEnvironment(env)
  if node.kind != Script:
    raise newException(EvaluatorError, "statements expects script syntax")
  var items: seq[Value]
  for statement in node.statements:
    items.add syntaxValue(statement, sourceEnv)
  list(items)

proc bodyOfCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "body-of", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 2:
    raise newException(EvaluatorError, "body-of expects script syntax and tag")
  let syntax = env.eval(arguments[0])
  let node = syntax.requireSyntax()
  let sourceEnv = syntax.syntaxEnvironment(env)
  let tag = env.eval(arguments[1]).requireText()
  if node.kind != Script:
    raise newException(EvaluatorError, "body-of expects script syntax")
  for statement in node.statements:
    if statement.kind == Command and statement.callee.kind == Symbol and
        statement.callee.symbol == tag:
      return syntaxValue(script(statement.body), sourceEnv)
  syntaxValue(script(@[]), sourceEnv)

proc commandArgCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "command-arg", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 2:
    raise newException(EvaluatorError, "command-arg expects command syntax and index")
  let syntax = env.eval(arguments[0])
  let node = syntax.requireSyntax()
  let sourceEnv = syntax.syntaxEnvironment(env)
  let index = env.eval(arguments[1]).requireNumber().int
  if node.kind != Command or index < 0 or index >= node.arguments.len:
    raise newException(EvaluatorError, "command-arg index out of range")
  syntaxValue(node.arguments[index], sourceEnv)

proc commandSymbolCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "command-symbol", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "command-symbol expects command syntax")
  let node = env.eval(arguments[0]).requireSyntax()
  if node.kind != Command or node.callee.kind != Symbol:
    raise newException(
      EvaluatorError, "command-symbol expects command syntax with a symbol callee"
    )
  text(node.callee.symbol)

proc commandBodyCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "command-body", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "command-body expects command syntax")
  let syntax = env.eval(arguments[0])
  let node = syntax.requireSyntax()
  let sourceEnv = syntax.syntaxEnvironment(env)
  if node.kind != Command:
    raise newException(EvaluatorError, "command-body expects command syntax")
  syntaxValue(script(node.body), sourceEnv)

proc bindingSymbolCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "binding-symbol", raises: [EvaluatorError].} =
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
): Value {.stdCommand: "binding-value", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "binding-value expects binding syntax")
  let syntax = env.eval(arguments[0])
  let node = syntax.requireSyntax()
  let sourceEnv = syntax.syntaxEnvironment(env)
  if node.kind != Binding:
    raise newException(EvaluatorError, "binding-value expects binding syntax")
  syntaxValue(node.value, sourceEnv)

proc evalWithCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "eval-with", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 3:
    raise newException(EvaluatorError, "eval-with expects symbol, value, and body")
  let symbolSyntax = env.eval(arguments[0])
  let symbolNode = symbolSyntax.requireSyntax()
  let value = env.eval(arguments[1])
  let bodySyntax = env.eval(arguments[2])
  let bodyNode = bodySyntax.requireSyntax()
  let local = bodySyntax.syntaxEnvironment(env).child()
  local.define(symbolNode.requireSymbol("binding symbol"), value)
  if bodyNode.kind == Script:
    local.evalBlock(bodyNode.statements)
  else:
    local.eval(bodyNode)

proc addStandardCommands*(env: Environment) {.raises: [].} =
  env.define("stdin", stdinStream())
  env.define("stdout", stdoutStream())
  env.define("nothing", nothing())
  for registration in commandRegistry:
    env.define(registration.name, nativeCommand(registration.command))
