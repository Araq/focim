# Package

version       = "0.8.0"
author        = "Araq"
description   = "Focim -- the Focussed Nim Editor: a code editor with an integrated terminal, laid out and colored by a config file that is one of its own tabs"
license       = "MIT"
srcDir        = "src"
bin           = @["focim"]

# Dependencies

requires "nim >= 2.0.0"
# The UI library focim grew up in: windows, fonts, drawing and input, with a
# native driver per platform. Not on the package list yet, hence the URL.
requires "https://github.com/nim-lang/uirelays >= 0.9.0"


task test, "Run the test suite":
  exec "nim c -r tests/tester.nim"
