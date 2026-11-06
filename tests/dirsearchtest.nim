## `search` in the terminal: every match under a directory, as lines a click
## goes to. Against a tree made for the purpose in the temp dir.
import std/[os, strutils, tables]
import focim/[dirsearch, search]

var failures = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc equals(name: string; got, want: string) =
  check(name, got == want, "got '" & got & "' want '" & want & "'")

echo "globs:"
check("a star is any run", globMatch("*.c", "x.c") and not globMatch("*.c", "x.h"))
check("including none", globMatch("a*", "a"))
check("a question mark is one character", globMatch("?.nim", "a.nim") and
      not globMatch("?.nim", "ab.nim"))
check("and the rest is itself", globMatch("nimcache", "nimcache") and
      not globMatch("nimcache", "nimcache2"))

let root = getTempDir() / "focim-dirsearchtest"
removeDir(root)
createDir(root / "src" / "sub")
createDir(root / "nimcache")
createDir(root / ".git")
createDir(root / "tests" / "data")
createDir(root / "other" / "data")
writeFile(root / "a.txt", "nothing here\n  the needle is here\nand needle again\n")
writeFile(root / "src" / "b.nim", "proc needles() = discard\nlet needle = 1\n")
writeFile(root / "src" / "sub" / "c.nim", "needle\n")
writeFile(root / "nimcache" / "gen.c", "needle\n")
writeFile(root / ".git" / "config", "needle\n")
writeFile(root / "tests" / "data" / "d.txt", "needle\n")
writeFile(root / "other" / "data" / "e.txt", "needle\n")
writeFile(root / "blob.bin", "needle\0\0\0")

proc run(term, flags: string; excludes: seq[string] = @[];
         unsaved = initTable[string, string]()): (seq[string], DirSearch) =
  var s = startDirSearch(root, term, parseSearchOptions(flags), excludes,
                         unsaved)
  var text = ""
  while s.active: text.add s.step(files = 2)
  result = (text.strip.splitLines, s)

proc sep(p: string): string = p.replace('/', DirSep)

echo "searching:"
block:
  let (lines, s) = run("needle", "")
  check("one line per matching line, the whole tree in name order",
        lines == @["a.txt:2:7: the needle is here".sep,
                   "a.txt:3:5: and needle again",
                   "nimcache/gen.c:1:1: needle".sep,
                   "other/data/e.txt:1:1: needle".sep,
                   "src/b.nim:1:6: proc needles() = discard".sep,
                   "src/b.nim:2:5: let needle = 1".sep,
                   "src/sub/c.nim:1:1: needle".sep,
                   "tests/data/d.txt:1:1: needle".sep],
        lines.join(" | "))
  check("never in .git", not lines.join("\n").contains(".git"))
  check("nor in a binary file", not lines.join("\n").contains("blob"))
  check("counted", s.matches == 8 and s.files == 6, $s.matches & " " & $s.files)

block:
  let (lines, _) = run("needle", "w")
  check("the options are find's: w leaves 'needles' out",
        not lines.join("\n").contains("needles"))

echo "excluding:"
block:
  let (lines, _) = run("needle", "", @["nimcache", "*.txt"])
  equals("by name, at any depth, and by glob", lines.join(" | "),
         ["src/b.nim:1:6: proc needles() = discard".sep,
          "src/b.nim:2:5: let needle = 1".sep,
          "src/sub/c.nim:1:1: needle".sep].join(" | "))
block:
  let (lines, _) = run("needle", "", @["tests/data,src"])
  let all = lines.join("\n")
  check("a path names that one place only, and commas list several",
        "other" & DirSep & "data" in all and not all.contains("tests") and
        not all.contains("src"), all)

echo "what a tab has:"
block:
  var unsaved = initTable[string, string]()
  unsaved[root / "src" / "sub" / "c.nim"] = "edited\nnow the needle is here\n"
  let (lines, _) = run("needle", "", @[], unsaved)
  check("an unsaved tab is searched as the tab has it",
        "src/sub/c.nim:2:9: now the needle is here".sep in lines,
        lines.join(" | "))

echo "the cap:"
block:
  var big = ""
  for i in 1 .. MaxSearchMatches + 50: big.add "needle\n"
  writeFile(root / "src" / "big.txt", big)
  let (lines, s) = run("needle", "")
  check("stops at the cap", lines.len == MaxSearchMatches and s.truncated,
        $lines.len)
  check("and says so", s.summary(false).contains("stopped at"))

echo "nothing found:"
block:
  let (_, s) = run("haystack", "")
  check("says so", s.summary(false).startsWith("no match"), s.summary(false))

removeDir(root)
echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
