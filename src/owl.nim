import owl/[commands, environment, evaluator, parser, syntax, typing, values]
import data
export commands, environment, evaluator, parser, syntax, typing, values, data

proc runScript*(path: string): Value {.discardable.} =
  let content = readFile path
  var evaluator = Evaluator.init()
  let ast = parse(content, path)
  result = evaluator.exec(ast)

proc evalSource*(source: string, path = "<eval>", evaluator = Evaluator.init()): Value {.discardable.} =
  var evaluator = evaluator
  result = evaluator.exec(parse(source, path))

when isMainModule:
  import std/os

  const OwlCLISource = staticRead"owl/cli.owl"

  try:
    let params = commandLineParams()
    if "--typed" in params:
      var typedArgs: seq[string]
      for param in params:
        if param != "--typed":
          typedArgs.add param
      var evaluator = Evaluator.init()
      evaluator.enableTyping()
      if typedArgs.len == 2 and typedArgs[0] == "--eval":
        discard evaluator.exec(parse(typedArgs[1], "<eval>"))
      elif typedArgs.len == 2 and typedArgs[0] == "run":
        discard evaluator.exec(parse(readFile(typedArgs[1]), typedArgs[1]))
      else:
        stderr.writeLine "usage: owl --typed [--eval <source>|run <path>]"
        quit 2
    else:
      var evaluator = Evaluator.init()
      discard evaluator.execUntyped(parse(OwlCLISource, "owl/cli.owl"))
  except OwlError as error:
    stderr.write report(error, useColor = true)
    quit 1
  except CatchableError as error:
    stderr.writeLine error.msg
    quit 1
