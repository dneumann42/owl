import std/[strutils, tables]

import fusion/matching

import objects, evaluation, libraries
export objects, evaluation, libraries

{.experimental: "caseStmtMacros".}

type
  ParseError* = object of CatchableError
  TokenKind* = enum
    Eof
    String
    Symbol
    Number
    Op

  Token* = object
    case kind*: TokenKind
    of Symbol:
      symbol*: string
    of Number:
      number*: float64
    of String:
      str*: string
    of Op:
      operator*: string
    of Eof:
      discard

  Lexer* = object
    tokens*: seq[Token]
    index*: int
    noMatch*: bool

proc `[]`*(lex: Lexer, idx: int): Token =
  if idx >= lex.tokens.len:
    return Token(kind: Eof)
  result = lex.tokens[idx]

proc peek*(lex: Lexer): Token =
  result = lex[lex.index]

proc next*(lex: var Lexer): Token =
  result = lex[lex.index]
  inc lex.index

proc lexeme*(t: Token): string =
  case t.kind
  of String:
    t.str
  of Symbol:
    t.symbol
  of Op:
    t.operator
  of Number:
    $t.number
  of Eof:
    "<eof>"

proc call*(lex: var Lexer, left: Object): Object

proc expectSymbol*(lex: var Lexer, s: string) =
  let t = lex.next()
  if t.kind != Symbol or t.symbol != s:
    raise ParseError.newException("Expected '" & s & "' got '" & t.lexeme() & "'")

proc expectOperator*(lex: var Lexer, s: string) =
  let t = lex.next()
  if t.kind != Op or t.operator != s:
    raise ParseError.newException("Expected '" & s & "' got '" & t.lexeme() & "'")

proc expectIdent*(lex: var Lexer, s: string): string =
  let t = lex.next()
  if t.kind != Symbol or t.symbol != s:
    raise
      ParseError.newException("Expected identifier " & s & " got '" & t.lexeme() & "'")
  result = t.symbol

proc expectOp*(lex: var Lexer, s: string) =
  let t = lex.next()
  if t.kind != Op or t.operator != s:
    raise ParseError.newException("Expected '" & s & "' got '" & t.lexeme() & "'")

proc atEof*(lex: Lexer): bool =
  lex.peek().kind == Eof

proc init*(T: typedesc[Lexer], str: string): T =
  result = Lexer()

  var index = 0
  proc atEof(): bool =
    index >= str.len()

  proc chr(): char =
    str[index]

  proc nextChr(): char =
    if index + 1 < str.len():
      str[index + 1]
    else:
      '\0'

  proc skipWs() =
    while not atEof() and chr() in Whitespace:
      inc index

  while not atEof():
    skipWs()
    if atEof():
      break

    let
      start = index
      ch = chr()

    if ch in Digits:
      inc index
      while not atEof() and chr() in Digits:
        inc index
      result.tokens.add(Token(kind: Number, number: parseFloat(str[start ..< index])))
      continue

    if ch in {'+', '-', '/', '*', '.'}:
      inc index
      result.tokens.add(Token(kind: Op, operator: $ch))
      continue

    if ch in {'=', '!', '<', '>'}:
      let n = nextChr()
      if n == '=':
        index += 2
        result.tokens.add(Token(kind: Op, operator: $ch & "="))
      else:
        inc index
        if ch in {'<', '>'}:
          result.tokens.add(Token(kind: Op, operator: $ch))
        else:
          result.tokens.add(Token(kind: Op, operator: $ch))
      continue

    if ch == '\'':
      inc index
      result.tokens.add(Token(kind: Symbol, symbol: "'"))
      continue

    if ch in {'(', ')', '{', '}', '[', ']', ','}:
      inc index
      result.tokens.add(Token(kind: Symbol, symbol: $ch))
      continue

    if ch in {'@'} and str[start + 1] == '{':
      index += 2
      result.tokens.add(Token(kind: Symbol, symbol: "@{"))
      continue

    if ch == '\"':
      index += 1
      let start = index
      while chr() != '\"':
        index += 1
        if atEof():
          raise Exception.newException("Missing closing quote")
      result.tokens.add(Token(kind: String, str: str[start ..< index]))
      index += 1
      continue

    if chr() notin IdentStartChars + {'#', ':'}:
      raise Exception.newException("Invalid character '" & chr() & "'")

    inc index
    while not atEof() and (chr() in IdentChars + {'-', '*', '+', '$', '_'}):
      inc index
    result.tokens.add(Token(kind: Symbol, symbol: str[start ..< index]))

proc infixPower*(op: Object): (uint8, uint8) =
  if op.kind != Symbol:
    raise Exception.newException("Expected symbol")
  case op.symbol
  of "==", "!=":
    (1, 2)
  of "<", "<=", ">", ">=":
    (3, 4)
  of "+", "-":
    (5, 6)
  of "*", "/":
    (7, 8)
  of ".":
    (9, 10)
  else:
    raise Exception.newException("Bad operator: " & op.symbol)

