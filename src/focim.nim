##[
focim -- the Focussed Nim Editor.

Design Notes:

Everything is text. The core widget is **SynEdit** -- a syntax-aware text
editor ported from NimEdit. Labels, status bars, and terminals are all
SynEdit instances with different configurations:

- **Editor**: Full editing with syntax highlighting, undo, line numbers
- **Label / status bar**: Read-only SynEdit via `setLabel()`
- **Terminal**: SynEdit wrapped with command execution, history, tab completion
- **Cmd+click** (macOS) / **Ctrl+click** (other): clickable text -- the app
  decides what happens (open file, go to definition, navigate directory)

Instead of a classical tab bar and a tree view there are two more edit fields,
each with its own *flipped* edit semantics:

- **Tab list**: every line is an open tab, and the line text is nothing but
  the file name. Click or Enter activates, deleting a line closes the tab,
  moving a line reorders the tabs, and undo (Ctrl+Z) reopens a closed tab --
  all of it falls out of the ordinary editing operations. State that is not a
  name (active, modified) lives in markers, never in the text, so that
  delete/copy/paste keep operating on a clean list.
- **Explorer**: a flat listing of one directory. Here it is the *first* line
  that is editable: it doubles as the path field and as a filter. Typing
  narrows the listing, Enter on a directory descends into it, and Enter on a
  partial name accepts the first match -- so there is no need for a modal
  "open file" dialog. Under `..` are the two places one keeps wanting to get
  back to: `[Editor]` for the directory of the file in the editor,
  `[Terminal]` for the one the terminal is in.
- **Branches**: the git branches of the repository the current file is in,
  when git tracks that file. A click checks one out and its (x) deletes it
  -- but only once its changes have landed in main or master, merged,
  rebased or squashed; anything else, and the default branch itself, is
  refused with the reason in the status bar. A switch git refuses
  -- changes in the work tree it would overwrite -- leaves the branch as it
  was and puts git's reason in the status bar.

The same idea applied to the window itself: tabs 0 and 1 are `[config]` and
`[layout]`, and their text IS the NIF this app is built from -- the
`(config ...)` whose `(theme ...)` colors the widgets, and the `(layout ...)`
that places them. Editing one recolors the window on the next frame and
editing the other relayouts it, so there is no separate settings dialog
either. Two lanes rather than one file because they answer different questions
and change on different days: the colors are picked once, the panels are
shoved about all the time, and a theme that arrived in the same text as the
layout could not be replaced without replacing the layout with it.

The layout is also the one of the two the mouse writes. The gaps between the
panels are the borders, and a border is a grip: press the left button on one
and it follows the pointer, moving the two boxes on either side of it and
leaving everything else in that container the size it was. The release writes
the new sizes into `[layout]` as a single edit -- so `Ctrl+Z` there undoes a
drag, and the file is stored by the same machinery that stores a layout typed
by hand. Each box keeps the unit it was written in: a `(px N)` follows the
pointer to the pixel, a `(lines N)` snaps to whole lines, and the boxes that
share what is left over have their weights rewritten from the pixels they now
have. Which is why the layout has a file to itself: it is the settings the
mouse edits, and it must not be replaced by anything that has an opinion about
color.

Leaving a widget out of the layout hides it without destroying it -- its
buffer, cursor and scroll position are still there when a later layout lists
it again. Only the `editor` cell has to stay, since it is where the layout
gets typed. A lane that does not parse is reported in the status bar, with the
line and column of the mistake, and ignored, so the last good one keeps the
window usable; a theme whose text would be unreadable on its own background is
refused the same way. Every color is written as `"#RRGGBB"`, which SynEdit
draws a chip of, so the palette is visible while it is being edited.

Both the terminal and the status bar take commands, and some of them act on the
buffer rather than on the machine: `o <file>` / `open <file>` opens one, `s` /
`save` writes the current one back, `s <file>` writes it somewhere else. A
relative path means what it would mean where it was typed: in the terminal,
relative to the directory the terminal is in; on the prompt, relative to the
file being edited. A name that is not found as written is looked for in the
directory of every open tab, then as an abbreviation of a file in one of them,
and then in the *project* those directories are in -- so `o synedit` finds
`src/focim/synedit.nim`, and `o xelim.nim` finds `src/hexer/xelim.nim` with
nothing but `nimony/README.md` open. See `doc/open.md`. Ctrl+P is
`open ` already typed into the prompt, for the muscle memory other editors
have trained.

Files change under an editor -- a build formats one, a `git checkout` swaps the
branch, another window saves. Nothing on a desktop reports that, so the files
behind the open tabs and the directory the explorer lists are asked every
couple of seconds whether they still say what they said. A tab with no unsaved
edits *is* its file and quietly becomes it again, the caret left on the line it
was on; a tab with unsaved edits is a second version of that file, and which of
the two survives is a question in the status bar -- the same `[yes|no]`
exchange an overwrite raises. A modification time that moved over unchanged
bytes -- a `touch`, a checkout that put the same text back -- is not a change
and is not mentioned. The explorer relists itself the same way, keeping the
filter that is typed in it and the place it is scrolled to.

`defaults`, in the prompt, puts what the app ships with back into both lanes
-- for settings that have been edited into a corner: a flattened palette, a
layout with the panel one is looking for left out of it. It is an edit like
any other, so `Ctrl+Z` in either tab brings the old text back. Only the prompt
understands the word; in the terminal it names a program, which is what the
terminal is for.

`theme` is the same door with more than one thing behind it: three configs
ship with the editor, `theme` lists them and `theme paper` puts one in the
tab. A theme is that whole lane rather than a palette spliced into the text
that is there -- it is written out of a `Theme` object, every field and every
token class, so nothing of the theme it replaces is left standing. What it
replaces is not lost either: `Ctrl+Z` has it for the session, and a config
that had been edited by hand goes to `config-backup.nif` beside `config.nif`
before the edit is made. `[layout]` is not touched by any of it. See
`doc/config.md`.

`find`, `findall`, `next`, `prev`, `replace` and `replaceall` are the same idea
applied to searching: no dialog, one line of text, and every match highlighted
in place -- in the other open tabs as well. Ctrl+F, F3 and Shift+F3 are there
for the fingers that expect them. See `doc/search.md`.

A command that has to ask something -- overwriting a file, replacing a match --
puts the question in the status bar and moves the caret there: the next line
typed *in the prompt* is the answer to it rather than a command. The terminal
is never asked anything, because it is where programs run and `yes` is one of
them. Both are the same SynEdit-backed `Terminal` widget; what makes one of
them a prompt is that the app points its `baseDir` at the current tab and lets
it carry a `question`.

What a terminal prints is highlighted too, by the console highlighter ported
from NimEdit: `Error:`, `Warning:` and `Hint:` take the three named colors, a
`[Tag]` behind a compiler message reads as one, and a diff is colored by the
first character of each line -- so `git diff` comes out in red and green with
its hunk headers picked out, without anything in the pipe emitting an escape
sequence.

What it printed is protected from editing, not from being read. The caret goes
up into the output, the arrow keys and the mouse move through it, and a
selection can be taken out of it exactly as in the editor. What brings the
caret back down is a key that edits -- a character, a paste, Tab, Enter -- so
those always land on the command line wherever the caret was left standing. Up
and Down are the command history while the caret is on that line and ordinary
caret keys above it; Ctrl+C copies while something is selected and stops the
running program when nothing is. A program that prints while its output is
being read leaves both the caret and the scroll position alone.

The settings and the list of open tabs are stored under `getConfigDir()` in
`focim/layout.nif`, `focim/config.nif` and `focim/tabs.txt`, so all of it
survives a restart. The two `.nif` files are the `[layout]` and `[config]`
tabs, and each is written back whenever the tab it belongs to parses. They
were one file once; a config that still has a `(layout ...)` in it has that
block moved across on the first start, and keeps a copy of itself while that
happens.

Markdown is still SynEdit, not a browser pane. Headings, links and fenced
code light up in place; Cmd/Ctrl+click on a `[label](path)` opens a relative
file (or jumps to `#heading`), so Nimony's `doc/*.md` can be explored without
leaving the editor.

Ctrl+Space completes a word. There is no compiler in the loop and nothing
here knows what a name *means*; what it knows is which names exist -- in the
open buffers, in a directory that `index <path>` was pointed at, and in the
Nimony vocabulary that ships with the editor. See `doc/completion.md`.

Ctrl+click on a name in a `.nim` file is the one place a compiler *is* in the
loop: `nim track` (or nimony) is asked where the name is declared and where it
is used, and the answer comes back as the same listing Ctrl+Space uses -- one
row per place, Enter to go there. The compiler runs in a thread, so the window
stays a window while it thinks. `(track (compiler "nim"))` in the config says
which compiler, and `"none"` says nobody. See `doc/track.md`.

The `clipboard` cell keeps what the clipboard held. A system clipboard holds
one thing, so copying twice before pasting once loses the first -- here the
last thirty texts that entered it stay, from this application or from any
other, numbered, and Ctrl+1 .. Ctrl+9 paste one at the caret. See
`doc/clipboard.md`.

Icon: `focim-icon.png` is the source art, and the files built from it that are
checked in next to it -- `focim-icon.netwm`, which the X11 branch below
`staticRead`s, and `focim.ico` / `.rc` / `.res`, which the Windows branch
links. Deriving those from the PNG, and installing the desktop entry or the
`.app` bundle, is somebody else's job: `iconbundler`
(https://github.com/Araq/iconbundler), which is a tool for any desktop
application and does not belong in an editor. It is a dependency, so:

    nimble icons      # after changing the PNG: remakes the four files above
    nimble bundle     # builds, and gives this build to the desktop

They are checked in rather than made by every build on purpose. Three of them
are inputs to the compiler, so a machine with no ImageMagick has to be able to
build all the same -- and two image tools do not resample a PNG to the same
bytes, so a build that remade them would rewrite files nobody edited. A
checkout that is missing one gets it made: that is the `before build` hook in
`focim.nimble`.

`StartupWMClass` / the bundle id stem must match the name of the executable,
which is what lands in `WM_CLASS` -- so the binary has to stay called `focim`.
]##

import std/[tables, os, algorithm]
from std/times import Time
from std/strutils import toLowerAscii, strip, endsWith, contains, splitLines,
                         startsWith, find, join
from std/cmdline import paramCount, paramStr
import uirelays
import uirelays/layout
import focim/[synedit, terminal, config, wordindex, cliphistory, search,
              filesearch]
import focim/track
import focim/configstore
import focim/shortcuts
import focim/gitbranches
import focim/dirsearch
import focim/gitdiff
import focim/completion
import focim/panels
import focim/images

# Derived from focim-icon.png by `iconbundler --prepare focim`.
when defined(windows):
  {.link: "focim.res".}

when defined(linux):
  const focimIconNetWm = staticRead("focim-icon.netwm")

  proc focimIcon(): seq[uint32] =
    ## The blob as the CARDINALs `createWindow` puts on the window.
    var raw = focimIconNetWm
    let n = raw.len div 4
    result = newSeq[uint32](n)
    if n > 0:
      copyMem(addr result[0], addr raw[0], n * 4)
else:
  proc focimIcon(): seq[uint32] = @[]
    ## Windows takes its icon from the linked `.res` and macOS from the bundle,
    ## so there is nothing for the window itself to carry.

const
  PathChars = {'a'..'z', 'A'..'Z', '0'..'9', '_', '.', '/', '\\',
               '-', '~', '\128'..'\255'}
  # Font sizes are *logical*: `fontForSize` turns them into physical ones with
  # the display's `uiScale`, so 16 looks the same on a 4K laptop panel as on a
  # 96 dpi monitor, and Ctrl+plus/minus steps by the same apparent amount on
  # both.
  DefaultFontSize = 16
  MinFontSize = 8
  MaxFontSize = 56
  WordsDirName = "words"
    ## Under the config dir: one file per indexed path, so that `index` is
    ## paid for once and not on every start.
  ShippedWords = staticRead("../data/nimony.txt")
    ## The vocabulary that comes with the editor -- in it, the way the icon
    ## is. It was a file beside the binary and that is one thing too many to
    ## get right: `nimble build` leaves the binary in the checkout, `nimble
    ## install` puts it in a package directory, an archive is extracted
    ## wherever, and a vocabulary that is missing is not an error anybody
    ## sees -- completion simply knows less and nobody can tell why. Twelve
    ## kilobytes in a binary that already carries eighty-six of icon settles
    ## it. `data/nimony.txt` stays the source: `tools/mkwordlist.nim` writes
    ## it, and what is compiled in is whatever it says at build time.
  MaxPreviewChars = 60
    ## How much of a line a tracking row quotes. A row is a thing to recognize
    ## a place by, not a place to read the code in.
  MaxPreviewBytes = 4_000_000
    ## Above this a file is not read for a one-line quote. Nothing anyone wrote
    ## by hand is that big, and the row is worth less than the pause would be.
  JobSliceMs = 30
    ## How long an index job is given per frame. The loop repaints the whole
    ## window once per pass, and the job has nothing to show for a pass but a
    ## file count -- so it is the frames that are rationed here, not the work:
    ## the job keeps reading for this long and the window is drawn once after.
    ## Thirty milliseconds is what the pointer and the keyboard wait for at
    ## worst while a job runs, and still leaves the count visibly moving.
  IdleFrameMs = BlinkMs
    ## The longest a frame may be put off when nothing has asked for one, and
    ## the caret is the whole of the reason there is a limit: it is the only
    ## thing on this window that moves by itself, and `SynEdit` moves it as it
    ## draws it. Hence the same number, and not a number of its own. It is
    ## also the rate a background job's progress count is seen to move at,
    ## which is as fast as a count is worth reading.
  WorkPollMs = 50
    ## How long work that is being done elsewhere may go unlooked-at: a
    ## compiler answering a Ctrl+click, a program printing in the terminal.
    ## Looking is a channel peek and costs nothing; it is *drawing* that is
    ## expensive, and a look that finds nothing does not lead to one.
  DiskCheckMs = 2000
    ## How often the files behind the open tabs, and the directory the
    ## explorer lists, are asked whether they still say what they said. This
    ## is a `stat` per open tab and one for the directory -- cheap enough to
    ## do often and not free enough to do every frame, and two seconds is
    ## about as long as one wants to look at a listing that a build has
    ## already made wrong. Everything that costs anything -- reading the file
    ## back, rebuilding the listing -- happens only when the cheap question
    ## was answered with a different number than last time.
  MaxTouchedTabs = 30
    ## How many of a branch's files a switch opens: the newest ones, which
    ## are the ones being worked on.
  OutputFrameMs = 100
    ## How long what a program has printed may sit collected but unshown.
    ## Collecting it is the peek above, so nothing waits longer than
    ## `WorkPollMs` to be *had*; this is the other question, of how often the
    ## window is repainted to show it, and a repaint of a window this size
    ## costs whole milliseconds where a peek costs none. Ten times a second
    ## already reads as a program printing, and a repaint per peek would read
    ## exactly the same at twenty times the price.

static:
  # The theme a widget falls back to and the theme a fresh config file names
  # are the same theme. Nothing enforces that but this line.
  doAssert defaultConfig == shippedConfig(defaultTheme()),
           "ShippedThemes[0] is not defaultTheme()"
  # And every one of them is a config this app can actually run on. A theme is
  # offered in a prompt, where the answer to picking a broken one would be a
  # parse error in the status bar; checked here, that answer cannot ship.
  for i in 0 ..< ShippedConfigs.len:
    let c = parseConfig(ShippedConfigs[i])
    doAssert c.error.len == 0, ShippedThemes[i].name & ": " & c.error
    doAssert c.note.len == 0, ShippedThemes[i].name & ": " & c.note
  # The other lane says where the widgets go, and the app needs some of them.
  let l = parseLayout(defaultLayout)
  doAssert l.error.len == 0, "the shipped layout: " & l.error
  doAssert panelsOf(l.cellNames, EditorStem).len > 0,
           "the shipped layout has no editor cell"

var gEditorCell = "editor"
  ## The cell the editor panel that the keystrokes are going to is drawn in.
  ## A global for the reason `gUiScale` below is one: every helper that hands
  ## the focus back to the editor after doing its work needs it, and none of
  ## them cares about anything else the window knows. It cannot be the word
  ## "editor" any more -- after a split the panel in question may be
  ## `editor3`, and the window may well have no cell called `editor` at all.
var gEditorSlot = 0
  ## The seat that panel sits in. A buffer keeps one caret per panel, so
  ## anything that puts a caret somewhere on the way to showing a file -- a
  ## jump to a definition, a search hit, `open foo.nim:120` -- has to put it
  ## in the seat the panel will read it out of. A global for the same reason
  ## the cell is one, and beside it because the two are always wanted
  ## together.
var gTerminalCell = "terminal"
  ## The same for the terminal a command goes to.

var gUiScale = 100
  ## Percent to enlarge text by on this display, from `ScreenLayout.uiScale`.
  ## A global because every `fontForSize` call needs it and none of them cares
  ## about anything else the window knows.

proc scaledPx(value: int): int {.inline.} =
  ## The same turn from logical to physical that `fontForSize` does for a font
  ## size, for the handful of pixel sizes this file states itself. The `(px N)`
  ## sizes in a layout are `resolve`'s business, not this one's.
  value * gUiScale div 100

proc fontForSize(fonts: var Table[int, Font]; size: int): Font =
  ## `size` and the cache key are logical; only what reaches `openFont` is
  ## physical.
  let clamped = clamp(size, MinFontSize, MaxFontSize)
  if clamped notin fonts:
    var metrics: FontMetrics
    fonts[clamped] = openFont("", clamped * gUiScale div 100, metrics)
  result = fonts[clamped]

proc extractPath(s: SynEdit; pos: int): tuple[path: string, a, b: int] =
  ## Extract the file path around buffer position `pos`.
  if pos < 0 or pos >= s.len or s[pos] notin PathChars:
    return ("", -1, -1)
  var first = pos
  var last = pos
  while first > 0 and s[first - 1] in PathChars: dec first
  while last + 1 < s.len and s[last + 1] in PathChars: inc last
  var path = ""
  for i in first .. last: path.add s[i]
  result = (path, first, last)

proc extractFilePosition(s: SynEdit; pos: int):
    tuple[file: string, line, col, a, b: int] =
  ## Parse "file.nim(10, 3)" or "file.nim:10:3:" starting from `pos`.
  result = ("", -1, -1, -1, -1)
  let (path, a, b) = s.extractPath(pos)
  if path.len == 0: return
  var i = b + 1
  if i >= s.len: return (path, -1, -1, a, b)
  var ln, fc: int
  template parseNum(num: var int) =
    while i < s.len and s[i] in {'0'..'9'}:
      num = num * 10 + (ord(s[i]) - ord('0'))
      inc i
  if s[i] == '(' and i + 1 < s.len and s[i + 1] in {'0'..'9'}:
    inc i
    parseNum(ln)
    if i < s.len and s[i] == ',':
      inc i
      while i < s.len and s[i] == ' ': inc i
      parseNum(fc)
    result = (path, ln, fc, a, i - 1)
  elif s[i] == ':' and i + 1 < s.len and s[i + 1] in {'0'..'9'}:
    inc i
    parseNum(ln)
    if i < s.len and s[i] == ':':
      inc i
      parseNum(fc)
    result = (path, ln, fc, a, i - 1)
  else:
    result = (path, -1, -1, a, b)

type
  BufferKind = enum
    ## A buffer is a file, or it is one of the two settings *lanes*: a tab
    ## whose text is a file under the config dir and takes effect as it is
    ## typed. Two of them rather than one because they answer different
    ## questions and change on different days -- the colors are picked once
    ## and the panels are shoved about all the time -- and because a theme
    ## that arrived in the same text as the layout could not be replaced
    ## without replacing the layout too.
    bufFile,            ## a file, or a scratch buffer with no file yet
    bufConfig,          ## this buffer's text IS `config.nif`: theme, tracking
    bufLayout           ## this buffer's text IS `layout.nif`: where things go

  BufferEntry = object
    ed: SynEdit
    id: int             ## what a panel calls this buffer by. The tab list
                        ## reorders and closes buffers by rewriting its own
                        ## lines, so an index into `buffers` is a name that
                        ## stops meaning what it meant; this one does not.
    path: string        ## "" for generated buffers
    kind: BufferKind    ## a file, or one of the settings lanes
    idx: BufferIndexer  ## how far the word index has walked this buffer
    search: BufferSearch ## the hits of the last search in this buffer
    diff: DiffView      ## its diff mode, see `toggleDiff`
    watch: bool         ## does this buffer stand for what is in a file? A
                        ## generated one does not, and neither does one that
                        ## holds the reason its file could not be read -- both
                        ## would report a change against a text that was never
                        ## the file's to begin with.
    timestamp: Time     ## the file's modification time as of the last read or
                        ## write through this buffer. What `harddiskCheck`
                        ## compares against, and the whole of what it takes to
                        ## notice that somebody else has written the file.

