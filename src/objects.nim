import std/[strutils, sequtils, tables, hashes, tables]

type
  ObjectKind* = enum
    Nothing
    Symbol
    Number
    Boolean
    List
    Record
    Function
    ForeignFunction

  Func* = ref object
    scope*: Env
    name*: string
    params*: seq[Object]
    body*: Object

  Object* = object
    case kind*: ObjectKind
    of Nothing:
      discard
    of Symbol:
      symbol*: string
    of Number:
      number*: float64
    of Boolean:
      isTrue*: bool
    of List:
      items*: seq[Object]
    of Record:
      rec*: Table[Object, Object]
    of Function:
      function*: Func = nil
    of ForeignFunction:
      ffunction*: proc(env: Env, args: seq[Object]): Object {.gcsafe, nimcall.}

  Env* = ref object
    functions*: Table[Object, Func]
    scope*: Object
    next*: Env

proc new*(T: typedesc[Env]): T =
  T(scope: Object(kind: Record, rec: initTable[Object, Object]()))

proc hash*(exp: Object): Hash =
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
  of Function, ForeignFunction:
    raise CatchableError.newException("No hash function available")

proc `==`*(a, b: Object): bool =
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
  of Function, ForeignFunction:
    false

const MaxWidth = 60

proc isCallable*(e: Object): bool =
  return false

proc formatObj(e: Object, indent: int, col: int): string {.gcsafe.} =
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
      parts.add(formatObj(it, indent + 2, col + 2))
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
          formatObj(k, indent + 2, col + 2) & " = " & formatObj(v, indent + 2, col + 2)
        )
      let oneLine = "{" & kvs.join(", ") & "}"
      if oneLine.len + col <= MaxWidth:
        oneLine
      else:
        let ind = " ".repeat(indent)
        "{\n" & kvs.mapIt(ind & it).join(",\n") & "\n" & " ".repeat(indent - 2) & "}"
  of Function:
    "Function"
  of ForeignFunction:
    "ForeignFunction"

proc `$`*(e: Object): string {.gcsafe.} =
  formatObj(e, 2, 0)

proc `$`*(es: seq[Object]): string {.gcsafe.} =
  for e in es:
    result &= "@[" & formatObj(e, 2, 0) & "]"

proc sym*(s: string): Object =
  Object(kind: Symbol, symbol: s)

proc num*(s: SomeNumber): Object =
  when s is SomeFloat:
    let n = s.float64
  else:
    let n = s.toFloat().float64
  Object(kind: Number, number: n)

proc ffunc*(fn: proc(env: Env, args: seq[Object]): Object {.gcsafe, nimcall.}): Object =
  Object(kind: ForeignFunction, ffunction: fn)

proc toBool*(o: Object): Object =
  if o.kind == Nothing or (o.kind == Number and o.number == 0.0):
    return Object(kind: Boolean, isTrue: false)
  else:
    return Object(kind: Boolean, isTrue: true)

let True* = Object(kind: Boolean, isTrue: true)
let False* = Object(kind: Boolean, isTrue: false)
let None* = Object(kind: Nothing)

proc node*(tag: string, xs: seq[Object]): Object =
  Object(kind: List, items: @[sym(tag)] & xs)

# Environment API

## Returns Nothing if not found

proc find*(env: Env, sym: Object): Object {.gcsafe.} =
  {.cast(gcsafe).}:
    if env.scope.rec.hasKey(sym):
      return env.scope.rec[sym]
    if not env.scope.rec.hasKey(sym) and not env.next.isNil:
      return env.next.find(sym)

proc has*(env: Env, sym: Object): bool {.gcsafe.} =
  {.cast(gcsafe).}:
    if env.scope.kind != Record:
      raise CatchableError.newException("Unable to index object '" & $env.scope & "'")
    if env.scope.rec.hasKey(sym):
      return true
    if not env.scope.rec.hasKey(sym) and not env.next.isNil:
      return env.next.has(sym)

proc add*(env: Env, key, val: Object) {.gcsafe.} =
  {.cast(gcsafe).}:
    env.scope.rec[key] = val

proc add*(env: Env, key: Object, val: Func): Object {.gcsafe, discardable.} =
  {.cast(gcsafe).}:
    result = Object(kind: Function, function: val)
    env.functions[key] = val
    env.scope.rec[key] = result

proc `[]=`*(env: Env, key, val: Object) {.gcsafe.} =
  env.add(key, val)
