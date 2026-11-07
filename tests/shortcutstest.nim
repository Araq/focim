## The window's shortcuts as one table: the key presses it answers to, and
## the strip of keys left of the prompt that shows them. Watched through
## stub relays; a character is 8 pixels wide.
import uirelays/[screen, coords, input]
import std/strutils
import focim/[shortcuts, theme]

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
  fillRect: proc (r: Rect; color: Color) = discard,
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

proc press(key: KeyCode; mods: set[Modifier]): (bool, Shortcut) =
  var sc = scOpen
  let e = Event(kind: KeyDownEvent, key: key, mods: mods)
  result = (matchShortcut(e, sc), sc)

echo "keys:"
check("Ctrl+F is find", press(KeyF, {CtrlPressed}) == (true, scFind))
check("and so is the Command key's", press(KeyF, {GuiPressed}) == (true, scFind))
check("F alone is a letter", not press(KeyF, {})[0])
check("Ctrl+= and Ctrl++ both make text bigger",
      press(KeyEqual, {CtrlPressed}) == (true, scBigger) and
      press(KeyPlus, {CtrlPressed}) == (true, scBigger))
check("Alt+Down is the next change", press(KeyDown, {AltPressed}) == (true, scHunk))
check("Ctrl+Down is not", not press(KeyDown, {CtrlPressed})[0])
check("Ctrl+Alt+Down is not either", not press(KeyDown, {CtrlPressed, AltPressed})[0])
check("Ctrl+Z is the editor's, not the window's", not press(KeyZ, {CtrlPressed})[0])
block:
  var taken: set[KeyCode] = {}
  var twice = false
  for info in Shortcuts:
    if (info.keys * taken) != {} and not info.alt: twice = true
    taken = taken + info.keys
  check("no key is in the table twice", not twice)
for s, info in Shortcuts:
  if not info.title.startsWith(if info.alt: "Alt+" else: "Ctrl+") or
     info.help.len == 0:
    check($s & " has a title naming its keys, and help", false, info.title)

echo "the strip:"
const Status = rect(0, 500, 800, 18)
block:
  let st = layoutStrip(Status, diffOn = false)
  check("a key for every shortcut but the hunk one",
        st.keys.len == Shortcut.high.ord and st.keys[^1].sc != scHunk)
  check("square, inside the line", st.keys[0].r.w == st.keys[0].r.h and
        st.keys[0].r.y >= Status.y and
        st.keys[0].r.y + st.keys[0].r.h <= Status.y + Status.h, $st.keys[0].r)
  check("in table order, left to right", st.keys[1].r.x > st.keys[0].r.x and
        st.keys[1].sc == scFind)
  check("and the prompt starts after the last one",
        st.width > st.keys[^1].r.x + st.keys[^1].r.w - Status.x)
  let k = st.keys[1].r
  check("the key under the pointer is found",
        st.keyAt(k.x + 1, k.y + 1) == 1)
  check("the gap between keys is none of them",
        st.keyAt(k.x - 1, k.y + 1) == -1)
  check("nor is the prompt", st.keyAt(st.width + 5, k.y + 1) == -1)
block:
  let st = layoutStrip(Status, diffOn = true)
  check("in diff mode the hunk key is there too",
        st.keys.len == Shortcut.high.ord + 1 and st.keys[^1].sc == scHunk)
  check("and the strip is a key wider",
        st.width > layoutStrip(Status, diffOn = false).width)

echo "the help:"
var m: FontMetrics
let font = openFont("", 16, m)
block:
  let lines = wrapWords(font, "aaa bbb ccc ddd", 7 * 8)
  check("words fill a line as far as it is wide",
        lines == @["aaa bbb", "ccc ddd"], $lines)
  let long = wrapWords(font, "a abcdefghij b", 4 * 8)
  check("a word too wide for any line gets one of its own",
        long == @["a", "abcdefghij", "b"], $long)
  check("nothing is no lines", wrapWords(font, "", 80).len == 0)
block:
  var st = layoutStrip(Status, diffOn = false)
  texts.setLen 0
  st.drawHelp(font, default(Theme), Status, 800)
  check("no key under the pointer, no help", texts.len == 0)
  st.hot = 1
  st.drawHelp(font, default(Theme), Status, 800)
  check("the key's title comes first",
        texts.len > 1 and texts[0].s == Shortcuts[scFind].title, $texts)
  var bottom = 0
  var said = ""
  for t in texts:
    bottom = max(bottom, t.y + 16)
    if t.s != Shortcuts[scFind].title: said.add t.s & " "
  check("then all of its help", said.strip == Shortcuts[scFind].help, said)
  check("above the prompt line", bottom <= Status.y, $bottom)
  var widest = 0
  for t in texts: widest = max(widest, t.x + t.s.len * 8)
  check("and inside the window", widest <= 800, $widest)
block:
  var st = layoutStrip(Status, diffOn = false)
  st.hot = 1
  texts.setLen 0
  st.drawHelp(font, default(Theme), Status, 300)
  var widest = 0
  for t in texts: widest = max(widest, t.x + t.s.len * 8)
  check("a narrow window wraps it narrower", texts.len > 3 and widest <= 300,
        $widest)

echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