var gBufferIds = 0
proc freshBufferId(): int =
  inc gBufferIds
  result = gBufferIds

proc isLane(b: BufferEntry): bool = b.kind != bufFile
  ## A lane stands for a settings file rather than for a file somebody opened:
  ## it saves itself, it cannot be closed, and no `open` ever lands on it.

proc laneStem(k: BufferKind): string =
  ## The lane's file, without the extension: also its name in the tab list and
  ## the stem its backups are numbered off. One word, said once.
  case k
  of bufFile: ""
  of bufConfig: "config"
  of bufLayout: "layout"

proc laneName(k: BufferKind): string = "[" & laneStem(k) & "]"
proc laneFile(k: BufferKind): string = laneStem(k) & ".nif"

proc fileStamp(path: string): Time =
  ## The file's modification time, or the zero time for a file that cannot be
  ## asked -- which is what a file that is not there yet answers, and is a
  ## different answer from every real one.
  try: result = getLastModificationTime(path)
  except OSError: result = Time()

proc applyFileKind(ed: var SynEdit; path: string) =
  ## What the name of a file says about how to show it. Runs when a buffer is
  ## created and again after a `save <other-name>`: a buffer that just became a
  ## `.md` is a markdown buffer from then on.
  let ext = path.splitFile.ext.toLowerAscii
  ed.setLanguage fileExtToLanguage(ext)
  ed.flags = {rfColorLiterals}
  if ext == ".md" or ext == ".markdown":
    ed.flags.incl rfMarkdownImages

proc newBuffer(font: Font; path: string): BufferEntry =
  var ed = createSynEdit(font)
  ed.showLineNumbers = true
  ed.applyFileKind(path)
  # The stamp is taken *before* the read, not after: a file rewritten in the
  # moment between the two would otherwise leave the buffer holding the old
  # text under the new file's time, and nothing would ever notice.
  let stamp = fileStamp(path)
  var watch = true
  # The explorer makes it easy to click anything at all, so a file that
  # cannot be read must not take the editor down with it.
  try:
    ed.loadFromFile(path)
    if ed.len == 0 and getFileSize(path) > 0:
      # loadFromFile silently refuses binaries; say so instead of showing
      # an empty buffer.
      ed.lang = langNone
      ed.setText(path.extractFilename & ": binary file, not shown")
      ed.readOnly = ed.len - 1
      watch = false
  except CatchableError:
    ed.lang = langNone
    ed.setText("cannot read " & path & ": " & getCurrentExceptionMsg())
    ed.readOnly = ed.len - 1
    watch = false
  result = BufferEntry(ed: ed, id: freshBufferId(), path: path, watch: watch,
                       timestamp: stamp)

proc diskContentDiffers(ed: SynEdit; path: string): bool =
  ## Does the file hold something other than what the buffer shows? Asked
  ## whenever the modification time moved, because it moves for reasons that
  ## are not an edit -- a `git checkout` that put the same bytes back, a
  ## `touch`, a formatter that rewrote a file with what was already in it --
  ## and a buffer reloaded, or worse a question asked, over a file that says
  ## exactly what it said before is noise the user cannot act on.
  ##
  ## The comparison is against what *loading* the file would put in the
  ## buffer rather than against its bytes: `setText` drops CR and turns a tab
  ## into `tabSize` spaces, so a file whose line endings this editor never
  ## had would otherwise differ from itself forever.
  var disk = ""
  try:
    disk = readFile(path)
  except CatchableError:
    # Unreadable is not "unchanged": say so and let the caller decide, which
    # for a file that went away means leaving the buffer alone.
    return true
  var j = 0
  let n = ed.len
  template take(expected: char) =
    if j >= n or ed[Natural(j)] != expected: return true
    inc j
  for c in disk:
    case c
    of '\C': discard
    of '\t':
      for _ in 1 .. ed.tabSize: take ' '
    else: take c
  result = j != n

proc reloadBuffer(b: var BufferEntry) =
  ## Put what is on disk into the buffer, and leave the caret on the line it
  ## was on. The file moved under somebody who is pointing at something in it;
  ## the line is the most of that which survives an arbitrary edit, and it
  ## survives the common one -- a change further down the file -- exactly.
  let (line, col) = b.ed.lineAndByteCol(b.ed.cursor)
  b.timestamp = fileStamp(b.path)
  try:
    b.ed.loadFromFile(b.path)
  except CatchableError:
    # The file was readable a moment ago, when the content was compared. If it
    # is not now, the buffer is the only copy left of it and is worth more
    # than the reload was.
    return
  b.ed.gotoLineBytes(line, col)

proc tabsText(buffers: seq[BufferEntry]): string =
  ## The open tabs, in tab order. Generated buffers have no path and so are
  ## not part of the session.
  result = ""
  for b in buffers:
    if b.path.len > 0: result.add b.path & "\n"

proc openFile(buffers: var seq[BufferEntry]; font: Font;
              path: string; line, col: int): int =
  ## Open a file or switch to it if already open. Returns the buffer index,
  ## which the caller makes `current` -- that, and nothing else, is what puts
  ## the file in front of the panel the keystrokes are going to.
  ##
  ## The buffer is sat down in that panel's seat first, because the caret
  ## belongs to a seat: a `gotoLine` into the one nobody is sitting in is a
  ## jump the window never shows, and a file just made starts out in seat 0
  ## whichever panel asked for it.
  for i, b in buffers:
    if b.path == path:
      buffers[i].ed.enter gEditorSlot
      if line >= 0: buffers[i].ed.gotoLine(line, max(col, 0))
      return i
  buffers.add newBuffer(font, path)
  buffers[^1].ed.enter gEditorSlot
  if line >= 0: buffers[^1].ed.gotoLine(line, max(col, 0))
  result = buffers.high

# ---------------------------------------------------------------------------
# Tab list -- an edit field whose lines ARE the open tabs
# ---------------------------------------------------------------------------

type
  ClosedTab = object
    name, path: string

  TabList = object
    ed: SynEdit
    names: seq[string]     ## display name per buffer, as last rendered
    closed: seq[ClosedTab] ## closed tabs, so that undo can reopen them
    note: string           ## why the last close was refused ("" = nothing)

proc displayNames(buffers: seq[BufferEntry]): seq[string] =
  ## One unique name per buffer. Uniqueness matters: the name is the only
  ## handle we have once the user has edited the list.
  var base: seq[string] = @[]
  for b in buffers:
    base.add(
      if b.isLane: laneName(b.kind)
      elif b.path.len > 0: b.path.extractFilename
      else: "[scratch]")
  result = @[]
  for i, n in base:
    var dup = false
    for j, m in base:
      if i != j and n == m: dup = true
    if dup and buffers[i].path.len > 0:
      let parent = buffers[i].path.parentDir.lastPathPart
      result.add(if parent.len > 0: parent & "/" & n else: n)
    else:
      result.add n
  for i in 0 ..< result.len:
    for j in 0 ..< i:
      if result[i] == result[j]:
        result[i] = result[i] & " #" & $(i + 1)

proc renderTabs(tabs: var TabList; buffers: seq[BufferEntry]) =
  ## Rebuild the buffer text from the model. This resets the undo stack, so
  ## it must only run when the model changed behind the tab list's back --
  ## never after an edit the user made *in* the tab list.
  tabs.names = displayNames(buffers)
  var text = ""
  for i, n in tabs.names:
    if i > 0: text.add "\n"
    text.add n
  let line = tabs.ed.currentLine
  tabs.ed.setText(text)
  tabs.ed.gotoLine(min(line, max(0, tabs.names.len - 1)) + 1, 0)

proc decorateTabs(tabs: var TabList; buffers: seq[BufferEntry]; current: int) =
  ## Active and modified state as colors, not as text. Offsets are derived
  ## from the names because the text is exactly `names` joined by newlines.
  let theme = tabs.ed.theme
  tabs.ed.clearMarkers()
  # The active tab takes the whole row, the same band the editor draws behind
  # the line the caret is on -- a tab is the row, not the word in it, and a
  # highlight that stops after the name makes the list look ragged instead of
  # making one line of it stand out.
  tabs.ed.setRowHighlight(current, theme.activeLineBg)
  # The modified mark stays a marker: it belongs to the name, and on the
  # active tab it has to be visible *on* the band rather than instead of it.
  var pos = 0
  for i, n in tabs.names:
    # The layout buffer never shows up here: the main loop consumes its changed
    # flag on the very next frame, which is also when it gets stored.
    if i < buffers.len and buffers[i].ed.changed:
      tabs.ed.addMarker(pos, pos + n.len - 1, theme.markerBg)
    pos += n.len + 1
  # A tab in diff mode has a bar at its edge, in the color of a changed line:
  # which tabs are showing a diff is visible without opening them.
  tabs.ed.clearLineDecorations()
  for i in 0 ..< min(buffers.len, tabs.names.len):
    if buffers[i].diff.on:
      tabs.ed.addLineDecoration(i, theme.fg[TokenClass.Yellow], decoBar)

proc applyTabEdits(tabs: var TabList; buffers: var seq[BufferEntry];
                   current: var int; font: Font) =
  ## Diff the buffer's lines against the model and apply the difference:
  ##   line gone      -> close that tab
  ##   lines reordered -> reorder the tabs
  ##   line back again -> reopen it (this is what makes Ctrl+Z work)
  if tabs.names.len != buffers.len: return
  var lines: seq[string] = @[]
  for i in 0 ..< tabs.ed.getLineCount():
    let t = tabs.ed.getLineText(i).strip()
    if t.len > 0: lines.add t
  if lines == tabs.names:
    # Blank lines are not tabs; drop them again.
    if tabs.ed.getLineCount() != tabs.names.len: renderTabs(tabs, buffers)
    return

  tabs.note = ""
  let currentName = if current < tabs.names.len: tabs.names[current] else: ""
  var order: seq[BufferEntry] = @[]
  var newNames: seq[string] = @[]
  var taken = newSeq[bool](buffers.len)
  for ln in lines:
    var idx = -1
    for i, n in tabs.names:
      if not taken[i] and n == ln:
        idx = i
        break
    if idx >= 0:
      taken[idx] = true
      order.add buffers[idx]
      newNames.add ln
    else:
      # A line the model does not know: an undone close, or a pasted path.
      var path = ""
      for c in tabs.closed:
        if c.name == ln: path = c.path
      if path.len == 0:
        let p = if isAbsolute(ln): ln else: os.getCurrentDir() / ln
        if fileExists(p): path = p
      if path.len > 0 and fileExists(path):
        order.add newBuffer(font, path)
        newNames.add ln

  # Some tabs refuse to close: put their line back.
  for i in 0 ..< tabs.names.len:
    if not taken[i]:
      if buffers[i].isLane:
        # Closing it would leave no way to edit the settings back.
        tabs.note = laneName(buffers[i].kind) & " stays open"
      elif buffers[i].path.len > 0 and buffers[i].ed.changed:
        # A buffer without a path cannot be saved, so the guard would be
        # a trap rather than a warning.
        tabs.note = tabs.names[i] & ": unsaved changes, Ctrl+S first"
      else:
        continue
      renderTabs(tabs, buffers)
      return
  if order.len == 0:
    # The last tab stays open.
    renderTabs(tabs, buffers)
    return

  for i in 0 ..< tabs.names.len:
    if not taken[i] and buffers[i].path.len > 0:
      tabs.closed.add ClosedTab(name: tabs.names[i], path: buffers[i].path)
  buffers = order
  tabs.names = newNames
  current = clamp(current, 0, buffers.high)
  for i, n in newNames:
    if n == currentName: current = i

proc laneNote(laneNotes: array[BufferKind, string]; fallback: string): string =
  ## What the status bar says: a lane that cannot be used says why, and the
  ## config lane goes first -- a window with the wrong colors is still a
  ## window, and a window whose theme was refused is showing the very text
  ## that has to be corrected.
  if laneNotes[bufConfig].len > 0: laneNotes[bufConfig]
  elif laneNotes[bufLayout].len > 0: laneNotes[bufLayout]
  else: fallback

proc reparseConfig(src: string; theme: var Theme; track: var Track;
                   note: var string) =
  ## The [config] buffer's text IS the colors of the window and the compiler
  ## behind a Ctrl+click. One that does not parse is reported and dropped --
  ## the last good one keeps the window usable so the text can be corrected.
  ## A theme that cannot be read is dropped by the parser in the same spirit,
  ## and says so in `note` while the rest of the config is kept.
  let parsed = parseConfig(src)
  if parsed.error.len > 0:
    note = "config: " & parsed.error
    return
  theme = parsed.theme
  track = parsed.track
  note = parsed.note

proc layoutMetrics(width, height, lineHeight: int): LayoutMetrics =
  ## The numbers a layout becomes rects by. In one place because three things
  ## ask: the frame that draws the window, the borders a pointer takes hold of
  ## in it, and the check that a layout has the cells this app cannot do
  ## without. Two of them working from different numbers would be a border
  ## that moves to somewhere other than where it was grabbed.
  LayoutMetrics(screenW: width, screenH: height, lineHeight: lineHeight,
                padding: scaledPx(6), gap: scaledPx(4), uiScale: gUiScale)

proc reparseLayout(src: string; width, height, lineHeight: int;
                   layout: var Layout; note: var string) =
  ## And the [layout] buffer's text IS where the widgets go. Dropped on the
  ## same terms, with one more of them: a layout may leave any widget out --
  ## it is then simply not drawn, and keeps its state until a later layout
  ## brings it back -- but an editor panel has to stay, since a window with no
  ## editor in it has nowhere to type the layout back. Any of them will do: a
  ## split may well have left the window with `editor2` and `editor3` and no
  ## cell called `editor` at all.
  let parsed = parseLayout(src)
  if parsed.error.len > 0:
    note = "layout: " & parsed.error
    return
  let names = parsed.cellNames
  if panelsOf(names, EditorStem).len == 0:
    note = "layout: no 'editor' cell"
    return
  # A buffer keeps a seat for every panel that might show it, so there is a
  # ceiling on the panels -- and a layout naming more of them would leave the
  # ones past it drawn by nobody, which is worse than being told.
  for stem in [EditorStem, TerminalStem]:
    if panelsOf(names, stem).len > MaxViews:
      note = "layout: at most " & $MaxViews & " " & stem & " panels"
      return
  layout = parsed
  note = ""

# ---------------------------------------------------------------------------
# Panels. The layout says which of them the window has -- a cell called
# `editor2` is a second editor panel -- so the lists below are not a second
# opinion about that but a reading of it, brought into line whenever the
# layout changes. Which is also all a split has to do: write the cell into
# `layout.nif` and let the next frame find it there.
# ---------------------------------------------------------------------------

type
  EditorView = object
    ## A panel showing a buffer. Which buffer is the panel's own business:
    ## two panels may well show the same one, at different lines, which is
    ## the whole reason to have two.
    cell: string        ## the layout cell it is drawn in
    buf: int            ## the buffer's id -- not its index, which moves
    slot: int           ## the seat it sits in, in whatever buffer it shows

  TerminalView = object
    cell: string
    term: Terminal

  Newborn = object
    ## A panel that a split has just written into the layout, and the panel it
    ## was split out of. Kept only until the next frame reads the layout and
    ## makes the panel, which is when it is used and forgotten.
    cell, parent: string

  PanelButton = enum
    ## The three things a panel offers in its own corner. Tilix's two split
    ## buttons, whose icons are the shape of what they make, and the `(x)`
    ## every panel of every tiling terminal has had for twenty years.
    btnNone,
    btnRight,   ## a panel beside this one
    btnDown,    ## a panel below it
    btnClose    ## away with this one

  PanelButtons = object
    ## Which panel's buttons are showing, and which of them the pointer is on.
    ## Nothing is drawn until the pointer is inside a panel -- the same rule
    ## the splitter grips follow, and the reason a window at rest is text and
    ## nothing else.
    cell: string
    hot: PanelButton
    splits: bool  ## whether this panel can be split at all. The tab list and
                  ## the status bar cannot: there is nothing to have two of.

proc buttonRect(area: Rect; b: PanelButton; size: int): Rect =
  ## The three sit in the panel's top right corner, in the order they are
  ## used: the two that make a panel, then the one that takes it away.
  let n = case b
          of btnRight: 2
          of btnDown: 1
          of btnClose: 0
          of btnNone: return Rect(x: 0, y: 0, w: 0, h: 0)
  let gap = max(2, size div 4)
  result = rect(area.x + area.w - (n + 1) * (size + gap),
                area.y + gap, size, size)

proc buttonAt(pb: PanelButtons; area: Rect; size, x, y: int): PanelButton =
  ## Which of a panel's buttons the pointer is on, if any.
  result = btnNone
  for b in [btnClose, btnDown, btnRight]:
    if b != btnClose and not pb.splits: continue
    if buttonRect(area, b, size).contains(point(x, y)): return b

proc drawPanelButtons(pb: PanelButtons; area: Rect; size: int; theme: Theme) =
  ## Drawn, not typed: the shapes say what they do -- a box with a `+` on the
  ## side the new panel appears on -- and no font has to have a glyph for
  ## them. The same reason the `(x)` on a tab list line is drawn.
  template ink(b: PanelButton): Color =
    if pb.hot == b:
      if b == btnClose: theme.closeColor else: theme.focusColor
    else: theme.scrollBarColor
  for b in [btnClose, btnDown, btnRight]:
    if b != btnClose and not pb.splits: continue
    let r = buttonRect(area, b, size)
    if r.w <= 0 or r.x < area.x: continue
    let fg = ink(b)
    if pb.hot == b: fillRect(r, theme.scrollTrackColor)
    let pad = max(2, size div 5)
    let x0 = r.x + pad
    let y0 = r.y + pad
    let x1 = r.x + r.w - 1 - pad
    let y1 = r.y + r.h - 1 - pad
    case b
    of btnClose:
      drawLine(x0, y0, x1, y1, fg)
      drawLine(x1, y0, x0, y1, fg)
    of btnRight, btnDown:
      # The box is the panel as it will be, and the `+` stands where the new
      # one is about to: to the right of it, or under it.
      let box = if b == btnRight: rect(x0, y0, (x1 - x0) div 2, y1 - y0 + 1)
                else: rect(x0, y0, x1 - x0 + 1, (y1 - y0) div 2)
      drawFrame(box, fg, 1)
      let cx = if b == btnRight: (box.x + box.w + x1 + 1) div 2
               else: (x0 + x1 + 1) div 2
      let cy = if b == btnRight: (y0 + y1 + 1) div 2
               else: (box.y + box.h + y1 + 1) div 2
      let arm = max(1, pad)
      drawLine(cx - arm, cy, cx + arm, cy, fg)
      drawLine(cx, cy - arm, cx, cy + arm, fg)
    of btnNone: discard

proc anyRunning(views: seq[TerminalView]): bool =
  ## Is a program running in any of the panels? What decides how soon the next
  ## frame is due: output arrives on a thread, and nothing else about a frame
  ## says that it has.
  for v in views:
    if v.term.processRunning: return true
  result = false

proc putLayout(buffers: var seq[BufferEntry]; layout: Layout) =
  ## The layout as it now stands, back into the `[layout]` tab -- which *is*
  ## the file, so this is the whole of storing it. One edit, so that Ctrl+Z
  ## there takes the whole of a drag or a split back, and the lane machinery
  ## at the top of the loop parses and saves it like any other typing.
  let tree = $layout
  if tree.len == 0: return
  for b in buffers.mitems:
    if b.kind == bufLayout:
      let text = withHeader(b.ed.fullText, tree)
      if b.ed.fullText == text: continue
      if b.ed.len > 0: b.ed.replaceRange(0, b.ed.len - 1, text)
      else: b.ed.insertText(text)

proc indexOfId(buffers: seq[BufferEntry]; id: int): int =
  result = -1
  for i in 0 ..< buffers.len:
    if buffers[i].id == id: return i

