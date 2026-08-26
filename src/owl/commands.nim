import std/[algorithm, macros, os, rdstdin, sets, strformat, strutils, tables, math, sequtils, macrocache, sugar]

import environment, parser, syntax, values

type CommandRegistration = object
  name: string
  command: NativeCommand

var commandRegistry {.threadvar.}: seq[CommandRegistration]
var commandEnv {.threadvar.}: Environment

const commandPrototypes = CacheTable"CommandPrototypes"

macro stdCommand*(name: static[string], node: untyped): untyped =
  commandPrototypes[name] = node
  
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
  case node.kind
  of Symbol:
    node.symbol
  of Command:
    if node.callee.kind == Symbol and node.arguments.len == 0 and node.layout == NoLayout and
        node.body.len == 0:
      node.callee.symbol
    else:
      raise newException(EvaluatorError, &"expected {role} to be a symbol")
  else:
    raise newException(EvaluatorError, &"expected {role} to be a symbol")

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

proc requireText(value: Value): string {.raises: [EvaluatorError].} =
  if value.kind != Text:
    raise newException(EvaluatorError, &"expected text, got {value}")
  value.text

proc resolveSourcePath(
    path: string, pos: SourcePos
): string {.raises: [EvaluatorError].} =
  if path.isAbsolute:
    return path.normalizedPath
  let base =
    try:
      if pos.hasSource:
        pos.sourcePath.parentDir
      else:
        getCurrentDir()
    except OSError as error:
      raise newException(EvaluatorError, error.msg)
  (base / path).normalizedPath

proc loadSourceFile(
    path: string, pos: SourcePos
): SyntaxNode {.raises: [EvaluatorError].} =
  let resolved = resolveSourcePath(path, pos)
  try:
    parse(readFile(resolved), resolved)
  except IOError as error:
    raise newException(EvaluatorError, resolved & ": " & error.msg)
  except OSError as error:
    raise newException(EvaluatorError, resolved & ": " & error.msg)
  except ParserError as error:
    let converted = newException(EvaluatorError, error.msg)
    converted.primary = error.primary
    converted.frames = error.frames
    raise converted

proc moduleName(path: string): string {.raises: [].} =
  let name = splitFile(path).name
  if name.len > 0: name else: path

proc modulePath(node: SyntaxNode): string {.raises: [EvaluatorError].} =
  result = node.requireSymbol("module name")
  if splitFile(result).ext.len == 0:
    result.add ".owl"

proc moduleDictionary(moduleEnv: Environment): Value {.raises: [].} =
  dictionary(moduleEnv.bindings)

proc useSymbolFilters(
    body: seq[SyntaxNode]
): tuple[hasIncludes: bool, includes, excludes: seq[string]] {.raises: [EvaluatorError].} =
  for clause in body:
    if clause.kind != Command or clause.callee.kind != Symbol:
      raise newException(EvaluatorError, "use filters must be include, only, or exclude commands")
    case clause.callee.symbol
    of "include", "only":
      result.hasIncludes = true
      for symbol in clause.arguments:
        result.includes.add symbol.requireSymbol("symbol to include")
    of "exclude", "except":
      for symbol in clause.arguments:
        result.excludes.add symbol.requireSymbol("symbol to exclude")
    else:
      raise newException(EvaluatorError, "use filters must be include, only, or exclude commands")

proc useSelectedSymbols(
    env: Environment, entries: Table[string, Value], body: seq[SyntaxNode]
) {.raises: [EvaluatorError].} =
  let filters = useSymbolFilters(body)
  for name, value in entries:
    let included = not filters.hasIncludes or name in filters.includes
    if included and name notin filters.excludes:
      env.define(name, value)

proc useSelectedSymbols(
    env, moduleEnv: Environment, body: seq[SyntaxNode]
) {.raises: [EvaluatorError].} =
  env.useSelectedSymbols(moduleEnv.bindings, body)

proc hasRecordField(value: Value, name: string): bool {.raises: [].} =
  value.kind == Record and name in value.recordFields

