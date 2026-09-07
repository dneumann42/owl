# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

# Keep this package buildable when invoked from another project's directory.
switch("path", thisDir() & "/src")
