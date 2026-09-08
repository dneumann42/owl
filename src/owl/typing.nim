import std/[strformat, tables]

import parser, syntax, values

type
  ## Carries Owl source frames while the checker descends the syntax tree. The
  ## evaluator converts this to its ordinary public error type at the boundary.
  TypeCheckError* = object of OwlError

  TypeEnv = Table[string, TypeSyntaxNode]

  RecordField = tuple[name: string, typeDef: TypeSyntaxNode]

  RecordInfo = object
    generics: seq[string]
    fields: seq[RecordField]

  TypeChecker* = object
    scopes: seq[TypeEnv]
    records: Table[string, RecordInfo]
    typeArities: Table[string, int]
    genericScopes: seq[seq[string]]

proc init*(T: typedesc[TypeChecker]): T {.raises: [].} =
  result.scopes = @[initTable[string, TypeSyntaxNode]()]
  result.records = initTable[string, RecordInfo]()
  result.typeArities = {
    "Any": 0, "Boolean": 0, "Nothing": 0, "Number": 0, "Text": 0,
    "Dict": 2, "List": 1,
  }.toTable
  result.genericScopes = @[newSeq[string]()]
  result.scopes[0]["value-of"] = functionTypeNode("value-of", TAny, [TAny])

proc define*(
    checker: var TypeChecker, name: string, value: TypeSyntaxNode
) {.raises: [].} =
  checker.scopes[^1][name] = value

proc lookup(
    checker: TypeChecker, name: string
): tuple[found: bool, value: TypeSyntaxNode] {.raises: [].} =
  for index in countdown(checker.scopes.high, 0):
    if checker.scopes[index].hasKey(name):
      return (true, checker.scopes[index].getOrDefault(name))

proc pushScope(checker: var TypeChecker, generics: seq[string] = @[]) {.raises: [].} =
  checker.scopes.add initTable[string, TypeSyntaxNode]()
  checker.genericScopes.add generics

proc popScope(checker: var TypeChecker) {.raises: [].} =
  discard checker.scopes.pop()
  discard checker.genericScopes.pop()

proc typeSpecNode*(
    genericType: TypeSyntaxNode, specifications: openArray[TypeSyntaxNode]
): TypeSyntaxNode {.raises: [].} =
  result = TypeSyntaxNode(kind: TypeSpec, specifications: @specifications)
  new(result.genericType)
  result.genericType[] = genericType

proc defineModule*(
    checker: var TypeChecker, name: string, exports: openArray[string]
) {.raises: [].} =
  var info: RecordInfo
  for symbol in exports:
    let item = checker.lookup(symbol)
    if item.found:
      info.fields.add (symbol, item.value)
  checker.records[name] = info
  checker.typeArities[name] = 0
  checker.define(name, typeSpecNode(symbolTypeNode(name), []))

proc typeCheck*(checker: var TypeChecker, ast: var SyntaxNode) {.raises: [TypeCheckError].}

proc isGeneric(typeDef: TypeSyntaxNode, generics: openArray[string]): bool {.raises: [].} =
  typeDef.kind == Symbol and typeDef.symbol in generics

proc hasGeneric(checker: TypeChecker, name: string): bool {.raises: [].} =
  for scope in checker.genericScopes:
    if name in scope:
      return true

proc validateType(
    checker: TypeChecker, typeDef: TypeSyntaxNode, generics: openArray[string] = []
) {.raises: [TypeCheckError]} =
  case typeDef.kind
  of Symbol:
    if typeDef.symbol in generics or checker.hasGeneric(typeDef.symbol):
      return
    if not checker.typeArities.hasKey(typeDef.symbol):
      raise newException(TypeCheckError, "unknown type: " & typeDef.symbol)
    if checker.typeArities.getOrDefault(typeDef.symbol) != 0:
      raise newException(TypeCheckError, "type requires arguments: " & typeDef.symbol)
  of Function:
    if typeDef.returnType.isNil:
      raise newException(TypeCheckError, "function type has no return type")
    checker.validateType(typeDef.returnType[], generics)
    for parameter in typeDef.parameters:
      checker.validateType(parameter, generics)
    if not typeDef.variadic.isNil:
      checker.validateType(typeDef.variadic[], generics)
  of TypeSpec:
    if typeDef.genericType.isNil or typeDef.genericType[].kind != Symbol:
      raise newException(TypeCheckError, "type constructor must be a symbol")
    let name = typeDef.genericType[].symbol
    if not checker.typeArities.hasKey(name):
      raise newException(TypeCheckError, "unknown type: " & name)
    if checker.typeArities.getOrDefault(name) != typeDef.specifications.len:
      raise newException(TypeCheckError, "wrong generic arity for type: " & name)
    for specification in typeDef.specifications:
      checker.validateType(specification, generics)

