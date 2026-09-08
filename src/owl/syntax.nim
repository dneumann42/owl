import std/[hashes, strformat, strutils, tables]

type
  SourceID* = uint32

  SourcePos* = object
    source*: SourceID
    line*: uint32
    column*: uint16

  SourceInfo* = object
    path*: string
    lines*: seq[string]
    fingerprint: Hash

  DiagnosticFrame* = object
    pos*: SourcePos
    label*: string

  OwlError* = object of CatchableError
    primary*: SourcePos
    frames*: seq[DiagnosticFrame]

  SyntaxKind* = enum
    Script
    Binding
    Command
    Symbol
    String

  LayoutKind* = enum
    NoLayout
    ColonLayout
    ContinuationLayout

  TypeSyntaxNodeKind* = enum
    Function
    TypeSpec
    Symbol

  TypeSyntaxNode* = object
    case kind*: TypeSyntaxNodeKind
    of Function:
      returnType*: ref TypeSyntaxNode
      parameters*: seq[TypeSyntaxNode]
    of TypeSpec:
      genericType*: ref TypeSyntaxNode
      specifications*: seq[TypeSyntaxNode]
    of Symbol:
      symbol*: string

  SyntaxNode* = ref object
    pos*: SourcePos
    hangingPipe*: bool
    typed*: seq[TypeSyntaxNode]
    case kind*: SyntaxKind
    of Script:
      statements*: seq[SyntaxNode]
    of Binding:
      bindingSymbol*: string
      value*: SyntaxNode
    of Command:
      callee*: SyntaxNode
      arguments*: seq[SyntaxNode]
      layout*: LayoutKind
      body*: seq[SyntaxNode]
    of Symbol:
      symbol*: string
    of String:
      stringValue*: string

const
  NoSource* = SourceID(0)
  Red* = "\e[31m"
  BoldRed* = "\e[1;31m"
  Reset* = "\e[0m"

var sourceRegistry: seq[SourceInfo]
var sourceRegistryByKey: Table[string, SourceID]

proc `==`*(a, b: TypeSyntaxNode): bool =
  if a.kind != b.kind:
    return false
  case a.kind:
  of Function:
    if a.returnType.isNil != b.returnType.isNil:
      return false
    if not a.returnType.isNil and a.returnType[] != b.returnType[]:
      return false
    if a.parameters.len != b.parameters.len:
      return false
    for i in 0 ..< a.parameters.len:
      if a.parameters[i] != b.parameters[i]:
        return false
    result = true
  of TypeSpec:
    if a.genericType.isNil != b.genericType.isNil:
      return false
    if not a.genericType.isNil and a.genericType[] != b.genericType[]:
      return false
    if a.specifications.len != b.specifications.len:
      return false
    for i in 0 ..< a.specifications.len:
      if a.specifications[i] != b.specifications[i]:
        return false
    result = true
  of Symbol:
    result = a.symbol == b.symbol

proc isType*(s: SyntaxNode, ts: openArray[TypeSyntaxNode]): bool =
  result = true
  if s.typed.len == 0:
    return false
  if s.typed.len != ts.len:
    return false
  for i in 0 ..< s.typed.len:
    if s.typed[i] != ts[i]:
      return false

proc isType*(s: SyntaxNode, t: TypeSyntaxNode): bool =
  result = s.isType([t])

proc symbolTypeNode*(sym: string): TypeSyntaxNode =
  TypeSyntaxNode(kind: Symbol, symbol: sym)

proc functionTypeNode*(sym: string, returnType: TypeSyntaxNode, parameters: openArray[TypeSyntaxNode] = []): TypeSyntaxNode =
  result = TypeSyntaxNode(kind: Function)
  new(result.returnType)
  result.returnType[] = returnType
  result.parameters = @parameters

let
  TNumber* = symbolTypeNode"Number"

proc noSourcePos*(): SourcePos {.raises: [].} =
  SourcePos(source: NoSource, line: 0, column: 0)

proc sourcePos*(source: SourceID, line, column: int): SourcePos {.raises: [].} =
  SourcePos(source: source, line: uint32(line), column: uint16(min(column, high(uint16).int)))

