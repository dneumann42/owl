import std/[
  algorithm, macrocache, macros, math, os, rdstdin, sequtils, strformat, strutils,
  sugar, tables,
]

import environment, parser, syntax, values

type CommandRegistration = object
  name: string
  command: NativeCommand

var
  commandRegistry {.threadvar.}: seq[CommandRegistration]
  commandAliases {.threadvar.}: seq[tuple[alias, target: string]]
  commandEnv {.threadvar.}: Environment
  recordShapes {.threadvar.}: Table[string, RecordShape]

proc declaredShape(name: string, fields: sink seq[string]): RecordShape {.raises: [].} =
  ## Record names live here rather than on the records, so that a
  ## declaration's constructor and predicate reach the same shape. Reusing a
  ## matching shape is also what lets host-built `Stream` records and the
  ## prelude's `record Stream:` agree.
  recordShapes.withValue(name, existing):
    if existing[].fields == fields:
      return existing[]
  result = RecordShape(fields: fields)
  recordShapes[name] = result

const commandDocs = CacheTable"OwlCommandDocs"

proc documentation(name, usage, doc: string): string {.compileTime.} =
  result = "** " & name & "\n#+begin_src owl\n" & name
  if usage.len > 0:
    result.add ' '
    result.add usage
  result.add "\n#+end_src"
  if doc.len > 0:
    result.add '\n'
    result.add doc

macro stdCommand(
    name, usage: static[string], arity: untyped, body: untyped
): untyped =
  ## Define and register a native command.
  ##
  ## `usage` names the arguments as `standard-commands` should show them and as
  ## an arity failure should report them. `arity` is an exact count, a `lo ..
  ## hi` range, or `any`. The body sees `env`, `arguments`, `layout`, and
  ## `body`, and a leading doc comment becomes the command's documentation.
  var
    doc = ""
    statements = body
  if body.kind == nnkStmtList and body.len > 0 and body[0].kind == nnkCommentStmt:
    doc = body[0].strVal
    statements = newStmtList()
    for index in 1 ..< body.len:
      statements.add body[index]
  commandDocs[name] = newLit(documentation(name, usage, doc))

  let expected =
    if usage.len == 0: name & " expects no arguments" else: name & " expects " & usage
  let check =
    case arity.kind
    of nnkIntLit:
      let count = arity.intVal.int
      quote do:
        if arguments.len != `count`:
          raise newException(EvaluatorError, `expected`)
    of nnkInfix: # `lo .. hi`
      let (low, high) = (arity[1], arity[2])
      quote do:
        if arguments.len < `low` or arguments.len > `high`:
          raise newException(EvaluatorError, `expected`)
    else: # `any`
      newStmtList()

  # The proc is assembled from plain identifiers rather than `quote`, so that
  # the body written at the call site binds to these parameters.
  let
    procName = genSym(nskProc, "owlCommand")
    nodes = nnkBracketExpr.newTree(ident"seq", ident"SyntaxNode")
    procBody = newStmtList()
  for parameter in ["env", "arguments", "layout", "body"]:
    procBody.add nnkDiscardStmt.newTree(ident(parameter))
  procBody.add check
  procBody.add statements

  let registration = quote do:
    commandRegistry.add CommandRegistration(name: `name`, command: `procName`)

  result = newStmtList(
    newProc(
      name = procName,
      params = [
        ident"Value",
        newIdentDefs(ident"env", ident"Environment"),
        newIdentDefs(ident"arguments", nodes),
        newIdentDefs(ident"layout", ident"LayoutKind"),
        newIdentDefs(ident"body", nodes),
      ],
      body = procBody,
      pragmas = nnkPragma.newTree(
        nnkExprColonExpr.newTree(
          ident"raises", nnkBracket.newTree(ident"EvaluatorError")
        )
      ),
    ),
    registration,
  )

macro stdAlias(alias, target: static[string], doc: static[string]): untyped =
  ## Register `alias` as a second name for an existing command.
  commandDocs[alias] =
    newLit(documentation(alias, "", doc & " Same as `" & target & "`."))
  result = quote do:
    commandAliases.add (`alias`, `target`)

proc requireSymbol(node: SyntaxNode, role: string): string {.raises: [EvaluatorError].} =
  ## A bare name reaches a command as either a symbol or an argument-less
  ## command node, depending on where it was written.
  let symbolNode =
    if node.kind == Command and node.callee.kind == Symbol and
        node.arguments.len == 0 and node.layout == NoLayout and node.body.len == 0:
      node.callee
    else:
      node
  if symbolNode.kind != Symbol:
    raise newException(EvaluatorError, &"expected {role} to be a symbol")
  result = symbolNode.symbol

proc requireNumber(value: Value): float64 {.raises: [EvaluatorError].} =
  if value.kind != Number:
    raise newException(EvaluatorError, &"expected number, got {value}")
  result = value.number

proc requireText(value: Value): string {.raises: [EvaluatorError].} =
  if value.kind != Text:
    raise newException(EvaluatorError, &"expected text, got {value}")
  result = value.text

proc requireSyntax(value: Value): SyntaxNode {.raises: [EvaluatorError].} =
  if value.kind != Syntax:
    raise newException(EvaluatorError, &"expected syntax, got {value}")
  result = value.syntax

proc requireList(value: Value): Value {.raises: [EvaluatorError].} =
  if value.kind != List:
    raise newException(EvaluatorError, &"expected list, got {value}")
  result = value

proc syntaxEnvironment(value: Value, fallback: Environment): Environment {.raises: [].} =
  if value.kind == Syntax and value.syntaxEnv != nil: value.syntaxEnv else: fallback