proc hasGeneric(typeDef: TypeSyntaxNode, generics: openArray[string]): bool {.raises: [].} =
  if typeDef.isGeneric(generics):
    return true
  case typeDef.kind
  of Symbol:
    false
  of Function:
    for parameter in typeDef.parameters:
      if parameter.hasGeneric(generics):
        return true
    if not typeDef.variadic.isNil and typeDef.variadic[].hasGeneric(generics):
      return true
    not typeDef.returnType.isNil and typeDef.returnType[].hasGeneric(generics)
  of TypeSpec:
    for specification in typeDef.specifications:
      if specification.hasGeneric(generics):
        return true
    not typeDef.genericType.isNil and typeDef.genericType[].hasGeneric(generics)

proc substitute(
    typeDef: TypeSyntaxNode, substitutions: Table[string, TypeSyntaxNode]
): TypeSyntaxNode {.raises: [].} =
  case typeDef.kind
  of Symbol:
    result = substitutions.getOrDefault(typeDef.symbol, typeDef)
  of Function:
    result = functionTypeNode("", typeDef.returnType[], generics = typeDef.generics)
    for parameter in typeDef.parameters:
      result.parameters.add parameter.substitute(substitutions)
    result.returnType[] = typeDef.returnType[].substitute(substitutions)
    if not typeDef.variadic.isNil:
      new(result.variadic)
      result.variadic[] = typeDef.variadic[].substitute(substitutions)
  of TypeSpec:
    result = typeSpecNode(typeDef.genericType[].substitute(substitutions), [])
    for specification in typeDef.specifications:
      result.specifications.add specification.substitute(substitutions)

proc unify(
    expected, actual: TypeSyntaxNode, generics: openArray[string],
    substitutions: var Table[string, TypeSyntaxNode],
): bool {.raises: [].} =
  if expected == TAny:
    return true
  if expected.isGeneric(generics):
    if substitutions.hasKey(expected.symbol):
      return substitutions.getOrDefault(expected.symbol) == actual
    substitutions[expected.symbol] = actual
    return true
  if expected.kind != actual.kind:
    return false
  case expected.kind
  of Symbol:
    expected == actual
  of Function:
    if expected.returnType.isNil != actual.returnType.isNil or
        expected.parameters.len != actual.parameters.len or
        expected.variadic.isNil != actual.variadic.isNil:
      return false
    if not expected.returnType.isNil and
        not expected.returnType[].unify(actual.returnType[], generics, substitutions):
      return false
    for index in 0 ..< expected.parameters.len:
      if not expected.parameters[index].unify(
          actual.parameters[index], generics, substitutions
      ):
        return false
    if not expected.variadic.isNil and not expected.variadic[].unify(
        actual.variadic[], generics, substitutions
    ):
      return false
    true
  of TypeSpec:
    if expected.genericType.isNil != actual.genericType.isNil or
        expected.specifications.len != actual.specifications.len:
      return false
    if not expected.genericType.isNil and
        not expected.genericType[].unify(actual.genericType[], generics, substitutions):
      return false
    for index in 0 ..< expected.specifications.len:
      if not expected.specifications[index].unify(
          actual.specifications[index], generics, substitutions
      ):
        return false
    true