proc field(value: Value, name: string): Value {.raises: [EvaluatorError].} =
  case value.kind
  of Dictionary:
    if not value.entries.hasKey(name):
      raise newException(EvaluatorError, &"missing field: {name}")
    value.entries.getOrDefault(name)
  of Record:
    if not value.recordEntries.hasKey(name):
      raise newException(EvaluatorError, &"missing field: {name}")
    value.recordEntries.getOrDefault(name)
  else:
    raise newException(EvaluatorError, &"expected dictionary or record, got {value}")

proc indexValue(value, key: Value): Value {.raises: [EvaluatorError].} =
  case value.kind
  of List:
    let index = key.requireNumber().int
    if index < 0 or index >= value.items.len:
      raise newException(EvaluatorError, "list index out of range")
    value.items[index]
  of Dictionary, Record:
    value.field(key.requireText())
  else:
    raise
      newException(EvaluatorError, &"expected list, dictionary, or record, got {value}")

proc setFieldValue(
    value: Value, name: string, entry: Value
): Value {.raises: [EvaluatorError].} =
  case value.kind
  of Dictionary:
    result = value
    result.entries = initTable[string, Value]()
    for key, current in value.entries.pairs:
      result.entries[key] = current
    result.entries[name] = entry
  of Record:
    if not value.hasRecordField(name):
      raise newException(EvaluatorError, &"cannot add record field: {name}")
    result = value
    result.recordEntries = initTable[string, Value]()
    for key, current in value.recordEntries.pairs:
      result.recordEntries[key] = current
    result.recordEntries[name] = entry
  else:
    raise newException(EvaluatorError, &"expected dictionary or record, got {value}")

proc setIndexValue(value, key, entry: Value): Value {.raises: [EvaluatorError].} =
  case value.kind
  of List:
    let index = key.requireNumber().int
    if index < 0 or index >= value.items.len:
      raise newException(EvaluatorError, "list index out of range")
    result = value
    result.items = @(value.items)
    result.items[index] = entry
  of Dictionary, Record:
    result = value.setFieldValue(key.requireText(), entry)
  else:
    raise
      newException(EvaluatorError, &"expected list, dictionary, or record, got {value}")

proc optionalField(value: Value, name: string): Value {.raises: [].} =
  if value.kind == Dictionary and value.entries.hasKey(name):
    value.entries.getOrDefault(name)
  elif value.kind == Record and value.recordEntries.hasKey(name):
    value.recordEntries.getOrDefault(name)
  else:
    nothing()

proc callOptionalField(
    env: Environment, receiver: Value, name: string
): Value {.raises: [EvaluatorError].} =
  let fieldValue = receiver.optionalField(name)
  if fieldValue.kind == Nothing:
    return receiver
  if fieldValue.kind != Command:
    raise newException(EvaluatorError, &"field is not a command: {name}")
  let value = env.call(fieldValue.command)
  if value.kind == Nothing: receiver else: value

proc commandDoc(body: seq[SyntaxNode]): tuple[description: string,
    body: seq[SyntaxNode]] {.raises: [].} =
  result = ("", body)
  if body.len > 0 and body[0].kind == String:
    result.description = body[0].stringValue
    if body.len == 1:
      result.body = @[]
    else:
      result.body = body[1 .. ^1]

proc defineClosure(
    env: Environment,
    arguments: seq[SyntaxNode],
    body: seq[SyntaxNode],
    evaluatesArguments, acceptsBlock: bool,
    interactive = false,
): Value {.raises: [EvaluatorError].} =
  if arguments.len == 0:
    raise newException(EvaluatorError, "expected command name")
  let commandName = arguments[0].requireSymbol("command name")
  var parameters: seq[string]
  for argument in arguments[1 .. ^1]:
    parameters.add argument.requireSymbol("parameter")
  let doc = commandDoc(body)
  result = closureCommand(parameters, doc.body, env, evaluatesArguments,
      acceptsBlock, id = commandName, description = doc.description,
      interactive = interactive)
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

  if target.kind == Command and target.callee.kind == Symbol and
      target.arguments.len == 2 and target.layout == NoLayout and target.body.len == 0:
    case target.callee.symbol
    of "field":
      let container = env.eval(target.arguments[0])
      let key = env.eval(target.arguments[1]).requireText()
      env.setTarget(target.arguments[0], container.setFieldValue(key, value))
      return
    of "index":
      let container = env.eval(target.arguments[0])
      let key = env.eval(target.arguments[1])
      env.setTarget(target.arguments[0], container.setIndexValue(key, value))
      return
    else:
      discard

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

