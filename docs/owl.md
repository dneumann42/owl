# Owl - a scripting language

```
Module        = (Expr (TERMINATOR+ | &'}' | !.))*

Expr          = PrattExpr

Primary       = Number
              | String
              | "true" | "false" | "nil"
              | "(" Expr ")"
              | List
              | Map
              | Block
              | IfExpr
              | FnExpr
              | DefExpr
              | MacroExpr
              | PipeExpr
              | Ident

List          = "[" (Expr ("," Expr)*)? "]"

Map           = "@{" BindingList? "}"
BindingList   = Binding (Sep Binding)*
Binding       = MapKey "=" Expr
MapKey        = Ident | String | Number
Sep           = "," | TERMINATOR+

Block         = "{" (Expr (TERMINATOR+ / &'}'))* "}"

IfExpr        = "if" "(" Expr ")" Block ("else" Block)?

FnExpr        = "fn" "(" ParamList? ")" Block
ParamList     = Ident ("," Ident)*

DefExpr       = "def" DefHead "=" Expr
              | "def" DefHead Block
              | "def" "{" BindingList "}" "in" Expr
DefHead       = Ident "(" ParamList? ")" | Ident

MacroExpr     = "macro" Ident "(" ParamList? ")" "=>" Expr

PipeExpr      = "pipe" "(" Expr ")" PipeChain
PipeChain     = ("|>" Call)+
Call          = Ident "(" ArgList? ")"
ArgList       = Expr ("," Expr)*
```

def x = 100

