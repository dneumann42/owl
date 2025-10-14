import objects, evaluation, libraries, reader
export objects, evaluation, libraries, reader

{.experimental: "caseStmtMacros".}

when isMainModule:
  var lex = Lexer.init(
    """
    let { x = 1, y = x + 1 } in 
    let { z = x + 2 } in 
    x + y + z
  """
  )
  var ev = Evaluator(root: Env.new())
  ev.root.loadCoreLibraries()
  var parsed = lex.module()
  echo parsed
  let res = ev.evaluate(parsed)
  echo "RESULT: ", res