proc hasSource*(pos: SourcePos): bool {.raises: [].} =
  pos.source != NoSource and pos.line > 0 and pos.column > 0

proc sourceRegistryKey(source: string; path: string): string {.raises: [].} =
  path & "\0" & $source.len & "\0" & $hash(source)

proc registerSource*(source: string; path = "<input>"): SourceID {.raises: [].} =
  let key = sourceRegistryKey(source, path)
  let existing = sourceRegistryByKey.getOrDefault(key, NoSource)
  if existing != NoSource:
    return existing
  sourceRegistry.add SourceInfo(
    path: path,
    lines: source.splitLines,
    fingerprint: hash(source),
  )
  result = SourceID(sourceRegistry.len)
  sourceRegistryByKey[key] = result

proc sourceInfo*(id: SourceID): SourceInfo {.raises: [].} =
  if id == NoSource or id.int > sourceRegistry.len:
    SourceInfo(path: "<unknown>", lines: @[])
  else:
    sourceRegistry[id.int - 1]

proc registeredSourceCount*(): int {.raises: [].} =
  sourceRegistry.len

proc sourcePath*(pos: SourcePos): string {.raises: [].} =
  sourceInfo(pos.source).path

proc sourceLine*(pos: SourcePos): string {.raises: [].} =
  let info = sourceInfo(pos.source)
  if pos.line == 0 or pos.line.int > info.lines.len:
    ""
  else:
    info.lines[pos.line.int - 1]

proc script*(statements: sink seq[SyntaxNode], pos = noSourcePos()): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: Script, pos: pos, statements: statements)

proc binding*(symbol: sink string, value: SyntaxNode, pos = noSourcePos()): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: Binding, pos: pos, bindingSymbol: symbol, value: value)

proc command*(
    callee: SyntaxNode, arguments: sink seq[SyntaxNode], pos = noSourcePos()
): SyntaxNode {.raises: [].} =
  SyntaxNode(
    kind: Command, pos: pos, hangingPipe: callee.hangingPipe,
    callee: callee, arguments: arguments, layout: NoLayout, body: @[]
  )

proc symbol*(value: sink string, pos = noSourcePos()): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: Symbol, pos: pos, symbol: value)

proc stringLiteral*(value: sink string, pos = noSourcePos()): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: String, pos: pos, stringValue: value)

proc isIdentifierSymbol*(value: string): bool {.raises: [].} =
  ## Whether an atom reads as a name rather than punctuation or a number.
  if value.len == 0 or value[0] notin {'A' .. 'Z', 'a' .. 'z', '_'}:
    return false
  for c in value:
    if c notin {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '-', '?', '/'}:
      return false
  result = true

proc isNumericSymbol*(value: string): bool {.raises: [].} =
  ## Whether an atom starts the way a number literal does.
  value.len > 0 and (
    value[0] in {'0' .. '9'} or
    value.len > 1 and value[0] in {'+', '-'} and value[1] in {'0' .. '9'}
  )

proc isOperatorSymbol*(value: string): bool {.raises: [].} =
  ## Punctuation-like atoms such as `[]`, `{}`, or `+`. They bind a trailing
  ## colon as their own layout instead of leaving it to the enclosing command.
  not value.isIdentifierSymbol and not value.isNumericSymbol

proc loc*(pos: SourcePos): string {.raises: [].} =
  if pos.hasSource:
    &"{pos.sourcePath}:{pos.line}:{pos.column}"
  else:
    "<unknown>:0:0"

proc underline(column, width: int): string {.raises: [].} =
  repeat(' ', max(column - 1, 0)) & repeat('^', max(width, 1))

proc addLocationPreview(target: var string, pos: SourcePos, useColor: bool) {.raises: [].} =
  if not pos.hasSource:
    return
  let line = pos.sourceLine
  if line.len == 0:
    return
  target.add "  "
  target.add line
  target.add '\n'
  target.add "  "
  let marks = underline(pos.column.int, 1)
  if useColor:
    target.add BoldRed
    target.add marks
    target.add Reset
  else:
    target.add marks
  target.add '\n'