proc binExpr*(lex: var Lexer, minBp = 0'u8): Object
proc primary*(lex: var Lexer): Object

proc expr*(lex: var Lexer): Object =
  lex.binExpr()

proc binExpr*(lex: var Lexer, minBp = 0'u8): Object =
  var left = lex.primary()
  left = lex.call(left)
  while true:
    let look = lex[lex.index]
    if look.kind != Op:
      break
    let op = Object(kind: Symbol, symbol: look.operator)
    let (lBp, rBp) = infixPower(op)
    if lBp < minBp:
      break
    discard lex.next()
    var right = lex.binExpr(rBp)
    right = lex.call(right)
    left = Object(kind: List, items: @[op, left, right])
  left

proc list*(lex: var Lexer): tuple[exp: Object, matched: bool]
proc rec*(lex: var Lexer): tuple[exp: Object, matched: bool]
proc codeBlock*(lex: var Lexer): tuple[exp: Object, matched: bool]
proc letExp*(lex: var Lexer): tuple[exp: Object, matched: bool]
proc argList*(lex: var Lexer): tuple[exp: Object, matched: bool]
proc fnExpr*(lex: var Lexer): tuple[exp: Object, matched: bool]
proc fnDefn*(lex: var Lexer): tuple[exp: Object, matched: bool]

template tryMatch(lex: var Lexer, ident) =
  let (v, isV) = lex.ident()
  if isV:
    return v

proc primary*(lex: var Lexer): Object =
  case lex.peek()
  of (kind: Number, number: @n):
    discard lex.next()
    return num(n)
  of (kind: Symbol, symbol: "#t"):
    discard lex.next()
    return True
  of (kind: Symbol, symbol: "#f"):
    discard lex.next()
    return False
  of (kind: Symbol, symbol: "none"):
    discard lex.next()
    return None
  of (kind: Symbol, symbol: "'"):
    discard lex.next()
    let quoted = lex.expr()
    return node("quote", @[quoted])
  of (kind: String, str: @s):
    discard lex.next()
    return Object(kind: String, str: s)
  else:
    discard

  lex.tryMatch(list)
  lex.tryMatch(codeBlock)
  lex.tryMatch(rec)
  lex.tryMatch(letExp)
  lex.tryMatch(fnExpr)
  lex.tryMatch(fnDefn)

  if lex.peek().kind == Symbol:
    let s = lex.peek().symbol
    if s notin ["(", ")", "{", "}", "[", "]", ",", "@{"]:
      discard lex.next()
      return sym(s)

  raise ParseError.newException("Unexpected token: " & lex.peek().lexeme)

proc symbol*(lex: var Lexer): tuple[exp: Object, matched: bool]

proc paramList*(lex: var Lexer): tuple[params: Object, matched: bool] =
  result = (Object(kind: List, items: @[]), true)
  while lex.peek().lexeme != ")":
    let (p, ok) = lex.symbol()
    if not ok:
      return (None, false)
    result.params.items.add(p)
    if lex.peek().lexeme == ")":
      break
    lex.expectSymbol(",")

proc fnExpr*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  if lex[lex.index].kind != Symbol or lex[lex.index].symbol != "fun":
    return (None, false)
  let save = lex.index
  lex.expectSymbol("fun")
  if lex.peek().kind != Symbol or lex.peek().symbol != "(":
    lex.index = save
    return (None, false)
  lex.expectSymbol("(")
  let (params, ok) = lex.paramList()
  if not ok:
    lex.index = save
    return (None, false)
  lex.expectSymbol(")")
  let body = lex.expr()
  (Object(kind: List, items: @[sym"lambda", params, body]), true)

proc fnDefn*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  if lex[lex.index].kind != Symbol or lex[lex.index].symbol != "fun":
    return (None, false)
  let save = lex.index
  lex.expectSymbol("fun")
  let (fname, okName) = lex.symbol()
  if not okName:
    lex.index = save
    return (None, false)
  if lex.peek().kind != Symbol or lex.peek().symbol != "(":
    lex.index = save
    return (None, false)
  lex.expectSymbol("(")
  let (params, ok) = lex.paramList()
  if not ok:
    lex.index = save
    return (None, false)
  lex.expectSymbol(")")
  let (blk, isBlk) = lex.codeBlock()
  if not isBlk:
    lex.index = save
    return (None, false)
  (Object(kind: List, items: @[sym"fun", fname, params, blk]), true)

proc bindingList*(lex: var Lexer, symbol: string): tuple[exp: Object, matched: bool]
proc binding*(lex: var Lexer): tuple[exp: Object, matched: bool]
proc recordKey*(lex: var Lexer): tuple[exp: Object, matched: bool]

proc rec*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  if lex[lex.index].kind != Symbol or lex[lex.index].symbol != "{":
    return (None, false)
  lex.expectSymbol("{")
  var (bindings, matched) = lex.bindingList("record")
  assert(matched)

  var xs = bindings.items[1]
  for item in xs.items:
    bindings.items.add(item)
  bindings.items.delete(1)

  result = (bindings, true)
  lex.expectSymbol("}")

proc bindingList*(lex: var Lexer, symbol: string): tuple[exp: Object, matched: bool] =
  result = (Object(kind: List, items: @[sym(symbol)]), true)
  var xs = newSeq[Object]()
  while lex.peek().lexeme != "}" and not lex.atEof():
    let (binding, isBinding) = lex.binding()
    assert(isBinding)
    xs.add(binding)
    if lex.peek().lexeme == "}":
      break
    lex.expectSymbol(",")
  result.exp.items.add(Object(kind: List, items: xs))

proc binding*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  let (key, isKey) = lex.recordKey()
  assert(isKey)
  lex.expectOperator("=")
  let expr = lex.expr()
  result = (Object(kind: List, items: @[sym"pair", key, expr]), true)

proc symbol*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  if lex.peek().kind != Symbol:
    return (None, false)
  result = (lex.next().lexeme.sym(), true)

proc number*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  if lex.peek().kind != Number:
    return (None, false)
  result = (lex.next().number.num(), true)

proc recordKey*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  let (sy, isSy) = lex.symbol()
  if isSy:
    return (sy, true)
  let (sn, isSn) = lex.number()
  if isSn:
    return (sn, true)
  raise ParseError.newException("Invalid record key " & $lex.peek())

proc codeBlock*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  if lex[lex.index].kind != Symbol or lex[lex.index].symbol != "do":
    return (None, false)
  lex.expectSymbol("do")
  var blk = Object(kind: List, items: @[sym"do"])
  while lex.peek().lexeme != "end" and not lex.atEof():
    let exp = lex.expr()
    blk.items.add(exp)
    if lex.peek().lexeme == "end":
      break
  result = (blk, true)
  lex.expectSymbol("end")

proc list*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  if lex.peek().lexeme != "[":
    return (None, false)
  discard lex.next()
  result = (Object(kind: List, items: @[sym"list"]), true)
  while lex.peek().lexeme != "]" and not lex.atEof():
    result.exp.items.add(lex.expr())
    if lex.peek().lexeme == "]":
      break
    lex.expectSymbol(",")
  discard lex.next()

proc argList*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  result = (Object(kind: List, items: @[]), true)
  while lex.peek().lexeme != ")":
    result.exp.items.add(lex.expr())
    if lex.peek().lexeme == ")":
      return
    lex.expectSymbol(",")

proc call*(lex: var Lexer, left: Object): Object =
  result = left
  while lex.peek().kind == Symbol and lex.peek().symbol == "(":
    lex.expectSymbol("(")
    let (args, ok) = lex.argList()
    if not ok:
      raise ParseError.newException("Failed to parse arguments")
    lex.expectSymbol(")")
    var xs = @[result]
    for a in args.items:
      xs.add(a)
    result = Object(kind: List, items: xs)

proc letHead*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  let start = lex.index
  let (ident, isSym) = lex.symbol()
  if not isSym or ident.symbol == "{":
    lex.index = start
    return (None, false)
  if lex[lex.index].lexeme != "(":
    return (ident, true)
  lex.expectSymbol("(")
  var (args, isArgs) = lex.argList()
  if not isArgs:
    raise ParseError.newException("Failed to parse arguments")
  lex.expectSymbol(")")
  args.items.insert(ident, 0)
  return (args, true)

proc letExp*(lex: var Lexer): tuple[exp: Object, matched: bool] =
  if lex[lex.index].lexeme != "let":
    return (None, false)
  lex.expectSymbol("let")
  let (head, isHead) = lex.letHead()
  if not isHead and lex[lex.index].lexeme == "{":
    discard lex.next()
    var (bindings, matched) = lex.bindingList("let")
    if not matched:
      raise ParseError.newException("Failed to parse block")
    lex.expectSymbol("}")
    lex.expectSymbol("in")
    bindings.items.add(lex.expr())
    return (bindings, true)
  elif isHead and lex.peek().lexeme == "=":
    lex.expectOperator("=")
    return (Object(kind: List, items: @[sym"let", head, lex.expr()]), true)
  elif isHead and lex.peek().lexeme == "{":
    discard lex.next()
    let (bindings, matched) = lex.bindingList("let")
    if not matched:
      raise ParseError.newException("Failed to parse block")
    lex.expectSymbol("}")
    let (blk, isBlk) = lex.codeBlock()
    if not isBlk:
      raise ParseError.newException("Failed to parse block")
    var le = Object(kind: List, items: @[sym"let", head, bindings, blk])
    return (le, true)

proc module*(lex: var Lexer): Object =
  result = Object(kind: List, items: @[sym"do"])
  while not lex.atEof():
    result.items.add(lex.expr())
