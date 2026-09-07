import std/strformat

import syntax
export syntax

type
  ParserError* = object of OwlError

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
    hangingPipe: bool

  Parser = object
    tokens: seq[Token]
    pos: int
    source: SourceID

const
  # Tokens that can begin an expression, an argument, or a callee.
  PrimaryStart = {Atom, StringLit, Equal, LBracket, LParen}
  # `END` in the grammar: everything a statement or argument line may stop at
  # without a newline of its own.
  BlockEnd = {Dedent, RParen, Eof}

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

proc escapeChar(c: char): char {.raises: [].} =
  ## The character `\c` stands for, or `\0` when `c` is not an escape.
  case c
  of '"': '"'
  of '\\': '\\'
  of 'n': '\n'
  of 'r': '\r'
  of 't': '\t'
  else: '\0'

proc add(
    tokens: var seq[Token], kind: TokenKind, lexeme: sink string, line, column: int,
    hangingPipe = false
) {.raises: [].} =
  tokens.add Token(
    kind: kind, lexeme: lexeme, line: line, column: column,
    hangingPipe: hangingPipe,
  )

proc tokenize*(
    source: string, sourceId = NoSource
): seq[Token] {.raises: [ParserError].} =
  var
    indents = @[0]
    # Indent-stack depth recorded when each still-open '(' was seen, so a ')'
    # can close the levels that were opened inside it.
    parenIndents: seq[int]
    atLineStart = true
    pendingIndent = 0
    previousLineWasPipe = false
    currentLineIsPipe = false
    currentLineHasHangingPipe = false
    havePreviousContentLine = false
    i = 0
    line = 1
    column = 1

  template advance() =
    inc i
    inc column

  template emitPendingIndent() =
    if atLineStart:
      let lineIsPipe =
        source[i] == '|' and
        (i + 1 >= source.len or source[i + 1] in {' ', '\t', '\r', '\n', ':'})
      currentLineHasHangingPipe = false
      # When a continued header's body returns to the continuation's first
      # column, the trailing colon belongs to the outer command. Move it past
      # the continuation dedents so the parser sees `arguments DEDENT :` and
      # can attach the body at that outer level.
      if not lineIsPipe and not previousLineWasPipe and result.len >= 2 and
          result[^1].kind == Newline and result[^2].kind == Colon and
          pendingIndent <= indents[^1]:
        let
          newlineToken = result.pop()
          colonToken = result.pop()
        while indents.len > 1 and pendingIndent <= indents[^1]:
          discard indents.pop()
          result.add(Dedent, "", line, 1)
        result.add colonToken
        result.add newlineToken
      let current = indents[^1]
      if lineIsPipe:
        # A leading `|` may hang in the column of the command whose suite it
        # belongs to.  Keep the nearest already-open child level anchored at
        # that column when a nested clause has just ended.  Immediately after
        # a colon, create that child level even though its physical column did
        # not increase.  In every other case `|` remains an ordinary sibling
        # (notably, the `|` following an `if`).
        var anchored = -1
        for level in countdown(indents.high, 1):
          if indents[level - 1] == pendingIndent:
            anchored = level
            break
        if anchored >= 0 and indents.high > anchored:
          currentLineHasHangingPipe = true
          while indents.high > anchored:
            discard indents.pop()
            result.add(Dedent, "", line, 1)
        elif result.len >= 2 and result[^1].kind == Newline and
            result[^2].kind == Colon and pendingIndent == current:
          currentLineHasHangingPipe = true
          indents.add pendingIndent
          result.add(Indent, "", line, 1)
        elif anchored < 0 and havePreviousContentLine and
            pendingIndent == current:
          # With no suite open yet, the pipe can start the continuation of a
          # regular call at the call's own physical indentation.
          currentLineHasHangingPipe = true
          indents.add pendingIndent
          result.add(Indent, "", line, 1)
        else:
          while indents.len > 1 and pendingIndent < indents[^1]:
            discard indents.pop()
            result.add(Dedent, "", line, 1)
          if pendingIndent != indents[^1]:
            fail("inconsistent indentation", sourceId, line, 1)
      elif previousLineWasPipe and pendingIndent == current:
        # The hanging pipe occupies the open suite's logical indentation, so
        # a conventionally indented following line is one level below it even
        # when both levels use the same physical column.
        indents.add pendingIndent
        result.add(Indent, "", line, 1)
      elif pendingIndent > current:
        indents.add pendingIndent
        result.add(Indent, "", line, 1)
      elif pendingIndent < current:
        while indents.len > 1 and pendingIndent < indents[^1]:
          discard indents.pop()
          result.add(Dedent, "", line, 1)
        if pendingIndent != indents[^1]:
          fail("inconsistent indentation", sourceId, line, 1)
      atLineStart = false
      currentLineIsPipe = lineIsPipe

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
      previousLineWasPipe = currentLineIsPipe
      havePreviousContentLine = true
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
      parenIndents.add indents.len
      result.add(LParen, "(", line, column)
      advance()
    of ')':
      # A group may be closed on the same line as the last line of its indented
      # body -- `(f\n  a\n  b)`. The dedents for those levels would otherwise
      # not be emitted until the next line, leaving the body unterminated and
      # the enclosing block short one dedent.
      if parenIndents.len > 0:
        let opened = parenIndents.pop()
        while indents.len > opened:
          discard indents.pop()
          result.add(Dedent, "", line, column)
      result.add(RParen, ")", line, column)
      advance()
    of '"':
      # A string becomes one `StringLit`, or, once it interpolates, the token
      # stream for `(concat <part> ... (to-string (<form>)) ...)`. Splitting it
      # here is what lets an interpolated form be any form at all.
      let
        startLine = line
        startColumn = column
      advance()
      var
        parts: seq[Token]
        interpolations = 0
        literal = ""
        literalColumn = column

      template addLiteral(c: char, at: int) =
        if literal.len == 0:
          literalColumn = at
        literal.add c

      template flushLiteral() =
        if literal.len > 0:
          parts.add(StringLit, literal, startLine, literalColumn)
          literal = ""

      while i < source.len and source[i] != '"':
        if source[i] in {'\r', '\n'}:
          fail("unterminated string", sourceId, startLine, startColumn)
        if source[i] != '\\':
          addLiteral(source[i], column)
          advance()
          continue

        let escapeColumn = column
        advance()
        if i >= source.len:
          fail("unterminated string escape", sourceId, startLine, startColumn)
        if source[i] != '(':
          let escaped = escapeChar(source[i])
          if escaped == '\0':
            fail("invalid string escape", sourceId, line, column)
          addLiteral(escaped, escapeColumn)
          advance()
          continue

        advance() # past '('
        let
          codeColumn = column
          codeStart = i
        var depth = 1
        while depth > 0:
          if i >= source.len or source[i] in {'\r', '\n'}:
            fail("unterminated string interpolation", sourceId, startLine, escapeColumn)
          case source[i]
          of '(':
            inc depth
          of ')':
            dec depth
          else:
            discard
          if depth > 0:
            advance()
        let code = source[codeStart ..< i]
        advance() # past ')'

        flushLiteral()
        inc interpolations
        let interpolated =
          try:
            tokenize(code, sourceId)
          except ParserError as error:
            if error.primary.hasSource and error.primary.line == 1:
              error.primary =
                sourcePos(sourceId, startLine, codeColumn + error.primary.column.int - 1)
            raise error
        parts.add(LParen, "(", startLine, codeColumn)
        parts.add(Atom, "to-string", startLine, codeColumn)
        parts.add(LParen, "(", startLine, codeColumn)
        for token in interpolated:
          if token.kind notin {Newline, Eof}:
            parts.add(token.kind, token.lexeme, startLine,
                codeColumn + token.column - 1)
        parts.add(RParen, ")", startLine, codeColumn)
        parts.add(RParen, ")", startLine, codeColumn)

      if i >= source.len:
        fail("unterminated string", sourceId, startLine, startColumn)
      advance() # past the closing quote

      if interpolations == 0:
        result.add(StringLit, literal, startLine, startColumn)
      else:
        flushLiteral()
        result.add(LParen, "(", startLine, startColumn)
        result.add(Atom, "concat", startLine, startColumn)
        result.add parts
        result.add(RParen, ")", startLine, startColumn)
    else:
      if not isAtomStartChar(c):
        fail(&"unexpected character {c}", sourceId, line, column)
      let start = i
      let startColumn = column
      while i < source.len and (isAtomPartChar(source[i]) or source.isNumberDot(i)):
        advance()
      result.add(
        Atom, source[start ..< i], line, startColumn,
        hangingPipe = currentLineHasHangingPipe and source[start ..< i] == "|",
      )

  if not atLineStart:
    result.add(Newline, "", line, column)
  while indents.len > 1:
    discard indents.pop()
    result.add(Dedent, "", line, 1)
  result.add(Eof, "", line, column)

