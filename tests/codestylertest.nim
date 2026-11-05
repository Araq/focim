## `markdownLangs`: a fence in the table goes to its styler, in whole, and
## anything else stays with the tokenizers in synedit.
import std/tables
import uirelays/[screen, coords, input]
import focim/[synedit, theme]

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
  fillRect: proc (r: Rect; c: Color) = discard,
  drawLine: proc (x1, y1, x2, y2: int; color: Color) = discard,
  drawPoint: proc (x, y: int; color: Color) = discard,
  loadImage: proc (path: string): Image = Image(0),
  freeImage: proc (img: Image) = discard,
  drawImage: proc (img: Image; src, dst: Rect) = discard)

clipboardRelays = ClipboardRelays(
  getText: proc (): string = "",
  putText: proc (text: string) = discard)

var seen: seq[string]

proc abc(code: string; runs: var seq[StyleRun]) =
  seen.add code
  runs.add StyleRun(first: 0, last: 2, tc: TokenClass.Keyword)

proc styled(text: string; withAbc = true): SynEdit =
  var m: FontMetrics
  result = createSynEdit(openFont("", 16, m), defaultTheme())
  result.lang = langMarkdown
  if withAbc: result.markdownLangs["abc"] = abc
  result.setText(text)
  result.render(rect(0, 0, 800, 600), showCursor = false)

block emptyTable:
  let s = styled("```abc\nabc def\n```\n", withAbc = false)
  doAssert seen.len == 0
  doAssert s.tokenClassAt(7) != TokenClass.Keyword

block claimed:
  let text = "```abc\nabc def\nsecond\n```\n"
  let s = styled(text)
  doAssert seen.len > 0
  doAssert seen[^1] == "abc def\nsecond\n"
  doAssert s.tokenClassAt(7) == TokenClass.Keyword
  doAssert s.tokenClassAt(11) == TokenClass.None
  doAssert s.tokenClassAt(0) == TokenClass.MarkdownFence

block unclosed:
  seen.setLen 0
  let s = styled("```abc\nabc def")
  doAssert seen.len > 0 and seen[^1] == "abc def"
  doAssert s.tokenClassAt(7) == TokenClass.Keyword

block unclaimed:
  seen.setLen 0
  let s = styled("```nim\nproc f() = discard\n```\n")
  doAssert seen.len == 0
  doAssert s.tokenClassAt(7) == TokenClass.Keyword   # the Nim tokenizer's `proc`

echo "codestylertest: ok"