proc syntaxArg(
    env: Environment, node: SyntaxNode
): tuple[node: SyntaxNode, env: Environment] {.raises: [EvaluatorError].} =
  ## Evaluate an argument that must be a syntax value, keeping the environment
  ## the syntax was captured in so it can be evaluated where it was written.
  let value = env.eval(node)
  result = (value.requireSyntax(), value.syntaxEnvironment(env))

proc scriptArg(
    env: Environment, node: SyntaxNode, role: string
): tuple[node: SyntaxNode, env: Environment] {.raises: [EvaluatorError].} =
  result = env.syntaxArg(node)
  if result.node.kind != Script:
    raise newException(EvaluatorError, &"{role} expects script syntax")

proc commandArg(
    env: Environment, node: SyntaxNode, role: string
): tuple[node: SyntaxNode, env: Environment] {.raises: [EvaluatorError].} =
  result = env.syntaxArg(node)
  if result.node.kind != Command:
    raise newException(EvaluatorError, &"{role} expects command syntax")

proc bindingArg(
    env: Environment, node: SyntaxNode, role: string
): tuple[node: SyntaxNode, env: Environment] {.raises: [EvaluatorError].} =
  result = env.syntaxArg(node)
  if result.node.kind != Binding:
    raise newException(EvaluatorError, &"{role} expects binding syntax")

proc evalSyntax(env: Environment, value: Value): Value {.raises: [EvaluatorError].} =
  ## Syntax evaluates where it was captured; anything else is already a value.
  if value.kind == Syntax:
    value.syntaxEnvironment(env).eval(value.syntax)
  else:
    value

proc bindingBody(
    body: seq[SyntaxNode], role: string
): seq[SyntaxNode] {.raises: [EvaluatorError].} =
  for node in body:
    if node.kind != Binding:
      raise newException(EvaluatorError, &"{role} entries must be bindings")
  result = body

proc field(value: Value, name: string): Value {.raises: [EvaluatorError].} =
  if value.kind != Record:
    raise newException(EvaluatorError, &"expected dictionary or record, got {value}")
  if not value.hasKey(name):
    raise newException(EvaluatorError, &"missing field: {name}")
  value[name]

proc checkedIndex(
    value: Value, index: float64, role: string
): int {.raises: [EvaluatorError].} =
  result = int(index)
  if result.float64 != index or result < 0 or result >= value.len:
    raise newException(
      EvaluatorError, &"{role}: index {index} is outside a list of {value.len}"
    )

proc indexValue(value, key: Value): Value {.raises: [EvaluatorError].} =
  case value.kind
  of List:
    let index = key.requireNumber().int
    if index < 0 or index >= value.len:
      raise newException(EvaluatorError, "list index out of range")
    value[index]
  of Record:
    value.field(key.requireText())
  else:
    raise newException(
      EvaluatorError, &"expected list, dictionary, or record, got {value}"
    )

proc setFieldValue(
    value: Value, name: string, entry: Value
): Value {.raises: [EvaluatorError].} =
  ## Records are updated by copy, so other holders of the original value keep
  ## seeing it unchanged.
  if value.kind != Record:
    raise newException(EvaluatorError, &"expected dictionary or record, got {value}")
  if value.isFixed and not value.hasKey(name):
    raise newException(EvaluatorError, &"cannot add record field: {name}")
  result = value
  result[name] = entry

proc setIndexValue(value, key, entry: Value): Value {.raises: [EvaluatorError].} =
  case value.kind
  of List:
    var updated = value.toSeq
    updated[value.checkedIndex(key.requireNumber(), "index")] = entry
    result = list(updated)
  of Record:
    result = value.setFieldValue(key.requireText(), entry)
  else:
    raise newException(
      EvaluatorError, &"expected list, dictionary, or record, got {value}"
    )

proc callOptionalField(
    env: Environment, receiver: Value, name: string
): Value {.raises: [EvaluatorError].} =
  ## Call `receiver.name` when it exists, otherwise leave the receiver alone. A
  ## handler that answers `nothing` also leaves the receiver as it was.
  let fieldValue = receiver[name]
  if fieldValue.kind == Nothing:
    return receiver
  if fieldValue.kind != Command:
    raise newException(EvaluatorError, &"field is not a command: {name}")
  let value = env.call(fieldValue.command)
  result = if value.kind == Nothing: receiver else: value

proc streamText(value: Value): string {.raises: [].} =
  if value.kind == Text: value.text else: $value

