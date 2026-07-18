import std/[os]
import crow/[commands, environment, evaluator, parser, syntax, values]
export commands, environment, evaluator, parser, syntax, values

proc start() =
  let cmds = commandLineParams()
  var content = readFile "scripts/repl.nest"
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
