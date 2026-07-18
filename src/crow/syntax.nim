import std/[strformat, strutils]

type
  SourceID* = uint32

  SourcePos* = object
    source*: SourceID
    line*: uint32
    column*: uint16

  SourceInfo* = object
    path*: string
    lines*: seq[string]

  DiagnosticFrame* = object
    pos*: SourcePos
    label*: string

  CrowError* = object of CatchableError
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

  SyntaxNode* = ref object
    pos*: SourcePos
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

proc noSourcePos*(): SourcePos {.raises: [].} =
  SourcePos(source: NoSource, line: 0, column: 0)

proc sourcePos*(source: SourceID, line, column: int): SourcePos {.raises: [].} =
  SourcePos(source: source, line: uint32(line), column: uint16(min(column, high(uint16).int)))

proc hasSource*(pos: SourcePos): bool {.raises: [].} =
  pos.source != NoSource and pos.line > 0 and pos.column > 0

proc registerSource*(source: string; path = "<input>"): SourceID {.raises: [].} =
  sourceRegistry.add SourceInfo(path: path, lines: source.splitLines)
  SourceID(sourceRegistry.len)

proc sourceInfo*(id: SourceID): SourceInfo {.raises: [].} =
  if id == NoSource or id.int > sourceRegistry.len:
    SourceInfo(path: "<unknown>", lines: @[])
  else:
    sourceRegistry[id.int - 1]

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
    kind: Command, pos: pos, callee: callee, arguments: arguments, layout: NoLayout, body: @[]
  )

proc symbol*(value: sink string, pos = noSourcePos()): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: Symbol, pos: pos, symbol: value)

proc stringLiteral*(value: sink string, pos = noSourcePos()): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: String, pos: pos, stringValue: value)

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

proc addFrame*(error: ref CrowError, pos: SourcePos, label: string) {.raises: [].} =
  if not pos.hasSource:
    return
  if error.primary.hasSource:
    if error.frames.len > 0 and error.frames[^1].pos == pos and error.frames[^1].label == label:
      return
    error.frames.add DiagnosticFrame(pos: pos, label: label)
  else:
    error.primary = pos

proc report*(error: ref CrowError, useColor = false): string {.raises: [].} =
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

proc quote(value: string): string {.raises: [].} =
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

proc render(
  node: SyntaxNode, indent: int, statement, bindingValue: bool
): string {.raises: [].}

proc renderBody(nodes: seq[SyntaxNode], indent: int): string {.raises: [].} =
  for index, node in nodes:
    if index > 0:
      result.add '\n'
    result.add node.render(indent, statement = true, bindingValue = false)

proc renderCommand(node: SyntaxNode, indent: int): string {.raises: [].} =
  result.add node.callee.render(indent, statement = false, bindingValue = false)
  for argument in node.arguments:
    result.add ' '
    result.add argument.render(indent, statement = false, bindingValue = false)

  case node.layout
  of NoLayout:
    discard
  of ColonLayout:
    result.add ":\n"
    result.add renderBody(node.body, indent + 2)
  of ContinuationLayout:
    result.add '\n'
    result.add renderBody(node.body, indent + 2)

proc render(
    node: SyntaxNode, indent: int, statement, bindingValue: bool
): string {.raises: [].} =
  if statement:
    result.appendIndent(indent)

  case node.kind
  of Script:
    result.add renderBody(node.statements, indent)
  of Binding:
    result.add node.bindingSymbol
    result.add " = "
    result.add node.value.render(indent, statement = false, bindingValue = true)
  of Command:
    let needsParens =
      not statement and node.layout == NoLayout and
      (not bindingValue or node.arguments.len > 0 or node.callee.kind == Command)
    if needsParens:
      result.add '('
    result.add node.renderCommand(indent)
    if needsParens:
      result.add ')'
  of Symbol:
    result.add node.symbol
  of String:
    result.add quote(node.stringValue)

proc toString*(node: SyntaxNode): string {.raises: [].} =
  node.render(0, statement = false, bindingValue = false)

proc `$`*(node: SyntaxNode): string {.raises: [].} =
  node.toString()
