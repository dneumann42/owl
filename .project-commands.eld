;;; -*- lisp-data -*-
((run . "nim r src/crow run scripts/repl.nest")
 (commands "nim r src/crow" "nim r src/crow/values"
	   "nim r src/crow -- run scripts/repl.nest")
 (build . "nim r src/crow"))