proc viewOf(views: seq[EditorView]; cell: string): int =
  result = -1
  for i in 0 ..< views.len:
    if views[i].cell == cell: return i

proc freeSlot(views: seq[EditorView]): int =
  ## The lowest seat number nobody is using. Lowest rather than next, so that
  ## a window whose panels come and go all afternoon keeps using the same few.
  for slot in 0 ..< MaxViews:
    var taken = false
    for v in views:
      if v.slot == slot: taken = true
    if not taken: return slot
  result = -1

proc reconcileEditors(views: var seq[EditorView]; cells: seq[string];
                      buffers: var seq[BufferEntry]; current: int;
                      born: Newborn) =
  ## Bring the panels into line with what the layout says there are. A panel
  ## whose cell has gone is dropped -- which closes a *panel*, never a file:
  ## the buffer stays open and its tab with it -- and a cell nothing is
  ## drawing gets a panel of its own.
  let want = panelsOf(cells, EditorStem)
  var i = 0
  while i < views.len:
    if views[i].cell notin want: views.delete i
    else: inc i
  for name in want:
    if views.viewOf(name) >= 0: continue
    let slot = views.freeSlot
    if slot < 0: continue
    var v = EditorView(cell: name, buf: buffers[current].id, slot: slot)
    # A panel that came out of a split shows what the panel it came out of
    # shows, at the same line: split, scroll one of them away, and there are
    # two windows onto one file.
    let parent = if name == born.cell: views.viewOf(born.parent) else: -1
    if parent >= 0:
      v.buf = views[parent].buf
      let b = buffers.indexOfId(v.buf)
      if b >= 0: buffers[b].ed.copySeat(views[parent].slot, slot)
    views.add v

proc reconcileTerminals(views: var seq[TerminalView]; cells: seq[string];
                        font: Font; theme: Theme; born: Newborn) =
  ## The same for the terminals, with one difference: a terminal panel whose
  ## cell has gone is *kept*, and only stops being drawn. What is in it is a
  ## shell's session -- a program halfway through running, an hour of output,
  ## a directory somebody walked to -- and none of that can be got back the
  ## way a file can be reopened. It is also the rule the layout has always
  ## followed for a widget it leaves out: not drawn, and there again with
  ## everything it had the moment the cell comes back.
  ##
  ## What a new one inherits is the directory of the panel it came out of: a
  ## terminal split off another is a second prompt where the first one had
  ## got to.
  for name in panelsOf(cells, TerminalStem):
    var have = false
    for v in views:
      if v.cell == name: have = true
    if have: continue
    var t = createTerminal(font, theme)
    if name == born.cell:
      for v in views:
        if v.cell == born.parent and v.term.cwd != t.cwd:
          # The prompt is written when the terminal is made, so it has to be
          # written again for the directory this one really starts in.
          t.cwd = v.term.cwd
          t.ed.clear()
          t.ed.lang = langConsole
          t.insertPrompt()
    views.add TerminalView(cell: name, term: t)

# ---------------------------------------------------------------------------
# Explorer -- a flat listing of one directory, with an editable path line
# ---------------------------------------------------------------------------

type
  Explorer = object
    ed: SynEdit
    dir: string          ## the directory currently listed
    base: string         ## anchor for resolving the path line; only explicit
                         ## navigation moves it, so typing stays predictable
    entries: seq[string] ## the lines below the header, in order
    header: string       ## line 0, as last rendered
    stamp: Time          ## `dir`'s modification time as of the last listing.
                         ## A directory's time moves when an entry is created,
                         ## removed or renamed -- which is exactly the set of
                         ## things that make a listing of it wrong, and none of
                         ## the things (a file being written into) that leave
                         ## it right.

proc normDir(dir: string): string =
  result = dir
  while result.len > 1 and result[^1] == DirSep:
    result.setLen result.len - 1
  if result.len == 0: result = $DirSep

proc resolveIn(base, s: string): string =
  ## Resolve the path line against `base`. A bare word like "syn" becomes
  ## `base/syn`, whose parent is `base` -- which is what turns it into a
  ## filter over the current listing.
  let e = expandTilde(s.strip())
  if e.len == 0: return ""
  result = if isAbsolute(e): e else: base / e

const NavEntries = ["..", "[Editor]", "[Terminal]"]
  ## The lines every unfiltered listing starts with, before the directory
  ## itself: up one level, the directory of the file in the editor, and the
  ## directory the terminal is in -- the two places one keeps wanting to get
  ## back to once the listing has wandered off somewhere else. The brackets
  ## are the tell that these are not entries of this directory; no file is
  ## named like that, and the position decides anyway.

proc listDir(dir, filter: string): seq[string] =
  ## The navigation lines first, then directories, then files. Dotfiles are
  ## listed too; a hidden file one cannot see is a file one cannot open.
  var dirs: seq[string] = @[]
  var files: seq[string] = @[]
  let f = filter.toLowerAscii
  for kind, path in walkDir(dir):
    let name = path.extractFilename
    if name.len == 0: continue
    if f.len > 0 and not name.toLowerAscii.contains(f): continue
    case kind
    of pcDir, pcLinkToDir: dirs.add name & $DirSep
    else: files.add name
  sort dirs
  sort files
  result = @[]
  # Filtering is a search through this directory, and the navigation lines are
  # not part of it -- they would survive every filter and be in the way of the
  # first match, which is what Enter takes.
  if filter.len == 0:
    for n in NavEntries: result.add n
  for d in dirs: result.add d
  for x in files: result.add x

proc renderExplorer(ex: var Explorer; header: string; cursorPos: int) =
  ex.header = header
  var text = header
  for e in ex.entries: text.add "\n" & e
  ex.ed.setText(text)
  ex.ed.gotoPos(clamp(cursorPos, 0, text.len))

proc showDir(ex: var Explorer; dir: string) =
  if not dirExists(dir): return
  ex.dir = normDir(dir)
  ex.base = ex.dir
  ex.stamp = fileStamp(ex.dir)
  ex.entries = listDir(ex.dir, "")
  let h = ex.dir & (if ex.dir.endsWith($DirSep): "" else: $DirSep)
  ex.renderExplorer(h, h.len)

proc resolveHeader(ex: Explorer; header: string): tuple[dir, filter: string] =
  ## What the path line asks for: the directory to list, and what to narrow it
  ## by. An existing directory switches the listing, anything else narrows it.
  let full = resolveIn(ex.base, header)
  var dir = ex.base
  var filter = ""
  if full.len > 0 and dirExists(full):
    dir = full
  elif full.len > 0:
    let parent = full.parentDir
    if parent.len > 0 and dirExists(parent):
      dir = parent
      filter = full.extractFilename
  result = (normDir(dir), filter)

proc applyHeader(ex: var Explorer; header: string) =
  ## The path line doubles as "cd" and as a filter.
  let (dir, filter) = ex.resolveHeader(header)
  ex.dir = dir
  ex.stamp = fileStamp(ex.dir)
  ex.entries = listDir(ex.dir, filter)
  ex.renderExplorer(header, ex.ed.cursor)

proc refreshListing(ex: var Explorer): bool =
  ## List the directory again if something in it has come or gone. Nothing
  ## reports that to a program, so this is a `stat` of the directory: its time
  ## moves when an entry is created, removed or renamed, and stands still
  ## while a file inside it is merely written.
  ##
  ## The header is read from the widget rather than from `ex.header`, because
  ## while the explorer has the focus that line is what is being typed, and the
  ## filter it spells is the listing anybody wants back.
  ##
  ## Nothing is redrawn unless the lines really did change: a directory whose
  ## time moved over a temporary file that has already gone again lists exactly
  ## as it did, and rebuilding the text over that would drop the selection
  ## somebody is holding in it. When they did change, the scroll position is
  ## put back -- a listing that rebuilt itself because a build wrote into the
  ## directory must not also send a reader back to the top of it.
  if ex.dir.len == 0: return false
  if not dirExists(ex.dir):
    # The directory itself went. Walk up to the nearest one that is still
    # there rather than keep a listing of somewhere that is not.
    var up = ex.dir.parentDir
    while up.len > 0 and not dirExists(up): up = up.parentDir
    if up.len == 0: return false
    ex.showDir(up)
    return true
  let stamp = fileStamp(ex.dir)
  if stamp == ex.stamp: return false
  let header = ex.ed.getLineText(0)
  # The header is resolved again rather than reused: a name that was a filter
  # a moment ago is a directory now if that is what just appeared under it.
  let (dir, filter) = ex.resolveHeader(header)
  let entries = listDir(dir, filter)
  ex.stamp = if dir == ex.dir: stamp else: fileStamp(dir)
  if dir == ex.dir and entries == ex.entries: return false
  ex.dir = dir
  ex.entries = entries
  let top = ex.ed.firstLine.int
  ex.renderExplorer(header, ex.ed.cursor)
  ex.ed.scrollTo(top)
  result = true

proc navShown(ex: Explorer): bool =
  ## Are the navigation lines in the listing? ".." gives it away: a filtered
  ## listing never contains it. Asking this instead of comparing the line's
  ## text means a real file could be called "[Editor]" and would still open --
  ## it is a different line, further down, and only the position decides.
  ex.entries.len >= NavEntries.len and ex.entries[0] == NavEntries[0]

proc activateEntry(ex: var Explorer; idx: int;
                   buffers: var seq[BufferEntry]; current: var int;
                   font: Font; focus: var string;
                   termDir: string; note: var string) =
  if idx < 0 or idx >= ex.entries.len: return
  if ex.navShown and idx < NavEntries.len:
    case idx
    of 0:
      let up = ex.dir.parentDir
      if up.len > 0: ex.showDir(up)
    of 1:
      # The file in the editor, not the tab list's idea of it: an unsaved
      # buffer has no directory to go to and says so rather than jumping
      # somewhere plausible.
      let p = buffers[current].path
      if p.len > 0: ex.showDir(p.parentDir)
      else: note = "this buffer has no file yet"
    else:
      if termDir.len > 0 and dirExists(termDir): ex.showDir(termDir)
      else: note = "the terminal is in " & termDir & ", which is gone"
    return
  let name = ex.entries[idx]
  if name.endsWith($DirSep):
    ex.showDir(ex.dir / name[0 ..< name.len - 1])
  else:
    let p = ex.dir / name
    if fileExists(p):
      current = buffers.openFile(font, p, -1, -1)
      focus = gEditorCell

# ---------------------------------------------------------------------------
# Branch list -- the git branches of the repository the current file is in
# ---------------------------------------------------------------------------
#
# The tab list's arrangement once more: every line is a branch, a click on one
# checks it out, and its (x) deletes it. Unlike a tab, a branch is not the
# list's to keep -- git has it -- so the text is never edited into a new
# state; it is rebuilt from what git says after every act, and an edit typed
# into it is simply put back.

type
  BranchList = object
    ed: SynEdit
    file: string         ## the file the listing was made for
    branches: Branches
    text: string         ## the text as last rendered

proc renderBranches(bl: var BranchList) =
  var text = ""
  for i, n in bl.branches.names:
    if i > 0: text.add "\n"
    text.add n
  if text == bl.text and bl.ed.fullText == text: return
  let line = bl.ed.currentLine
  let top = bl.ed.firstLine.int
  bl.text = text
  bl.ed.setText(text)
  bl.ed.gotoLine(min(line, max(0, bl.branches.names.len - 1)) + 1, 0)
  bl.ed.scrollTo(top)

proc decorateBranches(bl: var BranchList) =
  # The checked out branch takes the row, as the active tab does.
  bl.ed.setRowHighlight(bl.branches.current, bl.ed.theme.activeLineBg)

proc refreshBranches(bl: var BranchList; file: string; force = false): bool =
  ## Ask git again. The repository is looked up only when the file changed;
  ## the branches themselves are asked for every time, since a `git switch`
  ## typed into the terminal is as much a change as a click here.
  if file != bl.file or force:
    bl.file = file
    bl.branches.root = trackedRoot(file)
  let fresh = listBranches(bl.branches.root)
  if fresh == bl.branches and bl.ed.fullText == bl.text: return false
  bl.branches = fresh
  bl.renderBranches()
  result = true

proc actOnBranch(bl: var BranchList; line: int; delete: bool;
                 note: var string): bool =
  ## A click on row `line`, or on its (x). True when the work tree changed
  ## under the open buffers -- which a switch does and a delete does not.
  if line < 0 or line >= bl.branches.names.len: return false
  let name = bl.branches.names[line]
  var err = ""
  if delete:
    if deleteBranch(bl.branches.root, name, err): note = "deleted branch " & name
    else: note = err
  elif line == bl.branches.current:
    discard
  elif switchBranch(bl.branches.root, name, err):
    note = "switched to " & name
    result = true
  else:
    # Git left everything as it was, and so does the list.
    note = err
  discard bl.refreshBranches(bl.file)

# ---------------------------------------------------------------------------
# Word sets on disk
# ---------------------------------------------------------------------------

proc wordSetFile(name: string): string =
  ## A path is not a file name, so every separator becomes an underscore.
  ## Two paths could in principle collide here; the file says which one it
  ## holds, so the worst case is that a cache is rewritten.
  var s = ""
  for c in name:
    if c in {'a'..'z', 'A'..'Z', '0'..'9', '-', '.'}: s.add c
    elif s.len > 0 and s[^1] != '_': s.add '_'
  result = WordsDirName / s.strip(chars = {'_'}) & ".txt"

proc loadWordSet(words: var WordIndex; file: string) =
  ## Best effort, like everything else that reads a file the editor wrote: a
  ## word list is a cache, and a cache that is gone or unreadable is a reason
  ## to have fewer words, never a reason to stop.
  var text = ""
  try:
    text = readFile(file)
  except CatchableError:
    return
  var ws = parseWordSet(text)
  if ws.name.len == 0: ws.name = file
  words.addSet ws

proc loadWordSets(words: var WordIndex) =
  ## The shipped vocabulary, then everything `index` stored in earlier runs.
  block:
    var ws = parseWordSet(ShippedWords)
    if ws.name.len == 0: ws.name = "nimony"
    words.addSet ws
  try:
    for kind, p in walkDir(configPath(WordsDirName)):
      if kind == pcFile and p.endsWith(".txt"):
        loadWordSet(words, p)
  except CatchableError:
    discard

proc runIndexCommand(act: TermAction; words: var WordIndex; job: var IndexJob;
                     note: var string) =
  ## `index` on its own says what is indexed, `index <path>` starts a job, and
  ## `unindex <path>` forgets one.
  if act.path.len == 0:
    var s = $words.wordCount & " words, " & $words.liveCount & " of them from " &
            "the open buffers"
    for ws in words.sets: s.add "; " & ws.name & " " & $ws.words.len
    note = s
  elif act.forget:
    if words.dropSet(act.path):
      try: removeFile(configPath(wordSetFile(act.path)))
      except CatchableError: discard
      note = "forgot " & act.path
    else:
      note = "not indexed: " & act.path
  elif not fileExists(act.path) and not dirExists(act.path):
    note = "no such path: " & act.path
  else:
    job = startIndexJob(act.path)
    if job.active: note = job.progress
    else: note = "nothing to index in " & act.path

proc handleTermCtrlClick(buf: SynEdit; pos: int;
                         buffers: var seq[BufferEntry]; current: var int;
                         font: Font; term: var Terminal;
                         focus: var string) =
  let (file, ln, fc, a, b) = buf.extractFilePosition(pos)
  if file.len == 0: return
  let path = if isAbsolute(file): file else: term.base / file
  term.ed.underline(a, b)
  if dirExists(path):
    # The terminal's own idea of where it is -- the same thing `cd` moves, and
    # what the next command is run in. It does not go in the window title: the
    # title says which buffer is being edited, and a directory there would be
    # a second meaning that stays until the buffer happens to change. The
    # prompt already says where the terminal is.
    term.cwd = path
    term.ed.appendOutput("\L")
    term.insertPrompt()
    var lsCmd = "ls"
    discard term.runCommand(lsCmd)
  elif fileExists(path):
    # Columns are counted from 1 in what compilers and `search` print, and
    # `gotoLine` takes how many characters to step over: one fewer.
    current = buffers.openFile(font, path, ln, max(fc - 1, 0))
    focus = gEditorCell

proc splitMarkdownTarget(url: string): tuple[path, frag: string] =
  ## Split `path#heading` / `#heading` into path and fragment.
  let hash = url.find('#')
  if hash < 0: return (url, "")
  if hash == 0: return ("", url[1 .. ^1])
  result = (url[0 ..< hash], url[hash + 1 .. ^1])

proc isExternalUrl(url: string): bool =
  let u = url.toLowerAscii
  u.startsWith("http://") or u.startsWith("https://") or u.startsWith("mailto:")

proc markdownLinkAt(ed: SynEdit; pos: int): tuple[url: string; a, b: int] =
  ## Prefer a real markdown link; fall back to a bare path under the cursor.
  result = ed.extractMarkdownLink(pos)
  if result.a >= 0: return
  let (path, a, b) = ed.extractPath(pos)
  if path.len > 0: result = (path, a, b)

proc handleMarkdownCtrlClick(ed: var SynEdit; pos: int;
                             buffers: var seq[BufferEntry]; current: var int;
                             font: Font; focus: var string;
                             note: var string; explorer: var Explorer) =
  ## Follow a markdown link from the focused editor buffer.
  let (url, a, b) = ed.markdownLinkAt(pos)
  if url.len == 0: return
  ed.underline(a, b)
  let (path, frag) = splitMarkdownTarget(url)
  if path.len == 0:
    if not ed.gotoMarkdownHeading(frag):
      note = "no heading: #" & frag
    return
  if isExternalUrl(path):
    note = "external: " & path
    return
  let base =
    if buffers[current].path.len > 0: buffers[current].path.parentDir
    else: os.getCurrentDir()
  let full = if isAbsolute(path): path else: base / path
  if fileExists(full):
    current = buffers.openFile(font, full, -1, -1)
    focus = gEditorCell
    note = ""
    if frag.len > 0 and not buffers[current].ed.gotoMarkdownHeading(frag):
      note = "opened, but no heading: #" & frag
  elif dirExists(full):
    explorer.showDir(full)
    focus = "explorer"
    note = ""
  else:
    note = "not found: " & full

# ---------------------------------------------------------------------------
# Tracking -- where a name is declared and where it is used, per the compiler
# ---------------------------------------------------------------------------

proc startTrack(tracker: var Tracker; spec: Track; ed: var SynEdit; pos: int;
                path: string; note: var string) =
  ## What a Ctrl+click on a name in a `.nim` buffer asks for. The click has
  ## already put the caret in the name; the *start* of the name is what gets
  ## asked about, so that clicking anywhere in it is the same question.
  let (word, a, b) = ed.wordAt(pos)
  if word.len == 0:
    note = "nothing to look up here"
    return
  ed.underline(a, b)
  let (line, col) = ed.lineAndByteCol(a)
  discard tracker.start(spec, path, line, col, word)
  note = tracker.note

proc shortPath(path, base: string): string =
  ## What a row calls a file. Inside the project it is the path from the
  ## project down, which is how one talks about one's own files; outside it --
  ## the standard library, another package -- the last directory and the name,
  ## since the absolute path would be the widest thing in the listing and the
  ## least worth reading.
  if base.len > 0 and path.len > base.len and path.startsWith(base) and
     path[base.len] == DirSep:
    result = path[base.len + 1 .. ^1]
  else:
    let parent = path.parentDir.lastPathPart
    result = if parent.len > 0: parent & "/" & path.extractFilename
             else: path.extractFilename

proc sourceLine(path: string; line: int; buffers: seq[BufferEntry];
                cache: var Table[string, seq[string]]): string =
  ## Line `line` of `path`, for the row that offers to go there. An open buffer
  ## answers first: it is what the file *is* right now, and an unsaved edit is
  ## exactly the case where the text on disk would be misleading. Everything
  ## else is read once per file, however many rows point into it.
  for b in buffers:
    if b.path == path and not b.isLane:
      return b.ed.getLineText(line - 1).strip
  if path notin cache:
    var lines: seq[string] = @[]
    try:
      if getFileSize(path) <= MaxPreviewBytes:
        lines = readFile(path).splitLines
    except CatchableError:
      discard
    cache[path] = lines
  let lines = cache[path]
  result = if line >= 1 and line <= lines.len: lines[line - 1].strip else: ""

