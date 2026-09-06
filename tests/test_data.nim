import std/[json, oids, os, streams, tables, times, unittest]

import data
import owl/[syntax, values]

when defined(linux) or defined(windows):
  import std/atomics

  var fileChangeNotifications: Atomic[int]

  proc noteFileChange() {.gcsafe, raises: [].} =
    discard fileChangeNotifications.fetchAdd(1, moRelaxed)

type
  Flavor = enum
    vanilla
    chocolate

  Person = object
    name*: string
    age*: int
    tags*: seq[string]

  Menu = object
    commands*: Table[Flavor, string]

  Defaults = object
    name*: string
    count*: int
    active*: bool

  RefPerson = ref object
    name*: string
    friend*: RefPerson

suite "data conversions":
  test "basic scalar writers and readers":
    check (%~ 42).kind == Number
    check fromOwl(%~ 42, int) == 42
    check fromOwl(%~ 3.5, float) == 3.5
    check fromOwl(%~ true, bool)
    check fromOwl(%~ "owl", string) == "owl"
    check fromOwl(%~ 'x', char) == 'x'
    check fromOwl(%~ chocolate, Flavor) == chocolate

  test "sequence array set and table conversions":
    let values = @[1, 2, 3].toOwl()
    check fromOwl(values, seq[int]) == @[1, 2, 3]

    var fixed: array[3, int]
    fromOwl(values, fixed)
    check fixed == [1, 2, 3]

    let flags = {vanilla, chocolate}.toOwl()
    check fromOwl(flags, set[Flavor]) == {vanilla, chocolate}

    var table = initTable[string, int]()
    table["a"] = 1
    table["b"] = 2
    let roundTrip = fromOwl(table.toOwl(), Table[string, int])
    check roundTrip["a"] == 1
    check roundTrip["b"] == 2

    var enumTable = initTable[Flavor, string]()
    enumTable[vanilla] = "plain"
    enumTable[chocolate] = "dark"
    let enumRoundTrip = fromOwl(enumTable.toOwl(), Table[Flavor, string])
    check enumRoundTrip[vanilla] == "plain"
    check enumRoundTrip[chocolate] == "dark"

  test "object conversions use field names":
    let person = Person(name: "Ada", age: 36, tags: @["math", "code"])
    let value = person.toOwl()
    check value.kind == Record
    check fromOwl(value, Person) == person

    var commands = initTable[Flavor, string]()
    commands[chocolate] = "mix"
    let menu = Menu(commands: commands)
    check fromOwl(menu.toOwl(), Menu).commands[chocolate] == "mix"

  test "stream writer serializes values as readable Owl text":
    let person = Person(name: "Ada", age: 36, tags: @["math", "code"])
    var stream = newStringStream()

    stream.write(person.toOwl())

    check stream.data == $person.toOwl()

  test "default object helpers preserve missing target fields":
    var partial = Defaults(name: "old", count: 7, active: true)
    fromOwl((%~ Defaults(name: "new", count: 0, active: false)).entries["name"], partial.name)

    var entries = initTable[string, Value]()
    entries["count"] = 3.toOwl()
    owlToObject(record(entries), partial)

    check partial.name == "new"
    check partial.count == 3
    check partial.active
    check partial.objectToOwl().entries["count"].number == 3

  test "ref objects convert by default and nil maps to nothing":
    let person = RefPerson(name: "Ada", friend: RefPerson(name: "Grace"))
    let value = person.toOwl()

    check value.kind == Record
    check value.entries["friend"].entries["name"].text == "Grace"
    check fromOwl(value, RefPerson).friend.name == "Grace"

    var missing: RefPerson
    check missing.toOwl().kind == Nothing
    missing = fromOwl(nothing(), RefPerson)
    check missing.isNil

  test "time duration oid and syntax values":
    let dateTime = dateTime(2026, mAug, 23, 10, 11, 12, zone = utc())
    check fromOwl(dateTime.toOwl(), DateTime) == dateTime

    let duration = initDuration(seconds = 9, nanoseconds = 5)
    check fromOwl(duration.toOwl(), Duration) == duration

    let oid = genOid()
    check fromOwl(oid.toOwl(), Oid) == oid

    let node = binding("answer", symbol("42"))
    check fromOwl(node.toOwl(), SyntaxNode).bindingSymbol == "answer"

  test "json nodes convert recursively":
    let node = %* {"name": "owl", "items": [1, true, nil]}
    let owl = node.toOwl()
    check owl.kind == Record
    check owl.entries["items"][1].boolean

    let back = fromOwl(owl, JsonNode)
    check back["name"].getStr() == "owl"
    check back["items"][0].getFloat() == 1.0
    check back["items"][2].kind == JNull

suite "data loading":
  test "top-level bindings become the final dictionary and are available later":
    let loaded = loadOwlSource("""
1
a = 41
+ a 1
""")

    check loaded.kind == List
    check loaded.len == 3
    check loaded[0].number == 1
    check loaded[1].number == 42
    check loaded[2].kind == Record
    check loaded[2].entries["a"].number == 41

  test "data files can define procedures for later values":
    let loaded = loadOwlSource("""
fun inc n:
  + n 1
answer = inc 41
""")

    let bindings = loaded[loaded.len - 1]
    check bindings.entries["answer"].number == 42

  test "restricted mode blocks dangerous commands":
    expect EvaluatorError:
      discard loadOwlSource("""eval-source "1"""")

  test "unrestricted mode allows evaluator commands":
    let loaded = loadOwlSource("""eval-source "1"""", mode = unrestrictedOwlData)
    check loaded[0].number == 1

suite "file watching":
  test "detects changes and refreshes its baseline":
    let path = getTempDir() / "owl-file-watcher-test.owl"
    writeFile(path, "value = 1")
    defer: removeFile(path)
    var watcher = initOwlFileWatcher()
    defer: watcher.close()
    watcher.watch(path)
    check not watcher.changed()

    writeFile(path, "value = 22")
    check watcher.changed()
    watcher.refresh()
    check not watcher.changed()

    removeFile(path)
    check watcher.changed()

  when defined(linux) or defined(windows):
    test "native notifications wake clients without timestamp polling":
      let path = getTempDir() / "owl-file-notification-test.owl"
      writeFile(path, "value = 1")
      defer: removeFile(path)
      let watcher = initOwlFileWatcher()
      defer: watcher.close()
      watcher.watch(path)
      fileChangeNotifications.store(0, moRelaxed)
      require watcher.notifyChanges(noteFileChange)

      writeFile(path, "value = 2")
      for attempt in 0 ..< 100:
        if fileChangeNotifications.load(moRelaxed) > 0:
          break
        sleep(10)

      check fileChangeNotifications.load(moRelaxed) > 0
      check watcher.changed()