proc componentCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "component", raises: [EvaluatorError].} =
  commandCommand(env, arguments, layout, body)

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

proc defcommandCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "defcommand", raises: [EvaluatorError].} =
  discard layout
  env.defineClosure(arguments, body, evaluatesArguments = true,
      acceptsBlock = false, interactive = true)

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
    if env.bindings.hasKey(node.bindingSymbol):
      raise newException(EvaluatorError, &"symbol already defined: {node.bindingSymbol}")
    result = env.eval(node.value)
    env.define(node.bindingSymbol, result)

proc commandDefineCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "command-define", raises: [EvaluatorError].} =
  discard arguments
  discard layout
  result = nothing()
  for node in body:
    if node.kind != Binding:
      raise newException(EvaluatorError, "define body entries must be bindings")
    result = env.eval(node.value)
    commandEnv.define(node.bindingSymbol, result)

proc defineValueCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "define-caller-value", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 2:
    raise newException(EvaluatorError, "define-caller-value expects name and value")
  result = env.eval(arguments[1])
  let nameValue = env.eval(arguments[0])
  let nameNode =
    if nameValue.kind == Syntax:
      nameValue.syntax
    else:
      arguments[0]
  let name =
    if nameValue.kind == Text:
      nameValue.text
    else:
      nameNode.requireSymbol("definition name")
  let targetEnv = if env.parent == nil: env else: env.parent
  targetEnv.define(name, result)

proc importCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "import", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "import expects one path")
  let node = loadSourceFile(env.eval(arguments[0]).requireText(), arguments[0].pos)
  env.evalBlock(node.statements)

proc useCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "use", raises: [EvaluatorError].} =
  if arguments.len < 1 or arguments.len > 2:
    raise newException(EvaluatorError, "use expects a module name and optional namespace")

  if layout == ColonLayout and arguments.len == 2:
    raise newException(EvaluatorError, "use filters cannot be combined with a module name")
  if layout notin {NoLayout, ColonLayout}:
    raise newException(EvaluatorError, "use filters require a colon block")

  let requested = arguments[0].requireSymbol("module name")
  if env.hasNativeModule(requested):
    result = env.getNativeModule(requested)
    if result.kind != Dictionary:
      raise newException(EvaluatorError, "native module exports must be a dictionary")
    if layout == ColonLayout:
      env.useSelectedSymbols(result.entries, body)
      result = nothing()
    else:
      let name =
        if arguments.len == 2:
          arguments[1].requireSymbol("module namespace")
        else:
          moduleName(requested)
      env.define(name, result)
    return

  let path = modulePath(arguments[0])
  let node = loadSourceFile(path, arguments[0].pos)
  let name =
    if arguments.len == 2:
      arguments[1].requireSymbol("module namespace")
    else:
      moduleName(path)
  let moduleEnv = env.child()
  discard moduleEnv.evalBlock(node.statements)
  if layout == ColonLayout:
    env.useSelectedSymbols(moduleEnv, body)
    result = nothing()
  else:
    result = moduleDictionary(moduleEnv)
    env.define(name, result)

proc symbolTextCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "symbol-text", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "symbol-text expects one symbol")
  let value = env.eval(arguments[0])
  let node =
    if value.kind == Syntax:
      value.syntax
    else:
      arguments[0]
  text(node.requireSymbol("symbol"))

proc concatCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "concat", raises: [EvaluatorError].} =
  discard layout
  discard body
  # TODO: Make this work for lists and dictionaries
  var parts: seq[string]
  for argument in arguments:
    parts.add env.eval(argument).requireText()
  text(parts.join(""))

proc toStringCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "to-string", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "to-string expects one value")
  text($env.eval(arguments[0]))