proc requireSingleType(node: SyntaxNode, role: string): TypeSyntaxNode
    {.raises: [TypeCheckError].} =
  if node.typed.len != 1:
    raise newException(TypeCheckError, role & " must have exactly one type")
  node.typed[0]

proc requireSymbol(node: SyntaxNode, role: string): string
    {.raises: [TypeCheckError].} =
  if node.kind != Symbol:
    raise newException(TypeCheckError, role & " must be a symbol")
  node.symbol

proc typeCheckBinding(
    checker: var TypeChecker, ast: var SyntaxNode
) {.raises: [TypeCheckError].} =
  if ast.typed.len > 1:
    raise newException(TypeCheckError, "a binding can have only one type")
  let declared = if ast.typed.len == 1: ast.typed[0] else: TAny
  if ast.typed.len == 1:
    checker.validateType(declared)
  var value = ast.value
  checker.typeCheck(value)
  let actual = value.requireSingleType("binding value")
  var substitutions = initTable[string, TypeSyntaxNode]()
  if not declared.unify(actual, [], substitutions):
    raise newException(TypeCheckError, &"binding {ast.bindingSymbol} has an incompatible type")
  ast.typed = @[if declared == TAny: actual else: declared]
  checker.define(ast.bindingSymbol, ast.typed[0])

proc typeCheckScript(
    checker: var TypeChecker, ast: var SyntaxNode
) {.raises: [TypeCheckError].} =
  var last = TAny
  for statement in ast.statements.mitems:
    checker.typeCheck(statement)
    last = statement.requireSingleType("statement")
  ast.typed = @[last]

proc isCommandNamed(ast: SyntaxNode, name: string): bool {.raises: [].} =
  ast.callee.kind == Symbol and ast.callee.symbol == name

proc recordType(name: string, generics: openArray[string]): TypeSyntaxNode {.raises: [].} =
  var arguments: seq[TypeSyntaxNode]
  for generic in generics:
    arguments.add symbolTypeNode(generic)
  typeSpecNode(symbolTypeNode(name), arguments)

proc fieldType(
    checker: TypeChecker, valueType: TypeSyntaxNode, field: string
): TypeSyntaxNode {.raises: [TypeCheckError].} =
  if valueType.kind != TypeSpec or valueType.genericType.isNil or
      valueType.genericType[].kind != Symbol:
    raise newException(TypeCheckError, "field access requires a record")
  let name = valueType.genericType[].symbol
  if not checker.records.hasKey(name):
    raise newException(TypeCheckError, "unknown record type: " & name)
  let info = checker.records.getOrDefault(name)
  if valueType.specifications.len != info.generics.len:
    raise newException(TypeCheckError, "record type has the wrong generic arity")
  var substitutions = initTable[string, TypeSyntaxNode]()
  for index, generic in info.generics:
    substitutions[generic] = valueType.specifications[index]
  for item in info.fields:
    if item.name == field:
      return item.typeDef.substitute(substitutions)
  raise newException(TypeCheckError, "unknown record field: " & field)

proc typeCheckField(
    checker: var TypeChecker, ast: var SyntaxNode
) {.raises: [TypeCheckError].} =
  if ast.arguments.len != 2 or ast.arguments[1].kind != String:
    raise newException(TypeCheckError, "field expects a record and a field name")
  var target = ast.arguments[0]
  checker.typeCheck(target)
  ast.typed = @[checker.fieldType(
    target.requireSingleType("field target"), ast.arguments[1].stringValue
  )]

