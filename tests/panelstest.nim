## What a panel is called. The layout is the only place the window's panels
## are written down, so reading a cell name is how the app finds out what it
## has to draw -- and a name that reads wrong is a panel that quietly is not
## there.
import std/strutils
import focim/panels

var failures = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc equals(name: string; got, want: string) =
  check(name, got == want, "got '" & got & "' want '" & want & "'")

echo "reading a panel's name:"

check("the bare stem is the first panel", isEditor("editor"))
check("and a number behind it is another one", isEditor("editor2"))
check("however many there are", isEditor("editor12"))
check("terminals count the same way", isTerminal("terminal3"))
check("a longer word that starts the same is a cell of its own",
      not isEditor("editorial"))
check("so is one with something else behind the number",
      not isEditor("editor2b"))
check("numbering starts at two, since the first one has no number",
      not isEditor("editor1"))
check("and zero is nobody's panel", not isEditor("editor0"))
check("an editor is not a terminal", not isTerminal("editor2"))
check("and the panels are not the other widgets",
      not isEditor("tabs") and not isTerminal("status") and
      not isEditor("explorer"))
equals("a name says which kind it is", stemOf("terminal4"), "terminal")
equals("and says nothing for a cell that is neither", stemOf("clipboard"), "")

echo "naming a new one:"

equals("the first panel takes the bare stem",
       freeName(["tabs", "status"], "editor"), "editor")
equals("the second takes the first number",
       freeName(["editor", "status"], "editor"), "editor2")
equals("and the next one the next", freeName(["editor", "editor2"], "editor"),
       "editor3")
equals("a gap is filled before the count goes up",
       freeName(["editor", "editor3"], "editor"), "editor2")
equals("terminals are numbered apart from editors",
       freeName(["editor", "editor2", "terminal"], "terminal"), "terminal2")

echo "the panels a layout has:"

block:
  let cells = ["tabs", "editor", "editor2", "status", "terminal", "editor3"]
  equals("in the order the layout writes them",
         panelsOf(cells, "editor").join(" "), "editor editor2 editor3")
  equals("and only of the kind asked for",
         panelsOf(cells, "terminal").join(" "), "terminal")

block:
  let cells = ["tabs", "status"]
  check("a layout with no panel of that kind has none",
        panelsOf(cells, "terminal").len == 0)

echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
