import std/strformat

import syntax
export syntax

type
  ParserError* = object of CrowError

  TokenKind = enum
    Eof
    Newline
    Indent
    Dedent
    Comma
    Colon
    Equal
    Dot
    LBracket
    RBracket
    LParen
    RParen
    Atom
    StringLit

  Token = object
    kind: TokenKind
    lexeme: string
    line: int
    column: int

  Parser = object
    tokens: seq[Token]
    pos: int
    source: SourceID

proc fail(
    message: string, source: SourceID, line, column: int
) {.raises: [ParserError].} =
  let error = newException(ParserError, message)
  error.primary = sourcePos(source, line, column)
  raise error

proc isSpace(c: char): bool {.raises: [].} =
  c in {' ', '\t', '\r', '\n'}

proc isAtomStartChar(c: char): bool {.raises: [].} =
  not isSpace(c) and c notin {'"', '(', ')', '[', ']', ',', ':', '=', '.', ';'}

proc isAtomPartChar(c: char): bool {.raises: [].} =
  not isSpace(c) and c notin {'"', '(', ')', '[', ']', ',', ':', '.', ';'}

proc isNumberDot(source: string, index: int): bool {.raises: [].} =
  index > 0 and index + 1 < source.len and source[index] == '.' and
    source[index - 1] in {'0' .. '9'} and source[index + 1] in {'0' .. '9'}

proc add(
    tokens: var seq[Token], kind: TokenKind, lexeme: sink string, line, column: int
) {.raises: [].} =
  tokens.add Token(kind: kind, lexeme: lexeme, line: line, column: column)

proc tokenize*(
    source: string, sourceId = NoSource
): seq[Token] {.raises: [ParserError].} =
  var
    indents = @[0]
    atLineStart = true
    pendingIndent = 0
    i = 0
    line = 1
    column = 1

  template advance() =
    inc i
    inc column

  template emitPendingIndent() =
    if atLineStart:
      let current = indents[^1]
      if pendingIndent > current:
        indents.add pendingIndent
        result.add(Indent, "", line, 1)
      elif pendingIndent < current:
        while indents.len > 1 and pendingIndent < indents[^1]:
          discard indents.pop()
          result.add(Dedent, "", line, 1)
        if pendingIndent != indents[^1]:
          fail("inconsistent indentation", sourceId, line, 1)
      atLineStart = false

  while i < source.len:
    let c = source[i]
    if atLineStart:
      pendingIndent = 0
      while i < source.len and source[i] in {' ', '\t'}:
        pendingIndent += (if source[i] == '\t': 8 else: 1)
        advance()
      if i >= source.len:
        break
      if source[i] in {'\r', '\n'}:
        if source[i] == '\r' and i + 1 < source.len and source[i + 1] == '\n':
          inc i
        inc i
        inc line
        column = 1
        continue
      if source[i] == ';':
        while i < source.len and source[i] notin {'\r', '\n'}:
          advance()
        continue
      emitPendingIndent()
      continue

    case c
    of ' ', '\t':
      advance()
    of '\r', '\n':
      result.add(Newline, "", line, column)
      if c == '\r' and i + 1 < source.len and source[i + 1] == '\n':
        inc i
      inc i
      inc line
      column = 1
      atLineStart = true
    of ';':
      while i < source.len and source[i] notin {'\r', '\n'}:
        advance()
    of ',':
      result.add(Comma, ",", line, column)
      advance()
    of ':':
      result.add(Colon, ":", line, column)
      advance()
    of '=':
      result.add(Equal, "=", line, column)
      advance()
    of '.':
      result.add(Dot, ".", line, column)
      advance()
    of '[':
      result.add(LBracket, "[", line, column)
      advance()
    of ']':
      result.add(RBracket, "]", line, column)
      advance()
    of '(':
      result.add(LParen, "(", line, column)
      advance()
    of ')':
      result.add(RParen, ")", line, column)
      advance()
    of '"':
      let startLine = line
      let startColumn = column
      advance()
      var value = ""
      while i < source.len and source[i] != '"':
        if source[i] in {'\r', '\n'}:
          fail("unterminated string", sourceId, startLine, startColumn)
        if source[i] == '\\':
          advance()
          if i >= source.len:
            fail("unterminated string escape", sourceId, startLine, startColumn)
          case source[i]
          of '"':
            value.add '"'
          of '\\':
            value.add '\\'
          of 'n':
            value.add '\n'
          of 'r':
            value.add '\r'
          of 't':
            value.add '\t'
          else:
            fail("invalid string escape", sourceId, line, column)
          advance()
        else:
          value.add source[i]
          advance()
      if i >= source.len:
        fail("unterminated string", sourceId, startLine, startColumn)
      advance()
      result.add(StringLit, value, startLine, startColumn)
    else:
      if not isAtomStartChar(c):
        fail(&"unexpected character {c}", sourceId, line, column)
      let start = i
      let startColumn = column
      while i < source.len and (isAtomPartChar(source[i]) or source.isNumberDot(i)):
        advance()
      result.add(Atom, source[start ..< i], line, startColumn)

  if not atLineStart:
    result.add(Newline, "", line, column)
  while indents.len > 1:
    discard indents.pop()
    result.add(Dedent, "", line, 1)
  result.add(Eof, "", line, column)

