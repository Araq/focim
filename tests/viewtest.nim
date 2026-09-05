## Two panels on one buffer. The text, the undo history and the colors are
## the buffer's; where the caret is and which line is at the top belong to the
## panel looking at it, and `enter` is how the buffer changes hands. What this
## watches is the seam between those two: that nothing of one panel shows in
## the other, and that a panel handed the buffer back finds its caret in front
## of the same character it left it in front of, however much was typed
## somewhere else in the meantime.
##
## Through stub relays, the way `wraptest` and `tablisttest` do -- no window,
## no driver, and a font whose every glyph is 8 pixels wide, so what lands
## where is arithmetic.
import std/strutils
import uirelays/[screen, coords, input]
import focim/[synedit, theme]

const GlyphW = 8

var drawn: seq[tuple[x, y: int, text: string]]

fontRelays = FontRelays(
  openFont: proc (path: string; size: int; style: FontStyles;
                  metrics: var FontMetrics): Font =
    metrics = FontMetrics(ascent: 12, descent: 4, lineHeight: 16)
    Font(1),
  closeFont: proc (f: Font) = discard,
  getFontMetrics: proc (f: Font): FontMetrics =
    FontMetrics(ascent: 12, descent: 4, lineHeight: 16),
  measureText: proc (f: Font; text: string): TextExtent =
    TextExtent(w: text.len * GlyphW, h: 16),
  drawText: proc (f: Font; x, y: int; text: string;
                  fg, bg: Color): TextExtent =
    if text.len > 0: drawn.add (x, y, text)
    TextExtent(w: text.len * GlyphW, h: 16))

drawRelays = DrawRelays(
  fillRect: proc (r: Rect; color: Color) = discard,
  drawLine: proc (x1, y1, x2, y2: int; color: Color) = discard,
  drawPoint: proc (x, y: int; color: Color) = discard,
  loadImage: proc (path: string): Image = Image(0),
  freeImage: proc (img: Image) = discard,
  drawImage: proc (img: Image; src, dst: Rect) = discard)

var m: FontMetrics
let font = openFont("", 16, m)

var failures = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc equals(name: string; got, want: string) =
  check(name, got == want, "got '" & got & "' want '" & want & "'")

# Ten lines, each naming its own number, so what a panel is looking at can be
# read off what was drawn.
proc tenLines(): string =
  for i in 1..10: result.add "line " & $i & "\L"

# A window four rows high: the panels see different parts of the same text.
const Area = Rect(x: 0, y: 0, w: 400, h: 4 * 16)

var e = default(Event)

proc newBuffer(): SynEdit =
  result = createSynEdit(font, defaultTheme())
  result.lang = langNone
  result.setText(tenLines())
  # A panel that has never drawn does not yet know how many rows it has, and
  # `gotoLine` centres the line it is sent to on a guess when it does not.
  # One frame each, and both of them know.
  for slot in [1, 0]:
    result.enter slot
    discard result.draw(e, Area, focused = true)

proc shown(): string =
  ## The lines that were drawn, top to bottom.
  var ys: seq[int] = @[]
  var rows: seq[string] = @[]
  for d in drawn:
    let k = ys.find(d.y)
    if k < 0:
      ys.add d.y
      rows.add d.text
    else:
      rows[k].add d.text
  result = rows.join("/")

proc frame(s: var SynEdit; slot: int; focused = true) =
  ## A frame drawn by panel `slot`, and nobody else. Two of them, in fact:
  ## the widget learns how many rows it has by drawing them, so a view that
  ## has just been sent somewhere settles on the frame after.
  s.enter slot
  discard s.draw(e, Area, focused)
  drawn.setLen 0
  discard s.draw(e, Area, focused)

echo "two panels, one buffer:"

block: # they keep their own place in the text
  var ed = newBuffer()
  ed.enter 0
  ed.gotoLine 1, 0
  frame(ed, 0)
  equals("the first panel is at the top", shown(),
         "line 1/line 2/line 3")
  ed.enter 1
  ed.gotoLine 9, 0
  frame(ed, 1)
  equals("the second one is where it was sent", shown(),
         "line 8/line 9/line 10")
  frame(ed, 0)
  equals("and the first one has not moved", shown(),
         "line 1/line 2/line 3")
  ed.enter 1
  check("each keeps its own caret", ed.currentLine == 8, $ed.currentLine)
  ed.enter 0
  check("and its own line", ed.currentLine == 0, $ed.currentLine)