proc defineClosure(
    env: Environment,
    arguments, body: seq[SyntaxNode],
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
  ## Assign through a symbol, a selector such as `point.x` or `xs.[0]`, or a
  ## syntax value naming a symbol in the scope it was captured from.
  if target.kind == Symbol:
    env.setSymbol(target.symbol, value)
    return

  if target.kind == Command and target.callee.kind == Symbol and
      target.arguments.len == 2 and target.layout == NoLayout and target.body.len == 0 and
      target.callee.symbol in ["field", "index"]:
    let container = env.eval(target.arguments[0])
    let key = env.eval(target.arguments[1])
    let updated =
      if target.callee.symbol == "field":
        container.setFieldValue(key.requireText(), value)
      else:
        container.setIndexValue(key, value)
    env.setTarget(target.arguments[0], updated)
    return

  let (node, targetEnv) = env.syntaxArg(target)
  targetEnv.setSymbol(node.requireSymbol("set target"), value)

proc asEvaluatorError(error: ref ParserError): ref EvaluatorError {.raises: [].} =
  result = newException(EvaluatorError, error.msg)
  result.primary = error.primary
  result.frames = error.frames

proc parseSource(
    source, path: string
): SyntaxNode {.raises: [EvaluatorError].} =
  try:
    parse(source, path)
  except ParserError as error:
    raise error.asEvaluatorError()

proc readSource(path: string): string {.raises: [EvaluatorError].} =
  try:
    readFile(path)
  except IOError as error:
    raise newException(EvaluatorError, path & ": " & error.msg)
  except OSError as error:
    raise newException(EvaluatorError, path & ": " & error.msg)

proc loadSourceFile(
    path: string, pos: SourcePos
): SyntaxNode {.raises: [EvaluatorError].} =
  ## Resolve `path` against the file the reference was written in, so a module
  ## refers to its neighbours the same way wherever it is run from.
  let resolved =
    if path.isAbsolute:
      path.normalizedPath
    else:
      let base =
        try:
          if pos.hasSource: pos.sourcePath.parentDir else: getCurrentDir()
        except OSError as error:
          raise newException(EvaluatorError, error.msg)
      (base / path).normalizedPath
  result = parseSource(readSource(resolved), resolved)

proc modulePath(node: SyntaxNode): string {.raises: [EvaluatorError].} =
  result = node.requireSymbol("module name")
  if splitFile(result).ext.len == 0:
    result.add ".owl"

proc moduleName(path: string): string {.raises: [].} =
  let name = splitFile(path).name
  result = if name.len > 0: name else: path

proc useSelectedSymbols(
    env: Environment, entries: Table[string, Value], body: seq[SyntaxNode]
) {.raises: [EvaluatorError].} =
  var
    hasIncludes = false
    includes, excludes: seq[string]
  for clause in body:
    if clause.kind != Command or clause.callee.kind != Symbol:
      raise newException(
        EvaluatorError, "use filters must be include, only, or exclude commands"
      )
    case clause.callee.symbol
    of "include", "only":
      hasIncludes = true
      for symbol in clause.arguments:
        includes.add symbol.requireSymbol("symbol to include")
    of "exclude", "except":
      for symbol in clause.arguments:
        excludes.add symbol.requireSymbol("symbol to exclude")
    else:
      raise newException(
        EvaluatorError, "use filters must be include, only, or exclude commands"
      )

  for name, value in entries:
    if (not hasIncludes or name in includes) and name notin excludes:
      env.define(name, value)

stdCommand "command", "name parameter...", any:
  ## Define a command whose parameters receive raw argument syntax.
  env.defineClosure(arguments, body, evaluatesArguments = false, acceptsBlock = false)

stdCommand "block-command", "name parameter...", any:
  ## Define a raw-syntax command that may also be given a colon body.
  env.defineClosure(arguments, body, evaluatesArguments = false, acceptsBlock = true)

stdCommand "fun", "name parameter...", any:
  ## Define a command whose parameters receive evaluated argument values.
  env.defineClosure(arguments, body, evaluatesArguments = true, acceptsBlock = false)

stdCommand "fn", "parameter...", any:
  ## Create an anonymous command whose parameters receive evaluated values.
  var parameters: seq[string]
  for argument in arguments:
    parameters.add argument.requireSymbol("parameter")
  result =
    closureCommand(parameters, body, env, evaluatesArguments = true, acceptsBlock = false)

stdAlias "component", "command", "Define a raw-syntax command."
stdAlias "lambda", "fn", "Create an anonymous command."

stdCommand "define", "", any:
  ## Evaluate each binding in the body and bind it in the current scope. A
  ## symbol already bound in this scope is an error; use `set` to update it.
  result = nothing()
  for node in body.bindingBody("define body"):
    if env.bindings.hasKey(node.bindingSymbol):
      raise newException(
        EvaluatorError, &"symbol already defined: {node.bindingSymbol}"
      )
    result = env.eval(node.value)
    env.define(node.bindingSymbol, result)

stdCommand "command-define", "", any:
  ## Evaluate each binding here and bind it in the shared command environment,
  ## where it outlives the call and stays visible to every scope.
  result = nothing()
  for node in body.bindingBody("define body"):
    result = env.eval(node.value)
    commandEnv.define(node.bindingSymbol, result)

stdCommand "define-caller-value", "name value", 2:
  ## Bind a value in the calling scope under a symbol or text name. This is how
  ## an Owl-level command introduces a name for its caller.
  result = env.eval(arguments[1])
  let nameValue = env.eval(arguments[0])
  let name =
    if nameValue.kind == Text:
      nameValue.text
    elif nameValue.kind == Syntax:
      nameValue.syntax.requireSymbol("definition name")
    else:
      arguments[0].requireSymbol("definition name")
  (if env.parent == nil: env else: env.parent).define(name, result)

stdCommand "set", "target value", any:
  ## Update existing bindings, either as `set target value` or as a body of
  ## bindings. Unlike `define` the symbol must already exist.
  if arguments.len == 2 and body.len == 0:
    result = env.eval(arguments[1])
    env.setTarget(arguments[0], result)
    return
  if arguments.len != 0:
    raise newException(EvaluatorError, "set expects a symbol/value pair or a block")
  result = nothing()
  for node in body.bindingBody("set body"):
    result = env.eval(node.value)
    env.setSymbol(node.bindingSymbol, result)

stdCommand "value-of", "name", 1:
  ## The value bound to a name, without calling it.
  env.get(arguments[0].requireSymbol("value name"))

stdCommand "call", "command argument...", 1 .. int.high:
  ## Call a command value with the remaining arguments.
  let command = env.eval(arguments[0])
  if command.kind != Command:
    raise newException(EvaluatorError, &"call expected command, got {command}")
  result = env.call(command.command, arguments[1 .. ^1])

stdCommand "import", "path", 1:
  ## Evaluate another source file in the current scope.
  let node = loadSourceFile(env.eval(arguments[0]).requireText(), arguments[0].pos)
  result = env.evalBlock(node.statements)

stdCommand "use", "module [namespace]", 1 .. 2:
  ## Load a module and bind it under a namespace, or, with a colon body of
  ## `only`/`except` filters, bind the selected names directly.
  if layout == ColonLayout and arguments.len == 2:
    raise newException(
      EvaluatorError, "use filters cannot be combined with a module name"
    )
  if layout notin {NoLayout, ColonLayout}:
    raise newException(EvaluatorError, "use filters require a colon block")

  let requested = arguments[0].requireSymbol("module name")
  var entries: Table[string, Value]
  var name: string
  if env.hasNativeModule(requested):
    result = env.getNativeModule(requested)
    if result.kind != Record:
      raise newException(EvaluatorError, "native module exports must be a dictionary")
    entries = result.entries
    name = requested.moduleName
  else:
    let path = modulePath(arguments[0])
    let moduleEnv = env.child()
    discard moduleEnv.evalBlock(loadSourceFile(path, arguments[0].pos).statements)
    entries = moduleEnv.bindings
    result = record(entries)
    name = path.moduleName

  if layout == ColonLayout:
    env.useSelectedSymbols(entries, body)
    return nothing()
  if arguments.len == 2:
    name = arguments[1].requireSymbol("module namespace")
  env.define(name, result)

stdCommand "eval", "value...", any:
  ## Evaluate each argument, then evaluate any syntax it produced in the scope
  ## that syntax was captured from.
  result = nothing()
  for argument in arguments:
    result = env.evalSyntax(env.eval(argument))

stdCommand "eval-source", "source [path]", 1 .. 2:
  ## Parse and evaluate Owl source text in the current scope.
  let path =
    if arguments.len == 2: env.eval(arguments[1]).requireText() else: "<eval>"
  result = env.eval(parseSource(env.eval(arguments[0]).requireText(), path))

stdCommand "eval-file", "path", 1:
  ## Parse and evaluate a source file in the current scope.
  let path = env.eval(arguments[0]).requireText()
  result = env.eval(parseSource(readSource(path), path))

stdCommand "parse", "source", 1:
  ## Parse Owl source text into a syntax value captured in this scope.
  syntaxValue(parseSource(env.eval(arguments[0]).requireText(), "<input>"), env)

stdCommand "symbol-text", "symbol", 1:
  ## The text of a symbol, given either the symbol or a syntax value for it.
  let value = env.eval(arguments[0])
  let node = if value.kind == Syntax: value.syntax else: arguments[0]
  result = text(node.requireSymbol("symbol"))

stdCommand "statements", "script", 1:
  ## The statements of a script as a list of syntax values.
  let (node, sourceEnv) = env.scriptArg(arguments[0], "statements")
  result = list(node.statements.mapIt(syntaxValue(it, sourceEnv)))

stdCommand "body-of", "script tag", 2:
  ## The body of the first statement in a script that calls `tag`, as script
  ## syntax. Missing tags answer an empty script rather than failing.
  let (node, sourceEnv) = env.scriptArg(arguments[0], "body-of")
  let tag = env.eval(arguments[1]).requireText()
  for statement in node.statements:
    if statement.kind == Command and statement.callee.kind == Symbol and
        statement.callee.symbol == tag:
      return syntaxValue(script(statement.body), sourceEnv)
  result = syntaxValue(script(@[]), sourceEnv)

stdCommand "command-arg", "command index", 2:
  ## The syntax of one argument of a command, by position.
  let (node, sourceEnv) = env.commandArg(arguments[0], "command-arg")
  let index = env.eval(arguments[1]).requireNumber().int
  if index < 0 or index >= node.arguments.len:
    raise newException(EvaluatorError, "command-arg index out of range")
  result = syntaxValue(node.arguments[index], sourceEnv)

stdCommand "command-symbol", "command", 1:
  ## The callee name of a command that is called through a symbol.
  let (node, _) = env.commandArg(arguments[0], "command-symbol")
  if node.callee.kind != Symbol:
    raise newException(
      EvaluatorError, "command-symbol expects command syntax with a symbol callee"
    )
  result = text(node.callee.symbol)

stdCommand "command-body", "command", 1:
  ## The colon body of a command, as script syntax.
  let (node, sourceEnv) = env.commandArg(arguments[0], "command-body")
  result = syntaxValue(script(node.body), sourceEnv)

stdCommand "binding-symbol", "binding", 1:
  ## The name a binding introduces.
  text(env.bindingArg(arguments[0], "binding-symbol").node.bindingSymbol)

stdCommand "binding-value", "binding", 1:
  ## The syntax of the value a binding assigns.
  let (node, sourceEnv) = env.bindingArg(arguments[0], "binding-value")
  result = syntaxValue(node.value, sourceEnv)

stdCommand "eval-with", "symbol value body", 3:
  ## Evaluate body syntax in a child of the scope it came from, with one extra
  ## binding. This is what lets an Owl-level loop bind its iteration variable.
  let symbolNode = env.eval(arguments[0]).requireSyntax()
  let value = env.eval(arguments[1])
  let (node, sourceEnv) = env.syntaxArg(arguments[2])
  let local = sourceEnv.child()
  local.define(symbolNode.requireSymbol("binding symbol"), value)
  result =
    if node.kind == Script: local.evalBlock(node.statements) else: local.eval(node)

proc recordFieldOrder(fields: Value): seq[string] {.raises: [EvaluatorError].} =
  for item in fields:
    let field = item.requireText()
    if field in result:
      raise newException(EvaluatorError, &"duplicate record field: {field}")
    result.add field

stdCommand "record-constructor", "name fields defaults", 3:
  ## Build the constructor command behind `record Name:`. Fields are text
  ## names and defaults are syntax values evaluated per call.
  let shape = declaredShape(
    env.eval(arguments[0]).requireText(),
    env.eval(arguments[1]).requireList().recordFieldOrder()
  )
  let fieldOrder = shape.fields

  let defaults = env.eval(arguments[2]).requireList()
  for item in defaults:
    if item.kind != Syntax:
      raise newException(EvaluatorError, "record defaults must be syntax values")
  if fieldOrder.len != defaults.len:
    raise newException(EvaluatorError, "record fields/defaults length mismatch")

  result = nativeCommand(
    proc(
        env: Environment,
        arguments: seq[SyntaxNode],
        layout: LayoutKind,
        body: seq[SyntaxNode],
    ): Value {.raises: [EvaluatorError].} =
      discard layout
      if arguments.len > fieldOrder.len:
        raise newException(EvaluatorError, "record got too many arguments")

      # Which fields the call supplies is settled before any default is
      # evaluated, so a default that is about to be overwritten is never
      # evaluated at all. Most record literals set most of their fields.
      var overrides: seq[string]
      for node in body.bindingBody("record override"):
        if node.bindingSymbol notin fieldOrder:
          raise newException(
            EvaluatorError, &"unknown record field: {node.bindingSymbol}"
          )
        if node.bindingSymbol in overrides:
          raise newException(
            EvaluatorError, &"duplicate record override: {node.bindingSymbol}"
          )
        overrides.add node.bindingSymbol

      var entries = initTable[string, Value](max(nextPowerOfTwo(fieldOrder.len * 2), 4))
      for index, field in fieldOrder:
        if index >= arguments.len and field notin overrides:
          entries[field] = env.evalSyntax(defaults[index])
      for index, argument in arguments:
        entries[fieldOrder[index]] = env.eval(argument)
      for node in body:
        entries[node.bindingSymbol] = env.eval(node.value)
      result = record(entries, shape)
  )

stdCommand "record-predicate", "name fields", 2:
  ## Build the `Name?` command behind `record Name:`. It answers true for the
  ## records built against the shape this name and field list declare.
  let shape = declaredShape(
    env.eval(arguments[0]).requireText(),
    env.eval(arguments[1]).requireList().recordFieldOrder()
  )
  result = nativeCommand(
    proc(
        env: Environment,
        arguments: seq[SyntaxNode],
        layout: LayoutKind,
        body: seq[SyntaxNode],
    ): Value {.raises: [EvaluatorError].} =
      discard layout
      discard body
      if arguments.len != 1:
        raise newException(EvaluatorError, "record predicate expects one value")
      let value = env.eval(arguments[0])
      result = boolean(value.kind == Record and value.shape == shape)
  )

template foldNumbers(
    env: Environment, arguments: seq[SyntaxNode], step: untyped
): Value =
  ## Fold the arguments left as numbers, combining `total` with each `operand`.
  block:
    var total {.inject.} = env.eval(arguments[0]).requireNumber()
    for index in 1 ..< arguments.len:
      let operand {.inject.} = env.eval(arguments[index]).requireNumber()
      total = step
    number(total)

template updateNumber(
    env: Environment, arguments: seq[SyntaxNode], step: untyped
): Value =
  ## Combine an existing numeric symbol's `total` with `operand` and store it.
  block:
    let symbol = arguments[0].requireSymbol("assignment target")
    let
      total {.inject.} = env.get(symbol).requireNumber()
      operand {.inject.} = env.eval(arguments[1]).requireNumber()
      updated = number(step)
    env.setSymbol(symbol, updated)
    updated

template compareNumbers(
    env: Environment, arguments: seq[SyntaxNode], test: untyped
): Value =
  ## Compare two numeric arguments as `left` and `right`.
  block:
    let
      left {.inject.} = env.eval(arguments[0]).requireNumber()
      right {.inject.} = env.eval(arguments[1]).requireNumber()
    boolean(test)

stdCommand "+", "number...", 1 .. int.high:
  ## Sum of the arguments, folded left.
  env.foldNumbers(arguments, total + operand)

stdCommand "-", "number...", 1 .. int.high:
  ## Difference of the arguments, folded left.
  env.foldNumbers(arguments, total - operand)

stdCommand "*", "number...", 1 .. int.high:
  ## Product of the arguments, folded left.
  env.foldNumbers(arguments, total * operand)

stdCommand "/", "number...", 1 .. int.high:
  ## Quotient of the arguments, folded left.
  env.foldNumbers(arguments, total / operand)

stdCommand "+=", "symbol number", 2:
  ## Add to an existing numeric symbol and answer the new value.
  env.updateNumber(arguments, total + operand)

stdCommand "-=", "symbol number", 2:
  ## Subtract from an existing numeric symbol and answer the new value.
  env.updateNumber(arguments, total - operand)

stdCommand "*=", "symbol number", 2:
  ## Multiply an existing numeric symbol and answer the new value.
  env.updateNumber(arguments, total * operand)

stdCommand "/=", "symbol number", 2:
  ## Divide an existing numeric symbol and answer the new value.
  env.updateNumber(arguments, total / operand)

stdCommand "=", "left right", 2:
  ## Whether both arguments render to the same text.
  boolean($env.eval(arguments[0]) == $env.eval(arguments[1]))

stdCommand "<", "left right", 2:
  ## Whether the left number is less than the right.
  env.compareNumbers(arguments, left < right)

stdCommand "<=", "left right", 2:
  ## Whether the left number is less than or equal to the right.
  env.compareNumbers(arguments, left <= right)

stdCommand ">", "left right", 2:
  ## Whether the left number is greater than the right.
  env.compareNumbers(arguments, left > right)

stdCommand ">=", "left right", 2:
  ## Whether the left number is greater than or equal to the right.
  env.compareNumbers(arguments, left >= right)

stdCommand "floor", "number", 1:
  ## The largest integer that is not greater than the argument.
  number(floor(env.eval(arguments[0]).requireNumber()))

stdCommand "when", "condition", 1:
  ## Evaluate the body in the current scope while the condition is truthy.
  if env.eval(arguments[0]).isTruthy: env.evalBlock(body) else: nothing()

stdCommand "while", "condition", 1:
  ## Repeat the body while the condition stays truthy, answering its last
  ## value, or `nothing` when the body never ran.
  result = nothing()
  while env.eval(arguments[0]).isTruthy:
    result = env.evalBlock(body)

stdCommand "pick", "condition then else", 3:
  ## Evaluate the condition, then only the branch it selects.
  env.eval(arguments[if env.eval(arguments[0]).isTruthy: 1 else: 2])

stdCommand "and", "value...", any:
  ## The first falsey argument, or the last one, evaluating no further.
  result = boolean(true)
  for argument in arguments:
    result = env.eval(argument)
    if not result.isTruthy:
      return

stdCommand "or", "value...", any:
  ## The first truthy argument, or the last one, evaluating no further.
  result = boolean(false)
  for argument in arguments:
    result = env.eval(argument)
    if result.isTruthy:
      return

stdCommand "with", "resource name", 2:
  ## Open a resource, bind it under `name` for the body, and close it
  ## afterwards even if the body fails.
  let binding = arguments[1].requireSymbol("with binding")
  let resource = env.callOptionalField(env.eval(arguments[0]), "open")
  let local = env.child()
  local.define(binding, resource)
  try:
    result = local.evalBlock(body)
  finally:
    discard local.callOptionalField(resource, "close")

stdCommand "list", "", 0:
  ## An empty list.
  list(@[])

stdCommand "dict", "", 0:
  ## An empty dictionary.
  record(initTable[string, Value]())

stdCommand "cons", "value list", 2:
  ## A new list with the value in front of an existing list.
  var items = @[env.eval(arguments[0])]
  items.add env.eval(arguments[1]).requireList().toSeq
  result = list(items)

stdCommand "first", "list", 1:
  ## The first item of a non-empty list.
  let values = env.eval(arguments[0]).requireList()
  if values.len == 0:
    raise newException(EvaluatorError, "first expects a non-empty list")
  result = values[0]

stdCommand "rest", "list", 1:
  ## Everything after the first item, or an empty list.
  env.eval(arguments[0]).requireList().rest

stdCommand "empty?", "list", 1:
  ## Whether a list has no items.
  boolean(env.eval(arguments[0]).requireList().len == 0)

stdCommand "length", "value", 1:
  ## The number of items in a list or dictionary, or characters in text.
  let value = env.eval(arguments[0])
  case value.kind
  of List, Record, Text:
    number(value.len.float64)
  else:
    raise newException(
      EvaluatorError, &"expected list, record, or text, got {value}"
    )

stdCommand "nth", "list index", 2:
  ## The item at a position in a list.
  let values = env.eval(arguments[0]).requireList()
  result = values[values.checkedIndex(env.eval(arguments[1]).requireNumber, "nth")]

stdCommand "append-value", "list value", 2:
  ## A new list with the value on the end.
  env.eval(arguments[0]).requireList() & env.eval(arguments[1])

stdCommand "append", "list value", 2:
  ## Add a value to the end of a named list in place.
  let value = env.eval(arguments[1])
  # Growing the binding in place is what keeps this O(1). Rebuilding the list
  # through cons/rest made a single append cost a full copy of the list, so
  # filling an n-item list cost O(n^3) value copies.
  if arguments[0].kind == Symbol or (
    arguments[0].kind == Command and arguments[0].callee.kind == Symbol and
    arguments[0].arguments.len == 0 and arguments[0].layout == NoLayout and
    arguments[0].body.len == 0
  ):
    let name = arguments[0].requireSymbol("list name")
    let owner = env.find(name)
    if owner != nil:
      var appended = false
      owner.bindings.withValue(name, existing):
        if existing[].kind == List:
          existing[] = existing[] & value
          appended = true
      if appended:
        return nothing()
  env.setTarget(
    arguments[0], env.eval(arguments[0]).requireList() & value
  )
  result = nothing()

proc dropFront(
    env: Environment, arguments: seq[SyntaxNode]
): Value {.raises: [EvaluatorError].} =
  let values = env.eval(arguments[0]).requireList()
  let count = max(int(env.eval(arguments[1]).requireNumber), 0)
  result =
    if count >= values.len: list(@[]) else: list(values.toSeq[count .. ^1])

stdCommand "drop-front", "list count", 2:
  ## A new list without the leading `count` items.
  env.dropFront(arguments)

stdCommand "pop-front", "list count", 2:
  ## Drop the leading `count` items from a named list in place.
  env.setTarget(arguments[0], env.dropFront(arguments))
  result = nothing()

stdCommand "list-from", "syntax-list", 1:
  ## Evaluate a list of syntax values into a list of values. This is what
  ## `[]:` is built from.
  let nodes = env.eval(arguments[0]).requireList()
  var items = newSeqOfCap[Value](nodes.len)
  for node in nodes.items:
    items.add env.evalSyntax(node)
  result = list(items)

stdCommand "dict-from", "syntax-list", 1:
  ## Evaluate a list of binding syntax values into a dictionary. This is what
  ## `{}:` is built from.
  let nodes = env.eval(arguments[0]).requireList()
  # Sized once rather than grown, and filled last-to-first: the recursive
  # version put the head entry in on top of the tail, so an earlier binding
  # wins a repeated key and the later ones are evaluated first.
  var entries = initTable[string, Value](max(nextPowerOfTwo(nodes.len * 2), 4))
  for index in countdown(nodes.len - 1, 0):
    let node = nodes[index].requireSyntax()
    if node.kind != Binding:
      raise newException(EvaluatorError, "dict-from expects binding syntax")
    entries[node.bindingSymbol] =
      nodes[index].syntaxEnvironment(env).eval(node.value)
  result = record(entries)

stdCommand "dict-put", "dict key value", 3:
  ## A dictionary or record with one key updated.
  env.eval(arguments[0]).setFieldValue(
    env.eval(arguments[1]).requireText(), env.eval(arguments[2])
  )

stdCommand "dict-get", "dict key", 2:
  ## Read a key from a dictionary or record; a missing key is an error.
  env.eval(arguments[0]).field(env.eval(arguments[1]).requireText())

stdAlias "field", "dict-get", "Read a field; this is what `a.b` calls."

stdCommand "index", "value key", 2:
  ## Read a list position or a dictionary/record key; this is what `a.[k]`
  ## calls.
  indexValue(env.eval(arguments[0]), env.eval(arguments[1]))

stdCommand "concat", "text...", any:
  ## The arguments joined into one text value.
  # TODO: Make this work for lists and dictionaries
  var parts = newSeqOfCap[string](arguments.len)
  for argument in arguments:
    parts.add env.eval(argument).requireText()
  result = text(parts.join())

stdCommand "to-string", "value", 1:
  ## A value rendered as the Owl source that would produce it.
  text($env.eval(arguments[0]))

# Must stay in step with `record Stream:` in the prelude, or host-built
# streams and `Stream?` end up with different shapes.
const StreamFields =
  ["open", "close", "read", "read-line", "read-all", "write", "write-line"]

type
  StreamStep = proc(): Value {.closure, raises: [EvaluatorError].}
  StreamEmit = proc(part: string) {.closure, raises: [EvaluatorError].}

  StreamOps = object
    ## The handlers a stream supplies. Whatever is left nil becomes a field
    ## that reports an unsupported operation when it is called.
    label: string
    open, close, read, readLine, readAll: StreamStep
    emit: StreamEmit

proc niladic(label: string, step: StreamStep): Value {.raises: [].} =
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
      step()
  )

