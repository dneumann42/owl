import std/[oids, options, sets, strformat, strutils, tables, times]

import owl/[parser, syntax, values]

type DataError* = object of CatchableError

proc dataError(message: string): ref DataError {.raises: [].} =
  newException(DataError, message)

proc requireKind(value: Value, kind: ValueKind) {.raises: [DataError].} =
  if value.kind != kind:
    raise dataError(&"expected Owl {kind}, got {value.kind}")

proc toOwl*(value: Value): Value {.raises: [].} =
  value

proc fromOwl*(value: Value, target: var Value) {.raises: [].} =
  target = value

proc toOwl*(node: SyntaxNode): Value {.raises: [].} =
  syntaxValue(node)

proc fromOwl*(value: Value, target: var SyntaxNode) {.raises: [DataError, ParserError].} =
  case value.kind
  of Syntax:
    target = value.syntax
  of Text:
    target = parse(value.text)
  else:
    raise dataError(&"expected Owl syntax or text, got {value.kind}")

proc toOwl*(value: SomeInteger): Value {.raises: [].} =
  number(value.float64)

proc fromOwl*(value: Value, target: var SomeInteger) {.raises: [DataError].} =
  value.requireKind(Number)
  when target is SomeUnsignedInt:
    if value.number < 0:
      raise dataError("expected unsigned integer, got negative number")
  target = typeof(target)(value.number.int64)

proc toOwl*(value: SomeFloat): Value {.raises: [].} =
  number(value.float64)

proc fromOwl*(value: Value, target: var SomeFloat) {.raises: [DataError].} =
  value.requireKind(Number)
  target = typeof(target)(value.number)

proc toOwl*(value: bool): Value {.raises: [].} =
  boolean(value)

proc fromOwl*(value: Value, target: var bool) {.raises: [DataError].} =
  value.requireKind(Boolean)
  target = value.boolean

proc toOwl*(value: string): Value {.raises: [].} =
  text(value)

proc fromOwl*(value: Value, target: var string) {.raises: [DataError].} =
  value.requireKind(Text)
  target = value.text

proc toOwl*(value: char): Value {.raises: [].} =
  text($value)

proc fromOwl*(value: Value, target: var char) {.raises: [DataError].} =
  value.requireKind(Text)
  if value.text.len != 1:
    raise dataError("expected one-character text")
  target = value.text[0]

proc toOwl*[T: enum](value: T): Value {.raises: [].} =
  text($value)

proc fromOwl*[T: enum](value: Value, target: var T) {.raises: [DataError].} =
  value.requireKind(Text)
  try:
    target = parseEnum[T](value.text)
  except ValueError:
    raise dataError(&"invalid enum value: {value.text}")

proc toOwl*[T](value: Option[T]): Value =
  if value.isSome:
    value.get.toOwl()
  else:
    nothing()

proc fromOwl*[T](value: Value, target: var Option[T]) =
  if value.kind == Nothing:
    target = none(T)
  else:
    var item: T
    fromOwl(value, item)
    target = some(item)

proc toOwl*[T](values: openArray[T]): Value =
  var items: seq[Value]
  for item in values:
    items.add item.toOwl()
  list(items)

proc fromOwl*[T](value: Value, target: var seq[T]) =
  value.requireKind(List)
  target.setLen(0)
  for item in value.items:
    var converted: T
    fromOwl(item, converted)
    target.add converted

proc fromOwl*[N, T](value: Value, target: var array[N, T]) =
  value.requireKind(List)
  if value.listLen != target.len:
    raise dataError(&"expected array length {target.len}, got {value.listLen}")
  for index in 0 ..< target.len:
    fromOwl(value.at(index), target[index])

proc toOwl*[T](values: set[T]): Value =
  var items: seq[Value]
  for item in values:
    items.add item.toOwl()
  list(items)

proc fromOwl*[T](value: Value, target: var set[T]) =
  value.requireKind(List)
  target = {}
  for item in value.items:
    var converted: T
    fromOwl(item, converted)
    target.incl converted

proc toOwl*[T](values: HashSet[T]): Value =
  var items: seq[Value]
  for item in values:
    items.add item.toOwl()
  list(items)

proc fromOwl*[T](value: Value, target: var HashSet[T]) =
  value.requireKind(List)
  target = initHashSet[T]()
  for item in value.items:
    var converted: T
    fromOwl(item, converted)
    target.incl converted

proc tableKeyToField*[K](key: K): string {.raises: [].} =
  when K is string:
    key
  elif K is char:
    $key
  elif K is enum:
    $key
  elif K is SomeInteger:
    $key
  elif K is bool:
    if key: "true" else: "false"
  else:
    $key

