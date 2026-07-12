type
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

proc script*(statements: sink seq[SyntaxNode]): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: Script, statements: statements)

proc binding*(symbol: sink string, value: SyntaxNode): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: Binding, bindingSymbol: symbol, value: value)

proc command*(
    callee: SyntaxNode, arguments: sink seq[SyntaxNode]
): SyntaxNode {.raises: [].} =
  SyntaxNode(
    kind: Command, callee: callee, arguments: arguments, layout: NoLayout, body: @[]
  )

proc symbol*(value: sink string): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: Symbol, symbol: value)

proc stringLiteral*(value: sink string): SyntaxNode {.raises: [].} =
  SyntaxNode(kind: String, stringValue: value)

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