proc writer(label: string, emit: StreamEmit, newline: bool): Value {.raises: [].} =
  nativeCommand(
    proc(
        env: Environment,
        arguments: seq[SyntaxNode],
        layout: LayoutKind,
        body: seq[SyntaxNode],
    ): Value {.raises: [EvaluatorError].} =
      discard label
      discard layout
      discard body
      result = nothing()
      for argument in arguments:
        result = env.eval(argument)
        emit(result.streamText())
      if newline:
        emit("\n")
  )

proc unsupported(name: string): Value {.raises: [].} =
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

proc streamRecord(ops: StreamOps): Value {.raises: [].} =
  ## Assemble the `Stream` record for a set of handlers. Streams are records so
  ## that Owl code can reach their operations as ordinary command fields.
  var entries = initTable[string, Value](8)
  for (name, step) in {
    "open": ops.open, "close": ops.close, "read": ops.read,
    "read-line": ops.readLine, "read-all": ops.readAll,
  }:
    if step != nil:
      entries[name] = niladic(ops.label & " " & name, step)
  if ops.emit != nil:
    entries["write"] = writer(ops.label & " write", ops.emit, newline = false)
    entries["write-line"] = writer(ops.label & " write-line", ops.emit, newline = true)
  for name in StreamFields:
    if not entries.hasKey(name):
      entries[name] = unsupported(name)
  result = record(entries, declaredShape("Stream", @StreamFields))

