import owl/[commands, environment, evaluator, parser, syntax, values]
import data
export commands, environment, evaluator, parser, syntax, values, data

proc runScript*(path: string): Value {.discardable.} =
  let content = readFile path
  var evaluator = Evaluator.init()
  let ast = parse(content, path)
  result = evaluator.exec(ast)

proc evalSource*(source: string, path = "<eval>", evaluator = Evaluator.init()): Value {.discardable.} =
  var evaluator = evaluator
  result = evaluator.exec(parse(source, path))

const OwlCLISource = staticRead"owl/cli.owl"

when isMainModule:
  try:
    evalSource OwlCLISource, "owl/cli.owl"
  except OwlError as error:
    stderr.write report(error, useColor = true)
    quit 1
  except CatchableError as error:
    stderr.writeLine error.msg
    quit 1