proc peek(parser: Parser): Token {.raises: [].} =
  parser.tokens[parser.pos]

proc peek(parser: Parser, offset: int): Token {.raises: [].} =
  parser.tokens[parser.pos + offset]

proc at(parser: Parser, kind: TokenKind): bool {.raises: [].} =
  parser.peek.kind == kind

proc take(parser: var Parser): Token {.raises: [].} =
  result = parser.tokens[parser.pos]
  inc parser.pos

proc pos(parser: Parser, token: Token): SourcePos {.raises: [].} =
  sourcePos(parser.source, token.line, token.column)

proc expect(
    parser: var Parser, kind: TokenKind, message: string
): Token {.raises: [ParserError].} =
  if not parser.at(kind):
    let token = parser.peek
    fail(message, parser.source, token.line, token.column)
  parser.take()

proc parseStatementList(
  parser: var Parser, stop: set[TokenKind]
): seq[SyntaxNode] {.raises: [ParserError].}

proc parseForm(parser: var Parser): SyntaxNode {.raises: [ParserError].}
proc parseArgumentItem(parser: var Parser): SyntaxNode {.raises: [ParserError].}

proc parseIndentedBody(parser: var Parser): seq[SyntaxNode] {.raises: [ParserError].} =
  discard parser.expect(Newline, "expected newline before indented body")
  discard parser.expect(Indent, "expected indented body")
  result = parser.parseStatementList({Dedent})
  discard parser.expect(Dedent, "expected end of indented body")

proc startsArgumentItem(kind: TokenKind): bool {.raises: [].} =
  kind in {Atom, StringLit, Equal, LBracket, LParen}

proc parseArgumentLine(parser: var Parser): seq[SyntaxNode] {.raises: [ParserError].} =
  result.add parser.parseArgumentItem()
  while startsArgumentItem(parser.peek.kind):
    result.add parser.parseArgumentItem()
  if parser.at(Newline):
    discard parser.take()
  elif parser.peek.kind notin {Dedent, RParen, Eof}:
    let token = parser.peek
    fail("expected newline after argument", parser.source, token.line, token.column)

proc parseIndentedArguments(
    parser: var Parser
): seq[SyntaxNode] {.raises: [ParserError].} =
  discard parser.expect(Newline, "expected newline before indented arguments")
  discard parser.expect(Indent, "expected indented arguments")
  while not parser.at(Dedent):
    if parser.at(Newline):
      discard parser.take()
    else:
      result.add parser.parseArgumentLine()
  discard parser.expect(Dedent, "expected end of indented arguments")

