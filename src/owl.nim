import std/[strutils, sequtils, tables, hashes]

import fusion/matching
{.experimental: "caseStmtMacros".}

type
  ParseError* = object of CatchableError
  TokenKind* = enum
    Eof
    Symbol
    Number
    Op

  Token* = object
    case kind*: TokenKind
    of Symbol:
      symbol*: string
    of Number:
      number*: float64
    of Op:
      operator*: string
    of Eof:
      discard

  Lexer* = object
    tokens*: seq[Token]
    index*: int
    noMatch*: bool

  ExpKind* = enum
    Nothing
    Symbol
    Number
    Boolean
    List
    Record

  Exp* = object
    case kind*: ExpKind
    of Nothing:
      discard
    of Symbol:
      symbol*: string
    of Number:
      number*: float64
    of Boolean:
      isTrue*: bool
    of List:
      items*: seq[Exp]
    of Record:
      rec: Table[Exp, Exp]

proc hash*(exp: Exp): Hash =
  case exp.kind
  of Nothing:
    hash(0)
  of Symbol:
    hash(exp.symbol)
  of Number:
    hash(exp.number)
  of Boolean:
    hash(exp.isTrue)
  of List:
    hash(exp.items)
  of Record:
    hash(exp.rec)

proc `==`*(a, b: Exp): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of Nothing:
    true
  of Symbol:
    a.symbol == b.symbol
  of Number:
    a.number == b.number
  of Boolean:
    a.isTrue == b.isTrue
  of List:
    if a.items.len != b.items.len:
      return false
    for i in 0 ..< a.items.len:
      if a.items[i] != b.items[i]:
        return false
    true
  of Record:
    if a.rec.len != b.rec.len:
      return false
    for k, v in a.rec:
      if not b.rec.hasKey(k):
        return false
      if b.rec[k] != v:
        return false
    true

const MaxWidth = 60

proc formatExp(e: Exp, indent: int, col: int): string =
  case e.kind
  of Symbol:
    ":" & e.symbol
  of Number:
    let i = int64(e.number)
    if e.number == float64(i):
      $i
    else:
      $e.number
  of List:
    var parts: seq[string]
    for it in e.items:
      parts.add(formatExp(it, indent + 2, col + 2))
    let oneLine = "(" & parts.join(" ") & ")"
    if oneLine.len + col <= MaxWidth:
      oneLine
    else:
      let ind = " ".repeat(indent)
      "(\n" & parts.mapIt(ind & it).join("\n") & "\n" & " ".repeat(indent - 2) & ")"
  of Boolean:
    if e.isTrue: "#t" else: "#f"
  of Nothing:
    "Nothing"
  of Record:
    if e.rec.len == 0:
      "{}"
    else:
      var kvs: seq[string]
      for k, v in e.rec:
        kvs.add(
          formatExp(k, indent + 2, col + 2) & " = " & formatExp(v, indent + 2, col + 2)
        )
      let oneLine = "{" & kvs.join(", ") & "}"
      if oneLine.len + col <= MaxWidth:
        oneLine
      else:
        let ind = " ".repeat(indent)
        "{\n" & kvs.mapIt(ind & it).join(",\n") & "\n" & " ".repeat(indent - 2) & "}"

proc `$`*(e: Exp): string =
  formatExp(e, 2, 0)

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
  of Symbol:
    t.symbol
  of Op:
    t.operator
  of Number:
    $t.number
  of Eof:
    "<eof>"

proc call*(lex: var Lexer): tuple[exp: Exp, matched: bool]

proc sym*(s: string): Exp =
  Exp(kind: Symbol, symbol: s)

proc num*(s: SomeNumber): Exp =
  when s is SomeFloat:
    let n = s.float64
  else:
    let n = s.toFloat().float64
  Exp(kind: Number, number: n)

const True* = Exp(kind: Boolean, isTrue: true)
const False* = Exp(kind: Boolean, isTrue: false)
const None* = Exp(kind: Nothing)

proc node*(tag: string, xs: seq[Exp]): Exp =
  Exp(kind: List, items: @[sym(tag)] & xs)

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
    if ch in {'+', '-', '/', '*', '.', '='}:
      inc index
      result.tokens.add(Token(kind: Op, operator: $ch))
      continue
    if ch in {'(', ')', '{', '}', '[', ']', ','}:
      inc index
      result.tokens.add(Token(kind: Symbol, symbol: $ch))
      continue
    if ch in {'@'} and str[start + 1] == '{':
      index += 2
      result.tokens.add(Token(kind: Symbol, symbol: "@{"))
      continue
    if chr() notin IdentStartChars + {'#'}:
      raise Exception.newException("Invalid character '" & chr() & "'")
    inc index
    while not atEof() and chr() in IdentChars:
      inc index
    result.tokens.add(Token(kind: Symbol, symbol: str[start ..< index]))

proc infixPower*(op: Exp): (uint8, uint8) =
  if op.kind != Symbol:
    raise Exception.newException("Expected symbol")
  case op.symbol
  of "+", "-":
    (1, 2)
  of "*", "/":
    (3, 4)
  of ".":
    (6, 5)
  else:
    raise Exception.newException("Bad operator: " & op.symbol)

