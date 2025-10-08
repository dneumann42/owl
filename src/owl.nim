import std/[strutils, tables, sequtils]

import fusion/matching

import objects, evaluation, libraries, reader
export objects, evaluation, libraries, reader

{.experimental: "caseStmtMacros".}

when isMainModule:
  var lex = Lexer.init("""
    fn add1(a) { a + 1 }
  """)
  var ev = Evaluator(root: Env.new())
  ev.root.loadCoreLibraries()
  var parsed = lex.expr()
  echo parsed
  let res = ev.evaluate(parsed)
  echo res