proc typeCheckRecord(
    checker: var TypeChecker, ast: var SyntaxNode
) {.raises: [TypeCheckError].} =
  if ast.arguments.len != 1:
    raise newException(TypeCheckError, "record expects one name")
  let name = ast.arguments[0].requireSymbol("record name")
  var generics: seq[string]
  for annotation in ast.callee.typed:
    if annotation.kind != Symbol or annotation.symbol in generics:
      raise newException(TypeCheckError, "record generics must be unique symbols")
    generics.add annotation.symbol
  var info = RecordInfo(generics: generics)
  for node in ast.body:
    if node.kind != Binding or node.typed.len > 1:
      raise newException(TypeCheckError, "record fields must be bindings with at most one type")
    for field in info.fields:
      if field.name == node.bindingSymbol:
        raise newException(TypeCheckError, "duplicate record field: " & node.bindingSymbol)
    var fieldType: TypeSyntaxNode
    var checkedDefault = false
    if node.typed.len == 1:
      fieldType = node.typed[0]
      checker.validateType(fieldType, generics)
    else:
      var value = node.value
      checker.typeCheck(value)
      fieldType = value.requireSingleType("record field value")
      node.typed = @[fieldType]
      checkedDefault = true
    info.fields.add (node.bindingSymbol, fieldType)
    if not fieldType.hasGeneric(generics):
      var value = node.value
      if not checkedDefault:
        checker.typeCheck(value)
      var substitutions = initTable[string, TypeSyntaxNode]()
      if not fieldType.unify(
          value.requireSingleType("record field value"), [], substitutions
      ):
        raise newException(TypeCheckError, "record field default has an incompatible type")
  checker.records[name] = info
  checker.typeArities[name] = generics.len
  var parameters: seq[TypeSyntaxNode]
  for field in info.fields:
    parameters.add field.typeDef
  let constructor = functionTypeNode(
    name, recordType(name, generics), parameters, generics
  )
  checker.define(name, constructor)
  checker.define(name & "?", functionTypeNode(
    name & "?", TBoolean, [recordType(name, generics)], generics
  ))
  ast.typed = @[constructor]

proc typeCheckRecordCall(
    checker: var TypeChecker, ast: var SyntaxNode, name: string
) {.raises: [TypeCheckError].} =
  let info = checker.records.getOrDefault(name)
  if ast.arguments.len > info.fields.len:
    raise newException(TypeCheckError, "record got too many arguments")
  if ast.callee.typed.len notin {0, info.generics.len}:
    raise newException(TypeCheckError, "record generic arity does not match")
  var substitutions = initTable[string, TypeSyntaxNode]()
  for index, generic in info.generics:
    if ast.callee.typed.len > 0:
      checker.validateType(ast.callee.typed[index])
      substitutions[generic] = ast.callee.typed[index]
  for index in 0 ..< ast.arguments.len:
    var argument = ast.arguments[index]
    checker.typeCheck(argument)
    if not info.fields[index].typeDef.unify(
        argument.requireSingleType("record argument"), info.generics, substitutions
    ):
      raise newException(TypeCheckError, "record argument type does not match its field")
  var overrides: seq[string]
  for node in ast.body:
    if node.kind != Binding:
      raise newException(TypeCheckError, "record overrides must be bindings")
    var field: RecordField
    var found = false
    for item in info.fields:
      if item.name == node.bindingSymbol:
        field = item
        found = true
        break
    if not found or node.bindingSymbol in overrides:
      raise newException(TypeCheckError, "invalid record field override: " & node.bindingSymbol)
    var value = node.value
    checker.typeCheck(value)
    if not field.typeDef.unify(
        value.requireSingleType("record override"), info.generics, substitutions
    ):
      raise newException(TypeCheckError, "record override type does not match its field")
    overrides.add node.bindingSymbol
  for generic in info.generics:
    if not substitutions.hasKey(generic):
      raise newException(TypeCheckError, "could not infer record generic: " & generic)
  var specifications: seq[TypeSyntaxNode]
  for generic in info.generics:
    specifications.add substitutions.getOrDefault(generic)
  ast.typed = @[typeSpecNode(symbolTypeNode(name), specifications)]

proc assignmentType(
    checker: var TypeChecker, target: SyntaxNode
): TypeSyntaxNode {.raises: [TypeCheckError].} =
  if target.kind == Symbol:
    let found = checker.lookup(target.symbol)
    if not found.found:
      raise newException(TypeCheckError, "cannot set unknown symbol: " & target.symbol)
    return found.value
  if target.isCommandNamed("field"):
    var copy = target
    checker.typeCheckField(copy)
    return copy.requireSingleType("set field")
  raise newException(TypeCheckError, "set target must be a symbol or record field")

