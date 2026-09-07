# Package

version       = "0.1.0"
author        = "dneumann42"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"
bin           = @["owl"]


# Dependencies

requires "nim >= 2.2.10"

task test, "Run the Owl test suite":
  exec "nim c -r tests/test_parser.nim"
  exec "nim c -r tests/test_evaluator.nim"
  exec "nim c -r tests/test_prelude.nim"
  exec "nim c -r tests/test_eval_stdout.nim"
  exec "nim c -r tests/test_data.nim"
