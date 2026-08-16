import std/[os, osproc, times, unittest]

const EvalDir = currentSourcePath().parentDir / "eval"
const BuiltOwl = currentSourcePath().parentDir.parentDir / "build" / "owl-eval-suite"

proc owlBinary(): string =
  let root = currentSourcePath().parentDir.parentDir
  createDir(root / "build")
  let source = root / "src" / "owl.nim"
  if not fileExists(BuiltOwl) or getLastModificationTime(BuiltOwl) < getLastModificationTime(source):
    let (output, code) = execCmdEx("nim c --out:" & quoteShell(BuiltOwl) & " " & quoteShell(source))
    doAssert code == 0, output
  BuiltOwl

suite "stdout evaluation suite":
  for script in walkFiles(EvalDir / "*.owl"):
    let
      name = splitFile(script).name
      expectedPath = EvalDir / name & ".out"

    test name:
      check fileExists(expectedPath)
      let
        expected = readFile(expectedPath)
        command = owlBinary()
        output = execProcess(
          command,
          args = ["run", script],
          options = {poUsePath, poStdErrToStdOut},
        )
      check output == expected