proc typeCheckSet(
    checker: var TypeChecker, ast: var SyntaxNode
) {.raises: [TypeCheckError].} =
  if ast.arguments.len == 2 and ast.body.len == 0:
    let expected = checker.assignmentType(ast.arguments[0])
    var value = ast.arguments[1]
    checker.typeCheck(value)
    var substitutions = initTable[string, TypeSyntaxNode]()
    if not expected.unify(value.requireSingleType("set value"), [], substitutions):
      raise newException(TypeCheckError, "set value does not match its target type")
  elif ast.arguments.len == 0:
    for node in ast.body:
      if node.kind != Binding:
        raise newException(TypeCheckError, "set body requires bindings")
      let expected = checker.assignmentType(symbol(node.bindingSymbol))
      var value = node.value
      checker.typeCheck(value)
      var substitutions = initTable[string, TypeSyntaxNode]()
      if not expected.unify(value.requireSingleType("set value"), [], substitutions):
        raise newException(TypeCheckError, "set value does not match its target type")
  else:
    raise newException(TypeCheckError, "set expects a target/value pair or bindings")
  ast.typed = @[TNothing]

proc typeCheckCast(
    checker: var TypeChecker, ast: var SyntaxNode
) {.raises: [TypeCheckError].} =
  if ast.callee.typed.len != 1 or ast.arguments.len != 1:
    raise newException(TypeCheckError, "cast needs one target type and one value")
  checker.validateType(ast.callee.typed[0])
  var value = ast.arguments[0]
  checker.typeCheck(value)
  discard value.requireSingleType("cast value")
  ast.typed = @[ast.callee.typed[0]]

proc typeCheckValueOf(
    checker: var TypeChecker, ast: var SyntaxNode
) {.raises: [TypeCheckError].} =
  if ast.arguments.len != 1:
    raise newException(TypeCheckError, "value-of expects one argument")
  var target = ast.arguments[0]
  checker.typeCheck(target)
  ast.typed = @[target.requireSingleType("value-of argument")]

proc typeCheckDefinition(
    checker: var TypeChecker, ast: var SyntaxNode
) {.raises: [TypeCheckError].} =
  if ast.arguments.len == 0:
    raise newException(TypeCheckError, "function definition needs a name")
  var generics: seq[string]
  for annotation in ast.callee.typed:
    if annotation.kind != Symbol or annotation.symbol in generics:
      raise newException(TypeCheckError, "function generics must be unique symbols")
    generics.add annotation.symbol

  let name = ast.arguments[0].requireSymbol("function name")
  if ast.arguments[0].typed.len > 1:
    raise newException(TypeCheckError, "function return type must be singular")
  var returnType =
    if ast.arguments[0].typed.len == 1: ast.arguments[0].typed[0] else: TAny
  if ast.arguments[0].typed.len == 1:
    checker.validateType(returnType, generics)
  var parameters: seq[tuple[name: string, typeDef: TypeSyntaxNode]]
  for index in 1 ..< ast.arguments.len:
    let parameter = ast.arguments[index]
    if parameter.typed.len > 1:
      raise newException(TypeCheckError, "function parameter type must be singular")
    parameters.add (
      parameter.requireSymbol("function parameter"),
      if parameter.typed.len == 1: parameter.typed[0] else: TAny,
    )
    if parameter.typed.len == 1:
      checker.validateType(parameter.typed[0], generics)

  var parameterTypes: seq[TypeSyntaxNode]
  for parameter in parameters:
    parameterTypes.add parameter.typeDef
  var functionType = functionTypeNode(name, returnType, parameterTypes, generics)
  # Make recursive calls available before checking the body.
  checker.define(name, functionType)
  checker.pushScope(generics)
  defer: checker.popScope()
  for parameter in parameters:
    checker.define(parameter.name, parameter.typeDef)

  var body = script(ast.body)
  checker.typeCheck(body)
  let bodyType = body.requireSingleType("function body")
  var substitutions = initTable[string, TypeSyntaxNode]()
  if returnType == TAny:
    returnType = bodyType
    functionType.returnType[] = bodyType
  elif not returnType.unify(bodyType, generics, substitutions):
    raise newException(TypeCheckError, &"function {name} returns an incompatible type")
  ast.typed = @[functionType]

