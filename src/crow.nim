import crow/[parser, evaluator]
export parser

let Content = readFile "scripts/repl.nest"

proc start() =
  var evaluator = Evaluator.init()
  try:
    let ast = parse Content
    discard evaluator.exec(ast)
  except CatchableError as error:
    quit error.msg, 1

when isMainModule:
  start()
