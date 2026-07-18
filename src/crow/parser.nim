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

proc fail(message: string, source: SourceID, line, column: int) {.raises: [ParserError].} =
  let error = newException(ParserError, message)
  error.primary = sourcePos(source, line, column)
  raise error

proc isSpace(c: char): bool {.raises: [].} =
  c in {' ', '\t', '\r', '\n'}

proc isAtomStartChar(c: char): bool {.raises: [].} =
  not isSpace(c) and c notin {'"', '(', ')', ',', ':', '=', ';'}

proc isAtomPartChar(c: char): bool {.raises: [].} =
  not isSpace(c) and c notin {'"', '(', ')', ',', ':', ';'}

proc add(
    tokens: var seq[Token], kind: TokenKind, lexeme: sink string, line, column: int
) {.raises: [].} =
  tokens.add Token(kind: kind, lexeme: lexeme, line: line, column: column)

proc tokenize*(source: string; sourceId = NoSource): seq[Token] {.raises: [ParserError].} =
  var
    tokens: seq[Token]
    indents = @[0]
    atLineStart = true
    pendingIndent = 0
    i = 0
    line = 1
    column = 1

  template advance() =
    inc i
    inc column

  proc emitPendingIndent() {.raises: [ParserError].} =
    if atLineStart:
      let current = indents[^1]
      if pendingIndent > current:
        indents.add pendingIndent
        tokens.add(Indent, "", line, 1)
      elif pendingIndent < current:
        while indents.len > 1 and pendingIndent < indents[^1]:
          discard indents.pop()
          tokens.add(Dedent, "", line, 1)
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
      tokens.add(Newline, "", line, column)
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
      tokens.add(Comma, ",", line, column)
      advance()
    of ':':
      tokens.add(Colon, ":", line, column)
      advance()
    of '=':
      tokens.add(Equal, "=", line, column)
      advance()
    of '(':
      tokens.add(LParen, "(", line, column)
      advance()
    of ')':
      tokens.add(RParen, ")", line, column)
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
      tokens.add(StringLit, value, startLine, startColumn)
    else:
      if not isAtomStartChar(c):
        fail(&"unexpected character {c}", sourceId, line, column)
      let start = i
      let startColumn = column
      while i < source.len and isAtomPartChar(source[i]):
        advance()
      tokens.add(Atom, source[start ..< i], line, startColumn)

  if not atLineStart:
    tokens.add(Newline, "", line, column)
  while indents.len > 1:
    discard indents.pop()
    tokens.add(Dedent, "", line, 1)
  tokens.add(Eof, "", line, column)
  tokens

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

proc parseIndentedBody(parser: var Parser): seq[SyntaxNode] {.raises: [ParserError].} =
  discard parser.expect(Newline, "expected newline before indented body")
  discard parser.expect(Indent, "expected indented body")
  result = parser.parseStatementList({Dedent})
  discard parser.expect(Dedent, "expected end of indented body")

proc parseLayoutTail(
    parser: var Parser
): tuple[kind: LayoutKind, body: seq[SyntaxNode]] {.raises: [ParserError].} =
  if parser.at(Colon):
    discard parser.take()
    result = (ColonLayout, parser.parseIndentedBody())
  else:
    result = (ContinuationLayout, parser.parseIndentedBody())

proc parseSymbol(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  let token = parser.expect(Atom, "expected symbol")
  symbol(token.lexeme, parser.pos(token))

proc parseGroupedForm(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  discard parser.expect(LParen, "expected '('")
  result = parser.parseForm()
  if parser.at(Colon) or parser.at(Newline):
    let tail = parser.parseLayoutTail()
    if not result.attachLayout(tail.kind, tail.body):
      let token = parser.peek
      fail("layout can only be attached to a command", parser.source, token.line, token.column)
  discard parser.expect(RParen, "expected ')'")

proc parseCallee(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  case parser.peek.kind
  of Atom:
    result = parser.parseSymbol()
  of Equal:
    discard parser.take()
    result = symbol("=", parser.pos(parser.peek(-1)))
  of LParen:
    result = parser.parseGroupedForm()
  else:
    let token = parser.peek
    fail("expected command callee", parser.source, token.line, token.column)

proc parseArgument(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  case parser.peek.kind
  of Atom:
    result = parser.parseSymbol()
  of StringLit:
    let token = parser.take()
    result = stringLiteral(token.lexeme, parser.pos(token))
  of LParen:
    result = parser.parseGroupedForm()
  else:
    let token = parser.peek
    fail("expected argument", parser.source, token.line, token.column)

proc startsArgument(kind: TokenKind): bool {.raises: [].} =
  kind in {Atom, StringLit, LParen}

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
    result = stringLiteral(token.lexeme, parser.pos(token))
  else:
    result = parser.parseCommand()

proc parseForm(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  if parser.at(Atom) and parser.peek(1).kind == Equal:
    let bindingToken = parser.take()
    discard parser.take()
    result = binding(bindingToken.lexeme, parser.parseExpression(), parser.pos(bindingToken))
  else:
    result = parser.parseExpression()

proc parseStatement(parser: var Parser): seq[SyntaxNode] {.raises: [ParserError].} =
  var first = parser.parseForm()
  if parser.at(Colon) or parser.at(Newline) and parser.peek(1).kind == Indent:
    let tail = parser.parseLayoutTail()
    if not first.attachLayout(tail.kind, tail.body):
      let token = parser.peek
      fail("layout can only be attached to a command", parser.source, token.line, token.column)
    result.add first
    return

  result.add first
  while parser.at(Comma):
    discard parser.take()
    result.add parser.parseForm()
  discard parser.expect(Newline, "expected newline after statement")

proc parseStatementList(
    parser: var Parser, stop: set[TokenKind]
): seq[SyntaxNode] {.raises: [ParserError].} =
  while parser.peek.kind notin stop:
    if parser.at(Newline):
      discard parser.take()
    else:
      result.add parser.parseStatement()

proc parse*(source: string; path = "<input>"): SyntaxNode {.raises: [ParserError].} =
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