proc trackRows(hits: seq[TrackHit]; base: string;
               buffers: seq[BufferEntry]): seq[string] =
  ## One row per place: what it is, where it is, and what stands there. The
  ## `where` column is padded to a common width so that the source text lines
  ## up and the eye can run down it.
  var cache = initTable[string, seq[string]]()
  var where: seq[string] = @[]
  var widest = 0
  for h in hits:
    let w = (if h.isDef: "def " else: "use ") & shortPath(h.path, base) &
            ":" & $h.line
    where.add w
    widest = max(widest, w.len)
  result = @[]
  for i, h in hits:
    var row = where[i]
    while row.len < widest: row.add ' '
    let src = sourceLine(h.path, h.line, buffers, cache)
    if src.len > 0:
      row.add "  "
      row.add(if src.len > MaxPreviewChars: src[0 ..< MaxPreviewChars] & "..."
              else: src)
    result.add row

proc jumpTo(hit: TrackHit; buffers: var seq[BufferEntry]; current: var int;
            font: Font; focus: var string; note: var string) =
  ## Go where a row points. The answer is as old as the query that produced it,
  ## so the file may be gone by now -- which is a note, not a crash.
  if not fileExists(hit.path):
    note = "gone since the compiler saw it: " & hit.path
    return
  current = buffers.openFile(font, hit.path, -1, -1)
  buffers[current].ed.gotoLineBytes(hit.line, hit.col)
  focus = gEditorCell
  note = ""

proc updateStatus(status: var Terminal; ed: SynEdit; path, note: string) =
  let name = if path.len > 0: path.extractFilename else: "[scratch]"
  let info = name & "  Ln " & $(ed.currentLine + 1) &
             ", Col " & $(ed.currentCol + 1) &
             (if ed.changed: "  *" else: "") &
             (if note.len > 0: "  " & note else: "") & " > "
  status.ed.clear()
  status.ed.lang = langConsole
  status.ed.appendOutput(info)

proc prepareCommand(status: var Terminal; buffers: seq[BufferEntry];
                    current: int; cmd, note: string) =
  ## Leave the prompt as if `cmd` had just been typed into it. `updateStatus`
  ## rewrites the line on every frame the status bar is *not* focused, so this
  ## is only ever a keystroke away from being undone -- the caller moves the
  ## focus there.
  updateStatus(status, buffers[current].ed, buffers[current].path, note)
  status.ed.insertText(cmd)

proc addHistoryLine(history: var SynEdit; cmd: string) =
  ## Append a command to the history panel as an ordinary edit, so that the (x)
  ## button, a hand-made deletion and Ctrl+Z all act on it the same way. An
  ## existing copy moves to the end instead of being repeated -- the list is
  ## there to save typing, not to record every repetition.
  if cmd.len == 0: return
  for i in 0 ..< history.getLineCount():
    if history.getLineText(i) == cmd:
      history.gotoLine(i + 1, 0)
      history.deleteLine()
      break
  history.gotoPos(history.len)
  # One insertText, so one Ctrl+Z takes the whole row back out again.
  history.insertText(if history.len > 0: "\n" & cmd else: cmd)

# ---------------------------------------------------------------------------
# `o` and `save` -- the two commands that act on the buffer rather than on the
# machine. Both are typed in a Terminal (the status prompt or the terminal
# itself), and both take a path that is relative to whatever that widget
# considers current: the directory of the file being edited for the prompt,
# the directory the terminal is in for the terminal.
# ---------------------------------------------------------------------------

proc searchDirs(buffers: seq[BufferEntry]; base: string): seq[string] =
  ## Where a name that is not a path is looked for: the directory the command
  ## was typed against first, then the directory of every open tab. This is
  ## nimedit's search path without a list to maintain -- the open tabs already
  ## say which directories a session is about.
  result = @[]
  if base.len > 0 and dirExists(base): result.add normDir(base)
  for b in buffers:
    if b.path.len > 0:
      let d = normDir(b.path.parentDir)
      if d notin result and dirExists(d): result.add d

proc findFileSmart(buffers: seq[BufferEntry]; base, arg: string;
                   truncated: var bool): string =
  ## Three questions, cheapest first, each asked only because the one before it
  ## said no:
  ##
  ## 1. the path as given, against the directory the command was typed in --
  ##    nimedit's `findFile`;
  ## 2. the *listing* of that directory, for a name with pieces missing --
  ##    nimedit's `findFileAbbrev`, one `walkDir`;
  ## 3. the projects that directory and the directory of every open tab are
  ##    in, walked, ranked by nearness to where the command was typed first
  ##    and to the open tabs after that.
  ##
  ## The first two only ever look where the command was typed: a tab open in
  ## another project must not answer before the project one is standing in has
  ## been asked -- in a Nimony checkout `o strutils.nim` means Nimony's, even
  ## with Nim's `lib/pure` open in a tab. What the cheap steps cannot answer is
  ## a project that has any shape to it: with only `nimony/README.md` open,
  ## `xelim.nim` is three directories away in `src/hexer/`. That is what the
  ## walk is for, and why it is last -- it is the only step that costs
  ## anything.
  ##
  ## Steps 2 and 3 are the same ranking over a different scope. The tab
  ## directories are asked the cheap questions too, but only once the walk has
  ## said no -- a tab in a directory too big to walk is still a place to look.
  ## Directories are found too; the caller decides what to do with one.
  truncated = false
  if arg.len == 0: return ""
  let e = expandTilde(arg)
  if isAbsolute(e):
    return if fileExists(e) or dirExists(e): e else: ""
  let dirs = searchDirs(buffers, base)
  let here = if base.len > 0 and dirs.len > 0 and dirs[0] == normDir(base):
               @[dirs[0]]
             else: @[]
  for d in here:
    let p = d / e
    if fileExists(p) or dirExists(p): return p
  result = findInTrees(here, dirs, e, truncated, recurse = false)
  if result.len > 0: return
  var roots: seq[string] = @[]
  for d in dirs:
    let r = searchRoot(d)
    if r.len > 0 and r notin roots: roots.add r
  result = findInTrees(roots, dirs, e, truncated)
  if result.len > 0: return
  let walkTruncated = truncated
  for d in dirs:
    let p = d / e
    if fileExists(p) or dirExists(p): return p
  result = findInTrees(dirs, dirs, e, truncated, recurse = false)
  truncated = truncated or walkTruncated

proc runOpenCommand(act: TermAction; base: string;
                    buffers: var seq[BufferEntry]; current: var int;
                    font: Font; focus: var string; explorer: var Explorer;
                    note: var string) =
  if act.arg.len == 0:
    note = "open what? try 'o <file>'"
    return
  # `act.file` is what the widget resolved; anything smarter than that is this
  # application's business, because only it knows which files are open.
  var path = act.file
  var truncated = false
  if not fileExists(path) and not dirExists(path):
    path = findFileSmart(buffers, base, act.arg, truncated)
  if path.len == 0:
    note = "cannot open: " & act.arg &
      (if truncated: " -- and the tree was too big to search all of it" else: "")
  elif dirExists(path):
    # A directory is not a buffer; it is what the explorer is for.
    explorer.showDir(path)
    focus = "explorer"
    note = ""
  else:
    current = buffers.openFile(font, path, -1, -1)
    focus = gEditorCell
    note = ""

proc saveCurrent(buffers: var seq[BufferEntry]; current: int;
                 note: var string) =
  ## Write the buffer back to the file it came from. A buffer that has no file
  ## says so instead of quietly doing nothing.
  if buffers[current].path.len == 0:
    note =
      if buffers[current].isLane: laneName(buffers[current].kind) &
                                  " saves itself"
      else: "this buffer has no file yet: try 's <name>'"
    return
  try:
    buffers[current].ed.saveToFile(buffers[current].path)
    # The write is a change on disk like any other, and this is what keeps it
    # from being reported back to the one who made it.
    buffers[current].timestamp = fileStamp(buffers[current].path)
    note = ""
  except CatchableError:
    note = "cannot save " & buffers[current].path & ": " &
           getCurrentExceptionMsg()

proc saveBufferAs(buffers: var seq[BufferEntry]; current: int; path: string;
                  note: var string) =
  ## Write the buffer to `path` and let it belong there from now on. For an
  ## untitled tab that is a rename: the file it was is removed once the new
  ## one is written -- written, not moved, so it works from the config dir to
  ## any other disk.
  let old = buffers[current].path
  try:
    buffers[current].ed.saveToFile(path)
  except CatchableError:
    note = "cannot save " & path & ": " & getCurrentExceptionMsg()
    return
  if buffers[current].isLane:
    # A copy of the lane, not a move: the tab is where the setting is edited,
    # and the file under the config dir is where it is read from.
    note = "wrote " & path.extractFilename & "; " &
           laneName(buffers[current].kind) & " stays where it is"
    return
  var full = path
  try: full = expandFilename(path)
  except OSError: discard
  buffers[current].path = full
  buffers[current].ed.applyFileKind(full)
  # From here on this buffer stands for that file -- including a buffer that
  # stood for nothing until now, and one whose old file was never watched
  # because it could not be read.
  buffers[current].watch = true
  buffers[current].timestamp = fileStamp(full)
  note = ""
  if old.isUntitled and cmpPaths(old, full) != 0:
    try:
      removeFile(old)
    except CatchableError:
      note = "saved; " & old & " could not be removed"

type
  SaveOutcome = enum
    saveOver     ## nothing more to do, whether or not a file was written
    saveAsk      ## the name is taken; the answer to that decides

proc runSaveCommand(act: TermAction; buffers: var seq[BufferEntry];
                    current: int; note: var string): SaveOutcome =
  result = saveOver
  if act.arg.len == 0:
    saveCurrent(buffers, current, note)
    return
  let path = act.file
  if path.extractFilename.len == 0:
    note = "not a file name: " & act.arg
    return
  # A name that is already taken is a question, never a silent overwrite.
  if fileExists(path) and cmpPaths(path, buffers[current].path) != 0:
    return saveAsk
  saveBufferAs(buffers, current, path, note)

# ---------------------------------------------------------------------------
# Search and replace -- the commands, and the exchange a replace turns into.
# The hits live in the buffers; `Finder` is what a `next` or an answer needs to
# know to carry on.
# ---------------------------------------------------------------------------

type
  Finder = object
    term, replacement: string
    opts: SearchOptions
    replacing: bool      ## the search was started by `replace`, not by `find`
    allBuffers: bool     ## `findall` / `replaceall`: every open tab, not one
    replaced: int        ## how many replacements the running exchange made

  AskKind = enum
    askNothing
    askOverwrite   ## "<file> exists. Overwrite? [yes|no]"
    askReplace     ## "Replace? [yes|no|all|abort]"
    askReload      ## "<file> changed on disk. Reload? [yes|no]"

  Ask = object
    ## What the window is waiting to hear, and what the answer will mean. One
    ## per window, and the prompt's alone: the question is shown in the status
    ## bar, so that is the line it is answered in, whichever of the two places
    ## the command that raised it was typed in.
    kind: AskKind
    question: string
    path: string   ## askOverwrite: where the buffer would go.
                   ## askReload: which file changed under which buffer. The
                   ## file and not the tab number, because the tab list is
                   ## editable and the answer arrives some keystrokes later:
                   ## by then the tab may have been moved, or closed and
                   ## reopened somewhere else in the list.

const ReplaceQuestion = "Replace? [yes|no|all|abort]"

proc markAll(buffers: var seq[BufferEntry]; current: int; theme: Theme) =
  ## Paint every hit in every buffer. Only the buffer the finger is in has an
  ## active hit -- elsewhere a hit is just a hit, so that one glance says where
  ## `next` will land.
  for i in 0 ..< buffers.len:
    if buffers[i].search.hits.len > 0:
      buffers[i].search.mark(buffers[i].ed, theme.markerBg,
                             if i == current: theme.selBg else: theme.markerBg)

proc dropSearch(buffers: var seq[BufferEntry]) =
  for b in buffers.mitems:
    if b.search.hits.len > 0:
      b.search.clear()
      b.ed.clearMarkers()

proc searchNote(f: Finder; buffers: seq[BufferEntry]; current: int): string =
  let bs = buffers[current].search
  if bs.hits.len == 0: return "'" & f.term & "': no match in this tab"
  result = "'" & f.term & "' " & $(min(bs.active + 1, bs.hits.len)) & "/" &
           $bs.hits.len
  if f.allBuffers:
    var elsewhere = 0
    for i, b in buffers:
      if i != current: elsewhere += b.search.hits.len
    if elsewhere > 0: result.add " (+" & $elsewhere & " in other tabs)"

proc nextWithHits(buffers: seq[BufferEntry]; current: int;
                  backwards: bool): int =
  ## The next buffer along that has hits, wrapping around -- `current` itself
  ## is the last candidate, which is what makes a single-buffer search wrap
  ## instead of stopping. -1 when nothing was found anywhere.
  let n = buffers.len
  for k in 1 .. n:
    let i = ((current + (if backwards: -k else: k)) mod n + n) mod n
    if buffers[i].search.hits.len > 0: return i
  result = -1

proc runSearchCommand(act: TermAction; buffers: var seq[BufferEntry];
                      current: var int; f: var Finder; theme: Theme;
                      note: var string): bool =
  ## Start a search. True when it turned into a question -- a `replace` that
  ## found something has to ask before it touches the text.
  dropSearch(buffers)
  f = Finder()
  if act.term.len == 0:
    # `find` with nothing to look for is how the highlighting goes away again.
    note = ""
    return false
  f.term = act.term
  f.replacement = act.replacement
  f.opts = parseSearchOptions(act.opts)
  f.replacing = act.replacing
  f.allBuffers = act.allBuffers and currentFileOnly notin f.opts
  for i in 0 ..< buffers.len:
    if i == current or f.allBuffers:
      buffers[i].search.run(buffers[i].ed, f.term, f.opts, f.replacement)
  if buffers[current].search.hits.len == 0:
    let other = nextWithHits(buffers, current, backwards = false)
    if other >= 0: current = other
  markAll(buffers, current, theme)
  if buffers[current].search.hits.len == 0:
    note = "not found: " & f.term
    return false
  buffers[current].search.gotoActive(buffers[current].ed)
  note = searchNote(f, buffers, current)
  result = f.replacing

proc gotoNextMatch(buffers: var seq[BufferEntry]; current: var int;
                   f: Finder; backwards: bool; theme: Theme;
                   note: var string) =
  if f.term.len == 0:
    note = "no search yet -- try 'find <text>'"
    return
  var total = 0
  for b in buffers: total += b.search.hits.len
  if total == 0:
    # The text was edited, so the hits went with it. The term is still the one
    # that was asked for, so look again rather than answer "not found" about a
    # search nobody withdrew. The finger lands at the caret, which is where
    # this was going to move it anyway.
    for i in 0 ..< buffers.len:
      if i == current or f.allBuffers:
        buffers[i].search.run(buffers[i].ed, f.term, f.opts, f.replacement)
    if buffers[current].search.hits.len == 0:
      let other = nextWithHits(buffers, current, backwards)
      if other < 0:
        note = "not found: " & f.term
        return
      current = other
      buffers[current].search.rewind(toLast = backwards)
    markAll(buffers, current, theme)
    buffers[current].search.gotoActive(buffers[current].ed)
    note = searchNote(f, buffers, current)
    return
  if not buffers[current].search.step(backwards):
    # Off the end of this buffer: on to the next one that has something, which
    # for a search of one buffer is this one again.
    let nxt = nextWithHits(buffers, current, backwards)
    if nxt < 0:
      note = "not found: " & f.term
      return
    current = nxt
    buffers[current].search.rewind(toLast = backwards)
  markAll(buffers, current, theme)
  buffers[current].search.gotoActive(buffers[current].ed)
  note = searchNote(f, buffers, current)

proc nextPending(buffers: var seq[BufferEntry]; current: var int;
                 f: Finder): bool =
  ## Put the finger on the next hit still waiting for an answer, moving on to
  ## another buffer once this one is through. False when the exchange is over.
  if not buffers[current].search.done: return true
  if f.allBuffers:
    for i in 0 ..< buffers.len:
      if i != current and not buffers[i].search.done and
         buffers[i].search.hits.len > 0:
        current = i
        return true
  result = false

proc runAnswer(word: string; asked: var Ask; f: var Finder;
               buffers: var seq[BufferEntry]; current: var int;
               theme: Theme; note: var string): string =
  ## Act on the answer. Returns the next question, or "" when the exchange is
  ## over -- the caller arms the widget that asked with whatever comes back.
  result = ""
  case asked.kind
  of askNothing:
    note = "nothing to answer"
  of askOverwrite:
    if word.startsWith("y"):
      saveBufferAs(buffers, current, asked.path, note)
    else:
      note = "not saved"
    asked = Ask()
  of askReload:
    let path = asked.path
    let name = path.extractFilename
    asked = Ask()
    var idx = -1
    for i in 0 ..< buffers.len:
      if cmpPaths(buffers[i].path, path) == 0:
        idx = i
        break
    if idx < 0:
      # The tab was closed while the question stood. Nothing to reload into,
      # and nothing lost either -- closing it was the same answer.
      note = name & " is not open any more"
    elif word.startsWith("y"):
      reloadBuffer(buffers[idx])
      note = "reloaded " & name
    else:
      # The timestamp was taken when the question was put, so this file is not
      # asked about again until it changes once more.
      note = "kept the edits in " & name
  of askReplace:
    case word
    of "y", "yes":
      if not buffers[current].search.replaceActive(buffers[current].ed):
        # The hit is not there to be replaced: the text moved under it between
        # the question and the answer. Better to stop than to write into a
        # place that is no longer the one that was asked about.
        dropSearch(buffers)
        note = "the text changed -- search again"
        asked = Ask()
        return ""
      inc f.replaced
    of "n", "no":
      buffers[current].search.skipActive()
    of "all":
      # Every hit of this search, from the top of each buffer: `all` means the
      # ones already passed over as well.
      for b in buffers.mitems:
        if b.search.hits.len == 0: continue
        b.search.rewind(toLast = false)
        while b.search.replaceActive(b.ed): inc f.replaced
      dropSearch(buffers)
      note = "replaced " & $f.replaced
      asked = Ask()
      return ""
    of "a", "abort", "q", "quit":
      note = (if f.replaced > 0: "stopped after " & $f.replaced
              else: "nothing replaced")
      asked = Ask()
      return ""
    else:
      note = "'" & word & "'? " & ReplaceQuestion
      return ReplaceQuestion
    if nextPending(buffers, current, f):
      markAll(buffers, current, theme)
      buffers[current].search.gotoActive(buffers[current].ed)
      note = searchNote(f, buffers, current) & "  " & ReplaceQuestion
      return ReplaceQuestion
    dropSearch(buffers)
    note = "replaced " & $f.replaced
    asked = Ask()

type
  ConfigPut = enum
    ## What putting a config into the [config] tab came to.
    putNoTab     ## there is no such tab, so there was nowhere to put it
    putSame      ## the tab already says exactly this
    putDone      ## replaced

proc isShipped(kind: BufferKind; text: string): bool =
  ## Whether a lane still says exactly what the app put there. Anything else
  ## is somebody's own work, and is kept before it is replaced.
  case kind
  of bufFile: false
  of bufConfig: shippedName(text).len > 0
  of bufLayout: text == defaultLayout

proc putLane(buffers: var seq[BufferEntry]; kind: BufferKind; text: string;
             saved: var string): ConfigPut =
  ## Put `text` into a lane as an *edit*, so that Ctrl+Z in that tab brings
  ## back what was there -- which is why nothing is asked first: what this
  ## replaces is one keystroke away for as long as the tab is open. Text that
  ## was written by hand goes to a file as well, since a keystroke only lasts
  ## as long as the session does; `saved` says where, or is "" when there was
  ## nothing to save (the lane holds what the app shipped) or nowhere to save
  ## it. The main loop does the rest: it already reparses and stores a lane
  ## whenever it changed.
  saved = ""
  for b in buffers.mitems:
    if b.kind == kind:
      let old = b.ed.fullText
      if old == text: return putSame
      if not isShipped(kind, old) and old.strip.len > 0:
        saved = backupConfig(laneStem(kind), old)
      if b.ed.len > 0: b.ed.replaceRange(0, b.ed.len - 1, text)
      else: b.ed.insertText(text)
      return putDone
  result = putNoTab

