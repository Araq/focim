## gitdiff.nim -- what a file looked like at some revision, and where the text
## in the editor differs from that.
##
## The base comes from git, once per revision: `git show <rev>:<path>`. The
## difference is worked out here, on every edit, with the line diff that
## ships with Nim (`experimental/diff`) -- asking git again for every
## keystroke would be a process per character, and a diff against what is on
## disk would be a diff of the wrong text the moment the buffer has edits in
## it, which is exactly when one wants to see it.
##
## Nothing here raises: a file git does not know, a revision that does not
## exist and a git that is not installed all come back as `ok = false`, for
## the caller to say so.

import std/[os, osproc, strutils, hashes]
import experimental/diff
import gitbranches

type
  HunkKind* = enum
    hunkAdded       ## lines that are not in the base
    hunkChanged     ## lines that replace lines of the base
    hunkDeleted     ## lines of the base that are gone; covers no line here

  Hunk* = object
    kind*: HunkKind
    line*: int      ## 0-based, in the current text: the first line of the
                    ## hunk, or for a deletion the line the deleted lines
                    ## stood above -- the line count, for lines deleted at
                    ## the very end
    lines*: int     ## how many lines of the current text it covers; 0 for
                    ## a deletion
    baseLine*: int  ## 0-based, in the base
    baseLines*: int ## how many lines of the base it replaces or removes

  Base* = object
    ok*: bool
    error*: string  ## why not, when not `ok`
    sha*: string    ## the commit the revision named when it was asked
    lines*: seq[string]

proc git(dir: string; args: openArray[string]): tuple[output: string; code: int] =
  var cmd = "git -C " & quoteShell(dir)
  for a in args: cmd.add " " & quoteShell(a)
  try:
    let (output, code) = execCmdEx(cmd, options = {poUsePath, poStdErrToStdOut})
    result = (output, code)
  except CatchableError as e:
    result = (e.msg, -1)

proc textLines*(text: string): seq[string] =
  ## A text as the diff sees it: one entry per line, `\r` dropped, and no
  ## empty line made up out of the newline the last line ends with -- the
  ## editor shows a file that ends in one with an empty last line, git does
  ## not, and the two must not disagree about a line nobody wrote.
  result = text.split('\n')
  if result.len > 0 and result[^1].len == 0: result.setLen result.len - 1
  for l in result.mitems:
    if l.endsWith('\r'): l.setLen l.len - 1

proc resolveRev*(root, rev: string): tuple[sha, error: string] =
  ## The commit `rev` names now. `branch` is where the checked out branch
  ## forked from the default one (`baseRef`) -- which on the default branch
  ## itself is no fork at all, and is said to be.
  var r = rev
  if rev == "branch":
    let base = baseRef(root)
    if base.len == 0: return ("", "no default branch to compare with")
    let head = git(root, ["rev-parse", "HEAD"])
    let mb = git(root, ["merge-base", base, "HEAD"])
    if mb.code != 0: return ("", "no common history with " & base)
    if head.code == 0 and mb.output.strip == head.output.strip:
      return ("", "this is " & base & " itself: no branch to compare")
    r = mb.output.strip
  let v = git(root, ["rev-parse", "--verify", "-q", r & "^{commit}"])
  if v.code != 0: return ("", "no such revision: " & rev)
  result = (v.output.strip, "")

proc loadBaseAt*(root, file, sha: string): Base =
  ## `file` (absolute, under `root`) as it is in commit `sha`. A file the
  ## commit does not have is an empty base: everything in it is added, which
  ## is the true answer for a file this branch created. One `git show`, so a
  ## branch switch that opens thirty files in diff mode is thirty processes
  ## and not a hundred.
  let rel = relativePath(file, root).replace('\\', '/')
  let r = git(root, ["show", sha & ":" & rel])
  if r.code == 0:
    return Base(ok: true, sha: sha, lines: textLines(r.output))
  # Asked rather than read off the message, which git says in the user's
  # language. Only on the way out, so the common case stays one process.
  if git(root, ["cat-file", "-e", sha & ":" & rel]).code != 0 and
     git(root, ["cat-file", "-e", sha & "^{commit}"]).code == 0:
    return Base(ok: true, sha: sha)
  let first = r.output.strip.splitLines
  result = Base(error: if first.len > 0: first[0] else: "git show failed")

proc loadBase*(root, file, rev: string): Base =
  ## `loadBaseAt` for whatever `rev` names now.
  let (sha, error) = resolveRev(root, rev)
  if sha.len == 0: return Base(error: error)
  result = loadBaseAt(root, file, sha)

proc headSha*(root: string): string =
  ## The commit checked out in `root`. What tells a diff its base may have
  ## moved: every base there is to compare with is fixed until HEAD moves --
  ## `HEAD` and `branch` move with it, and a named revision that moves on its
  ## own is a fetch, which is rare enough to wait for the next checkout.
  let r = git(root, ["rev-parse", "HEAD"])
  result = if r.code == 0: r.output.strip else: ""

proc computeHunks*(base, current: openArray[string]): seq[Hunk] =
  ## Where `current` differs from `base`, top to bottom. Lines are compared
  ## by hash, which is what the diff wants to be handed -- and two different
  ## lines with the same hash are one bad hunk boundary, not a wrong file.
  var a = newSeq[int](base.len)
  var b = newSeq[int](current.len)
  for i, l in base: a[i] = hash(l)
  for i, l in current: b[i] = hash(l)
  result = @[]
  for it in diffInt(a, b):
    let kind =
      if it.deletedA == 0: hunkAdded
      elif it.insertedB == 0: hunkDeleted
      else: hunkChanged
    result.add Hunk(kind: kind, line: it.startB, lines: it.insertedB,
                    baseLine: it.startA, baseLines: it.deletedA)

proc hunkAt*(hunks: openArray[Hunk]; line: int): int =
  ## The hunk `line` is in, or the deletion right above it; -1 for none.
  result = -1
  for i, h in hunks:
    if h.kind == hunkDeleted:
      if h.line == line: return i
    elif line >= h.line and line < h.line + h.lines:
      return i

proc nextHunk*(hunks: openArray[Hunk]; line: int; backwards: bool): int =
  ## The hunk after (or before) the one `line` is in, wrapping around -- so
  ## walking the hunks of a file goes round it, like `next` does with
  ## matches. -1 when there are none.
  if hunks.len == 0: return -1
  if backwards:
    for i in countdown(hunks.high, 0):
      if hunks[i].line < line: return i
    result = hunks.high
  else:
    for i, h in hunks:
      if h.line > line: return i
    result = 0

proc repoRoot*(file: string): string =
  ## The work tree `file` is in, tracked or not -- an untracked file in a
  ## repository is all added, which is a diff worth seeing. "" outside one.
  if file.len == 0: return ""
  let r = git(file.parentDir, ["rev-parse", "--show-toplevel"])
  result = if r.code == 0: r.output.strip else: ""

type
  DiffView* = object
    ## A tab's diff mode: what it is compared with, and where it differs.
    on*: bool
    rev*: string        ## as asked: `HEAD`, `branch`, or any revision
    root*: string       ## the work tree
    sha*: string        ## what `rev` named when the base was read
    head*: string       ## the HEAD `sha` was resolved under
    base*: seq[string]
    hunks*: seq[Hunk]
    version*: int       ## the text version `hunks` are for; -1 is stale