block: # scrolling one does not scroll the other
  var ed = newBuffer()
  frame(ed, 0)
  ed.enter 1
  ed.wheelScroll -3
  frame(ed, 1)
  let below = shown()
  frame(ed, 0)
  equals("scrolling the second panel leaves the first at the top", shown(),
         "line 1/line 2/line 3")
  check("and the second one is further down", below != shown(), below)

block: # what one types, the other sees
  var ed = newBuffer()
  ed.enter 1
  ed.gotoLine 9, 0
  frame(ed, 1)
  ed.enter 0
  ed.gotoLine 1, 0
  ed.insertText "typed "
  frame(ed, 0)
  check("what is typed in one panel is in the buffer",
        shown().startsWith("typed line 1"), shown())
  frame(ed, 1)
  equals("and shows in the other", shown(), "line 8/line 9/line 10")
  ed.enter 1
  equals("whose caret is still in front of the same character",
         ed.getLineText(ed.currentLine), "line 9")
  check("having been carried along by the edit above it",
        ed.cursor == "typed ".len + len("line 1\Lline 2\Lline 3\Lline 4\L" &
                                        "line 5\Lline 6\Lline 7\Lline 8\L"),
        $ed.cursor)

block: # and what one deletes
  var ed = newBuffer()
  ed.enter 1
  ed.gotoLine 9, 0
  let was = ed.cursor
  ed.enter 0
  ed.replaceRange(0, len("line 1\L") - 1, "")
  ed.enter 1
  check("a line deleted above a panel pulls its caret up with it",
        ed.cursor == was - len("line 1\L"), $ed.cursor & " was " & $was)
  equals("and it is still on the line it was on",
         ed.getLineText(ed.currentLine), "line 9")
  frame(ed, 1)
  check("and that is the line it draws", shown().contains("line 9"), shown())

block: # a caret inside what was deleted lands where the text was
  var ed = newBuffer()
  ed.enter 1
  ed.gotoLine 3, 2
  ed.enter 0
  ed.replaceRange(len("line 1\L"), len("line 1\Lline 2\Lline 3\L") - 1, "")
  ed.enter 1
  check("the caret comes to rest where the deleted text began",
        ed.cursor == len("line 1\L"), $ed.cursor)

block: # a selection made in one panel is that panel's own
  var ed = newBuffer()
  ed.enter 1
  ed.gotoLine 9, 0
  ed.selectLine()
  equals("the second panel has a selection", ed.getSelectedText, "line 9")
  ed.enter 0
  check("the first one has none", not ed.hasSelection)
  ed.insertText "x"
  ed.enter 1
  equals("and the selection still covers the same text",
         ed.getSelectedText, "line 9")

block: # undo belongs to the buffer, wherever it is asked for
  var ed = newBuffer()
  ed.enter 0
  ed.gotoLine 1, 0
  ed.insertText "hello"
  ed.enter 1
  ed.undo()
  frame(ed, 1)
  check("undone in the other panel, and gone from both",
        not shown().contains("hello"), shown())
  ed.enter 0
  check("the buffer is back to what it was",
        ed.getLineText(0) == "line 1", ed.getLineText(0))

block: # a panel that never sat down starts at the top
  var ed = newBuffer()
  ed.enter 0
  ed.gotoLine 7, 0
  frame(ed, 0)
  frame(ed, 5)
  equals("a fresh panel is at the beginning of the buffer", shown(),
         "line 1/line 2/line 3")

block: # loading a file sits everybody down again
  var ed = newBuffer()
  ed.enter 1
  ed.gotoLine 9, 0
  frame(ed, 1)
  ed.enter 0
  ed.setText("one\Ltwo\Lthree\L")
  frame(ed, 1)
  equals("a buffer given new text starts every panel at the top", shown(),
         "one/two/three")
  ed.enter 1
  check("with the caret inside the text that is there",
        ed.cursor <= ed.len, $ed.cursor & " of " & $ed.len)

echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