proc putNote(outcome: ConfigPut; kind: BufferKind; saved, what: string;
             note: var string) =
  ## The one line all of this has to be said in.
  case outcome
  of putNoTab: note = "there is no " & laneName(kind) & " tab to put it in"
  of putSame: note = laneName(kind) & " already is " & what
  of putDone:
    note = laneName(kind) & ": " & what
    if saved.len > 0: note.add "; the edited one is in " & saved
    else: note.add "; Ctrl+Z in " & laneName(kind) & " undoes it"

proc runDefaults(buffers: var seq[BufferEntry]; note: var string) =
  ## `defaults`: put back what the app ships with -- both lanes of it, since
  ## the window one is looking at is the two of them together, and since that
  ## is what this word put back when they were one file.
  var savedConfig, savedLayout = ""
  let c = putLane(buffers, bufConfig, defaultConfig, savedConfig)
  let l = putLane(buffers, bufLayout, defaultLayout, savedLayout)
  if c == putSame and l == putSame:
    note = "both lanes already say what the app ships with"
    return
  note = "config and layout back to the defaults (" & ShippedThemes[0].name &
         ")"
  var kept: seq[string] = @[]
  if savedConfig.len > 0: kept.add savedConfig
  if savedLayout.len > 0: kept.add savedLayout
  if kept.len == 0: note.add "; Ctrl+Z in a lane undoes it"
  else:
    note.add "; the edited " & (if kept.len == 1: "one is" else: "ones are") &
             " in " & kept.join(" and ")

proc themeList(buffers: seq[BufferEntry]): string =
  ## What `theme` on its own answers: the names, what each one looks like, and
  ## which of them is up.
  result = "themes: "
  for i in 0 ..< ShippedThemes.len:
    if i > 0: result.add ", "
    result.add ShippedThemes[i].name & " (" & ShippedThemes[i].blurb & ")"
  var now = ""
  for b in buffers:
    if b.kind == bufConfig:
      now = shippedName(b.ed.fullText)
      break
  result.add "; now: " & (if now.len > 0: now else: "a config of your own")

proc runTheme(name: string; buffers: var seq[BufferEntry]; note: var string) =
  ## `theme` lists what there is, `theme <name>` puts one of them in the
  ## [config] tab. A theme is that whole lane and not a palette spliced into
  ## the text that is there, and a config that had been edited is saved off to
  ## a file first -- see `putLane`. The [layout] lane is not touched: where
  ## the panels are has nothing to do with what color they are.
  if name.len == 0:
    note = themeList(buffers)
    return
  for i in 0 ..< ShippedThemes.len:
    if ShippedThemes[i].name == name:
      # The very text `shippedName` recognizes, so that a tab holding a theme
      # is a tab nothing has to be backed up out of when the next one lands.
      var saved = ""
      putNote(putLane(buffers, bufConfig, ShippedConfigs[i], saved), bufConfig,
              saved, name, note)
      return
  note = "'" & name & "' is not one of the themes: " & themeNames()

proc runSave(act: TermAction; asked: var Ask; buffers: var seq[BufferEntry];
             current: int; note: var string) =
  ## `save`, with the question it may raise.
  case runSaveCommand(act, buffers, current, note)
  of saveOver: discard
  of saveAsk:
    asked = Ask(kind: askOverwrite, path: act.file,
                question: act.file.extractFilename &
                          " exists. Overwrite? [yes|no]")
    note = asked.question

proc runSearch(act: TermAction; asked: var Ask; f: var Finder;
               buffers: var seq[BufferEntry]; current: var int; theme: Theme;
               note: var string) =
  if runSearchCommand(act, buffers, current, f, theme, note):
    asked = Ask(kind: askReplace, question: ReplaceQuestion)
    note = note & "  " & ReplaceQuestion

proc harddiskCheck(buffers: var seq[BufferEntry]; current: var int;
                   asked: var Ask; focus: var string; note: var string): bool =
  ## Has anybody else written one of the open files? A compiler that formatted
  ## one, a `git checkout`, an edit made in another window: the editor is not
  ## told about any of it, so it asks -- a `stat` per open tab, `DiskCheckMs`
  ## apart. Returns whether anything came of it, which is what the caller
  ## needs to know to draw a frame.
  ##
  ## What is done about a file that did change depends on whether anything
  ## would be lost by taking it. A buffer with no unsaved edits is the file,
  ## and just becomes the file again -- asking about that is asking somebody
  ## to confirm the only answer. A buffer with unsaved edits is a second
  ## version of the file, and which of the two survives is nobody's decision
  ## but the user's, so that one is a question. Either way the timestamp is
  ## taken first, so a file is at most one question -- and, once answered,
  ## silent until it changes again.
  result = false
  var reloaded: seq[string] = @[]
  var vanished: seq[string] = @[]
  for i in 0 ..< buffers.len:
    if not buffers[i].watch or buffers[i].path.len == 0: continue
    let path = buffers[i].path
    let stamp = fileStamp(path)
    if stamp == buffers[i].timestamp: continue
    if not fileExists(path):
      # Deleted, or renamed away. The buffer is the last copy there is of it
      # and is worth more than the news, so it stays exactly as it is -- said
      # once, because the stamp of a file that is not there does not move
      # again until it comes back.
      buffers[i].timestamp = stamp
      vanished.add path.extractFilename
      result = true
      continue
    if not diskContentDiffers(buffers[i].ed, path):
      # The time moved and the text did not: a `touch`, or a checkout that put
      # the same bytes back. Take the new time and say nothing.
      buffers[i].timestamp = stamp
      continue
    if not buffers[i].ed.changed:
      reloadBuffer(buffers[i])
      reloaded.add path.extractFilename
      result = true
      continue
    # Two versions, one file. Only one question can be outstanding at a time,
    # so a second one waits -- and waits with its timestamp untouched, which
    # is what brings this round to it again once the first is answered.
    if asked.kind != askNothing: continue
    buffers[i].timestamp = stamp
    # Ask about the buffer the user is looking at: a question about a file
    # that is not on screen is one they cannot weigh.
    current = i
    asked = Ask(kind: askReload, path: path,
                question: path.extractFilename &
                          " changed on disk. Reload? [yes|no]")
    focus = "status"
    result = true
    break
  # The question, if there is one, is the note: it is the line that has to be
  # answered, and the reloads behind it are already on screen. A question that
  # was already standing keeps its line for the same reason -- it is still
  # waiting to be answered, and news of a reload is not worth taking it away.
  if asked.kind == askReload:
    note = asked.question
  elif asked.kind != askNothing:
    discard
  elif vanished.len > 0:
    note = vanished.join(", ") &
           (if vanished.len == 1: " is gone from disk; the buffer still has it"
            else: " are gone from disk; the buffers still have them")
  elif reloaded.len == 1:
    note = reloaded[0] & " changed on disk -- reloaded"
  elif reloaded.len > 1:
    note = $reloaded.len & " files changed on disk -- reloaded"

# ---------------------------------------------------------------------------
# The app -- everything one window knows, in one object, so that the pieces of
# the main loop below can each be a proc of their own that takes the window
# rather than a parameter list naming half of it.
# ---------------------------------------------------------------------------

type
  App = object
    width, height: int
    fonts: Table[int, Font]
    fm: FontMetrics              ## of `DefaultFontSize`: what lines measure
    panelFontSize, historyFontSize, terminalFontSize,
      statusFontSize, editorFontSize: int

    layout: Layout
    theme: Theme
    trackSpec: Track
    laneNotes: array[BufferKind, string]

    buffers: seq[BufferEntry]
    current: int
    savedTabs: string            ## `tabs.txt` as last written

    # The panels: one entry per cell the layout names, made and unmade as the
    # layout says so. `reconcileEditors` and `reconcileTerminals` keep them in
    # step with it; `activeEditor` and `activeTerm` say which of them the
    # keystrokes and the commands mean.
    editors: seq[EditorView]
    terms: seq[TerminalView]
    activeEditor, activeTerm: int
    born: Newborn                ## a panel a split has just written into the
                                 ## layout, waiting for the frame that reads
                                 ## the layout back and makes it
    status: Terminal
    tabs: TabList
    explorer: Explorer
    branches: BranchList
    history: SynEdit
    clips: ClipHistory
    comp: Completion

    focus: string
    lastActiveCell: string       ## the panel the keystrokes went to on the
                                 ## frame before this one. What tells a focus
                                 ## that moved to another panel -- where the
                                 ## file that panel was left showing is the
                                 ## one to go back to -- from a frame that
                                 ## merely opened a file in the panel already
                                 ## being typed in.
    lastCurrent: int
    lastTitle: string
    shownTab: int                ## what the tab list was last scrolled to
    tabsHadFocus: bool           ## show, and whether it had the focus then
    buttons: PanelButtons        ## those of the panel the pointer is in
    strip: ShortcutStrip         ## the keys left of the prompt
    btnSize: int
    pointerX, pointerY: int      ## where the pointer was last seen: a wheel
                                 ## event says nothing about where it was
    dragging, hovering: Splitter ## the border being dragged, and the one
                                 ## merely under the pointer

    words: WordIndex
    job: IndexJob
    finder: Finder               ## the last search
    asked: Ask                   ## what the prompt is waiting to hear about
    tracker: Tracker             ## the outstanding "where is this name?"
    grep: DirSearch              ## the `search` being written into
    diffTheme: Theme             ## the theme the diffs were painted in
    grepCell: string             ## the terminal panel it is written into
    jumps: seq[TrackHit]         ## and the places its answer named

    running: bool
    mustDraw: bool               ## a poll turned up something to show
    nextFrame: int               ## when a frame is due regardless
    nextDiskCheck: int
    windowFocused: bool

template term(app: App): untyped = app.terms[app.activeTerm].term
  ## The terminal the commands go to.

proc editorFont(app: var App): Font = app.fonts.fontForSize(app.editorFontSize)

proc endExchange(app: var App) =
  ## Only ever one question is outstanding, and anything the user starts
  ## instead of answering it withdraws it -- otherwise the next line typed
  ## would be read as an answer to something nobody can see any more.
  app.asked = Ask()
  app.status.question = ""

proc endExchange(app: var App; a: TermAction) =
  if a.kind notin {TermActionKind.noAction, TermActionKind.ctrlHover,
                   TermActionKind.ctrlClick, answer}:
    app.endExchange()

# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------

proc setPanelFont(app: var App; f: Font) =
  ## The panels that share `panelFontSize`.
  app.tabs.ed.setFont(f)
  app.explorer.ed.setFont(f)
  app.branches.ed.setFont(f)
  app.clips.setFont(f)

proc adjustFocusedFontSize(app: var App; delta: int) =
  template bump(size: untyped) =
    size = clamp(size + delta, MinFontSize, MaxFontSize)
  if app.focus.isEditor:
    bump app.editorFontSize
    let f = app.editorFont
    for i in 0 ..< app.buffers.len: app.buffers[i].ed.setFont(f)
  elif app.focus.isTerminal:
    bump app.terminalFontSize
    let f = app.fonts.fontForSize(app.terminalFontSize)
    for i in 0 ..< app.terms.len: app.terms[i].term.ed.setFont(f)
  else:
    case app.focus
    of "tabs", "explorer", "branches", "clipboard":
      bump app.panelFontSize
      app.setPanelFont(app.fonts.fontForSize(app.panelFontSize))
    of "history":
      bump app.historyFontSize
      app.history.setFont(app.fonts.fontForSize(app.historyFontSize))
    of "status":
      bump app.statusFontSize
      app.status.ed.setFont(app.fonts.fontForSize(app.statusFontSize))
    else:
      discard

proc reopenFonts(app: var App) =
  ## Dragged onto a display of another density. The logical sizes stay put
  ## and only their physical counterparts change, so every font that is
  ## already open has to be reopened at the new scale.
  for f in app.fonts.values: closeFont(f)
  app.fonts.clear()
  app.setPanelFont(app.fonts.fontForSize(app.panelFontSize))
  app.history.setFont(app.fonts.fontForSize(app.historyFontSize))
  let terminalFont = app.fonts.fontForSize(app.terminalFontSize)
  for i in 0 ..< app.terms.len: app.terms[i].term.ed.setFont(terminalFont)
  app.status.ed.setFont(app.fonts.fontForSize(app.statusFontSize))
  let f = app.editorFont
  for i in 0 ..< app.buffers.len: app.buffers[i].ed.setFont(f)
  app.fm = getFontMetrics(app.fonts.fontForSize(DefaultFontSize))

# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

proc listWidget(font: Font; actionFrom: int; closeButtons: bool): SynEdit =
  ## A panel whose rows are things rather than text: framed from `actionFrom`
  ## on, optionally with an (x) on every row, and `langNone` because a row is
  ## a label, not code to colorize.
  result = createSynEdit(font)
  result.lang = langNone
  result.setActionLines(actionFrom)
  if closeButtons: result.setCloseButtons(0)

proc migrateLayout(configText, layoutText: var string): string =
  ## A config from when the layout lived in it: move the block across before
  ## anything is parsed, and keep the file it came out of. Runs once -- what it
  ## writes has no layout in it to find the next time. Answers with what is to
  ## be said about it, "" when there was nothing to move.
  result = ""
  var taken = ""
  let rest = takeLayout(configText, taken)
  if taken.len == 0: return
  let kept = backupConfig("config", configText)
  configText = rest
  saveConfig("config.nif", configText)
  if layoutText.len == 0:
    layoutText = taken
    saveConfig("layout.nif", layoutText)
    result = "the layout moved to " & configPath("layout.nif")
  else:
    # There is a layout.nif already, so the one in the config is the older
    # of the two and nothing is lost by dropping it -- least of all here,
    # where the file it was in has just been copied.
    result = "the layout in config.nif was left behind; layout.nif has one"
  if kept.len > 0: result.add "; the config it was in is in " & kept

proc loadLanes(app: var App): tuple[configText, layoutText, moved: string] =
  ## What the window starts as: whatever was stored last time, unless it no
  ## longer works -- then the default, with the reason in the status bar. The
  ## shipped ones go through the same door first, so that a mistake in what
  ## the app itself ships is caught here and not in somebody's window.
  template notes: untyped = app.laneNotes
  reparseConfig(defaultConfig, app.theme, app.trackSpec, notes[bufConfig])
  doAssert notes[bufConfig].len == 0, notes[bufConfig]
  reparseLayout(defaultLayout, app.width, app.height, app.fm.lineHeight,
                app.layout, notes[bufLayout])
  doAssert notes[bufLayout].len == 0, notes[bufLayout]

  var configText = loadConfig("config.nif")
  var layoutText = loadConfig("layout.nif")
  let moved = migrateLayout(configText, layoutText)

  if configText.len > 0:
    reparseConfig(configText, app.theme, app.trackSpec, notes[bufConfig])
    if notes[bufConfig].len > 0:
      # Whatever was wrong with it, the stored text stays in the buffer: it is
      # what has to be corrected. Until it parses the window runs on the
      # default, which the call above left in place.
      notes[bufConfig] = configPath("config.nif") & ": " & notes[bufConfig]
  else:
    configText = defaultConfig
  if layoutText.len > 0:
    reparseLayout(layoutText, app.width, app.height, app.fm.lineHeight,
                  app.layout, notes[bufLayout])
    if notes[bufLayout].len > 0:
      notes[bufLayout] = configPath("layout.nif") & ": " & notes[bufLayout]
  else:
    layoutText = defaultLayout
  result = (configText, layoutText, moved)

proc openSession(app: var App; configText, layoutText: string) =
  ## The buffer list. The two lanes are tabs 0 and 1: editing one recolors the
  ## window on the next frame, editing the other relayouts it. The rest of the
  ## tabs are last session's.
  let font = app.editorFont
  app.current = 0
  for lane in [(bufConfig, configText), (bufLayout, layoutText)]:
    var ed = createSynEdit(font)
    # NIF is close enough to Nim for the tokenizer: parentheses, names, numbers
    # and '#' comments all land where they should -- and a quoted "#RRGGBB" is
    # a string literal, which is what makes `rfColorLiterals` draw a chip of
    # the color right beside it.
    ed.lang = langNim
    ed.flags = {rfColorLiterals}
    ed.showLineNumbers = true
    ed.setText(lane[1])
    app.buffers.add BufferEntry(ed: ed, id: freshBufferId(), path: "",
                                kind: lane[0])
  for line in loadConfig("tabs.txt").splitLines:
    let p = line.strip
    if p.len > 0 and fileExists(p):
      discard app.buffers.openFile(font, p, -1, -1)
  if paramCount() >= 1:
    app.current = app.buffers.openFile(font, paramStr(1), -1, -1)
  else:
    # The first tab that is a file, if the last session left one; otherwise the
    # config lane, which is at least something to look at.
    for i, b in app.buffers:
      if not b.isLane:
        app.current = i
        break

proc initApp(): App =
  # An editor wants the whole desktop, so ask for it -- as a window, not as
  # `fullScreen`: the menu bar and the other windows stay reachable, which
  # matters for an app whose terminal is meant to be used next to a browser.
  # The icon goes in with it: it is the bitmap a window manager shows when no
  # .desktop entry is installed to look one up in, and it has to be there
  # before the window is, or the desktop draws its placeholder first. Who the
  # window belongs to needs nothing said about it -- `createWindow` puts the
  # name of this executable in WM_CLASS, which is the "focim" a
  # StartupWMClass matches.
  let screen = createWindow(MaxWindowWidth, MaxWindowHeight,
                            icon = focimIcon())
  gUiScale = screen.uiScale
  result = App(width: screen.width, height: screen.height,
               panelFontSize: DefaultFontSize, historyFontSize: DefaultFontSize,
               terminalFontSize: DefaultFontSize,
               statusFontSize: DefaultFontSize,
               editorFontSize: DefaultFontSize,
               theme: defaultTheme(), trackSpec: defaultTrack(),
               focus: gEditorCell, shownTab: -1, pointerX: -1, pointerY: -1,
               running: true, mustDraw: true, nextFrame: getTicks(),
               nextDiskCheck: getTicks() + DiskCheckMs,
               # True to begin with, and not read from anywhere: a window is
               # normally focused the moment it is mapped, and every backend
               # says so -- but one that said so only on a *change* would
               # leave this false under a caret that then never blinked. The
               # other way round costs a window launched into the background a
               # repaint every half second until somebody clicks it, which is
               # the cheaper thing to be wrong about.
               windowFocused: true)

  # Markdown shows pictures, and on X11 the driver has no idea how to decode
  # one -- it offers somewhere to put pixels and nothing else. This is what
  # fills that in, and it does nothing at all on a backend that already draws
  # pictures. It goes after the window because there is no surface to ask
  # about before there is one.
  installPixieImages()

  let font = result.fonts.fontForSize(DefaultFontSize)
  result.fm = getFontMetrics(font)
  setWindowTitle("focim")

  # There is a terminal from the start, whether or not the layout shows one:
  # a command can be typed in the status bar and run in a panel nobody has on
  # screen, and the shell it runs in has to have been somewhere all along.
  result.terms.add TerminalView(cell: TerminalStem, term: createTerminal(font))
  result.status = createTerminal(font)
  # What makes this one the prompt rather than a second terminal: it takes the
  # questions (`question`), it resolves relative paths against the current tab
  # (`baseDir`, set every frame), and it is where a command that acts on the
  # app itself is typed.
  result.status.isPrompt = true
  # Every tab list line acts on click; in the explorer line 0 is the path
  # field, so only the listing below it does. The branch list is a tab list of
  # git's, and the history panel is a list of commands to act on: both get the
  # tab list's framed rows and its (x) -- which in the history forgets the
  # command and frees the row for a newer one.
  result.tabs = TabList(ed: listWidget(font, 0, closeButtons = true))
  result.explorer = Explorer(ed: listWidget(font, 1, closeButtons = false))
  result.branches = BranchList(ed: listWidget(font, 0, closeButtons = true))
  result.history = listWidget(font, 0, closeButtons = true)

  let (configText, layoutText, moved) = result.loadLanes()
  result.openSession(configText, layoutText)
  result.savedTabs = tabsText(result.buffers)
  # Said once the tabs exist to say it in: a move nobody asked for is a thing
  # to be told about, and both halves of it are open in front of them.
  if moved.len > 0: result.tabs.note = moved

  renderTabs(result.tabs, result.buffers)
  let p = result.buffers[result.current].path
  result.explorer.showDir(if p.len > 0: p.parentDir else: os.getCurrentDir())
  result.lastCurrent = result.current

  # The words Ctrl+Space can offer: the shipped Nimony vocabulary, whatever
  # `index` was pointed at in an earlier run, and -- from here on, a slice per
  # frame -- everything in the open buffers.
  loadWordSets(result.words)
  result.comp = initCompletion(result.editorFont)
  # What the clipboard held. Nothing reports a copy to us -- the editor's own
  # Ctrl+C goes to the system clipboard like everybody else's -- so this is
  # read rather than told, which is also what picks up a copy made in another
  # application.
  result.clips = initClipHistory(result.fonts.fontForSize(result.panelFontSize))