proc addFrame*(error: ref OwlError, pos: SourcePos, label: string) {.raises: [].} =
  if not pos.hasSource:
    return
  if error.primary.hasSource:
    if error.frames.len > 0 and error.frames[^1].pos == pos and error.frames[^1].label == label:
      return
    error.frames.add DiagnosticFrame(pos: pos, label: label)
  else:
    error.primary = pos

proc report*(error: ref OwlError, useColor = false): string {.raises: [].} =
  let message =
    if useColor:
      BoldRed & "error: " & Reset & error.msg
    else:
      "error: " & error.msg
  if error.primary.hasSource:
    result.add &"{error.primary.loc}: {message}\n"
    result.addLocationPreview(error.primary, useColor)
  else:
    result.add message
    result.add '\n'

  if error.frames.len > 0:
    result.add "Stack trace:\n"
    for frame in countdown(error.frames.high, 0):
      let item = error.frames[frame]
      result.add &"  at {item.pos.loc}"
      if item.label.len > 0:
        result.add &" in {item.label}"
      result.add '\n'

proc attachLayout*(
    node: SyntaxNode, layout: LayoutKind, body: sink seq[SyntaxNode]
): bool {.raises: [].} =
  case node.kind
  of Command:
    if layout == ContinuationLayout:
      node.layout = layout
      node.arguments.add body
      node.body = @[]
    else:
      node.layout = layout
      node.body = body
    true
  of Binding:
    attachLayout(node.value, layout, body)
  else:
    false

proc appendIndent(target: var string, amount: int) {.raises: [].} =
  for _ in 0 ..< amount:
    target.add ' '

proc quote*(value: string): string {.raises: [].} =
  result.add '"'
  for c in value:
    case c
    of '"':
      result.add "\\\""
    of '\\':
      result.add "\\\\"
    of '\n':
      result.add "\\n"
    of '\r':
      result.add "\\r"
    of '\t':
      result.add "\\t"
    else:
      result.add c
  result.add '"'

proc renderTypeDef(node: TypeSyntaxNode): string {.raises: [].}

proc renderTypeRef(node: ref TypeSyntaxNode): string {.raises: [].} =
  if not node.isNil:
    result = node[].renderTypeDef()

proc renderTypeDef(node: TypeSyntaxNode): string {.raises: [].} =
  case node.kind
  of Symbol:
    result = node.symbol
  of Function:
    result = "(" & node.returnType.renderTypeRef()
    for parameter in node.parameters:
      result.add " " & parameter.renderTypeDef()
    result.add ')'
  of TypeSpec:
    result = "<" & node.genericType.renderTypeRef()
    for specification in node.specifications:
      result.add " " & specification.renderTypeDef()
    result.add '>'

proc renderTypes(node: SyntaxNode): string {.raises: [].} =
  for annotation in node.typed:
    result.add '\''
    result.add annotation.renderTypeDef()

proc render(
  node: SyntaxNode, indent, column: int,
  statement, bindingValue, argumentLine: bool
): string {.raises: [].}

const FormatLineWidth* = 80

type FlatContext = enum
  FlatArgument
  FlatStatement
  FlatBinding
  FlatContinuation

proc renderFlat(
    node: SyntaxNode, context: FlatContext, valid: var bool
): string {.raises: [].} =
  ## Render a form only when it has a single-line representation. This small
  ## probe keeps line-breaking decisions independent of particular commands.
  case node.kind
  of Script, Binding:
    valid = false
  of Symbol:
    result.add node.symbol
    result.add node.renderTypes()
  of String:
    result.add quote(node.stringValue)
  of Command:
    if node.layout != NoLayout:
      valid = false
      return
    let needsParens =
      context == FlatArgument or
      context == FlatBinding and node.callee.kind == Command or
      context == FlatContinuation and node.arguments.len == 0
    if needsParens:
      result.add '('
    result.add node.callee.renderFlat(FlatArgument, valid)
    if not valid:
      return
    for argument in node.arguments:
      result.add ' '
      result.add argument.renderFlat(FlatArgument, valid)
      if not valid:
        return
    if needsParens:
      result.add ')'

proc renderFlat(
    node: SyntaxNode, context = FlatArgument
): tuple[text: string, valid: bool] =
  result.valid = true
  result.text = node.renderFlat(context, result.valid)