proc recordConstructorCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "record-constructor", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 3:
    raise newException(
      EvaluatorError, "record-constructor expects name, fields, and defaults"
    )

  let recordName = env.eval(arguments[0]).requireText()

  var fields: seq[string]
  for item in env.eval(arguments[1]).requireList():
    let field = item.requireText()
    if field in fields:
      raise newException(EvaluatorError, &"duplicate record field: {field}")
    fields.add field

  var defaults: seq[Value]
  for item in env.eval(arguments[2]).requireList():
    if item.kind != Syntax:
      raise newException(EvaluatorError, "record defaults must be syntax values")
    defaults.add item

  if fields.len != defaults.len:
    raise newException(EvaluatorError, "record fields/defaults length mismatch")

  let typeName = recordName
  let fieldOrder = fields
  let defaultValues = defaults
  nativeCommand(
    proc(
        callEnv: Environment,
        callArguments: seq[SyntaxNode],
        callLayout: LayoutKind,
        callBody: seq[SyntaxNode],
    ): Value {.raises: [EvaluatorError].} =
      discard callLayout
      if callArguments.len > fieldOrder.len:
        raise newException(EvaluatorError, "record got too many arguments")

      var entries = initTable[string, Value]()
      for index, field in fieldOrder:
        entries[field] = defaultValues[index].syntaxEnvironment(callEnv).eval(
            defaultValues[index].syntax
          )

      for index, argument in callArguments:
        entries[fieldOrder[index]] = callEnv.eval(argument)

      var seenOverrides: seq[string]
      for node in callBody:
        if node.kind != Binding:
          raise newException(EvaluatorError, "record overrides must be bindings")
        if node.bindingSymbol notin fieldOrder:
          raise
            newException(EvaluatorError, &"unknown record field: {node.bindingSymbol}")
        if node.bindingSymbol in seenOverrides:
          raise newException(
            EvaluatorError, &"duplicate record override: {node.bindingSymbol}"
          )
        seenOverrides.add node.bindingSymbol
        entries[node.bindingSymbol] = callEnv.eval(node.value)

      record(typeName, entries, fieldOrder)
  )

proc recordPredicateCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "record-predicate", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "record-predicate expects name")
  let typeName = env.eval(arguments[0]).requireText()
  nativeCommand(
    proc(
        callEnv: Environment,
        callArguments: seq[SyntaxNode],
        callLayout: LayoutKind,
        callBody: seq[SyntaxNode],
    ): Value {.raises: [EvaluatorError].} =
      discard callLayout
      discard callBody
      if callArguments.len != 1:
        raise newException(EvaluatorError, "record predicate expects one value")
      let value = callEnv.eval(callArguments[0])
      boolean(value.kind == Record and value.recordName == typeName)
  )

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

proc evalSourceCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "eval-source", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len < 1 or arguments.len > 2:
    raise newException(EvaluatorError, "eval-source expects source and optional path")
  let source = env.eval(arguments[0]).requireText()
  let path =
    if arguments.len == 2:
      env.eval(arguments[1]).requireText()
    else:
      "<eval>"
  try:
    env.eval(parse(source, path))
  except ParserError as error:
    let converted = newException(EvaluatorError, error.msg)
    converted.primary = error.primary
    converted.frames = error.frames
    raise converted

proc evalFileCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "eval-file", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "eval-file expects one path")
  let path = env.eval(arguments[0]).requireText()
  try:
    env.eval(parse(readFile(path), path))
  except IOError as error:
    raise newException(EvaluatorError, path & ": " & error.msg)
  except OSError as error:
    raise newException(EvaluatorError, path & ": " & error.msg)
  except ParserError as error:
    let converted = newException(EvaluatorError, error.msg)
    converted.primary = error.primary
    converted.frames = error.frames
    raise converted

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
    let converted = newException(EvaluatorError, error.msg)
    converted.primary = error.primary
    converted.frames = error.frames
    raise converted

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

proc commandIdCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "command-id", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "command-id expects one command")
  let value = env.eval(arguments[0])
  if value.kind != Command:
    raise newException(EvaluatorError, &"command-id expected command, got {value}")
  text(value.command.id)

proc commandDescriptionCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "command-description", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "command-description expects one command")
  let value = env.eval(arguments[0])
  if value.kind != Command:
    raise newException(EvaluatorError,
        &"command-description expected command, got {value}")
  text(value.command.description)

