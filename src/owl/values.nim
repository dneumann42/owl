import std/[algorithm, streams, strutils, tables]

import syntax

const MaxRenderedLineLength = 80

type
  ValueKind* = enum
    Nothing
    Number
    Boolean
    Text
    Stream
    List
    Dictionary
    Record
    Syntax
    Command
    Native

  EvaluatorError* = object of OwlError

  ListBuffer* = ref object
    values*: seq[Value]

  NativeValue* = ref object of RootObj

  StreamKind* = enum
    InputStream
    OutputStream

  Environment* = ref object
    parent*: Environment
    fallback*: Environment
    bindings*: Table[string, Value]
    nativeModules*: ref Table[string, Value]
    evaluator*: proc(
      env: Environment, node: SyntaxNode
    ): Value {.closure, raises: [EvaluatorError].}
    commandCaller*: proc(
      env: Environment, command: CommandValue, arguments: seq[SyntaxNode],
      layout: LayoutKind, body: seq[SyntaxNode]
    ): Value {.closure, raises: [EvaluatorError].}

  NativeCommand* = proc(
    env: Environment, arguments: seq[SyntaxNode], layout: LayoutKind,
    body: seq[SyntaxNode]
  ): Value {.closure, raises: [EvaluatorError].}

  CommandKind* = enum
    NativeCommandKind
    ClosureCommandKind

  CommandValue* = ref object
    case kind*: CommandKind
    of NativeCommandKind:
      native*: NativeCommand
    of ClosureCommandKind:
      parameters*: seq[string]
      body*: seq[SyntaxNode]
      captured*: Environment
      evaluatesArguments*: bool
      acceptsBlock*: bool
      usesBlock*: bool ## body mentions `block`, so a call must bind it
      usesLayout*: bool ## body mentions `layout`, so a call must bind it

  Value* = object
    case kind*: ValueKind
    of Nothing:
      discard
    of Number:
      number*: float64
    of Boolean:
      boolean*: bool
    of Text:
      text*: string
    of Stream:
      stream*: StreamKind
    of List:
      ## A view onto a shared buffer: `count` elements starting at `start`.
      ## Taking a tail is O(1) because the tail shares the buffer, and a view
      ## can only ever see the elements its own `count` covers.
      buffer*: ListBuffer
      start*, count*: int
    of Dictionary:
      entries*: Table[string, Value]
    of Record:
      recordName*: string
      recordEntries*: Table[string, Value]
      recordFields*: seq[string]
    of Syntax:
      syntax*: SyntaxNode
      syntaxEnv*: Environment
    of Command:
      command*: CommandValue
    of Native:
      native*: NativeValue

proc nothing*(): Value {.raises: [].} =
  Value(kind: Nothing)

proc number*(value: float64): Value {.raises: [].} =
  Value(kind: Number, number: value)

proc boolean*(value: bool): Value {.raises: [].} =
  Value(kind: Boolean, boolean: value)

proc text*(value: sink string): Value {.raises: [].} =
  Value(kind: Text, text: value)

proc stream*(value: StreamKind): Value {.raises: [].} =
  Value(kind: Stream, stream: value)

proc list*(items: sink seq[Value]): Value {.raises: [].} =
  let count = items.len
  result = Value(kind: List, buffer: ListBuffer(values: items), start: 0, count: count)

proc listLen*(value: Value): int {.inline, raises: [].} =
  ## How many elements this list view covers.
  value.count

iterator items*(value: Value): Value =
  for index in value.start ..< value.start + value.count:
    yield value.buffer.values[index]

proc at*(value: Value, index: int): Value {.inline, raises: [].} =
  ## The element at `index` within this view. The caller checks the bounds.
  value.buffer.values[value.start + index]

proc listSeq*(value: Value): seq[Value] {.raises: [].} =
  ## Copy the view out as a plain sequence.
  if value.buffer.isNil or value.count <= 0:
    @[]
  else:
    value.buffer.values[value.start ..< value.start + value.count]