proc peek(parser: Parser, offset = 0): Token {.raises: [].} =
  parser.tokens[parser.pos + offset]

proc at(parser: Parser, kind: TokenKind): bool {.raises: [].} =
  parser.peek.kind == kind

proc startsPrimary(parser: Parser): bool {.raises: [].} =
  parser.peek.kind in PrimaryStart

proc startsSuite(parser: Parser): bool {.raises: [].} =
  ## A newline followed by an indent, which is how a layout tail or an indented
  ## binding value begins.
  parser.at(Newline) and parser.peek(1).kind == Indent

proc take(parser: var Parser): Token {.raises: [].} =
  result = parser.tokens[parser.pos]
  inc parser.pos

proc pos(parser: Parser, token: Token): SourcePos {.raises: [].} =
  sourcePos(parser.source, token.line, token.column)

proc fail(parser: Parser, message: string) {.raises: [ParserError].} =
  let token = parser.peek
  fail(message, parser.source, token.line, token.column)

proc expect(
    parser: var Parser, kind: TokenKind, message: string
): Token {.raises: [ParserError].} =
  if not parser.at(kind):
    parser.fail(message)
  parser.take()

proc endStatement(parser: var Parser, message: string) {.raises: [ParserError].} =
  if parser.at(Newline):
    discard parser.take()
  elif parser.peek.kind notin BlockEnd:
    parser.fail(message)