proc ioError(error: ref IOError): ref EvaluatorError {.raises: [].} =
  newException(EvaluatorError, error.msg)

proc readAllFrom(file: File): Value {.raises: [EvaluatorError].} =
  try:
    var content = ""
    while not file.endOfFile:
      content.add file.readChar()
    text(content)
  except IOError as error:
    raise error.ioError()

proc readCharFrom(file: File): Value {.raises: [EvaluatorError].} =
  try:
    if file.endOfFile: nothing() else: text($file.readChar())
  except IOError as error:
    raise error.ioError()

proc stdinStream(): Value {.raises: [].} =
  proc readLine(): Value {.raises: [EvaluatorError].} =
    var line: string
    try:
      if readLineFromStdin("", line): text(line) else: nothing()
    except IOError as error:
      raise error.ioError()

  result = streamRecord(StreamOps(
    label: "stdin",
    open: () => nothing(),
    close: () => nothing(),
    read: () => readCharFrom(stdin),
    readLine: readLine,
    readAll: () => readAllFrom(stdin),
  ))

proc stdoutStream(): Value {.raises: [].} =
  proc emit(part: string) {.raises: [EvaluatorError].} =
    try:
      stdout.write(part)
    except IOError as error:
      raise error.ioError()

  result = streamRecord(StreamOps(
    label: "stdout",
    open: () => nothing(),
    close: () => nothing(),
    emit: emit,
  ))

