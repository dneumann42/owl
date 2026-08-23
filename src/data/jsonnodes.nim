import std/[json, tables]

import owl/values

proc jsonToOwl*(node: JsonNode): Value =
  case node.kind
  of JNull:
    nothing()
  of JBool:
    boolean(node.getBool())
  of JInt:
    number(node.getBiggestInt().float64)
  of JFloat:
    number(node.getFloat())
  of JString:
    text(node.getStr())
  of JArray:
    var items: seq[Value]
    for item in node.items:
      items.add item.jsonToOwl()
    list(items)
  of JObject:
    var entries = initTable[string, Value]()
    for key, item in node.fields:
      entries[key] = item.jsonToOwl()
    dictionary(entries)

proc owlToJson*(value: Value): JsonNode =
  case value.kind
  of Nothing:
    result = newJNull()
  of Boolean:
    result = newJBool(value.boolean)
  of Number:
    result = newJFloat(value.number)
  of Text:
    result = newJString(value.text)
  of List:
    result = newJArray()
    for item in value.items:
      result.add item.owlToJson()
  of Dictionary:
    result = newJObject()
    for key, item in value.entries:
      result[key] = item.owlToJson()
  of Record:
    result = newJObject()
    result["$type"] = newJString(value.recordName)
    for key, item in value.recordEntries:
      result[key] = item.owlToJson()
  else:
    result = newJString($value)

proc toOwl*(node: JsonNode): Value =
  node.jsonToOwl()

proc fromOwl*(value: Value, target: var JsonNode) =
  target = value.owlToJson()
