```ebnf
Module      = Expr*
Expr        = BinExpr ;; Pratt expr
Primary     = Number
            | String
            | #t | #f | none
            | "(" Exp ")"
            | List
            | Map
            | Block
            | IfExpr
            | FnExpr
            | FnDefn
            | WhileExpr
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
IfExpr      = "if" "(" Expr ")" Block ("else" Block)?
FnExpr      = "fn" "(" ArgList? ")" Expr
FnDefn      = "fn" Ident "(" ArgList? ")" Block
WhileExpr   = "while" Expr Block
ArgList     = Expr ("," Expr)*
LetExpr     = "let" LetHead "=" Expr
            | "let" LetHead Block
            | "let" "{" BindingList "}" "in" Expr
LetHead     = Ident "(" ArgList? ")" | Ident
MacroExpr   = "macro" Ident "(" ArgList? ")" "=>" Expr
PipeExpr    = "pipe" "(" Expr ")" PipeChain 
PipeChain   = ("|>" Call)+ 
Call        = Ident "(" ArgList? ")" 
```
