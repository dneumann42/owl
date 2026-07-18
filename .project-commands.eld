;;; -*- lisp-data -*-
((run . "nimble run -- run scripts/example.nest")
 (commands "nim r src/crow" "nim r src/crow/values"
	   "nim r src/crow -- run scripts/repl.nest"
	   "nimble run -- run scripts/example.nest"
	   "nim r src/crow.nim run scripts/example.nest")
 (build . "nim r src/crow"))