proc parseStatementList(
  parser: var Parser, stop: set[TokenKind]
): seq[SyntaxNode] {.raises: [ParserError].}

proc parseForm(parser: var Parser): SyntaxNode {.raises: [ParserError].}
proc parseArgument(
  parser: var Parser, inSuite: bool
): SyntaxNode {.raises: [ParserError].}

proc parseIndentedBody(
    parser: var Parser
): seq[SyntaxNode] {.raises: [ParserError].} =
  discard parser.expect(Newline, "expected newline before indented body")
  discard parser.expect(Indent, "expected indented body")
  result = parser.parseStatementList({Dedent})
  discard parser.expect(Dedent, "expected end of indented body")

proc parseLayoutBody(
    parser: var Parser
): seq[SyntaxNode] {.raises: [ParserError].} =
  ## A colon body is either the usual indented suite or comma-separated forms
  ## through the end of its current line.
  if parser.at(Newline):
    return parser.parseIndentedBody()
  if not parser.startsPrimary:
    parser.fail("expected block body")
  result.add parser.parseForm()
  while parser.at(Comma):
    discard parser.take()
    result.add parser.parseForm()
  parser.endStatement("expected newline after inline block")

proc parseIndentedArguments(
    parser: var Parser
): tuple[arguments, body: seq[SyntaxNode], hasBlock: bool] {.raises: [ParserError].} =
  discard parser.expect(Newline, "expected newline before indented arguments")
  discard parser.expect(Indent, "expected indented arguments")
  while not parser.at(Dedent):
    if parser.at(Newline):
      discard parser.take()
      continue
    var item = parser.parseArgument(inSuite = true)
    if item.kind == Command and item.layout != NoLayout:
      result.arguments.add item
      continue
    let startsLineCommand =
      item.kind == Command or
      item.kind == Symbol and not item.symbol.isNumericSymbol
    if parser.startsPrimary and startsLineCommand:
      var arguments: seq[SyntaxNode]
      while parser.startsPrimary:
        arguments.add parser.parseArgument(inSuite = false)
      item = command(item, arguments, item.pos)
      result.arguments.add item
    else:
      result.arguments.add item
      while parser.startsPrimary:
        result.arguments.add parser.parseArgument(inSuite = false)
    if parser.at(Colon):
      discard parser.take()
      if item.kind == Command and item.arguments.len > 0:
        if not item.attachLayout(ColonLayout, parser.parseLayoutBody()):
          parser.fail("layout can only be attached to a command")
        continue
      result.body = parser.parseLayoutBody()
      result.hasBlock = true
      break
    parser.endStatement("expected newline after argument")
  discard parser.expect(Dedent, "expected end of indented arguments")

