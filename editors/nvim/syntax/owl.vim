" Vim syntax file
" Language: Owl

if exists("b:current_syntax")
  finish
endif

" Basic comment until end of line with double semicolons, e.g. ;; comment
syn match owlComment /;;.*$/

" Strings and numbers
syn match owlNumber /\v(\d+(\.\d+)?|\.\d+)/
syn match owlString /\v"([^"\\]|\\.)*"/

" Booleans and special literals
syn match owlBoolean /#t\|#f/
syn keyword owlLiteral none

" Core special forms / keywords
syn keyword owlKeyword let in fun lambda do while if else macro pipe quote

" Pipe operator and arithmetic / comparison operators
syn match owlOperator /\v\|\>|==|!=|<=|>=|[-+*/.=]/

" Symbol identifiers (allow dashes and dollar signs) excluding keywords
syn match owlIdentifier /\v\%(let|in|fun|lambda|do|while|if|else|macro|pipe|quote)\@![A-Za-z_][A-Za-z0-9_\-$]*/

" Record opener @{ and list sugar
syn match owlRecord /@{/

hi def link owlComment       Comment
hi def link owlNumber        Number
hi def link owlString        String
hi def link owlBoolean       Boolean
hi def link owlLiteral       Constant
hi def link owlKeyword       Keyword
hi def link owlOperator      Operator
hi def link owlIdentifier    Identifier
hi def link owlRecord        Special

let b:current_syntax = "owl"
