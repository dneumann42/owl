import objects, evaluation, libraries, reader
export objects, evaluation, libraries, reader

{.experimental: "caseStmtMacros".}

when isMainModule:
  var lex = Lexer.init(
    """
  let tbl = @{
    x = 100,
    y = 20
  }
  tbl
  """
  )
  var ev = Evaluator(root: Env.new())
  ev.root.loadCoreLibraries()
  var parsed = lex.module()
  echo parsed
  let res = ev.evaluate(parsed)
  echo "RESULT: ", res