proc attachLayoutTail(
    parser: var Parser, node: var SyntaxNode
) {.raises: [ParserError].} =
  ## Consume `":" suite` or a continuation argument block and hang it on `node`.
  let (layout, body) =
    if parser.at(Colon):
      discard parser.take()
      (ColonLayout, parser.parseLayoutBody())
    else:
      let continuation = parser.parseIndentedArguments()
      if continuation.hasBlock:
        if node.kind == Symbol:
          node = command(node, @[], node.pos)
        if not node.attachLayout(ContinuationLayout, continuation.arguments) or
            not node.attachLayout(ColonLayout, continuation.body):
          parser.fail("layout can only be attached to a command")
        return
      if parser.at(Colon):
        discard parser.take()
        if node.kind == Symbol:
          node = command(node, @[], node.pos)
        if not node.attachLayout(ContinuationLayout, continuation.arguments) or
            not node.attachLayout(ColonLayout, parser.parseLayoutBody()):
          parser.fail("layout can only be attached to a command")
        return
      (ContinuationLayout, continuation.arguments)
  if node.kind == Symbol:
    node = command(node, @[], node.pos)
  if not node.attachLayout(layout, body):
    parser.fail("layout can only be attached to a command")

proc parseSymbolLike(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  ## A plain atom, or the punctuation accepted where a symbol is expected.
  if parser.peek.kind notin {Atom, Equal, LBracket}:
    parser.fail("expected symbol")
  let token = parser.take()
  if token.kind == LBracket:
    let closeToken = parser.expect(RBracket, "expected ']'")
    result = symbol(token.lexeme & closeToken.lexeme, parser.pos(token))
  else:
    result = symbol(token.lexeme, parser.pos(token))
  result.hangingPipe = token.hangingPipe

proc parsePostfix(
    parser: var Parser, base: SyntaxNode
): SyntaxNode {.raises: [ParserError].} =
  ## Selectors desugar to ordinary calls: `a.b` is `field a "b"` and `a.[i]`
  ## is `index a i`, so chains nest without any further evaluator support.
  result = base
  while parser.at(Dot):
    let dot = parser.take()
    let dotPos = parser.pos(dot)
    if parser.at(Atom):
      let fieldToken = parser.take()
      result = command(
        symbol("field", dotPos),
        @[result, stringLiteral(fieldToken.lexeme, parser.pos(fieldToken))],
        dotPos,
      )
    elif parser.at(LBracket):
      discard parser.take()
      let index = parser.parseForm()
      discard parser.expect(RBracket, "expected ']'")
      result = command(symbol("index", dotPos), @[result, index], dotPos)
    else:
      parser.fail("expected field name or index after '.'")

proc parseGroupedForm(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  let open = parser.expect(LParen, "expected '('")
  result = parser.parseForm()
  if parser.at(Colon) or parser.startsSuite:
    parser.attachLayoutTail(result)
  # A layout body can dedent to further forms before the closing paren -- an
  # `if`/`else` pair written as one expression arrives this way. Keep those
  # forms together as a single expression script.
  let rest = parser.parseStatementList({RParen})
  if rest.len > 0:
    result = script(@[result] & rest, parser.pos(open))
  discard parser.expect(RParen, "expected ')'")
  result = parser.parsePostfix(result)

proc parsePrimary(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  case parser.peek.kind
  of Atom, Equal, LBracket:
    result = parser.parseSymbolLike()
  of StringLit:
    let token = parser.take()
    result = stringLiteral(token.lexeme, parser.pos(token))
  of LParen:
    result = parser.parseGroupedForm()
  else:
    parser.fail("expected argument")

proc parseArgument(
    parser: var Parser, inSuite: bool
): SyntaxNode {.raises: [ParserError].} =
  ## `inSuite` marks an argument written on its own line inside a continuation
  ## block, where following indentation may supply its arguments.
  ##
  ## On a command line the colon is resolved lexically instead: an
  ## identifier-like or numeric argument leaves it to the enclosing command, so
  ## `if condition:` keeps its block form, while an operator-like one such as
  ## `[]` takes it as its own layout. The same colon rule applies to the last
  ## line of a continuation header.
  result = parser.parsePrimary()
  let takesLayout =
    if inSuite:
      parser.startsSuite or
        parser.at(Colon) and result.kind == Symbol and result.symbol.isOperatorSymbol
    else:
      parser.at(Colon) and result.kind == Symbol and result.symbol.isOperatorSymbol
  if takesLayout:
    parser.attachLayoutTail(result)
  result = parser.parsePostfix(result)

proc parseCallee(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  case parser.peek.kind
  of LParen:
    result = parser.parseGroupedForm()
  of Atom, Equal, LBracket:
    result = parser.parsePostfix(parser.parseSymbolLike())
  else:
    parser.fail("expected command callee")

proc parseExpression(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  if parser.at(StringLit):
    let token = parser.take()
    return parser.parsePostfix(stringLiteral(token.lexeme, parser.pos(token)))
  let callee = parser.parseCallee()
  var arguments: seq[SyntaxNode]
  while parser.startsPrimary:
    arguments.add parser.parseArgument(inSuite = false)
  # A group with no arguments after it is just the grouped form; wrapping it
  # would turn `(x)` into a call to whatever `x` holds.
  if callee.kind != Symbol and arguments.len == 0:
    result = callee
  else:
    result = command(callee, arguments, callee.pos)

proc parseIndentedBindingValue(
    parser: var Parser
): SyntaxNode {.raises: [ParserError].} =
  let values = parser.parseIndentedBody()
  if values.len == 0:
    parser.fail("expected indented binding value")
  if values.len == 1:
    result = values[0]
  else:
    result = script(values, values[0].pos)

proc parseForm(parser: var Parser): SyntaxNode {.raises: [ParserError].} =
  if not parser.at(Atom) or parser.peek(1).kind != Equal:
    return parser.parseExpression()
  let bindingToken = parser.take()
  discard parser.take()
  let value =
    if parser.startsSuite:
      parser.parseIndentedBindingValue()
    else:
      parser.parseExpression()
  result = binding(bindingToken.lexeme, value, parser.pos(bindingToken))

proc parseStatement(parser: var Parser): seq[SyntaxNode] {.raises: [ParserError].} =
  var first = parser.parseForm()
  if parser.at(Colon) or parser.startsSuite:
    parser.attachLayoutTail(first)
    return @[first]
  result.add first
  while parser.at(Comma):
    discard parser.take()
    result.add parser.parseForm()
  parser.endStatement("expected newline after statement")

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
  var parser =
    Parser(tokens: tokenize(source, sourceId), pos: 0, source: sourceId)
  let statements = parser.parseStatementList({Eof})
  discard parser.expect(Eof, "expected end of file")
  result = script(
    statements,
    if statements.len > 0: statements[0].pos else: sourcePos(sourceId, 1, 1),
  )
