```ebnf
Module      = Expr*
Exp         = BinExp ;; Pratt expr
Primary     = Number
            | String
            | #t | #f | none
            | "(" Exp ")"
            | List
            | Map
            | Block
            | IfExpr
            | FnExpr
            | DefExpr
            | MacroExpr
            | PipeExpr
            | Ident
List        = "[" (Expr ("," Expr)*)? "]"
Map         = "@{" BindingList? "}"
BindingList = Binding (Sep Binding)*
Binding     = MapKey "=" Expr
MapKey      = Ident | String | Number
Sep         = "," | TERMINATOR+
Block       = "{" Expr* "}"
IfExp       = "if" "(" Exp ")" Block ("else" Block)?
FnExp       = "fn" "(" ParamList? ")" Block
ParamList   = Ident ("," Ident)*
DefExp      = "def" DefHead "=" Exp
            | "def" DefHead Block
            | "def" "{" BindingList "}" "in" Exp
DefHead     = Ident "(" ParamList? ")" | Ident
MacroExpr   = "macro" Ident "(" ParamList? ")" "=>" Expr
PipeExpr    = "pipe" "(" Expr ")" PipeChain 
PipeChain   = ("|>" Call)+ 
Call        = Ident "(" ArgList? ")" 
ArgList     = Expr ("," Expr)*
```