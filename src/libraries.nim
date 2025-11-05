import std/[tables, os, sequtils, sugar]

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

  proc `list - add`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    var list = xs[0]
    for i in 1 ..< xs.len:
      list.items.add(env.evaluate(xs[i]))
    result = list

  proc `owl readLine`(env: Env, xs: seq[Object]): Object {.gcsafe.} =
    if xs.len > 0:
      stdout.write(xs[0])
    let line = stdin.readLine()
    result = str(line)

  let ps = commandLineParams().mapIt(Object(kind: String, str: it))
  env.add(sym"args", Object(kind: List, items: ps))
  env.add(sym"echo", ffunc echo)
  env.add(sym"list-add", ffunc `list - add`)
  env.add(sym"+", ffunc `owl +`)
  env.add(sym"-", ffunc `owl -`)
  env.add(sym"*", ffunc `owl *`)
  env.add(sym"/", ffunc `owl /`)
  env.add(sym"do", ffunc `owl do`)
  env.add(sym"while", ffunc `owl while`)
  env.add(sym"read-line", ffunc `owl readLine`)

  env.specialForm(":fun") do(ev: Env, items: seq[Object]) -> Object:
    let id = items[1]
    ev.add(
      id, Func(scope: ev.push(), name: $id, params: items[2].items, body: items[3])
    )

  env.specialForm(":lambda") do(ev: Env, items: seq[Object]) -> Object:
    Object(
      kind: Function,
      function:
        Func(scope: ev, name: "<lambda>", params: items[1].items, body: items[2]),
    )

  env.specialForm(":do") do(ev: Env, items: seq[Object]) -> Object:
    for i in 1 ..< items.len:
      result = ev.evaluate(items[i])

  env.specialForm(":quote") do(ev: Env, items: seq[Object]) -> Object:
    if items.len != 2:
      raise EvalError.newException("quote expects a single expression")
    result = items[1]

  env.specialForm(":list") do(ev: Env, items: seq[Object]) -> Object:
    Object(
      kind: List,
      items: collect(
        for i in items[1 ..< items.len]:
          ev.evaluate(i)
      ),
    )

  env.specialForm(":let") do(ev: Env, items: seq[Object]) -> Object:
    ev.evaluateLet(Object(kind: List, items: items))

  env.specialForm(":record") do(ev: Env, items: seq[Object]) -> Object:
    ev.evaluateRecDefinition(Object(kind: List, items: items))
