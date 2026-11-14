## dirsearch.nim -- every match under a directory, as lines a terminal can
## click on.
##
## What `search` in the terminal does: the directory the terminal is in, and
## everything below it, which is what makes the scope something one moves
## rather than something one configures -- `cd ..` and the same search again
## is the bigger search. `--exclude` takes out what is not wanted; `.git`,
## `.hg` and `.svn` are never wanted and are out without being asked.
##
## The walk is a job, stepped a slice at a time by the host the way an
## `index` job is: a search typed in `~` would otherwise be a window that
## stops answering until it is done. Each step hands back the lines it found,
## as `path:line:col: text`, which is a form the terminal already treats as a
## place to go.
##
## The matching is `search.nim`'s, so `w`, `c` and `i` mean what they mean
## for `find`. A file with unsaved edits in a tab is searched as the tab has
## it: that is the text the lines will be clicked into.

import std/[os, strutils, algorithm, tables]
import search

const
  MaxSearchMatches* = 1000
    ## Lines of output before the search stops itself. A term this common is
    ## a term to make longer, and a terminal with a hundred thousand lines in
    ## it is a terminal nobody scrolls through.
  MaxFileBytes = 4 * 1024 * 1024
    ## Bigger than this is a log, a dump or a database, not source.
  MaxLineChars = 160
    ## How much of a matching line is shown. Enough to recognise it; the
    ## click shows the rest.
  AlwaysExcluded = [".git", ".hg", ".svn"]

type
  DirSearch* = object
    active*: bool
    dir*: string             ## where it started; the paths are relative to it
    term*: string
    opts*: SearchOptions
    excludes*: seq[string]   ## glob patterns, see `excluded`
    exts*: seq[string]       ## extensions without the dot; empty is all files
    pending: seq[string]     ## absolute paths still to look at, a stack:
                             ## the next one is the last one
    unsaved: Table[string, string] ## path -> the text a tab has for it
    matches*: int            ## lines of output so far
    files*: int              ## files with at least one match
    searched*: int           ## files looked through
    truncated*: bool         ## stopped at `MaxSearchMatches`

proc globMatch*(pat, s: string): bool =
  ## `*` is any run of characters, `?` is one, everything else is itself.
  ## No character classes: an exclude names a directory or an extension, and
  ## this is all either needs.
  var p = 0
  var i = 0
  var star = -1
  var mark = 0
  while i < s.len:
    if p < pat.len and (pat[p] == '?' or pat[p] == s[i]):
      inc p
      inc i
    elif p < pat.len and pat[p] == '*':
      star = p
      mark = i
      inc p
    elif star >= 0:
      p = star + 1
      inc mark
      i = mark
    else:
      return false
  while p < pat.len and pat[p] == '*': inc p
  result = p == pat.len

proc excluded*(s: DirSearch; rel: string): bool =
  ## Whether the entry at `rel` (relative to `dir`) is left out. A pattern
  ## without a separator is matched against the entry's own name, so
  ## `nimcache` takes out every directory of that name at any depth and `*.c`
  ## every C file; one with a separator is matched against the whole relative
  ## path, for `tests/data` and nothing else called `data`.
  let name = rel.extractFilename
  if name in AlwaysExcluded: return true
  let unix = rel.replace('\\', '/')
  for p in s.excludes:
    if '/' in p:
      if globMatch(p.strip(chars = {'/'}), unix): return true
    elif globMatch(p, name):
      return true
  result = false

proc wantedExt*(s: DirSearch; path: string): bool =
  ## Whether a file is one of the extensions asked for -- any file, when none
  ## was. Case does not matter: `nim` is meant to find `X.NIM` too.
  if s.exts.len == 0: return true
  let e = path.splitFile.ext
  if e.len < 2: return false
  for x in s.exts:
    if cmpIgnoreCase(e[1 .. ^1], x) == 0: return true
  result = false

