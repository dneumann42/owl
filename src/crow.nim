import std/[os]
import crow/[parser, evaluator]
export parser

let ReplContent = readFile "scripts/repl.nest"

proc start() =
  let cmds = commandLineParams()
  var content = ReplContent
  if cmds[0] == "run":
    let path = cmds[1]
    content = readFile path

  var evaluator = Evaluator.init()
  try:
    let ast = parse content
    discard evaluator.exec(ast)
  except CatchableError as error:
    quit error.msg, 1

when isMainModule:
  start()