proc fileMode(mode: string): FileMode {.raises: [EvaluatorError].} =
  case mode
  of "r", "rb": fmRead
  of "w", "wb": fmWrite
  of "a", "ab": fmAppend
  else:
    raise newException(EvaluatorError, &"unsupported file mode: {mode}")

proc openFileStream(path, mode: string): Value {.raises: [].} =
  var
    file: File
    opened = false

  proc require() {.raises: [EvaluatorError].} =
    if not opened:
      raise newException(EvaluatorError, "file is not open")

  proc open(): Value {.raises: [EvaluatorError].} =
    if not opened:
      try:
        if not open(file, path, fileMode(mode)):
          raise newException(EvaluatorError, &"could not open file: {path}")
        opened = true
      except IOError as error:
        raise error.ioError()
    nothing()

  proc close(): Value {.raises: [EvaluatorError].} =
    if opened:
      close(file)
      opened = false
    nothing()

  proc read(): Value {.raises: [EvaluatorError].} =
    require()
    readCharFrom(file)

  proc readLine(): Value {.raises: [EvaluatorError].} =
    require()
    try:
      if file.endOfFile: nothing() else: text(file.readLine())
    except IOError as error:
      raise error.ioError()

  proc readAll(): Value {.raises: [EvaluatorError].} =
    require()
    readAllFrom(file)

  proc emit(part: string) {.raises: [EvaluatorError].} =
    require()
    try:
      file.write(part)
    except IOError as error:
      raise error.ioError()

  result = streamRecord(StreamOps(
    label: "file",
    open: open, close: close,
    read: read, readLine: readLine, readAll: readAll,
    emit: emit,
  ))

