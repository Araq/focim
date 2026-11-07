## What diff mode paints on a SynEdit: bars in the gutter, ticks between
## lines, tints behind the rows. Watched through stub relays that record the
## rectangles, since the colors are the whole of the feature.
import uirelays/[screen, coords, input]
import focim/synedit

type Fill = tuple[r: Rect; c: Color]
var fills: seq[Fill] = @[]

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

echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
