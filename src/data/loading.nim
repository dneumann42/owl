import std/[strformat, tables]

import data/conversions
import owl/[environment, evaluator, parser, syntax, values]

type OwlDataEvalMode* = enum
  restrictedOwlData
  unrestrictedOwlData

const RestrictedNames = [
  "import", "use", "eval-file", "eval-source", "open-file",
  "stdin", "stdout", "print", "repl", "exit", "command-line-arguments",
]

proc blockedCommand(name: string): Value {.raises: [].} =
  nativeCommand(
    proc(
        env: Environment,
        arguments: seq[SyntaxNode],
        layout: LayoutKind,
        body: seq[SyntaxNode],
    ): Value {.raises: [EvaluatorError].} =
      discard env
      discard arguments
      discard layout
      discard body
      raise newException(EvaluatorError, &"restricted Owl data cannot use {name}")
  )

proc installRestrictions(env: Environment) {.raises: [].} =
  for name in RestrictedNames:
    let value = blockedCommand(name)
    env.define(name, value)
    if env.fallback != nil:
      env.fallback.define(name, value)

proc dataEvaluator(mode: OwlDataEvalMode): Evaluator {.raises: [EvaluatorError].} =
  result = Evaluator.init()
  if mode == restrictedOwlData:
    result.env.installRestrictions()

proc bindingDictionary(bindings: Table[string, Value]): Value {.raises: [].} =
  record(bindings)

proc appendBindings(values: var seq[Value], bindings: Table[string, Value]) {.raises: [].} =
  values.add bindings.bindingDictionary()

proc collectData(
    evaluator: var Evaluator, node: SyntaxNode
): Value {.raises: [EvaluatorError].} =
  if node.kind != Script:
    return evaluator.exec(node)

  var
    values: seq[Value]
    bindings = initTable[string, Value]()

  for statement in node.statements:
    if statement.kind == Binding:
      let value = evaluator.env.eval(statement.value)
      evaluator.env.define(statement.bindingSymbol, value)
      bindings[statement.bindingSymbol] = value
    else:
      values.add evaluator.env.eval(statement)

  values.appendBindings(bindings)
  list(values)

proc loadOwlSource*(
    source: string, path = "<data>", mode = restrictedOwlData
): Value {.raises: [ParserError, EvaluatorError].} =
  var evaluator = dataEvaluator(mode)
  evaluator.collectData(parse(source, path))

proc loadOwlFile*(
    path: string, mode = restrictedOwlData
): Value {.raises: [IOError, ParserError, EvaluatorError].} =
  loadOwlSource(readFile(path), path, mode)

proc readOwl*(
    path: string, T: typedesc, mode = restrictedOwlData
): T {.raises: [IOError, ParserError, EvaluatorError, DataError].} =
  fromOwl(loadOwlFile(path, mode), result)

proc readOwlSource*(
    source: string, T: typedesc, path = "<data>", mode = restrictedOwlData
): T {.raises: [ParserError, EvaluatorError, DataError].} =
  fromOwl(loadOwlSource(source, path, mode), result)