proc openStringStream(content: string): Value {.raises: [].} =
  var
    buffer = content
    position = 0
    opened = false

  proc require() {.raises: [EvaluatorError].} =
    if not opened:
      raise newException(EvaluatorError, "string stream is not open")

  proc open(): Value {.raises: [EvaluatorError].} =
    position = 0
    opened = true
    nothing()

  proc close(): Value {.raises: [EvaluatorError].} =
    opened = false
    nothing()

  proc read(): Value {.raises: [EvaluatorError].} =
    require()
    if position >= buffer.len:
      return nothing()
    result = text($buffer[position])
    inc position

  proc readLine(): Value {.raises: [EvaluatorError].} =
    require()
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

  proc readAll(): Value {.raises: [EvaluatorError].} =
    require()
    result = text(buffer[min(position, buffer.len) .. ^1])
    position = buffer.len

  proc emit(part: string) {.raises: [EvaluatorError].} =
    buffer.add part

  result = streamRecord(StreamOps(
    label: "string",
    open: open, close: close,
    read: read, readLine: readLine, readAll: readAll,
    emit: emit,
  ))

stdCommand "open-file", "[path] mode", 1 .. 2:
  ## A file-backed stream. With one argument the path is a scratch file.
  if arguments.len == 1:
    openFileStream(getTempDir() / "owl-example-stream.txt",
        env.eval(arguments[0]).requireText())
  else:
    openFileStream(
      env.eval(arguments[0]).requireText(), env.eval(arguments[1]).requireText()
    )

