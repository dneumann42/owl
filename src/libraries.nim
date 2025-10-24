import std/[tables, os, sequtils]

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
    for x in xs:
      stdout.write($x)
    stdout.write("\n")

  proc `owl +`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    result = Object(kind: Number, number: 0.0)
    for v in xs:
      result.number += v.number

  proc `owl -`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    if xs.len == 0:
      return Object(kind: Number, number: 0.0)
    result = Object(kind: Number, number: xs[0].number)
    for i in 1 ..< xs.len:
      result.number -= xs[i].number

  proc `owl *`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    result = Object(kind: Number, number: 1.0)
    for v in xs:
      result.number *= v.number

  proc `owl /`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    if xs.len == 0:
      raise EvalError.newException("Division requires at least one argument")
    result = Object(kind: Number, number: xs[0].number)
    for i in 1 ..< xs.len:
      result.number /= xs[i].number

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

  let ps = commandLineParams().mapIt(Object(kind: String, str: it))
  env.add(sym"args", Object(kind: List, items: ps))
  env.add(sym"echo", ffunc echo)
  env.add(sym"+", ffunc `owl +`)
  env.add(sym"-", ffunc `owl -`)
  env.add(sym"*", ffunc `owl *`)
  env.add(sym"/", ffunc `owl /`)
  env.add(sym"do", ffunc `owl do`)
  env.add(sym"while", ffunc `owl while`)
