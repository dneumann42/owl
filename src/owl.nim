import objects, evaluation, libraries, reader
export objects, evaluation, libraries, reader

{.experimental: "caseStmtMacros".}

when isMainModule:
  var lex = Lexer.init(
    """
  fun x(y) {
    echo(y)
  }
  x([1, 2, 3])
  """
  )
  var ev = Evaluator(root: Env.new())
  ev.root.loadCoreLibraries()
  var parsed = lex.module()
  echo parsed
  let res = ev.evaluate(parsed)
  echo "RESULT: ", res
