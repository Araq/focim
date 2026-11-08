## gitbranches.nim -- the branches of the repository the current file is in.
##
## What the `branches` panel lists, and the two things a row of it can be
## asked to do: become the checked out branch, or go away. All of it is `git`
## run in the file's directory -- the program that owns the answers is asked
## for them, rather than `.git` being read behind its back, so a worktree, a
## submodule or a packed ref is git's business and not this file's.
##
## Nothing here raises. A git that is not installed, a directory that is not
## a repository and a file git does not track all come out the same way: no
## branches, which is a panel with nothing in it.

import std/[os, osproc, strutils]

type
  Branches* = object
    root*: string          ## the work tree, "" when there is no repository
    names*: seq[string]    ## local branches, in git's order
    current*: int          ## index into `names` of HEAD, -1 when detached

proc git(dir: string; args: openArray[string]): tuple[output: string; code: int] =
  var cmd = "git -C " & quoteShell(dir)
  for a in args: cmd.add " " & quoteShell(a)
  try:
    let (output, code) = execCmdEx(cmd, options = {poUsePath, poStdErrToStdOut})
    result = (output, code)
  except CatchableError as e:
    result = (e.msg, -1)

proc message(output: string): string =
  ## Git's complaint, in one line for the status bar. The `error:` line is the
  ## one that says what went wrong; the hints after it say what to do about
  ## it, which the status bar has no room for.
  var lines: seq[string] = @[]
  for l in output.splitLines:
    let s = l.strip
    if s.len > 0: lines.add s
  for l in lines:
    if l.startsWith("error:") or l.startsWith("fatal:"): return l
  result = if lines.len > 0: lines[0] else: "git failed"

proc trackedRoot*(file: string): string =
  ## The work tree `file` belongs to, or "" when git does not track it -- an
  ## untracked file in a repository has no business switching that
  ## repository's branches.
  if file.len == 0 or not fileExists(file): return ""
  let dir = file.parentDir
  let tracked = git(dir, ["ls-files", "--error-unmatch", "--", file.extractFilename])
  if tracked.code != 0: return ""
  let top = git(dir, ["rev-parse", "--show-toplevel"])
  result = if top.code == 0: top.output.strip else: ""

proc listBranches*(root: string): Branches =
  result = Branches(root: root, current: -1)
  if root.len == 0: return
  let r = git(root, ["for-each-ref", "--format=%(HEAD)%(refname:short)",
                     "refs/heads"])
  if r.code != 0:
    result.root = ""
    return
  for l in r.output.splitLines:
    if l.len < 2: continue
    if l[0] == '*': result.current = result.names.len
    result.names.add l[1 .. ^1]

proc switchBranch*(root, name: string; error: var string): bool =
  ## Check out `name`. Git refuses when that would overwrite changes in the
  ## work tree -- edited files, or untracked ones the other branch has -- and
  ## the refusal leaves everything as it was, which is what is wanted here:
  ## the branch stays and `error` says why.
  let r = git(root, ["switch", name])
  result = r.code == 0
  error = if result: "" else: message(r.output)

# ---------------------------------------------------------------------------
# What a branch is about -- the files it changed since it left the default
# branch, and where in each of them it first did
# ---------------------------------------------------------------------------

type
  Touched* = object
    path*: string   ## absolute
    line*: int      ## 1-based: the first line the branch changed in it

proc baseRef*(root: string): string =
  ## The branch everything else is measured against: the remote's default if
  ## the repository says which one that is, else a local `main` or `master`.
  ## "" when there is none of them, which leaves nothing to compare with.
  let r = git(root, ["rev-parse", "--abbrev-ref", "origin/HEAD"])
  if r.code == 0 and r.output.strip.len > 0 and r.output.strip != "origin/HEAD":
    return r.output.strip
  for name in ["main", "master"]:
    if git(root, ["rev-parse", "--verify", "-q", "refs/heads/" & name]).code == 0:
      return name
  result = ""

proc firstChangedLines(diff: string): seq[(string, int)] =
  ## From a `-U0 --no-prefix` diff: every file it changes, with the new-side
  ## line of its first hunk. A file the branch deleted (`+++ /dev/null`) has
  ## no new side and is left out; so is a binary one, which has no hunks.
  result = @[]
  var cur = ""
  var seen = false
  for l in diff.splitLines:
    if l.startsWith("+++ "):
      cur = l[4 .. ^1]
      seen = cur == "/dev/null"
    elif l.startsWith("@@ ") and not seen and cur.len > 0:
      # "@@ -a,b +c,d @@": c is where it starts on the branch's side; a hunk
      # that only deletes says the line before the gap, and 0 at the top.
      let plus = l.find(" +")
      var line = 0
      if plus >= 0:
        var i = plus + 2
        while i < l.len and l[i] in {'0'..'9'}:
          line = line * 10 + (ord(l[i]) - ord('0'))
          inc i
      result.add (cur, max(line, 1))
      seen = true

