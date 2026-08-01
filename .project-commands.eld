;;; -*- lisp-data -*-
((run
  . "nimble run -- run scripts/formatter.nest scripts/formatter.nest")
 (commands "nimble run -- run scripts/example.nest"
	   "nimble run -- run scripts/repl.nest"
	   "nimble run -- run scripts/formatter.nest scripts/formatter.nest")
 (build . "nim r src/crow"))
