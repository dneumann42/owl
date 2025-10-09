import objects, evaluation, libraries, reader
export objects, evaluation, libraries, reader

{.experimental: "caseStmtMacros".}

when isMainModule:
  var lex = Lexer.init(
    """
    let x = 100
  """
  )
  var ev = Evaluator(root: Env.new())
  ev.root.loadCoreLibraries()
  var parsed = lex.module()
  echo parsed
  let res = ev.evaluate(parsed)
  echo "RESULT: ", res