proc touchedFiles*(root: string; limit = 30): seq[Touched] =
  ## The files the checked out branch changed since it forked from
  ## `baseRef`, newest commit first, at most `limit` of them.
  ##
  ## The set comes from the three-dot diff, which is against the merge-base:
  ## what landed on the default branch since the fork is not this branch's
  ## doing, and a file changed and changed back again is not changed. The
  ## order comes from the log, because the cap has to cut the files nobody
  ## has looked at in a while and not the ones late in the alphabet.
  result = @[]
  let base = baseRef(root)
  if base.len == 0: return
  let d = git(root, ["-c", "core.quotePath=false", "diff", "-U0", "--no-color",
                     "--no-ext-diff", "--no-prefix", base & "...HEAD"])
  if d.code != 0: return
  let changed = firstChangedLines(d.output)
  if changed.len == 0: return
  let log = git(root, ["-c", "core.quotePath=false", "log", "--name-only",
                       "--format=", base & "..HEAD"])
  var order: seq[string] = @[]
  if log.code == 0:
    for l in log.output.splitLines:
      if l.len > 0 and l notin order: order.add l
  # Whatever the log did not name -- it always does, but a diff and a log are
  # two questions -- goes after it, in the diff's order.
  for (p, _) in changed:
    if p notin order: order.add p
  for p in order:
    if result.len >= limit: break
    for (q, line) in changed:
      if q == p:
        let full = root / p
        if fileExists(full): result.add Touched(path: full, line: line)
        break

# ---------------------------------------------------------------------------
# Deleting: only what has landed
# ---------------------------------------------------------------------------

proc landedIn*(root, name, base: string): bool =
  ## Are `name`'s changes in `base`? Asked three ways, since a pull request
  ## can land three ways:
  ##
  ## - merged: the branch is an ancestor of `base`;
  ## - rebased: every commit of it has a twin in `base` with the same patch,
  ##   which is what `git cherry` answers with a `-`;
  ## - squashed: the branch's whole change, as one commit on top of where it
  ##   forked, has such a twin. That commit is made for the question, never
  ##   signed -- nobody is asked for a passphrase to answer a click -- and
  ##   left unreferenced, so git's next gc takes it away again.
  if git(root, ["merge-base", "--is-ancestor", name, base]).code == 0:
    return true
  let each = git(root, ["cherry", base, name])
  if each.code != 0: return false
  var all = true
  for l in each.output.splitLines:
    if l.startsWith("+"): all = false
  if all: return true
  let fork = git(root, ["merge-base", base, name])
  if fork.code != 0: return false
  let squash = git(root, ["-c", "user.name=focim",
                          "-c", "user.email=focim@localhost",
                          "commit-tree", "--no-gpg-sign", name & "^{tree}",
                          "-p", fork.output.strip, "-m", "focim: " & name])
  if squash.code != 0: return false
  let one = git(root, ["cherry", base, squash.output.strip])
  result = one.code == 0 and one.output.strip.startsWith("-")

proc landingRefs(root: string): seq[string] =
  ## What a branch may have landed in: the remote's default branch and the
  ## local `main` or `master`. Either counts -- the remote's is the truth
  ## once fetched, the local one is ahead of it before a push.
  result = @[]
  let base = baseRef(root)
  if base.len > 0: result.add base
  for name in ["main", "master"]:
    if name notin result and
       git(root, ["rev-parse", "--verify", "-q", "refs/heads/" & name]).code == 0:
      result.add name

proc deleteBranch*(root, name: string; error: var string): bool =
  ## Only a branch whose changes have landed in the default branch goes: a
  ## click on an `x` is too small a gesture to throw away work with, and
  ## `git branch -D` in the terminal is there for the big one. "Landed" is
  ## `landedIn`, which knows a squash merge -- which `git branch -d` does not,
  ## and so the delete itself is `-D` once the question has been answered.
  ## The default branch is never deleted, nor the one that is checked out
  ## (git refuses that one itself).
  let refs = landingRefs(root)
  if refs.len == 0:
    error = "no main or master branch to have landed in"
    return false
  for r in refs:
    if name == r or "origin/" & name == r:
      error = name & " is the default branch"
      return false
  var landed = false
  for r in refs:
    if landedIn(root, name, r):
      landed = true
      break
  if not landed:
    error = name & " has changes that are not in " & refs[0]
    return false
  let r = git(root, ["branch", "-D", name])
  result = r.code == 0
  error = if result: "" else: message(r.output)