proc interactiveCommandsCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "interactive-commands", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 0:
    raise newException(EvaluatorError, "interactive-commands expects no arguments")
  proc collectInteractive(current: Environment, seenEnv: var HashSet[int],
      seenCommand: var HashSet[string], collected: var seq[tuple[id: string,
      value: Value]]) {.raises: [].} =
    if current.isNil:
      return
    let key = cast[int](current)
    if key in seenEnv:
      return
    seenEnv.incl key
    for name, value in current.bindings.pairs:
      if value.kind != Command or not value.command.interactive:
        continue
      let id =
        if value.command.id.len > 0:
          value.command.id
        else:
          name
      if id in seenCommand:
        continue
      seenCommand.incl id
      collected.add((id, value))
    collectInteractive(current.parent, seenEnv, seenCommand, collected)
    collectInteractive(current.fallback, seenEnv, seenCommand, collected)

  var
    seenEnv = initHashSet[int]()
    seenCommand = initHashSet[string]()
    collected: seq[tuple[id: string, value: Value]]
  collectInteractive(env, seenEnv, seenCommand, collected)
  collected.sort(proc(a, b: tuple[id: string, value: Value]): int =
    cmp(a.id.toLowerAscii(), b.id.toLowerAscii())
  )
  list(collect(for entry in collected: entry.value))

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

proc streamText(value: Value): string {.raises: [].} =
  if value.kind == Text:
    value.text
  else:
    $value

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
    parts.add result.streamText()
  try:
    stdout.write parts.join("")
  except:
    raise newException(EvaluatorError, getCurrentExceptionMsg())

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

const StreamFields =
  ["open", "close", "read", "read-line", "read-all", "write", "write-line"]

proc unsupportedStreamCommand(name: string): Value {.raises: [].} =
  nativeCommand(
    proc(
        env: Environment,
        arguments: seq[SyntaxNode],
        layout: LayoutKind,
        body: seq[SyntaxNode],
    ): Value {.raises: [EvaluatorError].} =
      discard env
      discard arguments
      discard layout
      discard body
      raise newException(EvaluatorError, &"unsupported stream operation: {name}")
  )

proc streamRecord(entries: sink Table[string, Value]): Value {.raises: [].} =
  for field in StreamFields:
    if not entries.hasKey(field):
      entries[field] = unsupportedStreamCommand(field)
  record("Stream", entries, @StreamFields)

template niladicStream(label: static string, handler: untyped): Value =
  nativeCommand(
    proc(
        env: Environment,
        arguments: seq[SyntaxNode],
        layout: LayoutKind,
        body: seq[SyntaxNode],
    ): Value {.raises: [EvaluatorError].} =
      discard env
      discard layout
      discard body
      if arguments.len != 0:
        raise newException(EvaluatorError, label & " expects no arguments")
      handler
  )

proc stdinStream(): Value {.raises: [].} =
  var entries = initTable[string, Value]()
  entries["read"] = niladicStream("stdin read"):
    try:
      if stdin.endOfFile:
        return nothing()
      text($stdin.readChar())
    except IOError as error:
      raise newException(EvaluatorError, error.msg)
  entries["read-line"] = niladicStream("stdin read-line"):
    var line: string
    if readLineFromStdin("", line):
      text(line)
    else:
      nothing()
  entries["read-all"] = niladicStream("stdin read-all"):
    try:
      var content = ""
      while not stdin.endOfFile:
        content.add stdin.readChar()
      text(content)
    except IOError as error:
      raise newException(EvaluatorError, error.msg)
  entries["open"] = niladicStream("stdin open"):
    nothing()
  entries["close"] = niladicStream("stdin close"):
    nothing()
  streamRecord(entries)

