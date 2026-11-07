## What diff mode paints on a SynEdit: bars in the gutter, ticks between
## lines, tints behind the rows. Watched through stub relays that record the
## rectangles, since the colors are the whole of the feature.
import uirelays/[screen, coords, input]
import std/strutils
import focim/synedit

type Fill = tuple[r: Rect; c: Color]
var fills: seq[Fill] = @[]
var texts: seq[tuple[x, y: int; s: string]] = @[]

fontRelays = FontRelays(
  openFont: proc (path: string; size: int; style: FontStyles;
                  metrics: var FontMetrics): Font =
    metrics = FontMetrics(ascent: 12, descent: 4, lineHeight: 16)
    Font(1),
  closeFont: proc (f: Font) = discard,
  getFontMetrics: proc (f: Font): FontMetrics =
    FontMetrics(ascent: 12, descent: 4, lineHeight: 16),
  measureText: proc (f: Font; text: string): TextExtent =
    TextExtent(w: text.len * 8, h: 16),
  drawText: proc (f: Font; x, y: int; text: string;
                  fg, bg: Color): TextExtent =
    texts.add((x, y, text))
    TextExtent(w: text.len * 8, h: 16))
drawRelays = DrawRelays(
  fillRect: proc (r: Rect; color: Color) = fills.add((r, color)),
  drawLine: proc (x1, y1, x2, y2: int; color: Color) = discard,
  drawPoint: proc (x, y: int; color: Color) = discard,
  loadImage: proc (path: string): Image = Image(0),
  freeImage: proc (img: Image) = discard,
  drawImage: proc (img: Image; src, dst: Rect) = discard)

var failures = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

var m: FontMetrics
let font = openFont("", 16, m)
const Area = rect(0, 0, 400, 200)
let green = color(0, 200, 0)
let tint = color(10, 40, 10)
let red = color(220, 0, 0)

proc rowY(ed: SynEdit; line: int): int =
  ## The top of `line`'s row, from the first one's.
  ed.padding.y + line * fontLineSkip(font)

proc fillsAt(y: int; c: Color): seq[Rect] =
  for f in fills:
    if f.r.y == y and f.c == c: result.add f.r

for numbers in [true, false]:
  echo "with line numbers ", (if numbers: "on:" else: "off:")
  var ed = createSynEdit(font)
  ed.lang = langNone
  ed.showLineNumbers = numbers
  ed.setText("one\ntwo\nthree\nfour\n")
  ed.gotoPos(0)           # the caret on line 0, away from what is tinted
  ed.addLineDecoration(1, green, decoBar)
  ed.setLineTint(1, tint)
  ed.addLineDecoration(3, red, decoTickAbove)
  ed.addLineDecoration(3, green, decoBar)
  fills.setLen 0
  ed.render(Area, showCursor = false)

  let y1 = ed.rowY(1)
  let y3 = ed.rowY(3)
  check("a tinted row is painted across, in its tint",
        fillsAt(y1, tint).len > 0 and fillsAt(y1, tint)[0].w > 300,
        $fillsAt(y1, tint))
  check("an untinted row is not", fillsAt(ed.rowY(2), tint).len == 0)
  let bar = fillsAt(y1, green)
  check("a bar runs down the left edge of its row",
        bar.len == 1 and bar[0].x == Area.x and bar[0].w == 3 and
        bar[0].h == fontLineSkip(font), $bar)
  let tick = fillsAt(y3, red)
  check("a tick runs along the top of its row",
        tick.len == 1 and tick[0].h == 2 and tick[0].w >= 8, $tick)
  check("and a line can have both", fillsAt(y3, green).len == 1)

echo "taking them away:"
block:
  var ed = createSynEdit(font)
  ed.setText("one\ntwo\n")
  ed.setLineTint(1, tint)
  ed.addLineDecoration(1, green, decoBar)
  ed.clearLineTints()
  ed.clearLineDecorations()
  fills.setLen 0
  ed.render(Area, showCursor = false)
  check("cleared, nothing of either is drawn",
        fillsAt(ed.rowY(1), tint).len == 0 and
        fillsAt(ed.rowY(1), green).len == 0)