# ---------------------------------------------------------------------------
# The looks -- everything a turn of the loop asks before deciding whether
# there is anything to draw
# ---------------------------------------------------------------------------

proc waitForEvent(app: var App): Event =
  ## The wait comes first, because it is what paces everything after it. How
  ## long it may last is how long the work already in flight can be left
  ## alone -- an index job wants every moment it can have, a compiler
  ## answering a Ctrl+click and a program printing want noticing promptly --
  ## and never longer than the next frame is due in.
  result = default Event
  let waitMs = min(
    if app.job.active or app.grep.active: 0
    elif app.tracker.busy or anyRunning(app.terms): WorkPollMs
    else: IdleFrameMs,
    max(0, app.nextFrame - getTicks()))
  if waitEvent(result, waitMs, {WantTextInput}): app.mustDraw = true
  # Read before anything is drawn, and not in the dispatch with the rest of
  # the events: what it decides is whether the caret blinks, and the panels
  # are told that before the drawing.
  if result.kind == WindowFocusGainedEvent: app.windowFocused = true
  elif result.kind == WindowFocusLostEvent: app.windowFocused = false

proc reparseLanes(app: var App) =
  ## Pick up edits to the config buffers before resolving, so that the rects
  ## and the hit tests within one frame always come from the same layout. The
  ## buffer's own changed flag is the signal; consuming it here re-parses once
  ## per edit, whether the new config works out or not.
  for b in app.buffers.mitems:
    if b.isLane and b.ed.changed:
      let src = b.ed.fullText
      case b.kind
      of bufConfig:
        reparseConfig(src, app.theme, app.trackSpec, app.laneNotes[bufConfig])
      of bufLayout:
        reparseLayout(src, app.width, app.height, app.fm.lineHeight,
                      app.layout, app.laneNotes[bufLayout])
      of bufFile: discard
      # Stored only once it works. A file that says something the window
      # could not be built from would come back as the same complaint on
      # every start, and the text that has to be corrected is in the tab.
      if app.laneNotes[b.kind].len == 0: saveConfig(laneFile(b.kind), src)
      b.ed.markSaved()
      app.mustDraw = true

proc panelTheme(app: App): Theme =
  ## Everything that is not the text being edited draws on `panelBg` instead
  ## of on `bg`: one color for the whole window makes a tab list, a listing
  ## and a terminal look like more of the document, and the eye has to find
  ## the seams before it can find the text.
  result = app.theme
  result.bg = app.theme.panelBg

proc spreadTheme(app: var App) =
  ## The theme goes out to every widget every frame. Buffers come and go and
  ## the colors can change with any keystroke in the config, so there is no
  ## single place to hook this that could not be forgotten later.
  let pt = app.panelTheme
  # A picture with transparency in it has to be resolved against something,
  # and the something is the color the row behind it was painted with. It
  # goes out with the theme and for the theme's reason: it can change with
  # any keystroke in the config tab, and a picture still showing the last
  # theme's background would be the one thing on screen that did not follow.
  setImageBackdrop app.theme.bg
  # Whether a caret blinks is not about which panel has it but about the
  # window. Beside the theme because it goes the same way and for the same
  # reason: it is per-frame state that every widget needs and no widget can
  # work out for itself, and one that was left out of the list would sit
  # there blinking alone.
  let blinks = app.windowFocused
  for ed in [addr app.history, addr app.tabs.ed, addr app.explorer.ed,
             addr app.branches.ed, addr app.status.ed]:
    ed.theme = pt
    ed.blinks = blinks
  for t in app.terms.mitems:
    t.term.ed.theme = pt
    t.term.ed.blinks = blinks
  app.comp.theme = pt
  app.comp.setFont app.buffers[app.current].ed.getFont
  app.clips.theme = pt
  app.clips.blinks = blinks
  for b in app.buffers.mitems:
    b.ed.theme = app.theme
    b.ed.blinks = blinks

# ---------------------------------------------------------------------------
# Diff mode -- a tab compared with a revision, the differences painted on the
# file itself. The tab stays the file: the diff is decoration, never text, so
# saving, searching and the word index never meet it.
# ---------------------------------------------------------------------------

proc blend(c, bg: Color; percent: int): Color =
  ## `c` laid over `bg` at `percent` -- a tint, light enough to read code on.
  template mix(x, y: uint8): uint8 =
    uint8((x.int * percent + y.int * (100 - percent)) div 100)
  color(mix(c.r, bg.r), mix(c.g, bg.g), mix(c.b, bg.b))

proc decorateDiff(b: var BufferEntry; theme: Theme) =
  ## The hunks as the gutter and the rows show them, in the colors a `git
  ## diff` has in the terminal: green for added, yellow for changed, red for
  ## where lines were deleted.
  b.ed.clearLineDecorations()
  b.ed.clearLineTints()
  b.ed.clearPhantomRows()
  if not b.diff.on: return
  let red = theme.fg[TokenClass.Red]
  let gone = blend(red, theme.bg, 14)
  # What is gone is read, not worked on: a step dimmer than the text.
  let goneText = blend(theme.fg[TokenClass.None], theme.bg, 70)
  for h in b.diff.hunks:
    if h.kind in {hunkAdded, hunkChanged}:
      let c = if h.kind == hunkAdded: theme.fg[TokenClass.Green]
              else: theme.fg[TokenClass.Yellow]
      let tint = blend(c, theme.bg, 14)
      for l in h.line ..< h.line + h.lines:
        b.ed.addLineDecoration(l, c, decoBar)
        b.ed.setLineTint(l, tint)
    if h.kind in {hunkDeleted, hunkChanged}:
      # The lines of the base that are gone, between the lines they stood
      # between -- for a change, above the lines that replaced them, so the
      # old and the new read top to bottom. Phantom rows: drawn, never text.
      b.ed.setPhantomRows(h.line, b.diff.base[h.baseLine ..< h.baseLine + h.baseLines],
                          goneText, gone, red,
                          if h.kind == hunkDeleted: "more deleted lines"
                          else: "more replaced lines")

proc diffLabel(d: DiffView): string =
  ## What the status bar says while a tab is in diff mode -- a tinted gutter
  ## is a mystery to somebody who forgot they asked for it.
  if not d.on: return ""
  result = "diff vs " & d.rev & ": " &
    (if d.hunks.len == 0: "no changes"
     elif d.hunks.len == 1: "1 hunk"
     else: $d.hunks.len & " hunks")

proc diffOff(b: var BufferEntry) =
  b.diff = DiffView()
  b.ed.clearLineDecorations()
  b.ed.clearLineTints()

proc startDiff(app: var App; idx: int; rev: string; sha = ""): bool =
  ## Put tab `idx` in diff mode against `rev`, or move it to `rev` when it is
  ## in diff mode already. `sha` is `rev` resolved, for a caller that starts
  ## many at once. A revision that does not work leaves the tab as it was.
  template b: untyped = app.buffers[idx]
  if b.path.len == 0 or b.isLane:
    app.tabs.note = "a diff needs a file"
    return false
  let root = repoRoot(b.path)
  if root.len == 0:
    app.tabs.note = "not in a git repository"
    return false
  let rev = if rev.len == 0: "HEAD" else: rev
  let base = if sha.len > 0: loadBaseAt(root, b.path, sha)
             else: loadBase(root, b.path, rev)
  if not base.ok:
    app.tabs.note = base.error
    return false
  b.diff = DiffView(on: true, rev: rev, root: root, sha: base.sha,
                    head: headSha(root), base: base.lines, version: -1)
  result = true

proc updateDiffs(app: var App) =
  ## The hunks follow the text: recomputed after every edit, in the turn
  ## after it, so the gutter is never more than one frame behind the typing.
  ## A line diff of a few thousand lines is a millisecond; the base is not
  ## asked for again -- it only changes when HEAD does, see `checkDiffBases`.
  let themeChanged = app.theme != app.diffTheme
  app.diffTheme = app.theme
  for b in app.buffers.mitems:
    if not b.diff.on: continue
    if b.diff.version != b.ed.textVersion:
      b.diff.hunks = computeHunks(b.diff.base, textLines(b.ed.fullText))
      b.diff.version = b.ed.textVersion
      b.decorateDiff(app.theme)
      app.mustDraw = true
    elif themeChanged:
      b.decorateDiff(app.theme)

proc toggleDiff(app: var App; rev: string) =
  ## `diff` in the prompt: on against HEAD, off again; `diff <rev>` on, or
  ## moved to `rev` while it is on.
  template b: untyped = app.buffers[app.current]
  if rev.len == 0 and b.diff.on:
    b.diffOff()
    app.tabs.note = "diff off"
    return
  if app.startDiff(app.current, rev):
    app.updateDiffs()
    app.tabs.note = ""

proc checkDiffBases(app: var App) =
  ## On the disk check: has HEAD moved under a tab in diff mode? Then what its
  ## revision names may have moved too -- a commit moves `HEAD`, a checkout
  ## moves everything. One `rev-parse` per repository, not per tab. A base
  ## that no longer resolves takes the tab out of diff mode: `branch` after
  ## switching to the default branch, which has no fork to compare with.
  var heads = initTable[string, string]()
  var dropped = 0
  for i in 0 ..< app.buffers.len:
    template b: untyped = app.buffers[i]
    if not b.diff.on: continue
    if b.diff.root notin heads: heads[b.diff.root] = headSha(b.diff.root)
    let head = heads[b.diff.root]
    if head == b.diff.head: continue
    let rev = b.diff.rev
    let saved = app.tabs.note
    if app.startDiff(i, rev):
      app.tabs.note = saved
    else:
      b.diffOff()
      app.tabs.note = saved
      inc dropped
    app.mustDraw = true
  if dropped > 0:
    app.tabs.note.add (if app.tabs.note.len > 0: "; " else: "") &
      "diff off for " & $dropped & (if dropped == 1: " tab" else: " tabs")

proc showHunk(app: var App; line: int) =
  ## A click on the summary row of a block too big to show: the whole hunk in
  ## the terminal, as `git diff` would print it -- where the console
  ## highlighter colors it, and where it can be read from top to bottom.
  template b: untyped = app.buffers[app.current]
  let i = hunkAt(b.diff.hunks, line)
  if i < 0: return
  let h = b.diff.hunks[i]
  let text = b.ed.fullText.textLines
  let rel = relativePath(b.path, app.term.base)
  var listing = rel & ":" & $(h.line + 1) & ": hunk " & $(i + 1) & "/" &
            $b.diff.hunks.len & " against " & b.diff.rev & "\L"
  listing.add "@@ -" & $(h.baseLine + 1) & "," & $h.baseLines & " +" &
          $(h.line + 1) & "," & $h.lines & " @@\L"
  for k in h.baseLine ..< h.baseLine + h.baseLines: listing.add "-" & b.diff.base[k] & "\L"
  for k in h.line ..< min(h.line + h.lines, text.len): listing.add "+" & text[k] & "\L"
  if not app.term.printOutput(listing):
    app.tabs.note = "the terminal is busy; the hunk is " & $h.baseLines &
                    " lines from line " & $(h.line + 1)

proc jumpHunk(app: var App; up: bool) =
  ## `hunk next` / `hunk prev`, Alt+Down / Alt+Up: to the next hunk, round
  ## the file the way `next` goes round the matches of a search.
  app.updateDiffs()
  template b: untyped = app.buffers[app.current]
  if not b.diff.on:
    app.tabs.note = "this tab shows no diff -- try 'diff'"
    return
  let i = nextHunk(b.diff.hunks, b.ed.currentLine, up)
  if i < 0:
    app.tabs.note = "no changes against " & b.diff.rev
    return
  let h = b.diff.hunks[i]
  b.ed.gotoLine(min(h.line, b.ed.getLineCount() - 1) + 1, 0)
  app.tabs.note = "hunk " & $(i + 1) & "/" & $b.diff.hunks.len
  app.focus = gEditorCell

proc checkDisk(app: var App) =
  ## What the disk has been doing behind the window's back. Asked at its own
  ## rate rather than at whatever rate the window happens to be repainting --
  ## a window nobody is typing in draws twice a second, and one with a build
  ## printing into it draws ten times a second, and neither is a reason to
  ## stat a directory more or less often.
  if getTicks() < app.nextDiskCheck: return
  app.nextDiskCheck = getTicks() + DiskCheckMs
  if harddiskCheck(app.buffers, app.current, app.asked, app.focus,
                   app.tabs.note):
    app.mustDraw = true
  if app.explorer.refreshListing(): app.mustDraw = true
  app.checkDiffBases()
  # Only while it is shown: a listing nobody can see is two git processes
  # every couple of seconds for nothing. It catches up when it reappears.
  if app.layout.cell("branches") and
     app.branches.refreshBranches(app.buffers[app.current].path):
    app.mustDraw = true

proc stepWordIndex(app: var App) =
  ## The word index, a slice of one buffer per frame: whichever buffer the
  ## last edit left behind is caught up on before any other work, and none of
  ## it is ever felt because none of it is ever more than a couple hundred
  ## lines. `index` jobs run the same way, a few files at a time.
  for b in app.buffers.mitems:
    if b.idx.needsIndexing(b.ed):
      discard app.words.indexSlice(b.ed, b.idx)
      break
  if not app.job.active: return
  # `JobSliceMs` worth of files, and then one frame -- rather than a frame
  # per batch, which on a fast disk is a repaint of the whole window for
  # every couple of milliseconds of reading.
  let deadline = getTicks() + JobSliceMs
  while stepIndexJob(app.job, files = 32) and getTicks() < deadline:
    discard
  if app.job.active:
    app.tabs.note = app.job.progress
  else:
    let ws = doneIndexJob(app.job)
    app.words.addSet ws
    saveConfig(wordSetFile(ws.name), ws.toText)
    app.tabs.note = "indexed " & ws.name & ": " & $ws.words.len & " words" &
      (if app.job.skipped > 0: ", " & $app.job.skipped & " files unreadable"
       else: "") &
      (if app.job.truncated: ", stopped at " & $MaxIndexFiles & " files"
       else: "")
    app.job = IndexJob()

proc searchTerminal(app: var App): int =
  ## The panel the running `search` writes into, -1 once it has gone.
  result = -1
  for i in 0 ..< app.terms.len:
    if app.terms[i].cell == app.grepCell: return i

proc finishSearch(app: var App; stopped: bool) =
  let i = app.searchTerminal()
  app.grep.stop()
  if i >= 0:
    app.terms[i].term.endSearch(app.grep.summary(stopped))
  app.grepCell = ""
  app.mustDraw = true

proc startSearch(app: var App; act: TermAction) =
  ## `search` in the terminal: every file under the directory it is in. One
  ## at a time -- a second one, from any terminal, ends the first.
  if app.grep.active: app.finishSearch(stopped = true)
  # A tab with edits in it is searched as the tab has it: those are the
  # lines a click on the result will land in.
  var unsaved = initTable[string, string]()
  for b in app.buffers:
    if b.path.len > 0 and b.ed.changed: unsaved[b.path] = b.ed.fullText
  app.grep = startDirSearch(act.dir, act.pattern, parseSearchOptions(act.flags),
                            act.excludes, unsaved)
  app.grepCell = app.terms[app.activeTerm].cell
  app.term.beginSearch()
  if not app.grep.active:
    app.finishSearch(stopped = false)

proc stepSearch(app: var App) =
  ## A slice of the `search` per turn, the way an `index` job runs: its lines
  ## appear as it finds them, and the window keeps answering while it does.
  if not app.grep.active and app.grepCell.len == 0: return
  let i = app.searchTerminal()
  if i < 0:
    # The panel was closed under it: nobody is reading any more.
    app.grep.stop()
    app.grepCell = ""
    return
  if app.terms[i].term.stopSearch:
    app.finishSearch(stopped = true)
    return
  let deadline = getTicks() + JobSliceMs
  var text = ""
  while app.grep.active and getTicks() < deadline:
    text.add app.grep.step(files = 16)
  app.terms[i].term.searchOutput(text)
  if text.len > 0:
    app.nextFrame = min(app.nextFrame, getTicks() + OutputFrameMs)
  if not app.grep.active: app.finishSearch(stopped = false)

proc pollTracker(app: var App) =
  ## The compiler answers frames after the click that asked it, which is the
  ## whole point of asking in a thread -- so nothing here may assume the
  ## editor still looks the way it did when the question was put.
  app.tracker.update()
  if app.tracker.note.len > 0:
    app.tabs.note = app.tracker.note
    app.tracker.note = ""
    app.mustDraw = true
  if not app.tracker.ready: return
  app.tracker.ready = false
  app.mustDraw = true
  app.jumps = app.tracker.hits
  if app.jumps.len == 1:
    # One place is not a choice. A listing of it would be a keystroke asking
    # which of the one.
    jumpTo(app.jumps[0], app.buffers, app.current, app.editorFont, app.focus,
           app.tabs.note)
    app.jumps.setLen 0
  else:
    app.comp.choose(trackRows(app.jumps, app.tracker.project.parentDir,
                              app.buffers),
                    app.buffers[app.current].ed)
    app.focus = gEditorCell

proc saveUntitled(app: var App) =
  ## An untitled tab is written back as it changes, like the two lanes: it is
  ## the editor's own file, and what is in it was never anywhere else.
  for b in app.buffers.mitems:
    if b.ed.changed and b.path.isUntitled:
      try:
        b.ed.saveToFile(b.path)
        b.timestamp = fileStamp(b.path)
        b.ed.markSaved()
      except CatchableError:
        app.tabs.note = "cannot save " & b.path & ": " & getCurrentExceptionMsg()

proc lookAround(app: var App) =
  app.reparseLanes()
  app.spreadTheme()
  # The prompt has no directory of its own, so a relative path typed there is
  # taken to be relative to the file being edited -- the same thing that path
  # would mean written inside that file. The terminal has a `cwd` and a `cd`
  # to move it with, and keeps resolving against those.
  let p = app.buffers[app.current].path
  app.status.baseDir = if p.len > 0: p.parentDir else: os.getCurrentDir()
  # Whether or not the layout shows the panel: what was copied while it was
  # hidden is exactly what somebody goes looking for after showing it.
  if app.clips.poll(): app.mustDraw = true
  app.checkDisk()
  # What a program has printed since the last look. This is the terminal's
  # own `draw` calling, and it is made here instead because a frame that is
  # never drawn would otherwise be a frame the program was never heard in --
  # and it is exactly what it printed that has to bring the frame about.
  # Bring about, and not demand: output is the one thing here that arrives
  # in a stream rather than one at a time, and a keystroke is worth a frame
  # of its own in a way that another line of a build log is not.
  for t in app.terms.mitems:
    if t.term.update():
      app.nextFrame = min(app.nextFrame, getTicks() + OutputFrameMs)
  # A question is the prompt's business, wherever the command that raised it
  # was typed: it is shown in the status bar, so that is the line it is
  # answered in, and the focus moves there when it is put. The terminal is
  # never armed -- it is where programs run, and `yes` is one of them.
  # `runCommand` clears its own copy when it hands the answer over.
  app.status.question = app.asked.question
  # An edit that the search did not make has moved every hit behind it, so
  # the hits go, and the highlighting with them. What was typed is what the
  # user is looking at now -- not what the search found before it.
  for b in app.buffers.mitems:
    if b.search.stale(b.ed):
      b.search.clear()
      b.ed.clearMarkers()
  app.updateDiffs()
  app.stepWordIndex()
  app.stepSearch()
  app.pollTracker()

# ---------------------------------------------------------------------------
# The frame -- panels, borders, and what the event did to them
# ---------------------------------------------------------------------------

