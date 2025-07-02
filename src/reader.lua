local lpeg         = require("lib.lulpeg")
local P            = lpeg.P
local S            = lpeg.S
local V            = lpeg.V
local C            = lpeg.C
local Ct           = lpeg.Ct
local locale       = lpeg.locale()
local digit        = locale.digit
local s0           = locale.space ^ 0
local s1           = locale.space ^ 1
local repr         = require("src.repr")
local alnum, alpha = locale.alnum, locale.alpha

local function tok(s)
  return C(P(s)) * s0
end

local function binexp(left, op, right)
  return { tag = "BinExpr", left, op, right }
end

local function script(o)
  o.tag = "Script"
  return o
end

local function symbol(s)
  return { tag = "Symbol", s }
end

local function call(_, ident, args)
  return { tag = "Call", ident, args }
end

local function dot(_, a, _, b)
  return { tag = "Dot", a, b }
end

local function dot_call(_, ...)
  local suffixes = { ... }
  local node = suffixes[1]
  for i = 2, #suffixes do
    if suffixes[i].tag == "CallSuffix" then
      node = { tag = "Call", node, suffixes[i][1] }
    elseif suffixes[i].tag == "DotSuffix" then
      node = { tag = "Dot", node, suffixes[i][1] }
    end
  end
  return node
end

local function do_block(_, ...)
  local xs = { ... }
  print("HERE: ", repr(xs))
  return ""
end

local function keyword(_, ...)
  local xs = { ... }
  print(repr(xs))
  return ""
end

local OwlSyntax = {
  "Script",
  Script      = Ct((s0 * V "Comment" ^ 0 * V "Expr") ^ 0) / script,
  Comment     = P ";" ^ 1 * (-P "\n" * P(1)) ^ 0 * P "\n" * s0,
  Expr        = V "Do" + V "DotCall" + V "BinExpr" * V "Comment" ^ 0,
  BinExpr     = (V "Value" * V "BinOp" * V "Expr") / binexp,
  BinOp       = tok "+" + tok "-" + tok "*" + tok "/",

  DotCall     = C(V "Value" * V "Suffix" ^ 0) / dot_call,
  Suffix      = V "CallSuffix" + V "DotSuffix",
  CallSuffix  = Ct(P("(") * (V "Expr" * s0 * (P(",") * s0 * V "Expr") ^ 0) ^ -1 * P(")")) / function(x)
    return { tag = "CallSuffix", x }
  end,
  DotSuffix   = Ct(tok(".") * V "Symbol") / function(xs)
    return { tag = "DotSuffix", xs[2] }
  end,

  Do          = C(P "do" * s1 * (V "Expr" * s0) ^ 0 * P "end") / do_block,
  Bar         = P "|" * s0 * V "Expr",
  Pair        = P ":" * s0 * V "Expr" * s1 * V "Expr",

  Value       = (V "Number" + V "Symbol" + V "Group") * s0,
  Group       = P "(" * V "Expr" * P ")",
  Number      = C(digit ^ 0 * (P "." * digit ^ 1) + digit ^ 1) / tonumber,

  Keyword     = C(P "~" * V "Symbol") / keyword,

  Symbol      = C(V "SymbolStart" * V "SymbolRest" ^ 0) / symbol,
  SymbolStart = alpha + P "_" + P "$" + P "*" + P "+",
  SymbolRest  = alnum + P "_" + P ">" + P "<" + P "-" + P "$" + P "*" + P "+",
}

return setmetatable({
  one = function(code)
    return P(OwlSyntax):match(code)[1]
  end,
}, {
  __call = function(_, code)
    return P(OwlSyntax):match(code)
  end,
})