proc fieldToTableKey*[K](field: string, target: var K) {.raises: [DataError].} =
  when K is string:
    target = field
  elif K is char:
    if field.len != 1:
      raise dataError("expected one-character table key")
    target = field[0]
  elif K is enum:
    try:
      target = parseEnum[K](field)
    except ValueError:
      raise dataError(&"invalid enum table key: {field}")
  elif K is SomeUnsignedInt:
    try:
      let parsed = parseBiggestUInt(field)
      target = K(parsed)
    except ValueError:
      raise dataError(&"invalid unsigned integer table key: {field}")
  elif K is SomeInteger:
    try:
      let parsed = parseBiggestInt(field)
      target = K(parsed)
    except ValueError:
      raise dataError(&"invalid integer table key: {field}")
  elif K is bool:
    case field
    of "true", "T":
      target = true
    of "false", "F":
      target = false
    else:
      raise dataError(&"invalid bool table key: {field}")
  else:
    raise dataError("table key type does not have a default Owl reader")

proc toOwl*[K, T](values: Table[K, T]): Value =
  var entries = initTable[string, Value]()
  for key, item in values:
    entries[key.tableKeyToField()] = item.toOwl()
  dictionary(entries)

proc fromOwl*[K, T](value: Value, target: var Table[K, T]) =
  value.requireKind(Dictionary)
  target = initTable[K, T]()
  for key, item in value.entries:
    var convertedKey: K
    fieldToTableKey(key, convertedKey)
    var converted: T
    fromOwl(item, converted)
    target[convertedKey] = converted

proc toOwl*[K, T](values: OrderedTable[K, T]): Value =
  var entries = initTable[string, Value]()
  for key, item in values:
    entries[key.tableKeyToField()] = item.toOwl()
  dictionary(entries)

proc fromOwl*[K, T](value: Value, target: var OrderedTable[K, T]) =
  value.requireKind(Dictionary)
  target = initOrderedTable[K, T]()
  for key, item in value.entries:
    var convertedKey: K
    fieldToTableKey(key, convertedKey)
    var converted: T
    fromOwl(item, converted)
    target[convertedKey] = converted

proc toOwl*(value: Time): Value {.raises: [].} =
  text(value.utc.format("yyyy-MM-dd'T'HH:mm:sszzz"))

proc fromOwl*(value: Value, target: var Time) {.raises: [DataError].} =
  value.requireKind(Text)
  try:
    target = parse(value.text, "yyyy-MM-dd'T'HH:mm:sszzz").toTime()
  except TimeParseError:
    raise dataError(&"invalid Time value: {value.text}")

proc toOwl*(value: DateTime): Value {.raises: [].} =
  text(value.format("yyyy-MM-dd'T'HH:mm:sszzz"))

proc fromOwl*(value: Value, target: var DateTime) {.raises: [DataError].} =
  value.requireKind(Text)
  try:
    target = parse(value.text, "yyyy-MM-dd'T'HH:mm:sszzz")
  except TimeParseError:
    raise dataError(&"invalid DateTime value: {value.text}")

proc toOwl*(value: Duration): Value {.raises: [].} =
  number(value.inNanoseconds.float64)

proc fromOwl*(value: Value, target: var Duration) {.raises: [DataError].} =
  value.requireKind(Number)
  target = initDuration(nanoseconds = value.number.int64)

proc toOwl*(value: Oid): Value {.raises: [].} =
  text($value)

proc fromOwl*(value: Value, target: var Oid) {.raises: [DataError].} =
  value.requireKind(Text)
  try:
    target = parseOid(value.text.cstring)
  except ValueError:
    raise dataError(&"invalid Oid value: {value.text}")

proc entriesOf(value: Value): Table[string, Value] {.raises: [DataError].} =
  case value.kind
  of Dictionary:
    value.entries
  of Record:
    value.recordEntries
  else:
    raise dataError(&"expected Owl dictionary or record, got {value.kind}")

proc objectToOwl*[T: object](value: T): Value =
  var entries = initTable[string, Value]()
  for key, field in value.fieldPairs:
    entries[key] = field.toOwl()
  dictionary(entries)

proc owlToObject*[T: object](value: Value, target: var T) =
  let entries = value.entriesOf()
  for key, field in target.fieldPairs:
    if entries.hasKey(key):
      fromOwl(entries.getOrDefault(key), field)

proc toOwl*[T: object](value: T): Value =
  value.objectToOwl()

proc fromOwl*[T: object](value: Value, target: var T) =
  owlToObject(value, target)

proc objectToOwl*[T: ref object](value: T): Value =
  if value.isNil:
    nothing()
  else:
    value[].objectToOwl()

proc owlToObject*[T: ref object](value: Value, target: var T) =
  if value.kind == Nothing:
    target = nil
    return
  if target.isNil:
    new target
  owlToObject(value, target[])

proc toOwl*[T: ref object](value: T): Value =
  value.objectToOwl()

proc fromOwl*[T: ref object](value: Value, target: var T) =
  owlToObject(value, target)

proc fromOwl*[T](value: Value, target: typedesc[T]): T =
  fromOwl(value, result)

proc parseOwl*(source: string, T: typedesc, path = "<data>"): T =
  var value = parse(source, path)
  fromOwl(syntaxValue(value), result)

proc `%~`*[T](value: T): Value =
  value.toOwl()
