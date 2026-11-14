## The window's own shortcuts, as one table: what `handleKey` dispatches on
## and what the strip of keys at the left of the prompt shows. A key on the
## strip does what its shortcut does when clicked and explains itself when
## the pointer rests on it, so the shortcuts can be found by looking rather
## than by reading -- and since both come out of the one table, the strip can
## never offer a shortcut that does not exist or leave out one that does.
##
## Only the commands of the window are here. Ctrl+Z, Ctrl+C and the rest of
## what an editor does are known to everybody who has used one, and a strip
## that listed them would hide the ones worth finding behind them.

import uirelays
import ./theme

type
  Shortcut* = enum
    scOpen, scFind, scNew, scClose, scSave, scComplete, scBigger, scSmaller,
    scHunk

  ShortcutInfo* = object
    keys*: set[KeyCode]  ## any of these, with the modifier below
    alt*: bool           ## Alt rather than Ctrl
    label*: string       ## the letter on the key; "" for one that is drawn
    title*: string       ## the first line of its help: the keys and the
                         ## command they stand for
    help*: string        ## the rest, wrapped to the help box

const Shortcuts*: array[Shortcut, ShortcutInfo] = [
  scOpen: ShortcutInfo(keys: {KeyP}, label: "P",
    title: "Ctrl+P   open <name>",
    help: "The prompt, with `open ` typed into it. A name with as much of " &
          "it left out as one can get away with: `xelim` finds " &
          "src/hexer/xelim.nim. Tab completes. A directory is shown in " &
          "the explorer."),
  scFind: ShortcutInfo(keys: {KeyF}, label: "F",
    title: "Ctrl+F   find <text>",
    help: "Searches the current file. F3 and Shift+F3 walk the matches; " &
          "`replace <new>` then asks about each one. In the terminal, " &
          "`search <text> [ext] --exclude <pattern>` searches every file " &
          "below its directory and lists the matches as lines to click."),
  scNew: ShortcutInfo(keys: {KeyN}, label: "N",
    title: "Ctrl+N   new tab",
    help: "A new file, untitled-N.txt in the config directory. It saves " &
          "itself as it is typed and comes back with the session; " &
          "`s <name>` moves it to where it belongs."),
  scClose: ShortcutInfo(keys: {KeyW}, label: "W",
    title: "Ctrl+W   close tab",
    help: "Deletes the tab's line in the tab list, so Ctrl+Z there opens " &
          "it again."),
  scSave: ShortcutInfo(keys: {KeyS}, label: "S",
    title: "Ctrl+S   save",
    help: "Writes the current file. `s <name>` on the prompt saves it " &
          "under another name."),
  scComplete: ShortcutInfo(keys: {KeySpace}, label: "",
    title: "Ctrl+Space   complete",
    help: "Lists the words that could continue what is being typed: those " &
          "of the open files, of `index <path>` and the shipped " &
          "vocabulary. Type on to narrow it, Up and Down to pick, Enter " &
          "to take it, Esc to drop it."),
  scBigger: ShortcutInfo(keys: {KeyEqual, KeyPlus}, label: "",
    title: "Ctrl++   bigger text",
    help: "Of the panel that has the focus."),
  scSmaller: ShortcutInfo(keys: {KeyMinus}, label: "",
    title: "Ctrl+-   smaller text",
    help: "In the panel that has the focus."),
  scHunk: ShortcutInfo(keys: {KeyUp, KeyDown}, alt: true, label: "",
    title: "Alt+Down / Alt+Up   next / previous change",
    help: "Only while the file is diffed -- `diff` on the prompt turns it " &
          "on and off, `diff <rev>` compares with any revision. Clicking " &
          "the row that counts more deleted lines prints the hunk in the " &
          "terminal.")
]

proc matchShortcut*(e: Event; sc: var Shortcut): bool =
  ## Which of the table's shortcuts a key press is, if any.
  let ctrl = CtrlPressed in e.mods or GuiPressed in e.mods
  let alt = AltPressed in e.mods
  for s, info in Shortcuts:
    if e.key in info.keys and (if info.alt: alt and not ctrl else: ctrl):
      sc = s
      return true
  result = false

# ---------------------------------------------------------------------------
# The strip
# ---------------------------------------------------------------------------

type
  ShortcutKey* = object
    sc*: Shortcut
    r*: Rect

  ShortcutStrip* = object
    keys*: seq[ShortcutKey]
    width*: int       ## what the strip takes from the left of its cell,
                      ## the gap before the prompt included
    hot*: int         ## the key under the pointer, -1 for none

