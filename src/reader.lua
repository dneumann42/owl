local lpeg      = require("lib.lulpeg")
local P         = lpeg.P
local S         = lpeg.S
local V         = lpeg.V
local C         = lpeg.C
local Ct        = lpeg.Ct
local locale    = lpeg.locale()
local digit     = locale.digit
local s0        = locale.space ^ 0
local s1        = locale.space ^ 1
local repr      = require("src.repr")

local OwlSyntax = {
  "Script",
  Script = digit ^ 1,
  -- Script  = Ct((s0 * V "Comment" ^ 0 * V "Expr") ^ 0),
  -- Comment = P ";" ^ 1 * (-P "\n" * P(1)) ^ 0 * P "\n" * s0,
  -- Expr    = V "Number" * V "Comment" ^ 0,
  -- Number  = C(digit ^ 0 * (P "." * digit ^ 1) + digit ^ 1) / tonumber,
}

return setmetatable({
  one = function(code)
    return P(OwlSyntax):match(code)[1]
  end,
}, {
  __call = function(_, code)
    print(repr(OwlSyntax))
    return P(OwlSyntax):match(code)
  end,
})