proc dragBorders(app: var App; e: var Event; lm: LayoutMetrics) =
  ## Borders, before the layout is resolved, so that a drag is in the frame
  ## it happened in rather than in the one after it. What a drag changes is
  ## the layout itself; the text of it is written back once, on the release --
  ## a buffer edited on every mouse move would be a hundred entries in the
  ## undo stack and a reparse for each of them. An event the drag took is
  ## cleared, so no panel sees it.
  case e.kind
  of MouseDownEvent:
    if e.button == LeftButton:
      let s = app.layout.splitterAt(lm, e.x, e.y)
      if s.found:
        app.dragging = s
        e = default Event
  of MouseMoveEvent:
    if app.dragging.found:
      discard app.layout.dragTo(lm, app.dragging, e.x, e.y)
      e = default Event
    else:
      app.hovering = app.layout.splitterAt(lm, e.x, e.y)
  of MouseUpEvent:
    if app.dragging.found:
      # The tab is the file, so this is where a drag ends up.
      putLayout(app.buffers, app.layout)
      app.dragging = Splitter()
      e = default Event
  of WindowFocusLostEvent:
    # A button released over another window is a release this one never
    # hears about, and a border that went on following the pointer after
    # that would be a window that resizes itself while nobody is looking.
    app.dragging = Splitter()
  else: discard

proc pickActivePanels(app: var App; cells: Table[string, Rect]) =
  ## Which panel the keystrokes are going to, and which buffer that panel is
  ## showing. Everything after this that reaches for `buffers[current].ed` --
  ## a clipping pasted into it, a completion, a jump to a definition, the
  ## line the status bar reports -- means this panel and no other, so its seat
  ## is the one the buffer wears from here to the end of the frame. The panels
  ## that are merely drawn borrow the buffer across their own `draw` and hand
  ## it straight back; see `drawEditors`.
  ##
  ## `current` and the active panel's `buf` are one fact written down twice,
  ## and the panel is the copy that is written *to*: a file opened anywhere
  ## -- the explorer, `open`, a Ctrl+click into another file, a search that
  ## ran on through the buffers -- moves `current` and has nothing else to
  ## remember. The panel is read back only when the focus has moved to a
  ## different one, which is the one moment it knows something `current` does
  ## not: which file was left in it.
  for i in 0 ..< app.editors.len:
    if app.editors[i].cell == app.focus: app.activeEditor = i
  if app.activeEditor >= app.editors.len: app.activeEditor = 0
  if app.editors.len > 0:
    template active: untyped = app.editors[app.activeEditor]
    gEditorCell = active.cell
    gEditorSlot = active.slot
    if gEditorCell != app.lastActiveCell:
      # By cell and not by index: panels come and go with the layout, so the
      # index of the one being typed in moves without the focus going
      # anywhere. A panel whose file has since been closed keeps `current`
      # as it stands rather than showing nothing.
      app.lastActiveCell = gEditorCell
      let b = app.buffers.indexOfId(active.buf)
      if b >= 0: app.current = b
    active.buf = app.buffers[app.current].id
    app.buffers[app.current].ed.enter active.slot
  for i in 0 ..< app.terms.len:
    if app.terms[i].cell == app.focus: app.activeTerm = i
  if app.activeTerm >= app.terms.len: app.activeTerm = 0
  if app.terms[app.activeTerm].cell notin cells:
    # The layout is not showing the terminal the commands were going to, so
    # they go to one it does show.
    for i in 0 ..< app.terms.len:
      if app.terms[i].cell in cells:
        app.activeTerm = i
        break
  gTerminalCell = app.terms[app.activeTerm].cell

proc showInActivePanel(app: var App) =
  ## `pickActivePanels` again, for a file picked further down the frame. The
  ## bit that matters is the seat: the panel draws `buffers[current]` below
  ## whatever `current` has become by then, so a buffer still sitting in some
  ## other panel's seat is drawn at that panel's line for one frame before the
  ## top of the next one puts it right. `openFile` takes the seat itself,
  ## which leaves the tab list -- the one place that makes a buffer current
  ## without opening it.
  if app.editors.len > 0:
    app.editors[app.activeEditor].buf = app.buffers[app.current].id
    app.buffers[app.current].ed.enter app.editors[app.activeEditor].slot

proc wheelPanel(app: var App; under: string; delta: int) =
  ## The wheel turns whatever it is pointing at, focused or not -- reaching
  ## for the wheel is not a decision to type there.
  case under
  of "tabs": app.tabs.ed.wheelScroll(delta)
  of "explorer": app.explorer.ed.wheelScroll(delta)
  of "branches": app.branches.ed.wheelScroll(delta)
  of "history": app.history.wheelScroll(delta)
  of "clipboard": app.clips.wheelScroll(delta)
  of "status": app.status.ed.wheelScroll(delta)
  else:
    if under.isEditor:
      # Scrolling is the panel's own affair and not the buffer's, so the
      # panel takes its seat for as long as it takes to scroll it.
      let i = app.editors.viewOf(under)
      let b = if i >= 0: app.buffers.indexOfId(app.editors[i].buf) else: -1
      if b >= 0:
        app.buffers[b].ed.enter app.editors[i].slot
        app.buffers[b].ed.wheelScroll(delta)
        if b == app.current:
          app.buffers[b].ed.enter app.editors[app.activeEditor].slot
    elif under.isTerminal:
      for t in app.terms.mitems:
        if t.cell == under: t.term.ed.wheelScroll(delta)

proc splitPanelAt(app: var App; panel: string; sideways: bool) =
  ## What the split buttons do, and what `split` does in the prompt -- one
  ## description of it, since they are the same act. It comes down to an edit
  ## of the layout, which the next frame reads back and turns into a panel.
  let stem = stemOf(panel)
  if stem.len == 0:
    app.tabs.note = panel & " is not a panel there can be two of"
  elif panelsOf(app.layout.cellNames, stem).len >= MaxViews:
    app.tabs.note = "at most " & $MaxViews & " " & stem & " panels"
  else:
    let fresh = freeName(app.layout.cellNames, stem)
    if app.layout.splitCell(panel, fresh, sideways):
      app.born = Newborn(cell: fresh, parent: panel)
      putLayout(app.buffers, app.layout)
      # The panel asked for is the one to type in, so it takes the
      # keystrokes. It exists from the next frame, when the layout is read
      # back -- and for exactly that long `focus` names a cell that is not
      # there yet, which is what `focus notin cells` is already for.
      app.focus = fresh

proc closePanelAt(app: var App; panel: string) =
  ## The (x) button, and `unsplit` in the prompt.
  if panel.isEditor and panelsOf(app.layout.cellNames, EditorStem).len == 1:
    app.tabs.note = "the last editor panel stays: there would be nowhere " &
                    "to type the layout back"
  elif app.layout.removeCell(panel):
    putLayout(app.buffers, app.layout)
    if app.focus == panel: app.focus = gEditorCell

proc explorerEnter(app: var App) =
  ## Enter in the explorer: on the path line it goes where the line says, or
  ## takes the first match of the filter; on an entry it activates the entry.
  let line = app.explorer.ed.currentLine
  var idx = line - 1
  if line == 0:
    let full = resolveIn(app.explorer.base, app.explorer.ed.getLineText(0))
    if full.len > 0 and dirExists(full):
      app.explorer.showDir(full)
      return
    elif full.len > 0 and fileExists(full):
      app.current = app.buffers.openFile(app.editorFont, full, -1, -1)
      app.focus = gEditorCell
      return
    # A partial name accepts the first match.
    idx = 0
  if idx < app.explorer.entries.len:
    app.explorer.activateEntry(idx, app.buffers, app.current, app.editorFont,
                               app.focus, app.term.cwd, app.tabs.note)

proc newTab(app: var App) =
  ## Ctrl+N: a new tab onto a new file, `untitled-N.txt` in the config dir.
  ## A file and not a buffer with no file behind it: it saves itself as it is
  ## typed (see `saveUntitled`), the session reopens it, and closing it loses
  ## nothing -- `s <name>` is what moves it to where it belongs.
  var taken: seq[string] = @[]
  for b in app.buffers: taken.add b.path
  let path = freshUntitled(taken)
  if path.len == 0:
    app.tabs.note = "cannot write " & untitledDir()
    return
  app.current = app.buffers.openFile(app.editorFont, path, -1, -1)
  app.showInActivePanel()
  app.focus = gEditorCell

proc prepareCommand(app: var App; cells: Table[string, Rect]; cmd: string) =
  ## Ctrl+P and Ctrl+F: the prompt, with the command already typed.
  if "status" in cells:
    app.endExchange()
    prepareCommand(app.status, app.buffers, app.current, cmd, app.tabs.note)
    app.focus = "status"
  else:
    # A layout without a status bar has nowhere to type it.
    app.tabs.note = "no 'status' cell in the layout"

proc runShortcut(app: var App; sc: Shortcut; cells: Table[string, Rect];
                 up = false; clicked = false): bool =
  ## What a shortcut of the table in `shortcuts.nim` does, pressed or clicked
  ## on the strip: the same thing either way. False for one that means
  ## nothing where the focus is, which leaves the key to the panel.
  result = true
  case sc
  of scSave:
    saveCurrent(app.buffers, app.current, app.tabs.note)
  of scOpen:
    # "Quick open", for the muscle memory every other editor has trained:
    # the prompt, with the command already typed, so that the file name is
    # all that is left to do. It is the ordinary `open` command -- Tab
    # completes it and Enter runs it like any other.
    app.prepareCommand(cells, "open ")
  of scFind:
    # The same quick way in as Ctrl+P, for the other command one reaches
    # for without thinking. `find ` and not `f `: the long name is the one
    # that says what the line is about while it is being typed.
    app.prepareCommand(cells, "find ")
  of scNew:
    app.newTab()
  of scClose:
    # Close the current tab by deleting its line, so that it goes through
    # the tab list's undo stack like a hand-made deletion would.
    app.tabs.ed.gotoLine(app.current + 1, 0)
    app.tabs.ed.deleteLine()
  of scBigger, scSmaller:
    app.adjustFocusedFontSize(if sc == scSmaller: -1 else: 1)
  of scComplete:
    if not app.focus.isEditor: return false
    app.comp.show(app.words, app.buffers[app.current].ed)
    if not app.comp.active:
      app.tabs.note = if app.comp.prefix.len > 0:
                        "no word starts with '" & app.comp.prefix & "'"
                      else: "no words indexed yet"
  of scHunk:
    # Only in diff mode: anywhere else the keys stay what SynEdit makes of
    # them. A click means the file on screen wherever the focus is.
    if not app.buffers[app.current].diff.on or
       not (clicked or app.focus.isEditor):
      return false
    app.jumpHunk(up)

proc handleKey(app: var App; e: var Event; cells: Table[string, Rect]) =
  ## The keys that mean something to the window rather than to the panel
  ## that has the focus. Every one of them consumes the event.
  let cmd = CtrlPressed in e.mods or GuiPressed in e.mods
  var sc: Shortcut
  if matchShortcut(e, sc) and
     app.runShortcut(sc, cells, up = e.key == KeyUp):
    e = default Event
    return
  if e.key == KeyF3:
    # What every other editor puts there, and the reason `next` and `prev`
    # do not have to be typed to walk a search. Moving the finger while a
    # replace was asking about a match would answer for a different one,
    # so it withdraws the question like any other command.
    app.endExchange()
    gotoNextMatch(app.buffers, app.current, app.finder,
                  ShiftPressed in e.mods, app.theme, app.tabs.note)
    app.focus = gEditorCell
  elif cmd and e.key in {Key1 .. Key9} and app.focus.isEditor and
       "clipboard" in cells:
    # The panel is numbered, so a row is taken by its number rather than by
    # being selected first. Nothing has to be up, nothing has to be aimed
    # at, and the arrow keys stay where they belong.
    let text = app.clips.entry(ord(e.key) - ord(Key1) + 1)
    if text.len > 0: app.buffers[app.current].ed.insertText(text)
  elif app.focus.isEditor and
       app.comp.handleKey(e, app.buffers[app.current].ed):
    # While the listing is up a few keys belong to it. Everything else --
    # letters, backspace, the arrows sideways -- goes to the editor as
    # usual and narrows the listing through the prefix.
    let pick = app.comp.chosen
    if pick >= 0 and pick < app.jumps.len:
      # A listing of places rather than of words: taking a row goes there.
      jumpTo(app.jumps[pick], app.buffers, app.current, app.editorFont,
             app.focus, app.tabs.note)
      app.jumps.setLen 0
  elif e.key == KeyEnter and app.focus == "tabs":
    # Enter activates a tab instead of inserting a newline.
    let idx = app.tabs.ed.currentLine
    if idx < app.buffers.len:
      app.current = idx
      app.showInActivePanel()
      app.focus = gEditorCell
  elif e.key == KeyEnter and app.focus == "explorer":
    app.explorerEnter()
  else:
    return
  e = default Event

proc handleEvent(app: var App; e: var Event; cells: Table[string, Rect]) =
  case e.kind
  of QuitEvent, WindowCloseEvent:
    app.running = false
  of WindowResizeEvent, WindowMetricsEvent:
    app.width = e.x
    app.height = e.y
    if e.kind == WindowMetricsEvent and e.uiScale > 0 and
       e.uiScale != gUiScale:
      gUiScale = e.uiScale
      app.reopenFonts()
  of MouseMoveEvent:
    app.pointerX = e.x
    app.pointerY = e.y
  of MouseWheelEvent:
    # Consumed, so the focused panel does not scroll along with the one under
    # the pointer.
    app.wheelPanel(cells.hitTest(app.pointerX, app.pointerY).name, e.y)
    e = default Event
  of MouseDownEvent:
    app.pointerX = e.x
    app.pointerY = e.y
    app.comp.dismiss()
    let hit = cells.hitTest(e.x, e.y)
    if hit.name.len > 0:
      app.focus = hit.name
  of TextInputEvent:
    # Ctrl+Space, Ctrl+<digit> and Ctrl+<letter> are commands, not text. X11
    # hands the app both, and the character would land in the buffer right
    # where the paste is about to go -- or, for a letter, as the control
    # character it stands for; the key event has already dealt with it.
    if CtrlPressed in e.mods and e.text[1] == '\0' and
       (e.text[0] in {' ', '1'..'9'} or e.text[0] < ' '):
      e = default Event
  of KeyDownEvent:
    app.handleKey(e, cells)
  else: discard

proc pressPanelButtons(app: var App; e: var Event;
                       cells: Table[string, Rect]) =
  ## The panel the pointer is in offers three buttons in its top right
  ## corner. Tested before a single widget is drawn, and the event is taken
  ## away when one of them is hit: a click on a button is not also a click in
  ## the text under it.
  app.btnSize = max(scaledPx(9), app.fm.lineHeight - scaledPx(3))
  let over = cells.hitTest(app.pointerX, app.pointerY)
  if over.name.len == 0:
    app.buttons = PanelButtons()
  else:
    app.buttons = PanelButtons(cell: over.name, hot: btnNone,
                               splits: over.name.isEditor or
                                       over.name.isTerminal)
    app.buttons.hot = app.buttons.buttonAt(cells[over.name], app.btnSize,
                                           app.pointerX, app.pointerY)
  if e.kind == MouseDownEvent and e.button == LeftButton and
     app.buttons.hot != btnNone:
    let cell = app.buttons.cell
    case app.buttons.hot
    of btnRight, btnDown: app.splitPanelAt(cell, app.buttons.hot == btnRight)
    of btnClose: app.closePanelAt(cell)
    of btnNone: discard
    app.buttons.hot = btnNone
    e = default Event

proc pressShortcutKeys(app: var App; e: var Event;
                       cells: Table[string, Rect]) =
  ## The strip of keys left of the prompt, laid out for this frame and
  ## clicked before anything else sees the click: before the focus moves to
  ## the status bar, so that a key acts on the panel one was in -- `+` makes
  ## that panel's text bigger, the space bar completes in that editor -- just
  ## as its shortcut would.
  if "status" notin cells:
    app.strip = ShortcutStrip(hot: -1)
    return
  let diffOn = app.current < app.buffers.len and
               app.buffers[app.current].diff.on
  app.strip = layoutStrip(cells["status"], diffOn)
  if e.kind == MouseDownEvent and e.button == LeftButton:
    let k = app.strip.keyAt(e.x, e.y)
    if k >= 0:
      discard app.runShortcut(app.strip.keys[k].sc, cells, clicked = true)
      e = default Event

proc followActiveTab(app: var App) =
  ## The list follows the active tab, which is chosen anywhere but here:
  ## Ctrl+W, a file opened from the explorer, a jump to a definition. While
  ## the list has the focus its own caret leads and the view goes with it --
  ## the arrows are for reading down the list, and a list that snapped back
  ## after every one of them could not be read. The moment it has not, the
  ## row that matters is the active tab again, so it goes to the middle,
  ## where it can be seen along with what is around it.
  ##
  ## The caret goes with it, rather than the view alone: it is where the
  ## arrow keys will start from when the list is next stepped into, and
  ## leaving it behind would make the first keystroke there jump the view
  ## back to wherever the list had been left.
  let focused = app.focus == "tabs"
  if app.current == app.shownTab and focused == app.tabsHadFocus: return
  if not focused and app.current < app.tabs.names.len:
    app.tabs.ed.gotoLine(app.current + 1, 0)
    app.tabs.ed.centerLine(app.current)
  # Not counted as done until the list has been drawn once: before that it
  # has no height, so there is no middle to put anything in yet.
  if app.tabs.ed.span > 0:
    app.shownTab = app.current
    app.tabsHadFocus = focused

proc drawTabs(app: var App; e: Event; cells: Table[string, Rect]) =
  ## The tab list -- its lines ARE the open tabs. The bookkeeping runs even
  ## when the list is hidden, because Ctrl+W still edits its buffer.
  if app.tabs.names != displayNames(app.buffers):
    renderTabs(app.tabs, app.buffers)
  decorateTabs(app.tabs, app.buffers, app.current)
  var act = EditAction(kind: noAction)
  if "tabs" in cells:
    app.followActiveTab()
    act = app.tabs.ed.draw(e, cells["tabs"], app.focus == "tabs")
  if act.kind == closeLine:
    # The (x) deletes the line, so closing by button and closing by hand
    # end up in the same undo stack.
    app.tabs.ed.gotoLine(act.line + 1, 0)
    app.tabs.ed.deleteLine()
  applyTabEdits(app.tabs, app.buffers, app.current, app.editorFont)
  if e.kind == MouseDownEvent and app.focus == "tabs" and
     act.kind != closeLine:
    let idx = app.tabs.ed.currentLine
    if idx < app.buffers.len:
      app.current = idx
      # The tab list picks the file for the panel the keystrokes were going
      # to, and leaves the other panels showing what they were showing.
      app.showInActivePanel()
      app.focus = gEditorCell

proc drawExplorer(app: var App; e: Event; area: Rect) =
  ## The explorer -- a flat directory listing, line 0 is the path/filter
  ## field.
  let focused = app.focus == "explorer"
  discard app.explorer.ed.draw(e, area, focused)
  if not focused: return
  if e.kind == MouseDownEvent:
    let line = app.explorer.ed.currentLine
    if line > 0 and line - 1 < app.explorer.entries.len:
      app.explorer.activateEntry(line - 1, app.buffers, app.current,
                                 app.editorFont, app.focus, app.term.cwd,
                                 app.tabs.note)
  else:
    let header = app.explorer.ed.getLineText(0)
    if header != app.explorer.header:
      app.explorer.applyHeader(header)
    elif app.explorer.ed.getLineCount() != app.explorer.entries.len + 1:
      # The listing itself is not editable; put it back.
      app.explorer.renderExplorer(app.explorer.header, app.explorer.ed.cursor)

proc followCurrent(app: var App) =
  ## The window title says which buffer is in the editor, out of the same
  ## names the tab list shows -- so the two cannot disagree, and a name that
  ## had to be made unique ("doc/config.md") is unique in the title too.
  ##
  ## Driven by what *is* current rather than set wherever something gets
  ## opened: the current buffer also changes by switching tabs, by closing
  ## one, and by undoing that, and none of those go through an open.
  let title =
    if app.current < app.tabs.names.len: app.tabs.names[app.current] else: ""
  if title != app.lastTitle:
    app.lastTitle = title
    setWindowTitle(if title.len > 0: "focim - " & title else: "focim")
  # The explorer follows the directory of the active file.
  if app.current != app.lastCurrent:
    app.lastCurrent = app.current
    let p = app.buffers[app.current].path
    if p.len > 0 and normDir(p.parentDir) != app.explorer.dir:
      app.explorer.showDir(p.parentDir)