proc typeCheckCommand(
    checker: var TypeChecker, ast: var SyntaxNode
) {.raises: [TypeCheckError].} =
  if ast.isCommandNamed("record"):
    checker.typeCheckRecord(ast)
    return
  if ast.isCommandNamed("set"):
    checker.typeCheckSet(ast)
    return
  if ast.isCommandNamed("cast"):
    checker.typeCheckCast(ast)
    return
  if ast.isCommandNamed("field"):
    checker.typeCheckField(ast)
    return
  if ast.isCommandNamed("value-of"):
    checker.typeCheckValueOf(ast)
    return
  if ast.isCommandNamed("fun") or ast.isCommandNamed("command"):
    checker.typeCheckDefinition(ast)
    return
  if ast.isCommandNamed("import") or ast.isCommandNamed("use"):
    ast.typed = @[TNothing]
    return

  if ast.callee.kind == Symbol and checker.records.hasKey(ast.callee.symbol):
    checker.typeCheckRecordCall(ast, ast.callee.symbol)
    return

  var callee = ast.callee
  checker.typeCheck(callee)
  if ast.arguments.len == 0 and ast.layout == NoLayout:
    ast.typed = callee.typed
    return
  let functionType = callee.requireSingleType("callee")
  if functionType.kind != Function:
    raise newException(TypeCheckError, "callee is not a function")
  if ast.arguments.len < functionType.parameters.len or
      functionType.variadic.isNil and ast.arguments.len != functionType.parameters.len:
    raise newException(
      TypeCheckError,
      &"expected {functionType.parameters.len} arguments, got {ast.arguments.len}",
    )
  var substitutions = initTable[string, TypeSyntaxNode]()
  for index in 0 ..< ast.arguments.len:
    var argument = ast.arguments[index]
    checker.typeCheck(argument)
    let actual = argument.requireSingleType("argument")
    let expected =
      if index < functionType.parameters.len:
        functionType.parameters[index]
      else:
        functionType.variadic[]
    if not expected.unify(
        actual, functionType.generics, substitutions
    ):
      raise newException(TypeCheckError, "argument type does not match its parameter")
  ast.typed = @[functionType.returnType[].substitute(substitutions)]

proc typeCheck*(checker: var TypeChecker, ast: var SyntaxNode) {.raises: [TypeCheckError].} =
  try:
    case ast.kind
    of Script:
      checker.typeCheckScript(ast)
    of Binding:
      checker.typeCheckBinding(ast)
    of Symbol:
      let parsed = parseNumber(ast.symbol)
      if parsed.ok:
        ast.typed = @[TNumber]
      elif ast.symbol in ["true", "false", "T", "F"]:
        ast.typed = @[TBoolean]
      else:
        let found = checker.lookup(ast.symbol)
        if not found.found:
          raise newException(TypeCheckError, "unknown symbol: " & ast.symbol)
        ast.typed = @[found.value]
    of Command:
      checker.typeCheckCommand(ast)
    of String:
      ast.typed = @[TText]
  except TypeCheckError as error:
    let label =
      case ast.kind
      of Script:
        ""
      of Binding:
        ast.bindingSymbol
      of Command:
        $ast.callee
      of Symbol:
        ast.symbol
      of String:
        "string"
    error.addFrame(ast.pos, label)
    raise error

when isMainModule:
  import std/strutils
  var checker = TypeChecker.init()
  checker.define("+", functionTypeNode("+", TNumber, [TNumber, TNumber]))
  checker.define("true", TBoolean)
  checker.define("false", TBoolean)
  let content = """
  record'x'y V2:
    x'x = cast'x 0
    y'y = cast'y 0
  p = V2 0 false
  """.dedent()
  var ast = parse(content)
  checker.typeCheck(ast)
  echo ast