proc parseLayoutTail(
    parser: var Parser
): tuple[kind: LayoutKind, body: seq[SyntaxNode]] {.raises: [ParserError].} =
  if parser.at(Colon):
    discard parser.take()
    result = (ColonLayout, parser.parseIndentedBody())
  else:
    result = (ContinuationLayout, parser.parseIndentedArguments())

proc attachLayoutTail(
    parser: Parser, node: var SyntaxNode, layout: LayoutKind, body: sink seq[SyntaxNode]
) {.raises: [ParserError].} =
  if node.kind == Symbol:
    node = command(node, @[], node.pos)
  if not node.attachLayout(layout, body):
    let token = parser.peek
    fail(
      "layout can only be attached to a command", parser.source, token.line,
      token.column,
    )

proc parseSymbol(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  let token = parser.expect(Atom, "expected symbol")
  symbol(token.lexeme, parser.pos(token))

proc parseEmptyListSymbol(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  let token = parser.expect(LBracket, "expected '['")
  discard parser.expect(RBracket, "expected ']'")
  symbol("[]", parser.pos(token))

proc parsePostfix(parser: var Parser, base: SyntaxNode): SyntaxNode {.raises: [ParserError].} =
  result = base
  while parser.at(Dot):
    let dot = parser.take()
    if parser.at(Atom):
      let fieldToken = parser.take()
      result = command(
        symbol("field", parser.pos(dot)),
        @[result, stringLiteral(fieldToken.lexeme, parser.pos(fieldToken))],
        parser.pos(dot),
      )
    elif parser.at(LBracket):
      discard parser.take()
      let index = parser.parseForm()
      discard parser.expect(RBracket, "expected ']'")
      result = command(symbol("index", parser.pos(dot)), @[result, index], parser.pos(dot))
    else:
      let token = parser.peek
      fail("expected field name or index after '.'", parser.source, token.line, token.column)

proc parseGroupedForm(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  discard parser.expect(LParen, "expected '('")
  result = parser.parseForm()
  if parser.at(Colon) or parser.at(Newline):
    let tail = parser.parseLayoutTail()
    parser.attachLayoutTail(result, tail.kind, tail.body)
  discard parser.expect(RParen, "expected ')'")
  result = parser.parsePostfix(result)

proc parseCallee(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  case parser.peek.kind
  of Atom:
    result = parser.parsePostfix(parser.parseSymbol())
  of Equal:
    discard parser.take()
    result = parser.parsePostfix(symbol("=", parser.pos(parser.peek(-1))))
  of LBracket:
    result = parser.parsePostfix(parser.parseEmptyListSymbol())
  of LParen:
    result = parser.parseGroupedForm()
  else:
    let token = parser.peek
    fail("expected command callee", parser.source, token.line, token.column)

proc isIdentifierSymbol(value: string): bool {.raises: [].} =
  if value.len == 0:
    return false
  if value[0] notin {'A' .. 'Z', 'a' .. 'z', '_'}:
    return false
  for c in value:
    if c notin {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '-', '?'}:
      return false
  true

proc isNumericSymbol(value: string): bool {.raises: [].} =
  value.len > 0 and (
    value[0] in {'0' .. '9'} or
    value.len > 1 and value[0] in {'+', '-'} and value[1] in {'0' .. '9'}
  )

proc parseArgument(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  case parser.peek.kind
  of Atom:
    result = parser.parseSymbol()
    if not result.symbol.isIdentifierSymbol and not result.symbol.isNumericSymbol and
        parser.at(Colon):
      let tail = parser.parseLayoutTail()
      parser.attachLayoutTail(result, tail.kind, tail.body)
    result = parser.parsePostfix(result)
  of StringLit:
    let token = parser.take()
    result = parser.parsePostfix(stringLiteral(token.lexeme, parser.pos(token)))
  of LBracket:
    result = parser.parseEmptyListSymbol()
    if parser.at(Colon):
      let tail = parser.parseLayoutTail()
      parser.attachLayoutTail(result, tail.kind, tail.body)
    result = parser.parsePostfix(result)
  of LParen:
    result = parser.parseGroupedForm()
  else:
    let token = parser.peek
    fail("expected argument", parser.source, token.line, token.column)

proc startsArgument(kind: TokenKind): bool {.raises: [].} =
  kind in {Atom, StringLit, LBracket, LParen}

proc parseArgumentItem(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  case parser.peek.kind
  of Atom:
    result = parser.parseSymbol()
  of Equal:
    discard parser.take()
    result = symbol("=", parser.pos(parser.peek(-1)))
  of StringLit:
    let token = parser.take()
    result = stringLiteral(token.lexeme, parser.pos(token))
  of LBracket:
    result = parser.parseEmptyListSymbol()
  of LParen:
    result = parser.parseGroupedForm()
  else:
    let token = parser.peek
    fail("expected argument", parser.source, token.line, token.column)

  if parser.at(Colon) or (parser.at(Newline) and parser.peek(1).kind == Indent):
    let tail = parser.parseLayoutTail()
    parser.attachLayoutTail(result, tail.kind, tail.body)
  result = parser.parsePostfix(result)

proc parseCommand(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  let callee = parser.parseCallee()
  var arguments: seq[SyntaxNode]
  while startsArgument(parser.peek.kind):
    arguments.add parser.parseArgument()
  if callee.kind == Command and arguments.len == 0:
    result = callee
  else:
    result = command(callee, arguments, callee.pos)

proc parseExpression(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  if parser.at(StringLit):
    let token = parser.take()
    result = parser.parsePostfix(stringLiteral(token.lexeme, parser.pos(token)))
  else:
    result = parser.parseCommand()

proc parseForm(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  if parser.at(Atom) and parser.peek(1).kind == Equal:
    let bindingToken = parser.take()
    discard parser.take()
    if parser.at(Newline) and parser.peek(1).kind == Indent:
      let values = parser.parseIndentedArguments()
      if values.len != 1:
        let token = parser.peek
        fail("expected one binding value", parser.source, token.line, token.column)
      result = binding(bindingToken.lexeme, values[0], parser.pos(bindingToken))
    else:
      result =
        binding(bindingToken.lexeme, parser.parseExpression(), parser.pos(bindingToken))
  else:
    result = parser.parseExpression()

proc parseStatement(parser: var Parser): seq[SyntaxNode] {.raises: [ParserError].} =
  var first = parser.parseForm()
  if parser.at(Colon) or (parser.at(Newline) and parser.peek(1).kind == Indent):
    let tail = parser.parseLayoutTail()
    parser.attachLayoutTail(first, tail.kind, tail.body)
    result.add first
    return

  result.add first
  while parser.at(Comma):
    discard parser.take()
    result.add parser.parseForm()
  if parser.at(Newline):
    discard parser.take()
  elif parser.peek.kind notin {Dedent, RParen, Eof}:
    let token = parser.peek
    fail("expected newline after statement", parser.source, token.line, token.column)

proc parseStatementList(
    parser: var Parser, stop: set[TokenKind]
): seq[SyntaxNode] {.raises: [ParserError].} =
  while parser.peek.kind notin stop:
    if parser.at(Newline):
      discard parser.take()
    else:
      result.add parser.parseStatement()

proc parse*(source: string, path = "<input>"): SyntaxNode {.raises: [ParserError].} =
  let sourceId = registerSource(source, path)
  var parser = Parser(tokens: tokenize(source, sourceId), pos: 0, source: sourceId)
  let statements = parser.parseStatementList({Eof})
  discard parser.expect(Eof, "expected end of file")
  let scriptPos =
    if statements.len > 0:
      statements[0].pos
    else:
      sourcePos(sourceId, 1, 1)
  script(statements, scriptPos)
