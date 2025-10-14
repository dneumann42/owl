import objects, evaluation, libraries, reader
export objects, evaluation, libraries, reader

{.experimental: "caseStmtMacros".}

when isMainModule:
  var lex = Lexer.init(
    """
  let add = fun(x) fun(y) x + y
  let a1 = add(1)
  a1(2)
  """
  )
  var ev = Evaluator(root: Env.new())
  ev.root.loadCoreLibraries()
  var parsed = lex.module()
  echo parsed
  let res = ev.evaluate(parsed)
  echo "RESULT: ", res
