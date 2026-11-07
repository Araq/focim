## The diff view's side of git and of the line diff: what a file was at a
## revision, and where the text differs from it. Against a throwaway
## repository; skipped when there is no `git` to ask.
import std/[os, osproc, strutils]
import focim/gitdiff

var failures = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc `$`(h: Hunk): string =
  $h.kind & "@" & $h.line & "+" & $h.lines & " base " & $h.baseLine & "+" &
    $h.baseLines

proc hunks(base, current: string): seq[Hunk] =
  computeHunks(textLines(base), textLines(current))

echo "lines:"
check("no line is made up out of the final newline",
      textLines("a\nb\n") == @["a", "b"])
check("one without a final newline has the same lines",
      textLines("a\nb") == @["a", "b"])
check("carriage returns are not part of a line",
      textLines("a\r\nb\r\n") == @["a", "b"])
check("an empty text has none", textLines("").len == 0)

echo "hunks:"
block:
  let h = hunks("a\nb\nc\n", "a\nb\nc\n")
  check("the same text has none", h.len == 0, $h)
block:
  let h = hunks("a\nc\n", "a\nb\nc\n")
  check("a line put in is added, where it is",
        h.len == 1 and h[0].kind == hunkAdded and h[0].line == 1 and
        h[0].lines == 1, $h)
block:
  let h = hunks("a\nb\nc\n", "a\nc\n")
  check("a line taken out is deleted, above the line that followed it",
        h.len == 1 and h[0].kind == hunkDeleted and h[0].line == 1 and
        h[0].lines == 0 and h[0].baseLine == 1 and h[0].baseLines == 1, $h)
block:
  let h = hunks("a\nb\nc\n", "a\nB\nc\n")
  check("a line replaced is changed",
        h.len == 1 and h[0].kind == hunkChanged and h[0].line == 1 and
        h[0].lines == 1 and h[0].baseLines == 1, $h)
block:
  let h = hunks("a\nb\n", "a\n")
  check("lines deleted at the end stand above the line count",
        h.len == 1 and h[0].kind == hunkDeleted and h[0].line == 1, $h)
block:
  let h = hunks("", "a\nb\n")
  check("against an empty base, everything is added",
        h.len == 1 and h[0].kind == hunkAdded and h[0].line == 0 and
        h[0].lines == 2, $h)
block:
  let h = hunks("1\n2\n3\n4\n5\n6\n", "0\n1\n2\nX\n4\n5\n")
  check("several, top to bottom",
        h.len == 3 and h[0].kind == hunkAdded and h[1].kind == hunkChanged and
        h[1].line == 3 and h[2].kind == hunkDeleted and h[2].line == 6, $h)

  echo "walking them:"
  check("the hunk a line is in", hunkAt(h, 3) == 1)
  check("and a deletion counts for the line below it", hunkAt(h, 6) == 2)
  check("a line in none is in none", hunkAt(h, 2) == -1)
  check("forward from above the first goes to the first",
        nextHunk(h, -1, backwards = false) == 0)
  check("forward from inside one goes to the next",
        nextHunk(h, 3, backwards = false) == 2)
  check("forward from the last goes round to the first",
        nextHunk(h, 6, backwards = false) == 0)
  check("backward goes to the one above",
        nextHunk(h, 5, backwards = true) == 1)
  check("and from the first round to the last",
        nextHunk(h, 0, backwards = true) == 2)
  check("without hunks there is nowhere to go",
        nextHunk(@[], 0, backwards = false) == -1)

if findExe("git").len == 0:
  echo "no git; the rest is skipped"
  quit(if failures == 0: 0 else: 1)

let repo = getTempDir() / "focim-gitdifftest"
removeDir(repo)
createDir(repo / "src")

proc sh(cmd: string) =
  let (output, code) = execCmdEx("git -C " & quoteShell(repo) & " " & cmd)
  doAssert code == 0, cmd & ": " & output

sh "init -q -b main"
sh "config user.email test@example.com"
sh "config user.name test"
sh "config commit.gpgsign false"
writeFile(repo / "src" / "a.nim", "one\ntwo\n")
sh "add src/a.nim"
sh "commit -q -m one"
writeFile(repo / "src" / "a.nim", "one\ntwo\nthree\n")
sh "commit -q -am two"

echo "the base:"
let file = repo / "src" / "a.nim"
block:
  let b = loadBase(repo, file, "HEAD")
  check("HEAD's version of the file", b.ok and
        b.lines == @["one", "two", "three"], b.error & " " & $b.lines)
  check("with the commit it came from", b.sha.len == 40, b.sha)
block:
  let b = loadBase(repo, file, "HEAD~1")
  check("any revision", b.ok and b.lines == @["one", "two"], $b.lines)
block:
  let b = loadBase(repo, repo / "src" / "new.nim", "HEAD")
  check("a file the revision does not have is an empty base",
        b.ok and b.lines.len == 0, b.error)
block:
  let b = loadBase(repo, file, "nosuchrev")
  check("a revision that does not exist says so",
        not b.ok and b.error.contains("nosuchrev"), b.error)
block:
  let b = loadBase(repo, file, "branch")
  check("`branch` on the default branch itself is refused",
        not b.ok and b.error.contains("itself"), b.error)
sh "switch -q -c topic"
writeFile(file, "one\nTWO\nthree\n")
sh "commit -q -am three"
block:
  let b = loadBase(repo, file, "branch")
  check("on a branch, `branch` is where it forked",
        b.ok and b.lines == @["one", "two", "three"], b.error & " " & $b.lines)
  let h = computeHunks(b.lines, textLines(readFile(file)))
  check("and the branch's change is the one hunk",
        h.len == 1 and h[0].kind == hunkChanged and h[0].line == 1, $h)

removeDir(repo)
echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
