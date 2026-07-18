import std/[strutils, tables]

import syntax

type
  ValueKind* = enum
    Nothing
    Number
    Boolean
    Text
    Stream
    List
    Dictionary
    Syntax
    Command
    Native

  EvaluatorError* = object of CatchableError

  NativeValue* = ref object of RootObj

  StreamKind* = enum
    InputStream
    OutputStream

  Environment* = ref object
    parent*: Environment
    bindings*: Table[string, Value]
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
      items*: seq[Value]
    of Dictionary:
      entries*: Table[string, Value]
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
  Value(kind: List, items: items)

proc dictionary*(entries: sink Table[string, Value]): Value {.raises: [].} =
  Value(kind: Dictionary, entries: entries)

proc syntaxValue*(node: SyntaxNode, env: Environment = nil): Value {.raises: [].} =
  Value(kind: Syntax, syntax: node, syntaxEnv: env)

proc nativeCommand*(native: NativeCommand): Value {.raises: [].} =
  Value(kind: Command, command: CommandValue(kind: NativeCommandKind, native: native))

proc nativeValue*(native: NativeValue): Value {.raises: [].} =
  Value(kind: Native, native: native)

proc closureCommand*(
    parameters: sink seq[string], body: sink seq[SyntaxNode], captured: Environment,
    evaluatesArguments, acceptsBlock: bool
): Value {.raises: [].} =
  Value(
    kind: Command,
    command: CommandValue(
      kind: ClosureCommandKind,
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

proc `$`*(value: Value): string {.raises: [].} =
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
    value.text
  of Stream:
    case value.stream
    of InputStream:
      "<stdin>"
    of OutputStream:
      "<stdout>"
  of List:
    var parts: seq[string]
    for item in value.items:
      parts.add $item
    "[" & parts.join(", ") & "]"
  of Dictionary:
    var parts: seq[string]
    for key, entry in value.entries:
      parts.add key & ": " & $entry
    "{" & parts.join(", ") & "}"
  of Syntax:
    $value.syntax
  of Command:
    "<command>"
  of Native:
    "<native>"

proc parseNumber*(symbol: string): tuple[ok: bool, value: Value] {.raises: [].} =
  try:
    if symbol.contains('.') or symbol.contains('e') or symbol.contains('E'):
      return (true, number(parseFloat(symbol)))
    return (true, number(parseInt(symbol).float64))
  except ValueError:
    return (false, nothing())

when isMainModule:
  discard
