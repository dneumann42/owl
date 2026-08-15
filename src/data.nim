import owl/values

proc toOwl*(n: SomeNumber): Value =
  result = number(float64(when n is SomeInteger: n.toFloat() else: n))

proc fromOwl*(v: Value, n: var SomeNumber) =
  assert(v.kind == Number)
  when n is SomeInteger:
    n = v.number.toString()
  else:
    n = v.number

proc toOwl*(n: string): Value =
  result = text(n)

proc fromOwl*(v: Value, n: var string) =
  assert(v.kind == Text)
  n = v.text

proc toOwl*(b: bool): Value =
  result = boolean(b)

proc fromOwl*(v: Value, b: var bool) =
  b = v.boolean
