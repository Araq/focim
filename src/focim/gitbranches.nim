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

proc deleteBranch*(root, name: string; error: var string): bool =
  ## `git branch -d`: a branch that is not merged anywhere is refused, as is
  ## the one that is checked out. A click on an `x` is too small a gesture to
  ## throw away commits with; `git branch -D` in the terminal is the big one.
  let r = git(root, ["branch", "-d", name])
  result = r.code == 0
  error = if result: "" else: message(r.output)