proc openTouched(app: var App) =
  ## After a switch the tabs become what the branch is about: the files it
  ## changed since it left the default branch, each at the first line it
  ## changed there, and in place of everything else that was open. Kept
  ## whatever happens: the file in front, the two lanes, and any tab with
  ## edits in it -- a branch switch is no reason to lose typing. On the
  ## default branch itself nothing was changed, and the tabs stay as they are.
  ##
  ## The files are opened first and the others closed after, by deleting
  ## their lines in the tab list: closing a tab is an edit there, so Ctrl+Z
  ## in the list brings back what the switch took away. (Opening one is not
  ## -- the list is rebuilt for that -- which is why it goes first.)
  let touched = touchedFiles(app.branches.branches.root, MaxTouchedTabs)
  if touched.len == 0: return
  let font = app.editorFont
  let front = app.buffers[app.current].path
  var keep: seq[string] = @[]
  for t in touched:
    keep.add t.path
    if t.path == front: continue
    discard app.buffers.openFile(font, t.path, t.line, 0)
  # And they come up showing what the branch did to them: a switch is a
  # review of the branch. The fork point is the same for all of them, so it
  # is asked for once.
  let said0 = app.tabs.note
  let (fork, _) = resolveRev(app.branches.branches.root, "branch")
  if fork.len > 0:
    for i in 0 ..< app.buffers.len:
      if app.buffers[i].path in keep and
         (not app.buffers[i].diff.on or app.buffers[i].diff.rev == "branch"):
        discard app.startDiff(i, "branch", fork)
  app.tabs.note = said0
  renderTabs(app.tabs, app.buffers)
  var closing = 0
  for i in countdown(app.buffers.high, 0):
    let b = app.buffers[i]
    if i == app.current or b.isLane or b.path.len == 0 or b.ed.changed or
       b.path in keep:
      continue
    app.tabs.ed.gotoLine(i + 1, 0)
    app.tabs.ed.deleteLine()
    inc closing
  # Which clears the note; what the switch said there is still to be said.
  let said = app.tabs.note
  applyTabEdits(app.tabs, app.buffers, app.current, font)
  app.tabs.note = said & "; " & $touched.len & " files of the branch open" &
    (if closing > 0: ", " & $closing & " others closed" else: "")

proc drawBranches(app: var App; e: Event; area: Rect) =
  ## The branch list -- the branches of the current file's repository. It
  ## follows the current file the way the explorer does, and is asked again
  ## on the disk check for the branches somebody made or switched in the
  ## terminal.
  template bl: untyped = app.branches
  let file = app.buffers[app.current].path
  if file != bl.file:
    discard bl.refreshBranches(file)
  decorateBranches(bl)
  let focused = app.focus == "branches"
  let act = bl.ed.draw(e, area, focused)
  if act.kind == closeLine:
    discard bl.actOnBranch(act.line, delete = true, app.tabs.note)
  elif e.kind == MouseDownEvent and focused and e.button == LeftButton and
       e.clicks == 1 and e.x < area.x + area.w - ScrollBarWidth:
    # The row under the pointer and not the caret's: a click below the last
    # branch puts the caret on it, and must not check it out.
    let lineH = fontLineSkip(bl.ed.getFont)
    let row = if lineH > 0:
                bl.ed.firstLine.int + (e.y - area.y - bl.ed.padding.y) div lineH
              else: -1
    if e.y - area.y >= bl.ed.padding.y and row < bl.branches.names.len:
      if bl.actOnBranch(row, delete = false, app.tabs.note):
        app.openTouched()
        # The files under the tabs are another branch's now; ask the disk at
        # once rather than in a couple of seconds.
        app.nextDiskCheck = 0
      app.focus = gEditorCell
  elif bl.ed.fullText != bl.text:
    # Typed into: a branch is git's, not the list's, so it goes back.
    bl.renderBranches()

proc drawEditors(app: var App; e: Event;
                 cells: Table[string, Rect]): EditAction =
  ## The editor panels. The focused one is drawn last and its seat is left in
  ## the buffer, because everything after this -- the completion listing, the
  ## status line, the next frame's keystrokes -- means that panel's caret.
  ## The others borrow the buffer they show across their own `draw` and give
  ## it straight back. Answers with what the focused one was asked to do.
  result = EditAction(kind: noAction)
  for i in 0 ..< app.editors.len:
    if app.editors[i].cell notin cells: continue
    let b = app.buffers.indexOfId(app.editors[i].buf)
    if b < 0:
      # The file this panel was showing has been closed. It shows what the
      # active panel shows rather than nothing: a blank panel with no way to
      # put anything in it would be a hole in the window.
      app.editors[i].buf = app.buffers[app.current].id
      continue
    if i == app.activeEditor: continue
    app.buffers[b].ed.enter app.editors[i].slot
    discard app.buffers[b].ed.draw(e, cells[app.editors[i].cell], false)
    # Handed back at once when it is the buffer the focused panel is in:
    # from here to the end of the frame, `buffers[current].ed` has to mean
    # that panel's caret.
    if b == app.current:
      app.buffers[b].ed.enter app.editors[app.activeEditor].slot
  if app.editors.len > 0 and app.editors[app.activeEditor].cell in cells:
    let cell = app.editors[app.activeEditor].cell
    result = app.buffers[app.current].ed.draw(e, cells[cell],
                                              app.focus == cell)

proc runEditAction(app: var App; act: EditAction) =
  ## What a Ctrl+click or a Ctrl+hover in the editor means: a link to follow
  ## in markdown, a name to look up in Nim.
  template ed: untyped = app.buffers[app.current].ed
  case act.kind
  of ctrlClick:
    if ed.lang == langMarkdown:
      handleMarkdownCtrlClick(ed, act.pos, app.buffers, app.current,
                              app.editorFont, app.focus, app.tabs.note,
                              app.explorer)
    elif ed.lang == langNim:
      # Where is this name? Only a compiler knows, so one is asked -- and the
      # answer arrives some frames from now, in `pollTracker`.
      startTrack(app.tracker, app.trackSpec, ed, act.pos,
                 app.buffers[app.current].path, app.tabs.note)
  of ctrlHover:
    if ed.lang == langMarkdown:
      let (_, a, b) = ed.markdownLinkAt(act.pos)
      ed.underline(a, b)
    elif ed.lang == langNim:
      # The name under the pointer is what the click would ask about, so it
      # is what gets underlined -- the same promise the markdown links make.
      let (word, a, b) = ed.wordAt(act.pos)
      if word.len > 0: ed.underline(a, b)
      else: ed.underline(-1, -1)
  of closeLine:
    discard # the editor has no close buttons
  of phantomClick:
    app.showHunk(act.line)
  of noAction:
    ed.underline(-1, -1)

proc drawClipboard(app: var App; e: Event; area: Rect) =
  ## The clipboard panel -- what the clipboard held, newest first. Drawn only
  ## when the layout shows it, which is the same thing Ctrl+<digit> checks: a
  ## row nobody can read is a row nobody can pick a number out of.
  let act = app.clips.draw(e, area, app.focus == "clipboard")
  if act.drop > 0:
    # The (x) forgets an entry -- which is how a password copied by mistake
    # stops being one keystroke away from every buffer.
    app.clips.drop act.drop
  elif act.take > 0:
    # Clicking a row pastes it and hands the caret straight back: nobody
    # clicks a clipping in order to end up in the panel.
    app.buffers[app.current].ed.insertText(app.clips.entry(act.take))
    app.focus = gEditorCell

proc drawHistory(app: var App; e: Event; cells: Table[string, Rect]) =
  ## The history panel -- its lines ARE the command list, so a click re-runs
  ## a line and the (x) deletes one. The ingest runs even when the layout
  ## leaves the panel out, so nothing typed while it was hidden goes missing.
  for t in app.terms.mitems:
    for cmd in t.term.ran: app.history.addHistoryLine(cmd)
    t.term.ran.setLen 0
  if "history" notin cells: return
  let act = app.history.draw(e, cells["history"], app.focus == "history")
  if act.kind == closeLine:
    # Same as the tab list: the button deletes the line, so closing by
    # button and closing by hand share one undo stack.
    app.history.gotoLine(act.line + 1, 0)
    app.history.deleteLine()
  elif e.kind == MouseDownEvent and app.focus == "history":
    # Only a click on the row itself re-runs it: the (x) took the branch
    # above and must not activate what it is removing.
    var cmd = app.history.getLineText(app.history.currentLine)
    if cmd.len > 0:
      discard app.term.runCommand(cmd)
      app.focus = gTerminalCell

proc runTermAction(app: var App; act: TermAction) =
  ## What a command typed into the terminal panel asks of the editor.
  case act.kind
  of openFile:
    runOpenCommand(act, app.term.base, app.buffers, app.current,
                   app.editorFont, app.focus, app.explorer, app.tabs.note)
  of saveFile:
    runSave(act, app.asked, app.buffers, app.current, app.tabs.note)
    # A command typed here may still end in a question, and the question is
    # put in the prompt -- so that is where the caret goes to answer it.
    if app.asked.question.len > 0: app.focus = "status"
  of searchText:
    runSearch(act, app.asked, app.finder, app.buffers, app.current, app.theme,
              app.tabs.note)
    if app.asked.question.len > 0: app.focus = "status"
  of gotoMatch:
    gotoNextMatch(app.buffers, app.current, app.finder, act.backwards,
                  app.theme, app.tabs.note)
  of answer:
    # Unreachable: only the prompt is ever armed with a question.
    discard
  of indexWords:
    runIndexCommand(act, app.words, app.job, app.tabs.note)
  of searchFiles:
    app.startSearch(act)
  of resetConfig, selectTheme, splitPanel, closePanel, diffMode, hunkJump:
    # Unreachable: `defaults`, `theme` and the panel commands are the
    # prompt's, and this is the terminal -- there the words are programs'
    # names.
    discard
  of ctrlHover:
    let (_, _, _, a, b) = app.term.ed.extractFilePosition(act.pos)
    app.term.ed.underline(a, b)
  of ctrlClick:
    app.term.ed.underline(-1, -1)
    handleTermCtrlClick(app.term.ed, act.pos, app.buffers, app.current,
                        app.editorFont, app.term, app.focus)
  of noAction:
    app.term.ed.underline(-1, -1)

proc drawTerminals(app: var App; e: Event; cells: Table[string, Rect]) =
  ## Every terminal panel is drawn; what one of them *says* is acted on only
  ## when it is the panel being typed in, since a command is something
  ## somebody typed.
  var act = TermAction(kind: noAction)
  for i in 0 ..< app.terms.len:
    if app.terms[i].cell notin cells: continue
    let focused = app.focus == app.terms[i].cell
    let a = app.terms[i].term.draw(e, cells[app.terms[i].cell], focused)
    if focused:
      app.activeTerm = i
      gTerminalCell = app.terms[i].cell
      act = a
  app.endExchange(act)
  app.runTermAction(act)

proc redrawStatus(app: var App) =
  ## The command has just changed what the line says about the buffer, and
  ## the prompt it left behind belongs to a terminal, not to a status bar.
  ## A tab in diff mode says so first: it is what the tinted gutter means.
  let note = laneNote(app.laneNotes, app.tabs.note)
  let label = diffLabel(app.buffers[app.current].diff)
  updateStatus(app.status, app.buffers[app.current].ed,
               app.buffers[app.current].path,
               if label.len == 0: note
               elif note.len == 0: label
               else: label & "  " & note)

proc runStatusAction(app: var App; act: TermAction) =
  ## What a command typed into the prompt asks for. A question keeps the
  ## focus there: the answer is typed into the line the question is shown in.
  ## Anything else is finished with, and the caret belongs back in the text.
  template backToText() =
    if app.asked.question.len == 0: app.focus = gEditorCell
  case act.kind
  of openFile:
    runOpenCommand(act, app.status.base, app.buffers, app.current,
                   app.editorFont, app.focus, app.explorer, app.tabs.note)
  of saveFile:
    runSave(act, app.asked, app.buffers, app.current, app.tabs.note)
    backToText()
  of searchText:
    runSearch(act, app.asked, app.finder, app.buffers, app.current, app.theme,
              app.tabs.note)
    backToText()
  of gotoMatch:
    gotoNextMatch(app.buffers, app.current, app.finder, act.backwards,
                  app.theme, app.tabs.note)
    app.focus = gEditorCell
  of answer:
    app.asked.question = runAnswer(act.word, app.asked, app.finder,
                                   app.buffers, app.current, app.theme,
                                   app.tabs.note)
    backToText()
  of indexWords:
    runIndexCommand(act, app.words, app.job, app.tabs.note)
    return
  of searchFiles:
    app.tabs.note = "search is typed in the terminal: it looks through the " &
                    "directory the terminal is in"
  of resetConfig:
    runDefaults(app.buffers, app.tabs.note)
  of selectTheme:
    runTheme(act.name, app.buffers, app.tabs.note)
  of splitPanel:
    # The panel the keystrokes were going to before they came here to be
    # typed: a command about the editor means the editor you were in.
    app.splitPanelAt(gEditorCell, act.sideways)
    return
  of diffMode:
    app.toggleDiff(act.rev)
    app.focus = gEditorCell
  of hunkJump:
    app.jumpHunk(act.up)
  of closePanel:
    app.closePanelAt(gEditorCell)
    return
  of ctrlHover, ctrlClick, noAction:
    return
  app.redrawStatus()

proc drawStatus(app: var App; e: Event; cells: Table[string, Rect]) =
  ## The status bar / prompt -- the line about the buffer is rewritten on
  ## every frame it is not being typed in. A lane that does not parse is the
  ## more urgent of the two notes: it is what the user is looking at while
  ## typing in that tab.
  if app.focus != "status":
    app.redrawStatus()
  var act = TermAction(kind: noAction)
  if "status" in cells:
    let area = cells["status"]
    let w = min(app.strip.width, area.w)
    fillRect(rect(area.x, area.y, w, area.h), app.theme.panelBg)
    app.strip.drawStrip(app.fonts.fontForSize(app.statusFontSize), app.theme)
    act = app.status.draw(e, rect(area.x + w, area.y, area.w - w, area.h),
                          app.focus == "status")
  app.endExchange(act)
  app.runStatusAction(act)

proc frameCell(app: App; cells: Table[string, Rect]; name: string) =
  ## Which panel the next keystroke goes to, said once and in one place. The
  ## frame lands in the gap the layout leaves between the cells -- half of it
  ## per side, so two neighbours cannot both claim the same pixel -- and
  ## therefore takes no room from the widget and cannot move its text.
  if name notin cells: return
  # Clamped to the window: a cell against an edge has no gap on that side,
  # and a frame drawn past it would simply not be there.
  let f = cells[name]
  let fw = scaledPx(2)
  let x0 = max(0, f.x - fw)
  let y0 = max(0, f.y - fw)
  let x1 = min(app.width - 1, f.x + f.w - 1 + fw)
  let y1 = min(app.height - 1, f.y + f.h - 1 + fw)
  drawFrame(rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1), app.theme.focusColor, fw)

proc drawOverlays(app: var App; cells: Table[string, Rect]) =
  # The completion listing, last: it goes over everything, and it can only
  # be placed once the editor has drawn the caret it hangs from.
  if app.editors.len > 0 and app.editors[app.activeEditor].cell in cells:
    app.comp.draw(app.words, app.buffers[app.current].ed,
                  cells[app.editors[app.activeEditor].cell],
                  app.focus.isEditor)
  # The buttons of the panel the pointer is in, over its content and under
  # nothing: a panel is split and closed from where it is, and a button that
  # took a corner of the text away permanently would cost every panel a
  # corner for the sake of the two seconds it is wanted.
  if app.buttons.cell.len > 0 and app.buttons.cell in cells:
    drawPanelButtons(app.buttons, cells[app.buttons.cell], app.btnSize,
                     app.theme)
  app.frameCell(cells, app.focus)
  # The tab list is framed along with the editor, not instead of it: it is
  # less a panel of its own than the editor's label, and the row it marks is
  # the buffer the keystrokes are landing in. Lighting up both says where
  # the text goes and which of the open files it goes into, in one glance.
  if app.focus.isEditor: app.frameCell(cells, "tabs")
  # The help of the key under the pointer, over all of it -- the focus
  # frames included, which would otherwise run straight through the box.
  if "status" in cells:
    app.strip.drawHelp(app.fonts.fontForSize(app.statusFontSize), app.theme,
                       cells["status"], app.width)

proc renderFrame(app: var App; e: var Event) =
  let lm = layoutMetrics(app.width, app.height, app.fm.lineHeight)
  app.dragBorders(e, lm)

  let cells = app.layout.resolve(lm)
  # The panels are whatever the layout says they are: a split writes a cell
  # into `layout.nif` and this is where that cell becomes a panel, as does
  # one typed into the file by hand.
  reconcileEditors(app.editors, app.layout.cellNames, app.buffers,
                   app.current, app.born)
  reconcileTerminals(app.terms, app.layout.cellNames,
                     app.fonts.fontForSize(app.terminalFontSize),
                     app.panelTheme, app.born)
  app.born = Newborn()
  app.pickActivePanels(cells)
  # A layout may have dropped the cell that had the focus.
  if app.focus notin cells: app.focus = gEditorCell

  # Fill background -- gaps between cells show this color as borders, so it
  # comes from the theme: `actionColor` is what the theme already uses to
  # frame things.
  fillRect(rect(0, 0, app.width, app.height), app.theme.actionColor)
  # The border under the pointer, in the colors the theme already keeps for
  # a thing that is dragged: this is a scrollbar grip by another name, and a
  # window whose panels can be pushed about has to say so before they are.
  let grip = if app.dragging.found: app.dragging else: app.hovering
  if grip.found:
    fillRect(app.layout.splitterRect(lm, grip),
             if app.dragging.found: app.theme.scrollBarActiveColor
             else: app.theme.scrollBarColor)

  app.pressShortcutKeys(e, cells)
  app.handleEvent(e, cells)
  app.pressPanelButtons(e, cells)
  app.strip.hot = app.strip.keyAt(app.pointerX, app.pointerY)

  # Widgets the layout leaves out are simply not drawn. They keep their
  # state, so they come back exactly as they were once a layout lists
  # them again.
  app.drawTabs(e, cells)
  if "explorer" in cells: app.drawExplorer(e, cells["explorer"])
  app.followCurrent()
  if "branches" in cells: app.drawBranches(e, cells["branches"])
  app.runEditAction(app.drawEditors(e, cells))
  if "clipboard" in cells: app.drawClipboard(e, cells["clipboard"])
  app.drawHistory(e, cells)
  app.drawTerminals(e, cells)
  app.drawStatus(e, cells)
  app.drawOverlays(cells)

  # Persist the session once everything that could have changed it has run --
  # and the untitled tabs with it, in the frame the typing happened in.
  app.saveUntitled()
  let tt = tabsText(app.buffers)
  if tt != app.savedTabs:
    app.savedTabs = tt
    saveConfig("tabs.txt", tt)

proc main =
  var app = initApp()
  while app.running:
    var e = app.waitForEvent()
    app.lookAround()
    # Everything above was a look; below is the frame. The loop polls far
    # more often than it draws. Waiting is free, looking at a channel is
    # nearly free, and drawing this window is neither -- it is a repaint of
    # every panel and a copy of a screenful of pixels, and on a maximized
    # window that is the whole cost of the frame. So a turn that woke up with
    # nothing new to show goes straight back to sleep. An index job's count is
    # deliberately not among the things that ask for a frame -- a job wants
    # the time the drawing would take, and twice a second is as often as a
    # number going up is worth being redrawn for.
    if not app.mustDraw and getTicks() < app.nextFrame: continue
    app.mustDraw = false
    app.renderFrame(e)

    # When the next frame is due even if nothing happens between now and
    # then. The caret is what the deadline is for, so a window whose caret has
    # stopped moving has no deadline at all -- it goes on waking to look at
    # the clipboard, and goes back to sleep without drawing until somebody
    # comes back to it. A job counting up is a reason of its own and keeps its
    # deadline either way; so does a program printing, which brings its own
    # deadline forward as it prints.
    #
    # Stamped now that the frame is done rather than when it was decided on:
    # what has to be `IdleFrameMs` apart is one caret blink and the next, and
    # `SynEdit` blinks the caret in the middle of the drawing above -- so a
    # deadline measured from before the drawing is a deadline the blink is
    # always a frame's width short of, and a caret that blinks every other
    # frame or every frame depending on how long the frame took.
    app.nextFrame =
      if app.windowFocused or app.job.active: getTicks() + IdleFrameMs
      else: high(int)
    refresh()

  for _, f in app.fonts:
    closeFont(f)
  shutdown()

main()