proc listRest*(value: Value): Value {.raises: [].} =
  ## Everything after the first element, sharing the buffer rather than
  ## copying it. This is what keeps a recursive walk linear.
  if value.count <= 1:
    list(@[])
  else:
    Value(kind: List, buffer: value.buffer, start: value.start + 1,
        count: value.count - 1)

proc listAppended*(value: Value, item: sink Value): Value {.raises: [].} =
  ## This list with `item` on the end.
  ##
  ## When the view already ends the buffer the item is written straight into
  ## it: every other view keeps its own smaller `count`, so none of them can
  ## see the new element. Otherwise the view is copied out first.
  if value.buffer.isNil:
    return list(@[item])
  if value.start + value.count == value.buffer.values.len:
    value.buffer.values.add item
    Value(kind: List, buffer: value.buffer, start: value.start,
        count: value.count + 1)
  else:
    var copied = value.listSeq()
    copied.add item
    list(copied)

proc dictionary*(entries: sink Table[string, Value]): Value {.raises: [].} =
  Value(kind: Dictionary, entries: entries)

proc record*(
    name: sink string, entries: sink Table[string, Value], fields: sink seq[string]
): Value {.raises: [].} =
  Value(kind: Record, recordName: name, recordEntries: entries, recordFields: fields)

proc syntaxValue*(node: SyntaxNode, env: Environment = nil): Value {.raises: [].} =
  Value(kind: Syntax, syntax: node, syntaxEnv: env)

proc nativeCommand*(native: NativeCommand): Value {.raises: [].} =
  Value(kind: Command, command: CommandValue(kind: NativeCommandKind, native: native))

proc nativeValue*(native: NativeValue): Value {.raises: [].} =
  Value(kind: Native, native: native)

proc referencesSymbol(node: SyntaxNode, name: string): bool {.raises: [].}

proc referencesSymbol(nodes: seq[SyntaxNode], name: string): bool {.raises: [].} =
  for node in nodes:
    if node.referencesSymbol(name):
      return true

proc referencesSymbol(node: SyntaxNode, name: string): bool {.raises: [].} =
  ## Whether `name` appears anywhere in this subtree, nested closures included.
  ##
  ## Answered once when a closure is created so that calling it can skip
  ## binding names the body never reads.
  if node.isNil:
    return false
  case node.kind
  of Symbol:
    node.symbol == name
  of String:
    false
  of Binding:
    node.value.referencesSymbol(name)
  of Script:
    node.statements.referencesSymbol(name)
  of Command:
    node.callee.referencesSymbol(name) or node.arguments.referencesSymbol(name) or
      node.body.referencesSymbol(name)

proc usesCallName(
    parameters: seq[string], body: seq[SyntaxNode], name: string
): bool {.raises: [].} =
  ## Whether a call has to bind `name`. A parameter of the same name is the
  ## body's own, so binding the call's would silently shadow it.
  name notin parameters and body.referencesSymbol(name)

proc closureCommand*(
    parameters: sink seq[string], body: sink seq[SyntaxNode], captured: Environment,
    evaluatesArguments, acceptsBlock: bool
): Value {.raises: [].} =
  Value(
    kind: Command,
    command: CommandValue(
      kind: ClosureCommandKind,
      usesBlock: parameters.usesCallName(body, "block"),
      usesLayout: parameters.usesCallName(body, "layout"),
      parameters: parameters,
      body: body,
      captured: captured,
      evaluatesArguments: evaluatesArguments,
      acceptsBlock: acceptsBlock
    )
  )

proc isTruthy*(value: Value): bool {.raises: [].} =
  case value.kind
  of Nothing:
    false
  of Boolean:
    value.boolean
  else:
    true

proc addIndent(target: var string, amount: int) {.raises: [].} =
  for _ in 0 ..< amount:
    target.add ' '