proc isClause(node: SyntaxNode): bool {.raises: [].} =
  node.kind == Command and node.callee.kind == Symbol and
    (node.callee.symbol == "|" or node.callee.symbol == "then" or node.callee.symbol == "else")

proc isBlockStatement(node: SyntaxNode): bool {.raises: [].} =
  case node.kind
  of Command:
    node.layout == ColonLayout
  of Binding:
    node.value.kind == Command and node.value.layout == ColonLayout
  else:
    false

proc shouldSeparateStatements(left, right: SyntaxNode): bool {.raises: [].} =
  if left.kind == Binding and right.kind == Binding:
    return false
  if left.isClause or right.isClause:
    return false
  result = left.isBlockStatement or right.isBlockStatement

proc renderBody(
    nodes: seq[SyntaxNode], indent: int, separate = true,
    argumentLines = false
): string {.raises: [].} =
  for index, node in nodes:
    if index > 0:
      result.add '\n'
      if separate and shouldSeparateStatements(nodes[index - 1], node):
        result.add '\n'
    let
      commandSymbol =
        if node.kind == Command and node.callee.kind == Symbol:
          node.callee.symbol
        else:
          ""
      nodeIndent =
        if commandSymbol == "|" and node.hangingPipe:
          max(indent - 2, 0)
        else:
          indent
    result.add node.render(nodeIndent, nodeIndent,
      statement = true, bindingValue = false, argumentLine = argumentLines)

proc renderCommand(node: SyntaxNode, indent, column: int): string {.raises: [].} =
  let flatCallee = node.callee.renderFlat()
  if flatCallee.valid:
    result.add flatCallee.text
  else:
    result.add node.callee.render(indent, column,
      statement = false, bindingValue = false, argumentLine = false)

  case node.layout
  of NoLayout:
    for argument in node.arguments:
      result.add '\n'
      result.add argument.render(indent + 2, indent + 2,
        statement = true, bindingValue = false, argumentLine = true)
  of ColonLayout:
    var valid = flatCallee.valid
    var flatHead = flatCallee.text
    for argument in node.arguments:
      let flatArgument = argument.renderFlat()
      valid = valid and flatArgument.valid
      flatHead.add ' '
      flatHead.add flatArgument.text
    if valid and column + flatHead.len + 1 <= FormatLineWidth:
      result = flatHead
      result.add ":\n"
      result.add renderBody(node.body, indent + 2)
    else:
      for argument in node.arguments:
        result.add '\n'
        result.add argument.render(indent + 2, indent + 2,
          statement = true, bindingValue = false, argumentLine = true)
      result.add ":\n"
      result.add renderBody(node.body, indent + 2)
  of ContinuationLayout:
    result.add '\n'
    result.add renderBody(node.arguments, indent + 2,
      separate = false, argumentLines = true)

proc render(
    node: SyntaxNode, indent, column: int,
    statement, bindingValue, argumentLine: bool
): string {.raises: [].} =
  if statement:
    result.appendIndent(indent)

  case node.kind
  of Script:
    result.add renderBody(node.statements, indent)
  of Binding:
    result.add node.bindingSymbol
    result.add node.renderTypes()
    result.add " = "
    result.add node.value.render(indent, column + node.bindingSymbol.len + 3,
      statement = false, bindingValue = true, argumentLine = false)
  of Command:
    let context =
      if argumentLine: FlatContinuation
      elif statement: FlatStatement
      elif bindingValue: FlatBinding
      else: FlatArgument
    let flat = node.renderFlat(context)
    if flat.valid and
        (node.arguments.len == 0 or column + flat.text.len <= FormatLineWidth):
      result.add flat.text
    else:
      result.add node.renderCommand(indent, column)
  of Symbol:
    result.add node.symbol
    result.add node.renderTypes()
  of String:
    result.add quote(node.stringValue)

proc toString*(node: SyntaxNode): string {.raises: [].} =
  node.render(0, 0,
    statement = false, bindingValue = false, argumentLine = false)

proc `$`*(node: SyntaxNode): string {.raises: [].} =
  node.toString()