stdCommand "open-string", "text", 1:
  ## A stream backed by a text buffer.
  openStringStream(env.eval(arguments[0]).requireText())

stdCommand "print", "value...", any:
  ## Write each argument to standard output without a trailing newline.
  var parts = newSeqOfCap[string](arguments.len)
  result = nothing()
  for argument in arguments:
    result = env.eval(argument)
    parts.add result.streamText()
  try:
    stdout.write parts.join()
  except IOError as error:
    raise error.ioError()

stdCommand "error", "value...", any:
  ## Fail with the arguments rendered as the message.
  var message = ""
  for argument in arguments:
    message.add $env.eval(argument)
  raise newException(EvaluatorError, message)

stdCommand "command-line-arguments", "", 0:
  ## The arguments this program was started with.
  list((try: commandLineParams() except CatchableError: @[]).mapIt(text(it)))

stdCommand "standard-commands", "", 0:
  ## Org-formatted documentation for every native command.
  const Documentation = block:
    var entries: seq[string]
    for name, doc in commandDocs:
      entries.add doc.strVal
    sorted(entries)
  result = list(Documentation.mapIt(text(it)))

stdCommand "repl", "", 0:
  ## Read, evaluate, and print lines until `q`, `quit`, or end of input.
  proc emit(target: File, message: string) {.raises: [EvaluatorError].} =
    try:
      target.write message
    except IOError as error:
      raise error.ioError()

  var history: seq[string]
  result = nothing()
  while true:
    var line: string
    try:
      if not readLineFromStdin("> ", line):
        break
    except IOError as error:
      raise error.ioError()
    case line
    of "q", "quit":
      break
    of "history":
      stdout.emit $history & "\n"
    else:
      history.add line
      try:
        result = env.eval(parse(line, "<repl>"))
        stdout.emit $result & "\n"
      except OwlError as error:
        stderr.emit report(error, useColor = true)
      except CatchableError as error:
        stderr.emit error.msg & "\n"

stdCommand "exit", "[code]", 0 .. 1:
  ## Stop the program, with an optional exit code.
  if arguments.len == 0:
    quit(0)
  quit(env.eval(arguments[0]).requireNumber().toInt())

proc addStandardCommands*(env: Environment) {.raises: [].} =
  ## Install the native commands into `env` and into the command environment
  ## that backs it, so commands can share state across calls.
  commandEnv = newEnvironment()
  commandEnv.evaluator = env.evaluator
  commandEnv.commandCaller = env.commandCaller
  env.fallback = commandEnv
  recordShapes = initTable[string, RecordShape]()

  var globals = {
    "stdin": stdinStream(), "stdout": stdoutStream(), "nothing": nothing()
  }.toTable
  for registration in commandRegistry:
    globals[registration.name] = nativeCommand(registration.command)
  for (alias, target) in commandAliases:
    globals[alias] = globals.getOrDefault(target)

  for name, value in globals:
    env.define(name, value)
    commandEnv.define(name, value)