proc binExpr*(lex: var Lexer, minBp = 0'u8): Exp
proc primary*(lex: var Lexer): Exp

proc expr*(lex: var Lexer): Exp =
  lex.binExpr()

proc binExpr*(lex: var Lexer, minBp = 0'u8): Exp =
  var left = lex.primary()

  while true:
    let look = lex[lex.index]
    if look.kind != Op:
      break
    let op = Exp(kind: Symbol, symbol: look.operator)
    let (lBp, rBp) = infixPower(op)
    if lBp < minBp:
      break
    discard lex.next()
    let right = lex.binExpr(rBp)
    left = Exp(kind: List, items: @[op, left, right])

  result = left

proc list*(lex: var Lexer): tuple[exp: Exp, matched: bool]
proc rec*(lex: var Lexer): tuple[exp: Exp, matched: bool]
proc codeBlock*(lex: var Lexer): tuple[exp: Exp, matched: bool]

template tryMatch(lex: var Lexer, ident) =
  let (v, isV) = lex.ident()
  if isV:
    return v

proc primary*(lex: var Lexer): Exp =
  case lex.peek()
  of (kind: Number, number: @n):
    discard lex.next(); return num(n)
  of (kind: Symbol, symbol: "#t"):
    discard lex.next(); return True
  of (kind: Symbol, symbol: "#f"):
    discard lex.next(); return False
  of (kind: Symbol, symbol: "none"):
    discard lex.next(); return None
  else:
    discard

  lex.tryMatch(list)
  lex.tryMatch(codeBlock)
  lex.tryMatch(rec)

  if lex.peek().kind == Symbol:
    let s = lex.peek().symbol
    if s notin ["(", ")", "{", "}", "[", "]", ",", "@{"]:
      discard lex.next()
      return sym(s)

  raise ParseError.newException("Unexpected token: " & lex.peek().lexeme)

proc bindingList*(lex: var Lexer, symbol: string): tuple[exp: Exp, matched: bool]
proc binding*(lex: var Lexer): tuple[exp: Exp, matched: bool]
proc recordKey*(lex: var Lexer): tuple[exp: Exp, matched: bool]
proc argList*(lex: var Lexer): tuple[exp: Exp, matched: bool]

proc rec*(lex: var Lexer): tuple[exp: Exp, matched: bool] =
  if lex[lex.index].kind != Symbol or lex[lex.index].symbol != "@{":
    return (None, false)
  lex.expectSymbol("@{")
  let (bindings, matched) = lex.bindingList("record")
  assert(matched)
  result = (bindings, true)
  lex.expectSymbol("}")

proc bindingList*(lex: var Lexer, symbol: string): tuple[exp: Exp, matched: bool] =
  result = (Exp(kind: List, items: @[sym(symbol)]), true)
  while lex.peek().lexeme != "}" and not lex.atEof():
    let (binding, isBinding) = lex.binding()
    assert(isBinding)
    result.exp.items.add(binding)
    if lex.peek().lexeme == "}":
      break
    lex.expectSymbol(",")

proc binding*(lex: var Lexer): tuple[exp: Exp, matched: bool] =
  let (key, isKey) = lex.recordKey()
  assert(isKey)
  lex.expectOperator("=")
  let expr = lex.expr()
  result = (Exp(kind: List, items: @[sym"pair", key, expr]), true)
 
proc symbol*(lex: var Lexer): tuple[exp: Exp, matched: bool] =
  if lex.peek().kind != Symbol:
    return (None, false)
  result = (lex.next().lexeme.sym(), true)

proc number*(lex: var Lexer): tuple[exp: Exp, matched: bool] =
  if lex.peek().kind != Number:
    return (None, false)
  result = (lex.next().number.num(), true)

proc recordKey*(lex: var Lexer): tuple[exp: Exp, matched: bool] =
  let (sy, isSy) = lex.symbol()
  if isSy:
    return (sy, true)
  let (sn, isSn) = lex.number()
  if isSn:
    return (sn, true)
  raise ParseError.newException("Invalid record key " & $lex.peek())

proc codeBlock*(lex: var Lexer): tuple[exp: Exp, matched: bool] =
  if lex[lex.index].kind != Symbol or lex[lex.index].symbol != "{":
    return (None, false)
  lex.expectSymbol("{")
  var blk = Exp(kind: List, items: @[sym"do"])
  while lex.peek().lexeme != "}" and not lex.atEof():
    let exp = lex.expr()
    blk.items.add(exp)
    if lex.peek().lexeme == "}":
      break
  result = (blk, true)
  lex.expectSymbol("}")

proc list*(lex: var Lexer): tuple[exp: Exp, matched: bool] =
  if lex.peek().lexeme != "[":
    return (None, false)
  discard lex.next()
  result = (Exp(kind: List), true)
  while lex.peek().lexeme != "]" and not lex.atEof():
    result.exp.items.add(lex.expr())
    if lex.peek().lexeme == "]":
      break
    lex.expectSymbol(",")
  discard lex.next()

proc argList*(lex: var Lexer): tuple[exp: Exp, matched: bool] =
  discard

proc call*(lex: var Lexer):  tuple[exp: Exp, matched: bool] =
  let (ident, isSym) = lex.symbol()
  if not isSym:
    return (None, false)

proc module*(lex: var Lexer): Exp =
  result = Exp(kind: List)
  while not lex.atEof():
    result.items.add(lex.expr())

when isMainModule:
  var lex = Lexer.init("{}")
  echo lex
  echo codeBlock(lex).exp