proc stdoutStream(): Value {.raises: [].} =
  var entries = initTable[string, Value]()
  entries["write"] = nativeCommand(
    proc(
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
          stdout.write(result.streamText())
        except IOError as error:
          raise newException(EvaluatorError, error.msg)
  )
  entries["write-line"] = nativeCommand(
    proc(
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
          stdout.write(result.streamText())
        except IOError as error:
          raise newException(EvaluatorError, error.msg)
      try:
        stdout.write("\n")
      except IOError as error:
        raise newException(EvaluatorError, error.msg)
  )
  entries["open"] = niladicStream("stdout open"):
    nothing()
  entries["close"] = niladicStream("stdout close"):
    nothing()
  streamRecord(entries)

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

  entries["open"] = niladicStream("file open"):
    if not opened:
      try:
        if not open(file, path, fileMode(mode)):
          raise newException(EvaluatorError, &"could not open file: {path}")
        opened = true
      except IOError as error:
        raise newException(EvaluatorError, error.msg)
    nothing()
  entries["close"] = niladicStream("file close"):
    if opened:
      close(file)
      opened = false
    nothing()
  entries["read"] = niladicStream("file read"):
    if not opened:
      raise newException(EvaluatorError, "file is not open")
    try:
      if file.endOfFile:
        return nothing()
      text($file.readChar())
    except IOError as error:
      raise newException(EvaluatorError, error.msg)
  entries["read-line"] = niladicStream("file read-line"):
    if not opened:
      raise newException(EvaluatorError, "file is not open")
    try:
      if file.endOfFile:
        return nothing()
      text(file.readLine())
    except IOError as error:
      raise newException(EvaluatorError, error.msg)
  entries["read-all"] = niladicStream("file read-all"):
    if not opened:
      raise newException(EvaluatorError, "file is not open")
    try:
      var content = ""
      while not file.endOfFile:
        content.add file.readChar()
      text(content)
    except IOError as error:
      raise newException(EvaluatorError, error.msg)
  entries["write"] = nativeCommand(
    proc(
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
          file.write(result.streamText())
        except IOError as error:
          raise newException(EvaluatorError, error.msg)
  )
  entries["write-line"] = nativeCommand(
    proc(
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
          file.write(result.streamText())
        except IOError as error:
          raise newException(EvaluatorError, error.msg)
      try:
        file.write("\n")
      except IOError as error:
        raise newException(EvaluatorError, error.msg)
  )
  streamRecord(entries)

proc openStringStream(content: string): Value {.raises: [].} =
  var entries = initTable[string, Value]()
  var buffer = content
  var position = 0
  var opened = false

  entries["open"] = niladicStream("string open"):
    position = 0
    opened = true
    nothing()
  entries["close"] = niladicStream("string close"):
    opened = false
    nothing()
  entries["read"] = niladicStream("string read"):
    if not opened:
      raise newException(EvaluatorError, "string stream is not open")
    if position >= buffer.len:
      return nothing()
    result = text($buffer[position])
    inc position
  entries["read-line"] = niladicStream("string read-line"):
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
  entries["read-all"] = niladicStream("string read-all"):
    if not opened:
      raise newException(EvaluatorError, "string stream is not open")
    if position >= buffer.len:
      return text("")
    result = text(buffer[position .. ^1])
    position = buffer.len
  entries["write"] = nativeCommand(
    proc(
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
        buffer.add result.streamText()
  )
  entries["write-line"] = nativeCommand(
    proc(
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
        buffer.add result.streamText()
      buffer.add "\n"
  )
  streamRecord(entries)

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
    openFileStream(getTempDir() / "owl-example-stream.txt", mode)
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
  var acc = env.eval(arguments[0]).requireNumber()
  for index in 1 ..< arguments.len:
    let rhs = env.eval(arguments[index]).requireNumber()
    case op
    of "+":
      acc += rhs
    of "-":
      acc -= rhs
    of "*":
      acc *= rhs
    of "/":
      acc /= rhs
    else:
      raise newException(EvaluatorError, &"unknown arithmetic operator: {op}")
  number(acc)

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

proc lengthCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "length", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 1:
    raise newException(EvaluatorError, "length expects one value")
  let value = env.eval(arguments[0])
  case value.kind
  of List:
    number(value.items.len.float64)
  of Dictionary:
    number(value.entries.len.float64)
  of Text:
    number(value.text.len.float64)
  else:
    raise
      newException(EvaluatorError, &"expected list, dictionary, or text, got {value}")

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

proc andCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "and", raises: [EvaluatorError].} =
  discard layout
  discard body
  result = boolean(true)
  for argument in arguments:
    result = env.eval(argument)
    if not result.isTruthy:
      return

proc orCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "or", raises: [EvaluatorError].} =
  discard layout
  discard body
  result = boolean(false)
  for argument in arguments:
    result = env.eval(argument)
    if result.isTruthy:
      return

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
  original.setFieldValue(env.eval(arguments[1]).requireText(), env.eval(arguments[2]))

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

proc indexCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "index", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 2:
    raise newException(EvaluatorError, "index expects value and key")
  indexValue(env.eval(arguments[0]), env.eval(arguments[1]))

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

proc floorCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    _: LayoutKind,
    _: seq[SyntaxNode],
): Value {.stdCommand: "floor", raises: [EvaluatorError].} =
  discard """
  Returns largest integer not greater than argument.  
  """
  if arguments.len != 1:
    raise newException(EvaluatorError, "floor expects one number")
  number(floor(env.eval(arguments[0]).requireNumber()))

proc commandLineArgumentsCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "command-line-arguments", raises: [EvaluatorError].} =
  discard """
  Returns command line arguments passed to the script.
  """
  let args = (try: commandLineParams() except: @[])
  list(args.mapIt(text(it)))

proc standardCommandsCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "standard-commands", raises: [EvaluatorError].} =
  discard env
  discard layout
  discard body
  if arguments.len != 0:
    raise newException(EvaluatorError, "standard-commands expects no arguments")
  const Prototypes = collect:
    for name, command in commandPrototypes:
      let rep = name.repr[1 ..< ^1]
      &"""** {rep}
#+begin_src owl
{command[3].repr}
#+end_src"""
  list(Prototypes.mapIt(text(it)))

proc replCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "repl", raises: [EvaluatorError].} =
  discard layout
  discard body
  if arguments.len != 0:
    raise newException(EvaluatorError, "repl expects no arguments")

  proc writeOutput(value: Value) {.raises: [EvaluatorError].} =
    try:
      stdout.writeLine value
    except IOError as error:
      raise newException(EvaluatorError, error.msg)

  proc writeError(message: string) {.raises: [EvaluatorError].} =
    try:
      stderr.write message
    except IOError as error:
      raise newException(EvaluatorError, error.msg)

  var history: seq[string]
  result = nothing()
  while true:
    var line: string
    if not readLineFromStdin("> ", line):
      break
    case line
    of "q", "quit":
      break
    of "history":
      try:
        stdout.writeLine history
      except IOError as error:
        raise newException(EvaluatorError, error.msg)
      continue
    else:
      discard

    history.add line
    try:
      result = env.eval(parse(line, "<repl>"))
      writeOutput result
    except OwlError as error:
      writeError report(error, useColor = true)
    except CatchableError as error:
      writeError error.msg & "\n"