proc layoutStrip*(area: Rect; diffOn: bool): ShortcutStrip =
  ## The keys in table order, square and as tall as the line. The hunk key
  ## is only there while the file is diffed: it is the one shortcut that
  ## means nothing otherwise, and a key that is there says the mode is on.
  result = ShortcutStrip(hot: -1)
  let size = max(4, area.h - 2)
  let gap = max(2, size div 6)
  var x = area.x + gap
  for s in Shortcut:
    if s == scHunk and not diffOn: continue
    result.keys.add ShortcutKey(sc: s,
                                r: rect(x, area.y + (area.h - size) div 2,
                                        size, size))
    x += size + gap
  result.width = x - area.x + gap

proc keyAt*(st: ShortcutStrip; x, y: int): int =
  for i, k in st.keys:
    if k.r.contains(point(x, y)): return i
  result = -1

proc drawStrip*(st: ShortcutStrip; font: Font; theme: Theme) =
  ## Muted at rest -- always there, but less than the text beside it -- and
  ## lit like a panel button under the pointer. Letters are typed; the
  ## others are drawn, so no font has to have a glyph for them.
  for i, k in st.keys:
    let hot = i == st.hot
    let fg = if hot: theme.focusColor else: theme.scrollBarColor
    if hot: fillRect(k.r, theme.scrollTrackColor)
    drawFrame(k.r, fg, 1)
    let r = k.r
    let pad = max(2, r.w div 4)
    let x0 = r.x + pad
    let x1 = r.x + r.w - 1 - pad
    let y0 = r.y + pad
    let y1 = r.y + r.h - 1 - pad
    let cx = r.x + r.w div 2
    let cy = r.y + r.h div 2
    let label = Shortcuts[k.sc].label
    if label.len > 0:
      let ext = measureText(font, label)
      discard drawText(font, r.x + (r.w - ext.w) div 2,
                       r.y + (r.h - ext.h) div 2, label, fg,
                       if hot: theme.scrollTrackColor else: theme.panelBg,
                       ext)
    else:
      case k.sc
      of scComplete:
        # The space bar: a trough.
        drawLine(x0, cy, x0, y1, fg)
        drawLine(x0, y1, x1, y1, fg)
        drawLine(x1, cy, x1, y1, fg)
      of scBigger:
        drawLine(x0, cy, x1, cy, fg)
        drawLine(cx, y0, cx, y1, fg)
      of scSmaller:
        drawLine(x0, cy, x1, cy, fg)
      of scHunk:
        # Up and down: two arrowheads.
        let arm = max(1, (x1 - x0) div 2)
        drawLine(cx - arm, y0 + arm, cx, y0, fg)
        drawLine(cx, y0, cx + arm, y0 + arm, fg)
        drawLine(cx - arm, y1 - arm, cx, y1, fg)
        drawLine(cx, y1, cx + arm, y1 - arm, fg)
        drawLine(cx, y0, cx, y1, fg)
      else: discard

proc wrapWords*(font: Font; text: string; width: int): seq[string] =
  ## `text` in lines no wider than `width`, broken between words. A word
  ## wider than that on its own gets a line of its own rather than being cut.
  result = @[]
  var line = ""
  var word = ""
  template flushWord =
    if word.len > 0:
      let cand = if line.len == 0: word else: line & " " & word
      if line.len > 0 and measureText(font, cand).w > width:
        result.add line
        line = word
      else:
        line = cand
      word = ""
  for c in text:
    if c == ' ': flushWord()
    else: word.add c
  flushWord()
  if line.len > 0: result.add line

proc drawHelp*(st: ShortcutStrip; font: Font; theme: Theme;
               above: Rect; windowW: int) =
  ## The hot key's help, in a box standing on the line the strip is in --
  ## above it, since that line is the bottom of the window -- and starting
  ## where the key does. Over everything, like the completion listing, and
  ## gone the moment the pointer leaves the key.
  if st.hot < 0 or st.hot >= st.keys.len: return
  let key = st.keys[st.hot]
  let info = Shortcuts[key.sc]
  let charW = max(1, measureText(font, "n").w)
  let lineH = max(1, measureText(font, "Ag").h)
  let pad = max(4, charW)
  let boxW = min(56 * charW, windowW - 2 * pad)
  if boxW <= 2 * pad: return
  let lines = wrapWords(font, info.help, boxW - 2 * pad)
  let boxH = (lines.len + 1) * lineH + lineH div 2 + 2 * pad
  let x = clamp(key.r.x, 0, max(0, windowW - boxW))
  let y = max(0, above.y - boxH - 2)
  let box = rect(x, y, boxW, boxH)
  fillRect(box, theme.bg)
  drawFrame(box, theme.focusColor, 1)
  var ty = y + pad
  discard drawText(font, x + pad, ty, info.title, theme.focusColor, theme.bg)
  ty += lineH + lineH div 2
  for l in lines:
    discard drawText(font, x + pad, ty, l, theme.fg[TokenClass.None],
                     theme.bg)
    ty += lineH