proc pushDir(s: var DirSearch; dir: string) =
  ## The entries of `dir`, so that they come off the stack in order:
  ## directories and files alike sorted by name, a directory's contents
  ## listed where the directory is. Links to directories are not followed --
  ## one that points up the tree would be a search that never ends.
  var entries: seq[string] = @[]
  try:
    for kind, path in walkDir(dir):
      if kind in {pcFile, pcLinkToFile, pcDir}:
        if kind != pcDir and not s.wantedExt(path): continue
        if not s.excluded(relativePath(path, s.dir)): entries.add path
  except CatchableError:
    return
  entries.sort(proc (a, b: string): int = cmp(b, a))
  s.pending.add entries

proc startDirSearch*(dir, term: string; opts: SearchOptions;
                     excludes: seq[string];
                     unsaved: Table[string, string];
                     exts: seq[string] = @[]): DirSearch =
  result = DirSearch(active: term.len > 0 and dirExists(dir), dir: dir,
                     term: term, opts: opts, unsaved: unsaved, exts: exts)
  for e in excludes:
    # `--exclude a,b` is two of them; an empty one would match nothing anyway.
    for p in e.split(','):
      if p.len > 0: result.excludes.add p
  if result.active: result.pushDir(dir)

proc readText(s: DirSearch; path: string; text: var string): bool =
  if path in s.unsaved:
    text = s.unsaved[path]
    return true
  try:
    if getFileSize(path) > MaxFileBytes: return false
    text = readFile(path)
  except CatchableError:
    return false
  # A NUL near the start is a binary file: its "lines" are noise, and a click
  # into one is an editor full of garbage.
  for i in 0 ..< min(text.len, 2000):
    if text[i] == '\0': return false
  result = true

proc searchFile(s: var DirSearch; path: string; output: var string) =
  var text = ""
  if not s.readText(path, text): return
  inc s.searched
  let hits = findHits(text, s.term, s.opts)
  if hits.len == 0: return
  inc s.files
  let rel = relativePath(path, s.dir)
  # Line numbers are counted forward from the last hit, so a file is walked
  # once however many hits it has.
  var line = 1
  var lineStart = 0
  var at = 0
  var lastLine = 0
  for h in hits:
    while at < h.a:
      if text[at] == '\n':
        inc line
        lineStart = at + 1
      inc at
    # One line of output per line of text: a line with three hits is one
    # place to go, at the first of them.
    if line == lastLine: continue
    lastLine = line
    var lineEnd = lineStart
    while lineEnd < text.len and text[lineEnd] notin {'\n', '\r'}: inc lineEnd
    var shown = text[lineStart ..< lineEnd].strip(trailing = false)
    if shown.len > MaxLineChars: shown = shown[0 ..< MaxLineChars] & "..."
    output.add rel & ":" & $line & ":" & $(h.a - lineStart + 1) & ": " &
               shown & "\n"
    inc s.matches
    if s.matches >= MaxSearchMatches:
      s.truncated = true
      s.active = false
      return

proc step*(s: var DirSearch; files: int): string =
  ## Look through up to `files` more files and hand back the lines they
  ## produced. `active` goes false when there is nothing left to look at, or
  ## enough has been found.
  result = ""
  var n = 0
  while s.active and n < files:
    if s.pending.len == 0:
      s.active = false
      break
    let path = s.pending.pop()
    if dirExists(path) and not symlinkExists(path):
      s.pushDir(path)
    elif fileExists(path):
      s.searchFile(path, result)
      inc n

proc stop*(s: var DirSearch) =
  s.active = false
  s.pending.setLen 0

proc summary*(s: DirSearch; stopped: bool): string =
  result =
    if s.matches == 0: "no match for '" & s.term & "'"
    else: $s.matches & " lines in " & $s.files & " files"
  let kinds = if s.exts.len == 0: "" else: "*." & s.exts.join(", *.") & " "
  result.add " (" & $s.searched & " " & kinds & "files searched in " & s.dir &
             ")"
  if s.truncated:
    result.add "; stopped at " & $MaxSearchMatches & " -- narrow it down"
  elif stopped:
    result.add "; stopped"