echo "the caret's line:"
block:
  var ed = createSynEdit(font)
  ed.setText("one\ntwo\n")
  ed.setLineTint(1, tint)
  ed.gotoLine(2, 0)
  fills.setLen 0
  ed.render(Area, showCursor = true)
  check("the caret's band wins over a tint",
        fillsAt(ed.rowY(1), ed.theme.activeLineBg).len > 0 and
        fillsAt(ed.rowY(1), tint).len == 0)

echo "phantom rows:"
proc textAt(y: int): string =
  ## Everything drawn on the row at `y`, left to right, glued together.
  for t in texts:
    if t.y == y: result.add t.s

block:
  var ed = createSynEdit(font)
  ed.lang = langNone
  ed.setText("one\ntwo\nthree\n")
  ed.gotoPos(0)
  ed.setPhantomRows(1, @["old a", "old b"], color(200, 200, 200), tint, red)
  fills.setLen 0
  texts.setLen 0
  ed.render(Area, showCursor = false)
  check("they come above their line, in order",
        textAt(ed.rowY(1)) == "old a" and textAt(ed.rowY(2)) == "old b",
        textAt(ed.rowY(1)) & "|" & textAt(ed.rowY(2)))
  check("and push the line down below them", textAt(ed.rowY(3)) == "two",
        textAt(ed.rowY(3)))
  check("on a band of their own, with a bar",
        fillsAt(ed.rowY(1), tint).len > 0 and fillsAt(ed.rowY(1), red).len > 0)
  check("they are not text", ed.fullText == "one\ntwo\nthree\n")

  # A click on one puts the caret at the start of the line it stands above.
  var click = Event(kind: MouseDownEvent, x: 50, y: ed.rowY(2) + 3,
                    button: LeftButton, clicks: 1)
  texts.setLen 0
  let act = ed.draw(click, Area, focused = true)
  check("a click on one goes to the line below it",
        ed.currentLine == 1 and ed.cursor == 4 and act.kind == noAction,
        $ed.currentLine & " " & $ed.cursor & " " & $act.kind)

block:
  var ed = createSynEdit(font)
  ed.lang = langNone
  ed.setText("one\ntwo\n")
  var many: seq[string] = @[]
  for k in 1 .. 50: many.add "gone " & $k
  ed.setPhantomRows(1, many, color(200, 200, 200), tint, red, "deleted lines")
  texts.setLen 0
  ed.render(Area, showCursor = false)
  # 200 pixels, 16 a row: twelve rows, a third of that is four.
  let summaryY = ed.rowY(4)
  check("a big block shows a third of the widget",
        textAt(ed.rowY(3)) == "gone 3" and textAt(summaryY).contains("47 deleted lines"),
        textAt(ed.rowY(3)) & "|" & textAt(summaryY))
  check("and then the line it stands above", textAt(ed.rowY(5)) == "two",
        textAt(ed.rowY(5)))
  let act = ed.draw(Event(kind: MouseDownEvent, x: 50, y: summaryY + 3,
                          button: LeftButton, clicks: 1), Area, focused = true)
  check("a click on the summary row asks for the rest",
        act.kind == phantomClick and act.line == 1, $act.kind)
  check("and the phantom text can be had back", ed.phantomRowsAt(1).len == 50)
  ed.clearPhantomRows()
  check("cleared, none are left", ed.phantomRowsAt(1).len == 0)

block:
  var ed = createSynEdit(font)
  ed.lang = langNone
  ed.setText("one\ntwo")          # no final newline: two lines
  ed.setPhantomRows(2, @["the end"], color(200, 200, 200), tint, red)
  texts.setLen 0
  ed.render(Area, showCursor = false)
  check("a block at the line count comes after the last line",
        textAt(ed.rowY(2)) == "the end", textAt(ed.rowY(2)))

block:
  var ed = createSynEdit(font)
  ed.lang = langNone
  ed.setText("x\n")
  ed.setPhantomRows(0, @["\tindented " & "w".repeat(80)],
                    color(200, 200, 200), tint, red)
  texts.setLen 0
  ed.render(Area, showCursor = false)
  let row = textAt(ed.rowY(0))
  check("a long row is cut to fit, with an ellipsis, tabs as spaces",
        row.startsWith(" ") and '\t' notin row and "indented" in row and
        row.endsWith("\xE2\x80\xA6") and
        row.len * 8 < 420, row)

echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
