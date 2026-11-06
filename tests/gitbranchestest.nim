## The branches panel's side of git: listing, switching, deleting -- against a
## throwaway repository, so nothing of yours is touched. Skipped when there is
## no `git` to ask.
import std/[os, osproc, strutils]
import focim/gitbranches

var failures = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

if findExe("git").len == 0:
  echo "no git; skipped"
  quit 0

let repo = getTempDir() / "focim-gitbranchestest"
removeDir(repo)
createDir(repo)

proc sh(cmd: string) =
  let (output, code) = execCmdEx("git -C " & quoteShell(repo) & " " & cmd)
  doAssert code == 0, cmd & ": " & output

sh "init -q -b main"
sh "config user.email test@example.com"
sh "config user.name test"
sh "config commit.gpgsign false"
writeFile(repo / "a.txt", "one\n")
writeFile(repo / "c.txt", "1\n2\n3\n4\n5\n")
sh "add a.txt c.txt"
sh "commit -q -m one"
sh "branch side"
sh "switch -q side"
writeFile(repo / "a.txt", "two\n")
sh "commit -q -am two"
writeFile(repo / "c.txt", "1\n2\n3\nfour\n5\n")
sh "commit -q -am three"
sh "switch -q main"
sh "branch merged"

let file = repo / "a.txt"
writeFile(repo / "loose.txt", "x")

echo "finding the repository:"
let root = trackedRoot(file)
check("a tracked file has a work tree", root.len > 0 and
      sameFile(root, repo), root)
check("an untracked one does not", trackedRoot(repo / "loose.txt") == "")
check("nor does a file outside any repository",
      trackedRoot(getTempDir() / "focim-no-such-file") == "")

echo "listing:"
var b = listBranches(root)
check("every local branch", b.names == @["main", "merged", "side"],
      b.names.join(" "))
check("and which is checked out",
      b.current >= 0 and b.names[b.current] == "main")

echo "switching:"
var err = ""
check("a clean tree switches", switchBranch(root, "side", err), err)
check("and HEAD moves", listBranches(root).current == 2)
check("and back", switchBranch(root, "main", err), err)
writeFile(file, "dirty\n")
check("a change the other branch would overwrite is refused",
      not switchBranch(root, "side", err))
check("with git's reason", err.startsWith("error:"), err)
check("and the branch stays where it was",
      listBranches(root).current == 0)
check("and so does the change", readFile(file) == "dirty\n")
sh "checkout -q -- a.txt"

echo "what a branch touched:"
check("measured against the local main", baseRef(root) == "main",
      baseRef(root))
check("the default branch itself touched nothing", touchedFiles(root).len == 0)
check("onto the branch", switchBranch(root, "side", err), err)
var t = touchedFiles(root)
var names: seq[string] = @[]
for x in t: names.add x.path.extractFilename
check("its files, newest commit first", names == @["c.txt", "a.txt"],
      names.join(" "))
check("at the first line it changed", t.len == 2 and t[0].line == 4 and
      t[1].line == 1)
check("as absolute paths", t.len > 0 and t[0].path.isAbsolute)
check("and no more of them than asked for", touchedFiles(root, 1).len == 1)
check("back again", switchBranch(root, "main", err), err)

echo "deleting:"
check("a merged branch goes", deleteBranch(root, "merged", err), err)
check("and is not listed any more",
      listBranches(root).names == @["main", "side"])
check("an unmerged one is refused", not deleteBranch(root, "side", err))
check("and so is the one checked out", not deleteBranch(root, "main", err))
check("with a reason", err.len > 0)

removeDir(repo)
echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