proc exitCommand(
    env: Environment,
    arguments: seq[SyntaxNode],
    layout: LayoutKind,
    body: seq[SyntaxNode],
): Value {.stdCommand: "exit", raises: [EvaluatorError].} =
  if arguments.len == 0:
    quit(0)
  let exitCode = env.eval(arguments[0]).requireNumber().toInt()
  quit(exitCode)

proc addStandardCommands*(env: Environment) {.raises: [].} =
  commandEnv = newEnvironment()
  commandEnv.evaluator = env.evaluator
  commandEnv.commandCaller = env.commandCaller
  commandEnv.define("stdin", stdinStream())
  commandEnv.define("stdout", stdoutStream())
  commandEnv.define("nothing", nothing())
  env.fallback = commandEnv
  env.define("stdin", stdinStream())
  env.define("stdout", stdoutStream())
  env.define("nothing", nothing())
  for registration in commandRegistry:
    env.define(registration.name, nativeCommand(registration.command))
    commandEnv.define(registration.name, nativeCommand(registration.command))

proc getCommandPrototypes*(): seq[string] =
  const Prototypes = collect:
    for name, command in commandPrototypes:
      let rep = name.repr[1 ..< ^1]
      &"""** {rep}
#+begin_src owl
{command[3].repr}
#+end_src"""
  result = Prototypes
