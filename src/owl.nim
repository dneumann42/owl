import std/[os]

import objects, evaluation, libraries, reader
export objects, evaluation, libraries, reader

{.experimental: "caseStmtMacros".}

when isMainModule:
  var lex = Lexer.init(readFile("scripts/repl.owl"))
  var ev = Evaluator(root: Env.new())
  ev.root.loadCoreLibraries()
  var parsed = lex.module()
  discard ev.evaluate(parsed)
