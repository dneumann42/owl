import std/[os, rdstdin]
import crow/[commands, environment, evaluator, parser, syntax, values]
export commands, environment, evaluator, parser, syntax, values

proc runRepl() =
  var evaluator = Evaluator.init()
  var history: seq[string]
  while true:
    var line: string
    if not readLineFromStdin("> ", line):
      break
    case line
    of "q", "quit":
      break
    of "history":
      echo history
      continue
    else:
      discard

    history.add line
    try:
      echo evaluator.exec(parse(line, "<repl>"))
    except CrowError as error:
      stderr.write report(error, useColor = true)
    except CatchableError as error:
      stderr.writeLine error.msg

proc start() =
  let cmds = commandLineParams()
  try:
    if cmds.len == 0:
      runRepl()
      return
    if cmds[0] != "run" or cmds.len != 2:
      quit "usage: crow [run <path>]", 2

    let path = cmds[1]
    let content = readFile path
    var evaluator = Evaluator.init()
    let ast = parse(content, path)
    discard evaluator.exec(ast)
  except CrowError as error:
    quit report(error, useColor = true), 1
  except CatchableError as error:
    quit error.msg, 1

when isMainModule:
  start()