proc render(value: Value, indent: int): string {.raises: [].}

proc renderList(value: Value, indent: int): string {.raises: [].} =
  if value.listLen == 0:
    return "[]"

  var compactParts: seq[string]
  var canUseCompact = true
  for item in value.items:
    let rendered = item.render(indent + 2)
    if rendered.contains('\n'):
      canUseCompact = false
      break
    compactParts.add rendered

  let compact = "[]:\n" & repeat(" ", indent + 2) & compactParts.join(", ")
  if canUseCompact and compact.len <= MaxRenderedLineLength:
    return compact

  result = "[]:"
  for item in value.items:
    result.add '\n'
    result.addIndent(indent + 2)
    result.add item.render(indent + 2)

proc renderDictionaryLiteral(value: Value, indent: int): string {.raises: [].} =
  if value.entries.len == 0:
    return "{}"

  result = "{}:"
  var keys: seq[string]
  for key in value.entries.keys:
    keys.add key
  keys.sort()

  var compactParts: seq[string]
  var canUseCompact = true
  for key in keys:
    let rendered = value.entries.getOrDefault(key).render(indent + 2)
    if rendered.contains('\n'):
      canUseCompact = false
      break
    compactParts.add key & " = " & rendered

  let compact = "{}:\n" & repeat(" ", indent + 2) & compactParts.join(", ")
  if canUseCompact and compact.len <= MaxRenderedLineLength:
    return compact

  for key in keys:
    result.add '\n'
    result.addIndent(indent + 2)
    result.add key
    result.add " = "
    result.add value.entries.getOrDefault(key).render(indent + 2)

proc renderDictionary(value: Value, indent: int): string {.raises: [].} =
  var keys: seq[string]
  for key in value.entries.keys:
    keys.add key
  keys.sort()

  var canUseLiteral = true
  for key in keys:
    if not key.isIdentifierSymbol:
      canUseLiteral = false
      break
  if canUseLiteral:
    return value.renderDictionaryLiteral(indent)

  result = "(dict)"
  for key in keys:
    result = "(dict-put " & result & " " & quote(key) & " " &
      value.entries.getOrDefault(key).render(indent) & ")"

proc render(value: Value, indent: int): string {.raises: [].} =
  case value.kind
  of Nothing:
    "nothing"
  of Number:
    if value.number == value.number.int.float:
      $value.number.int
    else:
      $value.number
  of Boolean:
    if value.boolean: "true" else: "false"
  of Text:
    quote(value.text)
  of Stream:
    case value.stream
    of InputStream:
      "<stdin>"
    of OutputStream:
      "<stdout>"
  of List:
    value.renderList(indent)
  of Dictionary:
    value.renderDictionary(indent)
  of Record:
    var parts: seq[string]
    for key in value.recordFields:
      if value.recordEntries.hasKey(key):
        parts.add key & ": " & value.recordEntries.getOrDefault(key).render(indent)
    "{" & parts.join(", ") & "}"
  of Syntax:
    $value.syntax
  of Command:
    "<command>"
  of Native:
    "<native>"

proc `$`*(value: Value): string {.raises: [].} =
  value.render(0)

proc write*(stream: streams.Stream, value: Value) {.raises: [IOError, OSError].} =
  stream.write($value)

proc parseNumber*(symbol: string): tuple[ok: bool, value: Value] {.raises: [].} =
  if symbol.len == 0 or (
      symbol[0] notin {'0' .. '9'} and
      not (symbol.len > 1 and symbol[0] in {'+', '-'} and symbol[1] in {'0' .. '9'})):
    return (false, nothing())
  try:
    if symbol.contains('.') or symbol.contains('e') or symbol.contains('E'):
      return (true, number(parseFloat(symbol)))
    return (true, number(parseInt(symbol).float64))
  except ValueError:
    return (false, nothing())

when isMainModule:
  discard
