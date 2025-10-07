import std/[tables, sugar, sequtils, strutils]

import objects, evaluation

type #
  Library* = object
    name*: Object
    modules*: Table[Object, Module]

  Module* = object
    name*: Object
    script*: Object

proc init*(T: typedesc[Library], name: Object | string): T =
  when name is string:
    let n = sym(name)
  else:
    let n = name
  T(name: n, modules: initTable[Object, Module]())

proc init*(T: typedesc[Module], name: Object | string): T =
  when name is string:
    let n = sym(name)
  else:
    let n = name
  T(name: n, script: None)

proc loadCoreLibraries*(env: Env) =
  proc echo(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    for x in xs.mapIt($env.evaluate(it)):
      stdout.write($x)
    stdout.write("\n")

  proc `owl +`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    result = Object(kind: Number, number: 0.0)
    for v in xs:
      var n = env.evaluate(v)
      result.number += n.number

  proc `owl -`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    result = Object(kind: Number, number: xs[0].number)
    for i in 1 ..< xs.len:
      var n = env.evaluate(xs[i])
      result.number -= n.number

  proc `owl *`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    result = Object(kind: Number, number: 1.0)
    for v in xs:
      var n = env.evaluate(v)
      result.number *= n.number

  proc `owl /`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    result = Object(kind: Number, number: xs[0].number)
    for i in 1 ..< xs.len:
      var n = env.evaluate(xs[i])
      result.number /= n.number

  proc `owl do`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    for x in xs:
      result = env.evaluate(x)

  proc `owl while`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    var newXs = xs
    newXs.insert(sym"do", 0)
    let prog = Object(kind: List, items: newXs)
    while env.evaluate(xs[0]).toBool().isTrue:
      result = env.evaluate(prog)
      echo prog

  env.add(sym"echo", Object(kind: ForeignFunction, ffunction: echo))
  env.add(sym"+", Object(kind: ForeignFunction, ffunction: `owl +`))
  env.add(sym"-", Object(kind: ForeignFunction, ffunction: `owl -`))
  env.add(sym"*", Object(kind: ForeignFunction, ffunction: `owl *`))
  env.add(sym"/", Object(kind: ForeignFunction, ffunction: `owl /`))
  env.add(sym"do", Object(kind: ForeignFunction, ffunction: `owl do`))
  env.add(sym"while", Object(kind: ForeignFunction, ffunction: `owl while`))
