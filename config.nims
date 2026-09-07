# Load Atlas's generated dependency paths only in this checkout. Nimble copies
# nimble.paths into its temporary install tree, where its absolute source paths
# would mix the checkout with the staged package.
import std/[os, strutils]

const
  owlConfigDir = currentSourcePath().parentDir
  owlNimblePaths = owlConfigDir / "nimble.paths"
when system.fileExists(owlNimblePaths):
  if system.readFile(owlNimblePaths).contains(owlConfigDir):
    include "nimble.paths"

# Keep this package buildable when invoked from another project's directory.
switch("path", owlConfigDir / "src")
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
