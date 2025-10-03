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
            | LetExpr
            | MacroExpr
            | PipeExpr
            | Ident
List        = "[" (Expr ("," Expr)*)? "]"
Record      = "@{" BindingList? "}"
BindingList = Binding (Sep Binding)*
Binding     = MapKey "=" Expr
RecordKey   = Ident | String | Number
Sep         = "," | TERMINATOR+
Block       = "{" Expr* "}"
IfExp       = "if" "(" Exp ")" Block ("else" Block)?
FnExp       = "fn" "(" ArgList? ")" Block
ArgList     = Expr ("," Expr)*
LetExp      = "let" LetHead "=" Exp
            | "let" LetHead Block
            | "let" "{" BindingList "}" "in" Exp
LetHead     = Ident "(" ArgList? ")" | Ident
MacroExpr   = "macro" Ident "(" ArgList? ")" "=>" Expr
PipeExpr    = "pipe" "(" Expr ")" PipeChain 
PipeChain   = ("|>" Call)+ 
Call        = Ident "(" ArgList? ")" 
```
