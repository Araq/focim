# Rule-based English -> focim NIF commands (no LLM), Nimony + std/rex.
#   nl2focim "replace all foobar with Foobar"   -> replace foobar Foobar
# Exit code 1 + message on stderr when the request is not understood.
#
# Pipeline: pull out quoted text -> normalize (politeness, idioms) -> split
# into clauses at "and/then" -> per clause pick the verb by an ordered rule
# list -> extract options, targets and arguments with patterns -> emit NIF.
#
# All patterns are compiled into the binary by `re`. They are written in
# lowercase and matched against a lowercased copy of the input (same byte
# offsets), and the text is then cut out of the original. They use
# `reAllowEvil` (leftmost-longest, no determinism check); captures are only
# read from patterns with a single possible reading, and "lazy" splits such
# as `A with B` are done in code at the first separator.

import std / [rex, syncio, strutils, cmdline]

template ev(p: untyped): untyped =
  ## a pattern in non-deterministic mode (leftmost-longest, no determinism check)
  re(p, {reExtended, reAllowEvil})


var quoted {.threadvar.}: seq[string]   # texts the user put in quotes, referenced as @@i@@
var failMsg {.threadvar.}: string

proc fail(msg: string): string =
  if failMsg.len == 0: failMsg = msg
  result = ""

proc lc(s: string): string = toLowerAscii(s)

proc has(s: string; r: Regex): bool = contains(lc(s), r)

proc grab(s: string; r: Regex): string =
  ## first non-empty capture group of the first match, or ""
  result = ""
  var caps: seq[Capture] = @[]
  let (f, l) = findBounds(lc(s), r, caps)
  if f >= 0:
    for i in 0 ..< caps.len:
      let t = capture(s, caps, i)
      if t.len > 0: return t

proc take(s: var string; r: Regex; got: var seq[string]): bool =
  ## like grab, but also removes the matched text from `s`
  var caps: seq[Capture] = @[]
  let (f, l) = findBounds(lc(s), r, caps)
  if f < 0: return false
  got = @[]
  for i in 0 ..< caps.len: got.add capture(s, caps, i)
  s = substr(s, 0, f-1) & " " & substr(s, l+1)
  result = true

proc take(s: var string; r: Regex): bool =
  var got: seq[string] = @[]
  result = take(s, r, got)

proc sub(s: string; r: Regex; by: string): string =
  ## every match replaced by `by`; the rest keeps its original case
  result = ""
  var last = 0
  for (f, l) in findAll(lc(s), r):
    if l >= f:
      result.add substr(s, last, f-1)
      result.add by
      last = l+1
  result.add substr(s, last)

proc after(s: string; r: Regex): string =
  ## the text after the first match of `r`, or ""
  let (f, l) = findBounds(lc(s), r)
  result = if f >= 0: substr(s, l+1) else: ""

proc splitFirst(s: string; sep: Regex; a, b: var string): bool =
  ## split at the first match of `sep` (what a lazy `(.+?) sep (.+)` does)
  let (f, l) = findBounds(lc(s), sep)
  if f <= 0 or l+1 >= s.len: return false
  a = substr(s, 0, f-1)
  b = substr(s, l+1)
  result = true

proc firstNonEmpty(c: seq[string]): string =
  result = ""
  for x in c:
    if x.len > 0: return x

proc pint(s: string): int =
  result = 0
  for c in s:
    if c in {'0'..'9'}: result = result * 10 + (ord(c) - ord('0'))

proc hex2(n: int): string =
  const d = "0123456789ABCDEF"
  result = ""
  result.add d[(n shr 4) and 15]
  result.add d[n and 15]

# ---------------------------------------------------------------- values

proc toNum(s: string): string =
  let l = lc(s)
  if l.len > 0 and allCharsInSet(l, {'0'..'9'}): return l
  case l
  of "one", "a", "an", "once": result = "1"
  of "two", "twice", "double": result = "2"
  of "three", "thrice", "triple": result = "3"
  of "four": result = "4"
  of "five": result = "5"
  of "six": result = "6"
  of "seven": result = "7"
  of "eight": result = "8"
  of "nine": result = "9"
  of "ten": result = "10"
  of "twenty": result = "20"
  else: result = ""

proc restore(s: string): string =
  result = s
  for i in 0 ..< quoted.len: result = result.replace("@@" & $i & "@@", quoted[i])

proc stripEnds(s: string): string =
  ## strip whitespace and commas at both ends
  var a = 0
  var b = s.len - 1
  while a <= b and s[a] in {' ', '\t', '\n', '\r', ','}: inc a
  while b >= a and s[b] in {' ', '\t', '\n', '\r', ','}: dec b
  result = substr(s, a, b)

proc clean(s: string): string =
  ## trim whitespace, punctuation and dangling filler words
  var t = s
  while true:
    let before = t
    t = stripEnds(t)
    while t.len > 0 and t[t.len-1] in {',', ';', '!', '?', '.', ':'} and not allCharsInSet(t, {'.'}):
      t = substr(t, 0, t.len-2)
    t = stripEnds(t)
    t = sub(t, ev"\s+(?:but|and|only|then|so|now|too|also)$", "")
    t = sub(t, ev"^(?:only|just)\s+", "")
    if t == before: break
  t = sub(t, ev"\s+", " ")
  result = restore(t)

proc q(s: string): string =
  ## NIF atom: bare identifier/number, otherwise a quoted string
  if s.len > 0 and (contains(s, ev"^[a-zA-Z_][a-zA-Z0-9_]*$") or allCharsInSet(s, {'0'..'9'})):
    return s
  result = "\""
  for c in s:
    if c == '"': result.add "\\^"
    elif c == '\\': result.add "\\|"
    elif c == '\t': result.add "\\t"
    elif c == '\n': result.add "\\n"
    elif c == '\r': result.add "\\r"
    elif c < ' ': result.add "\\" & hex2(ord(c))
    else: result.add c
  result.add '"'

proc qs(s: string): string =
  ## always a string literal (`run` demands one)
  result = q(s)
  if result[0] != '"': result = "\"" & result & "\""

const stop = ["show", "me", "everywhere", "is", "are", "used", "where", "the", "a",
  "an", "of", "to", "in", "all", "find", "usages", "uses", "usage", "references",
  "callers", "who", "calls", "called", "defined", "declared", "go", "jump",
  "definition", "declaration", "please", "can", "you", "i", "want", "see", "list",
  "get", "function", "proc", "procedure", "variable", "type", "symbol", "method",
  "named", "its", "it", "this", "that", "for", "being", "gets", "implemented",
  "implementation", "take", "lives", "located", "location", "what", "which", "file",
  "places", "every", "place", "code", "lookup", "look", "up", "and", "or", "whose",
  "has", "appears", "occurs", "referenced", "spot", "spots", "locations", "open"]

proc isStop(w: string): bool =
  result = false
  let l = lc(w)
  for x in stop:
    if x == l: return true

proc ident(s: string): string =
  ## best guess for a symbol name: prefer camelCase/snake_case/digits, else last non-stopword
  result = ""
  var plain = ""
  for (f, l) in findAll(s, re"[A-Za-z_][A-Za-z0-9_]*"):
    let w = substr(s, f, l)
    if isStop(w): continue
    let rest = substr(w, 1)
    if contains(w, ev"[a-z][A-Z]|_|[0-9]") or (w.len > 1 and rest != lc(rest)):
      return w
    plain = w
  result = plain

proc special(x: string): string =
  ## "tabs" -> tab character, "4 spaces" -> "    " (for replace arguments)
  let n = grab(x, ev"^(\d+|one|two|three|four|five|six|seven|eight|nine|ten|twenty)\s+spaces?$")
  if n.len > 0: return repeat(' ', pint(toNum(n)))
  if has(x, ev"^(?:a\s+)?(?:single\s+)?space$"): return " "
  if has(x, ev"^(?:all\s+)?(?:the\s+)?(?:a\s+)?(?:tabs?|tab\s+characters?)$"): return "\t"
  if has(x, ev"^(?:newlines?|line\s*breaks?)$"): return "\n"
  if has(x, ev"^(?:nothing|empty(?:\s+string)?|an\s+empty\s+string)$"): return ""
  result = x

proc arg(raw: string; specials = false): string =
  let t = stripEnds(raw)
  if contains(t, ev"^@@\d+@@[\s,.;:!?]*$"): return q(clean(t))  # quoted text: take verbatim
  let c = clean(raw)
  result = q(if specials: special(c) else: c)

# ------------------------------------------------------- targets, options

proc takeTarget(s: var string; allowBuffer = true; pronouns = true): string =
  var c: seq[string] = @[]
  if take(s, ev"(?:(?:only\s+)?(?:in|within|inside|on|for|of|from|at|between|over)\s+)?\b(?:(?:from\s+)?lines\s+(\d+)\s*(?:-|–|to|through|thru|until|till|\.\.|and)\s*(?:line\s+)?(\d+)|from\s+line\s+(\d+)\s*(?:-|to|through|thru|until|till)\s*(?:line\s+)?(\d+)|line\s+(\d+)\s*(?:-|–|\.\.)\s*(\d+)|(?:the\s+)?range\s+(\d+)\s*(?:-|–|to|through|\.\.)\s*(\d+)|(\d+)\s*(?:-|–|\.\.)\s*(\d+))\b", c):
    var nums: seq[string] = @[]
    for x in c:
      if x.len > 0: nums.add x
    if nums.len >= 2: return "(lines " & nums[0] & " " & nums[1] & ")"
  if take(s, ev"(?:(?:only\s+)?(?:in|within|inside|on|for|of|from|at|between|over)\s+)?\bline\s+(?:number\s+|no\.?\s+)?(\d+)\b", c):
    return "(line " & firstNonEmpty(c) & ")"
  if take(s, ev"(?:(?:only\s+)?(?:in|within|inside|on|for|of|from|at|between|over)\s+)?\b(?:(?:the\s+)?(?:current(?:ly)?\s+)?(?:selection|selected(?:\s+(?:lines?|text|code|region|block|part|stuff|bit))?|highlighted(?:\s+(?:lines?|text|code|region|block|part))?)|what\s+i\s+(?:have\s+)?(?:selected|highlighted))\b"):
    return "(selection)"
  if take(s, ev"(?:(?:only\s+)?(?:in|within|inside|on|for|of|from|at|between|over)\s+)?\b(?:(?:the\s+)?(?:current|this|cursor|active|my)\s+line|the\s+line\s+(?:i\s+am|i'm)\s+on|the\s+line)\b"):
    return "(current)"
  if take(s, ev"(?:(?:only\s+)?(?:in|within|inside|on|for|of|from|at|between|over)\s+)?\b(?:(?:the\s+)?(?:current|this)\s+word|(?:the\s+)?word\s+(?:under|at)\s+(?:the\s+)?cursor)\b"):
    return "(word)"
  if allowBuffer and take(s, ev"(?:(?:only\s+)?(?:in|within|inside|on|for|of|from|at|between|over)\s+)?\b(?:(?:the\s+)?(?:whole|entire|full|complete)\s+(?:file|buffer|document|text|contents?)(?:\s+of\s+(?:this|the)\s+(?:file|buffer|document))?|everything|all\s+(?:the\s+)?lines|all\s+of\s+it|(?:this|the)\s+(?:file|buffer|document)|all)\b"):
    return "(buffer)"
  if pronouns and take(s, ev"\b(?:it|that|them|this|this\s+one)\b"):
    return "(current)"
  result = ""

proc takeOpts(s: var string; tabs, ask: bool): string =
  result = ""
  if take(s, ev",?\s*(?:and\s+|but\s+)?\b(?:(?:keeping|keep|with|using|respecting)\s+)?(?:case[-\s]?sensitive(?:ly)?|case[-\s]?sensitivity(?:\s+in\s+mind)?|match(?:ing)?\s+(?:the\s+)?case|case\s+match(?:ing)?|respect(?:ing)?\s+(?:the\s+)?case|exact\s+case|with\s+case|same\s+case|case\s+matters)\b"):
    result.add " (case)"
  if take(s, ev",?\s*(?:and\s+|but\s+)?\b(?:(?:only\s+)?(?:matching\s+|match\s+|for\s+|on\s+)?(?:as\s+)?(?:the\s+|a\s+)?(?:whole|full|entire|complete|exact)[-\s]words?(?:\s+only)?(?:\s+matches)?|(?:on\s+)?word\s+boundar(?:y|ies))\b"):
    result.add " (word)"
  if tabs and take(s, ev",?\s*(?:and\s+)?\b(?:(?:in|across|throughout|over|through)\s+(?:all|every|each)\s+(?:of\s+)?(?:the\s+|my\s+)?(?:open(?:ed)?\s+|active\s+)?(?:tabs?|buffers?|open\s+files)|(?:in\s+|across\s+)?(?:all|every)\s+(?:the\s+|my\s+)?(?:open(?:ed)?|active)\s+(?:tabs?|buffers?|files)|in\s+open\s+(?:tabs|files|buffers))\b|,\s*(?:in\s+)?all\s+tabs\b"):
    result.add " (tabs)"
  if ask and take(s, ev",?\s*(?:but\s+|and\s+)?\b(?:(?:ask(?:ing)?|prompt(?:ing)?)(?:\s+me)?|confirm(?:ing|ation)?|let\s+me\s+(?:confirm|approve|decide|check))(?:\s+(?:for|before|on|about|at|with|of)?\s*(?:each|every|all)\s+(?:single\s+)?(?:one|match|occurrence|replacement|change|time|instance|hit|file|rename)s?|\s+first|\s+beforehand)?\b|,?\s*\bone\s+(?:by|at)\s+(?:one|a\s+time)\b|,?\s*\binteractive(?:ly|\s+mode)?\b"):
    result.add " (ask)"

proc extName(w: string): string =
  case w
  of "markdown": "md"
  of "python": "py"
  of "javascript": "js"
  of "typescript": "ts"
  of "rust": "rs"
  of "text": "txt"
  of "shell": "sh"
  of "header": "h"
  of "config": "cfg"
  else: w

const extSkip = ["all", "the", "open", "project", "source", "these", "those", "my", "other",
  "every", "any", "rename", "find", "search", "list", "named", "called", "some", "which", "of", "in",
  "for", "with", "to", "from", "by", "on"]

proc extOk(w: string): bool =
  result = w.len > 0
  for x in extSkip:
    if x == w: return false

proc takeExt(s: var string): string =
  result = ""
  var c: seq[string] = @[]
  let e1 = ev",?\s*(?:in\s+|of\s+)?(?:all\s+|the\s+)?\*\.(\w+)(?:\s+files?)?\b"
  let e2 = ev",?\s*(?:in|of|across|among|through)?\s*(?:all\s+|the\s+|only\s+|every\s+|any\s+)*\.(\w+)\s+files?\b"
  let e3 = ev",?\s*(?:in|of|across|among|through)?\s*(?:all\s+|the\s+|only\s+)*(\w+)\s+files\b"
  for r in [e1, e2, e3]:
    let w = lc(grab(s, r))
    if extOk(w):
      discard take(s, r, c)
      return " (ext " & q(extName(w)) & ")"

proc takeExclude(s: var string): string =
  result = ""
  var c: seq[string] = @[]
  if take(s, ev",?\s*(?:but\s+|and\s+)?\b(?:skip(?:ping)?|exclud(?:e|ing)|except|ignor(?:e|ing)|not\s+in|without|outside(?:\s+of)?|leave\s+out|leaving\s+out|don't\s+include|do\s+not\s+include|but\s+not)\s+(?:for\s+)?(?:those\s+|anything\s+|files\s+|everything\s+|the\s+ones\s+)?(?:in\s+|under\s+|inside\s+|from\s+)?(?:the\s+)?([^\s,;]+)(?:\s+(?:folder|directory|dir))?", c):
    var x = firstNonEmpty(c)
    while x.len > 1 and x[x.len-1] == '.' and not allCharsInSet(x, {'.'}): x = substr(x, 0, x.len-2)
    result = " (exclude " & arg(x) & ")"

# ------------------------------------------------------------- verbs

let fnRx = ev"\bfile\s*names?\b|\bfilenames?\b|\bfiles?\s+(?:named|called)\b|\bfiles?\s+whose\s+names?\b|\bnames?\s+of\s+(?:the\s+)?files\b|\bin\s+(?:their|its|the)\s+(?:file\s*)?names?\b|\bthe\s+file\s+(?:named|called)\b|\brename\s+(?:all\s+|every\s+|the\s+|any\s+)?(?:\*?\.?\w+\s+)?files?\b"

let runVerbRx = ev"\b(?:run|execute|exec|build|compile|launch)\b"
let runNotRx = ev"\b(?:run|execute|exec|build|compile|launch)\s+(?:a\s+)?(?:find|search|grep|replace)\b"
let runToolRx = ev"^\s*(?:nimble|nim|git|cmake|cargo|npm|yarn|pnpm|python3?|pip|gcc|clang|docker|ctest|pytest|node|deno|bun|ninja|meson)\s+\S"
let runToolNotRx = ev"^\s*\w+\s+files?\b"

let rules = [
  ("cls", ev"\bcls\b|\bclear\s+(?:the\s+)?(?:terminal|screen|console|output|scrollback)\b|\b(?:terminal|screen|console)\s+clear\b"),
  ("cd", ev"\bcd\b|\bchdir\b|\bchange\s+(?:the\s+)?(?:working\s+|current\s+)?dir(?:ectory)?\b|\bswitch\s+(?:to\s+)?(?:the\s+)?(?:directory|folder)\b|\b(?:go\s+)?up\s+(?:a|one)\s+(?:dir(?:ectory)?|folder|level)\b|\bparent\s+(?:dir(?:ectory)?|folder)\b|\b(?:go|navigate|move|switch|step|change)\s+(?:in)?to\s+(?:the\s+)?\S+\s+(?:directory|folder|dir)\b|\b(?:go|navigate|step)\s+(?:in)?to\s+(?:the\s+)?(?:[\w.-]+/)+[\w-]*/?\s*[.!]?\s*$"),
  ("defaults", ev"\bdefaults?\b|\bfactory\s+settings\b|\breset\s+(?:the\s+|all\s+|my\s+)?(?:config(?:uration)?|settings|preferences|options)\b"),
  ("unsplit", ev"\bunsplit\b|\bclose\s+(?:this\s+|the\s+|that\s+)?(?:other\s+|second\s+)?(?:panel|pane|split|view|editor|window)\b|\bmerge\s+(?:the\s+)?(?:panes|panels|views|splits)\b"),
  ("split", ev"\bsplit\b|\b(?:another|new|second|extra)\s+(?:editor|pane|panel|view|window|column)\b|\bside\s+by\s+side\b"),
  ("theme", ev"\btheme\b|\bcolou?r\s*scheme\b"),
  ("undo", ev"\bundo\b|\btake\s+back\b|\brevert\s+(?:the\s+)?(?:last|previous|my\s+last)\b"),
  ("redo", ev"\bredo\b"),
  ("hunk", ev"\bhunk\b|\b(?:next|previous|prev|last|following)\s+(?:change|modification|diff|edit)\b"),
  ("diff", ev"\bdiff\b|\bwhat(?:'s|\s+is|\s+has|\s+have|\s+i)?\s+changed\b|\bchanges\s+since\b|\bcompare\b|\buncommitted\b|\bdiffers?\b|\bdifferences?\b"),
  ("run", runVerbRx),   # see detect: also the bare tool form, and not "run a find"
  ("usages", ev"\busages?\b|\b(?:is|are|gets?|being)\s+(?:used|referenced|called)\b|\breferences?\s+(?:to|of|for)\b|\bcallers?\s+of\b|\bwho\s+calls\b|\bwhere\b.*\bused\b|\buses\s+of\b|\b(?:every|each|all)\s+(?:the\s+)?(?:locations?|places?|spots?)\s+where\b|\bwhere\b.*\b(?:appears|occurs)\b"),
  ("decl", ev"\bwhere\b.*\b(?:defined|declared|implemented)\b|\b(?:definition|declaration|implementation)\b"),
  ("uncomment", ev"\buncomment\b|\bremove\s+(?:the\s+)?comments?\s+(?:from|on)\b"),
  ("comment", ev"\bcomments?\b"),
  ("dedent", ev"\b(?:unindent|dedent|outdent|de-indent)\b|\bindent\b.*\bless\b|\bremove\s+(?:the\s+|one\s+level\s+of\s+)?indentation\b|\bshift\b.*\bleft\b"),
  ("indent", ev"\bindent\b|\bshift\b.*\bright\b"),
  ("sort", ev"\bsort\b|\balphabeti[sz]e\b"),
  ("case", ev"\b(?:upper|lower|title)\s*-?case\b|\bcapitali[sz]e\b|\ball\s+caps\b|\bcaps\b"),
  ("move", ev"\b(?:move|relocate|shift)\b.*(?:->|=>|→)"),
  ("replace", ev"\b(?:replace|rename|substitute|swap)\b|\b(?:change|convert|turn)\s+(?:all\s+|every\s+|each\s+)?\S+(?:\s+\S+)?\s+(?:to|into)\s|->|=>|→|\binstead\s+of\b|\bbecomes\b|@@\d+@@\s+(?:to|with|into|by)\s+@@\d+@@"),
  ("fnsearch", fnRx),
  ("next", ev"^\s*(?:go\s+to\s+)?(?:the\s+)?next\s*$|\bnext\s+(?:match|result|occurrence|hit|one)\b|\bfind\s+next\b"),
  ("prev", ev"^\s*(?:go\s+to\s+)?(?:the\s+)?prev(?:ious)?\s*$|\b(?:previous|prev|last)\s+(?:match|result|occurrence|hit|one)\b|\bfind\s+prev(?:ious)?\b"),
  ("search", ev"\b(?:grep|search|find|look\s+for|locate)\b.*\b(?:project|codebase|repo|repository|workspace|all\s+(?:the\s+)?(?:\w+\s+)?files|every\s+(?:\w+\s+)?file|\.?\w+\s+files|everywhere)\b|\bgrep\b|\*\.\w"),
  ("find", ev"\b(?:find|search|look\s+for|locate|where\s+is|highlight\s+all)\b"),
  ("insert", ev"\b(?:insert|add|append|prepend|put|type)\b|^\s*(?:line\s+\d+|(?:the\s+)?(?:top|bottom|end|start|beginning)(?:\s+of\s+(?:the\s+)?file)?)\s*:\s*\S"),
  ("duplicate", ev"\b(?:duplicate|dup|dupe|clone|copy|double)\b|\bappear\s+(?:twice|two\s+times)\b"),
  ("move2", ev"\b(?:move|relocate)\b|\bshift\s+lines?\b.*\bto\b"),  # see detect: not "move to"/"move me"
  ("delete", ev"\b(?:delete|del|rm|remove|nuke|erase|kill|wipe|clear|cut|drop|empty)\b|\bget\s+rid\s+of\b"),
  ("select", ev"\b(?:select|highlight|mark|grab)\b"),
  ("save", ev"\b(?:save|write|store)\b"),
  ("open", ev"\b(?:open|edit|load|view)\b|\bshow\s+(?:me\s+)?(?:the\s+)?file\b|\bbring\s+up\b"),
  ("goto", ev"\b(?:go\s*to|goto|jump|take\s+me|navigate|scroll|move\s+(?:to|me))\b|\bgo\s+(?:back\s+)?to\b|^\s*(?:line\s+)?\d+\s*[.!]?\s*$|^\s*(?:the\s+)?(?:top|bottom|end|start|beginning)(?:\s+of\s+(?:the\s+)?file)?\s*[.!]?\s*$"),
]

let thisFileRx = ev"\b(?:this|the\s+current|current)\s+(?:file|buffer|document)\b"
let openTabsRx = ev"\b(?:in|across)\s+(?:all\s+|every\s+)?(?:the\s+|my\s+)?(?:open|active)\s+(?:tabs|files|buffers)\b|\b(?:all|every)\s+(?:the\s+)?(?:open|active)\s+tabs?\b"

proc detect(s: string): string =
  result = ""
  for r in rules:
    let name = r[0]
    if name == "run":
      if (has(s, runVerbRx) and not has(s, runNotRx)) or (has(s, runToolRx) and not has(s, runToolNotRx)):
        return "run"
    elif name == "move2":
      if has(s, ev"\brelocate\b|\bshift\s+lines?\b.*\bto\b") or (has(s, ev"\bmove\b") and not has(s, ev"\bmove\s+(?:to|me)\b")):
        return "move"
    elif has(s, r[1]):
      if name == "search" and (has(s, openTabsRx) or has(s, thisFileRx)):
        return "find"
      return name

# ------------------------------------------------------------- commands

proc stripTrailingPunct(x: string): string =
  result = x
  while result.len > 0 and result[result.len-1] in {'?', '.', '!'}: result = substr(result, 0, result.len-2)

proc buildCd(s: string): string =
  if has(s, ev"\bup\s+(?:a|one)\b|\bparent\b"): return "cd \"..\""
  var d = grab(s, ev"(@@\d+@@)")
  if d.len == 0: d = grab(s, ev"\b(?:in)?to\s+(?:the\s+)?(\S+)\s+(?:directory|folder|dir)\b")
  if d.len == 0: d = grab(s, ev"\b(?:cd|chdir|directory|folder|dir)\s+(?:to\s+|into\s+)?(?:the\s+)?(\S+)")
  if d.len == 0: d = grab(s, ev"(?:^|\s)((?:[\w.-]+/)+[\w-]*/?)")
  if d.len == 0: return fail("cd: no directory")
  result = "cd " & arg(d)

proc buildTheme(s: string): string =
  var n = grab(s, ev"(@@\d+@@)")
  if n.len == 0: n = grab(s, ev"\b(?:theme|scheme)\s+(?:to\s+)?(?:the\s+)?([\w-]+)")
  if n.len == 0 or lc(n) in ["the", "a", "to"]:
    n = ""
    for (f, l) in findAll(lc(s), ev"\b[\w-]+\s+(?:theme|colou?r\s*scheme)\b"):
      let w = grab(substr(s, f, l), ev"^([\w-]+)")
      if lc(w) notin ["the", "a", "my", "new", "different", "another", "current", "color", "colour"]:
        n = w
        break
  if n.len == 0: return fail("theme: no name")
  result = "theme " & arg(n)

proc buildUndo(cmd, s: string): string =
  var n = grab(s, ev"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|twenty)\s+(?:changes?|steps?|times|edits?|actions?|things?|operations?)\b")
  if n.len == 0: n = grab(s, ev"\b(twice|thrice)\b")
  if n.len == 0: n = grab(s, ev"\b(?:undo|redo)\s+(\d+)\b")
  result = if n.len > 0: cmd & " " & toNum(n) else: cmd

proc buildDiff(s: string): string =
  var rev = grab(s, ev"(@@\d+@@)")
  if rev.len == 0:
    rev = grab(s, ev"\b(?:against|with|to|vs\.?|versus|since|from)\s+(?:the\s+)?(?:revision\s+|commit\s+|branch\s+)?([^\s?.!]+|[^\s]*[^\s?.!])(?:\s+branch)?[?.!]*\s*$")
  if rev.len == 0: rev = grab(s, ev"(?:^|\s)((?:head|origin/)\S*|\S+~\d+|\S+\^+|[0-9a-f]{7,40})(?:\s|$)")
  if rev.len == 0: rev = grab(s, ev"\bdiff\s+(\S+)\s*$")
  rev = stripTrailingPunct(rev)
  if lc(rev) in ["", "last", "previous", "saved", "disk", "file", "it", "this", "that",
                 "version", "commit", "original", "before", "now"]:
    result = "diff"
  else:
    result = "diff " & arg(rev)

proc buildRun(s: string): string =
  var t = grab(s, ev"(@@\d+@@)")
  if t.len == 0: t = after(s, ev"\b(?:with|using|via|use)\s+")
  if t.len == 0: t = after(s, ev"\b(?:run|execute|exec|launch)\s+(?:the\s+)?(?:shell\s+)?(?:command\s+)?")
  if t.len == 0 and has(s, runToolRx) and not has(s, runVerbRx): t = s
  t = sub(t, ev"\s+(?:to|in\s+order\s+to|so\s+(?:that\s+)?(?:it|we|i))\s+(?:execute|run|build|compile|test|check|make|get)\b.*$", "")
  if clean(t).len == 0: return fail("run: no command")
  result = "run " & qs(clean(t))

proc buildUsages(s: string): string =
  var n = grab(s, ev"(@@\d+@@)")
  if n.len == 0: n = grab(s, ev"\beverywhere\s+(\S+)\s+is\s+used")
  if n.len == 0: n = grab(s, ev"\bwhere\s+(?:is\s+)?(\S+)\s+(?:is\s+)?(?:used|referenced|called)")
  if n.len == 0: n = grab(s, ev"\b(?:usages|uses|references|callers|calls)\s+(?:of|to|for)\s+(?:the\s+)?(?:proc\s+|function\s+|variable\s+|type\s+|symbol\s+)?(\S+)")
  if n.len == 0: n = grab(s, ev"\bwho\s+calls\s+(\S+)")
  if n.len == 0: n = grab(s, ev"\busages\s+(\S+)")
  if n.len == 0: n = grab(s, ev"(\S+)\s+(?:is|gets)\s+(?:used|referenced|called)")
  if n.len == 0: n = grab(s, ev"\bwhere\s+(\S+)\s+(?:appears|occurs)")
  if n.len == 0 or isStop(n): n = ident(s)
  if n.len == 0: return fail("usages: no name")
  result = "usages " & arg(n)

proc buildDecl(s: string): string =
  var n = grab(s, ev"(@@\d+@@)")
  if n.len == 0: n = grab(s, ev"\bwhere\s+(?:is|are)\s+(\S+)\s+(?:defined|declared|implemented)")
  if n.len == 0: n = grab(s, ev"\bwhere's\s+(\S+)\s+(?:defined|declared)")
  if n.len == 0: n = grab(s, ev"\bwhere\s+(\S+)\s+(?:is|are)\s+(?:defined|declared|implemented)")
  if n.len == 0: n = grab(s, ev"\b(?:definition|declaration|implementation)\s+of\s+(?:the\s+)?(?:proc\s+|function\s+|type\s+|variable\s+)?(\S+)")
  if n.len == 0 or isStop(n): n = ident(s)
  if n.len == 0: return fail("goto: no name")
  result = "goto (decl " & arg(n) & ")"

proc buildGoto(s: string): string =
  var n = grab(s, ev"\bline\s+(?:number\s+)?(\d+)")
  if n.len == 0: n = grab(s, ev"\b(?:go\s*to|goto|jump\s+to|line)\s+(\d+)\b")
  if n.len == 0: n = grab(s, ev"^\s*(\d+)\s*[.!]?\s*$")
  if n.len > 0: result = "goto " & n
  elif has(s, ev"\b(?:top|beginning|start|first\s+line)\b"): result = "goto (top)"
  elif has(s, ev"\b(?:end|bottom|last\s+line)\b"): result = "goto (bottom)"
  else: result = fail("goto: where?")

proc buildOpen(s: string): string =
  var p = grab(s, ev"(@@\d+@@)")
  if p.len == 0: p = grab(s, ev"(?:^|\s)([\w~.-]*[/.][\w./~-]*\w)")
  if p.len == 0: p = grab(s, ev"\b(?:open|edit|load|view)\s+(?:up\s+)?(?:the\s+|a\s+)?(?:file\s+)?(\S+)")
  if p.len == 0: return fail("open: no file")
  result = "open " & arg(p)

proc buildSave(s: string): string =
  var p = grab(s, ev"(@@\d+@@)")
  if p.len == 0:
    p = grab(s, ev"\b(?:as|to|into)\s+(\S+)")
    if lc(p) == "disk": p = ""
  if p.len == 0: p = grab(s, ev"(?:^|\s)([\w~.-]*/[\w./~-]*\w|[\w~-]+\.\w+)(?:\s|$)")
  result = if p.len > 0: "save " & arg(p) else: "save"

proc buildSearch(cmd, s0: string): string =
  var s = s0
  let fn = cmd == "fnsearch"
  var tail = ""
  var t = ""
  if fn:
    tail = " (filenames)"
    t = grab(s, ev"\b(?:named|called)\s+(@@\d+@@|\S+)")
    if t.len == 0: t = grab(s, ev"\bwhose\s+(?:file\s*)?names?\s+(?:contains?|includes?|has|have|with|matche?s?|starts?\s+with|ends?\s+with|is|are)\s+(@@\d+@@|\S+)")
    if t.len == 0: t = grab(s, ev"\b(?:have|has|with|contain|containing|include|including)\s+(@@\d+@@|\S+)\s+in\s+(?:their|the|its)\s+(?:file\s*)?names?")
    if t.len == 0: t = grab(s, ev"\b(?:file\s*names?|names?)\s+(?:that\s+)?(?:contains?|includes?|with|matching|like|containing)\s+(@@\d+@@|\S+)")
    discard take(s, ev"\b(?:whose\s+)?(?:file\s*names?|filenames?)\b|\bnames?\s+of\s+(?:the\s+)?files\b|\bin\s+(?:their|its|the)\s+names?\b")
  if cmd != "find":
    tail.add takeExclude(s)
    tail.add takeExt(s)
  let opts = takeOpts(s, tabs = cmd == "find", ask = false)
  if t.len == 0: t = grab(s, ev"(@@\d+@@)")
  if t.len == 0: t = after(s, ev"\bfor\s+(?:files\s+)?(?:named\s+|called\s+)?")
  if t.len == 0:
    t = after(s, ev"\b(?:find|search|grep|look|locate|where\s+is|highlight\s+all|list|show)\s+(?:me\s+)?(?:in\s+|through\s+|across\s+)?(?:the\s+)?(?:whole\s+|entire\s+)?(?:project\s+|codebase\s+|repo(?:sitory)?\s+|this\s+file\s+|the\s+file\s+|files?\s+)?(?:all\s+(?:occurrences\s+of\s+|instances\s+of\s+)?|occurrences\s+of\s+|instances\s+of\s+)?(?:the\s+(?:text|string|word|phrase|term)\s+)?")
  t = sub(t, ev"\s+(?:in|within|inside|across|throughout)?\s*(?:this|the|current|whole|entire)\s+(?:file|buffer|document|project|codebase|repo(?:sitory)?)\s*[.?!]?\s*$|\s+(?:here|everywhere)\s*[.?!]?\s*$", "")
  t = sub(sub(t, ev"^\s*where\s+", ""), ev"\s+(?:is|appears|occurs)(?:\s+located)?\s*[.?!]?\s*$", "")
  if clean(t).len == 0:
    t = sub(s, ev"\b(?:find|search|grep|look\s+for|locate|list|show)\b", "")   # verb last: "TODO find"
  if clean(t).len == 0: return fail(cmd & ": no text")
  result = (if fn: "search" else: cmd) & " " & arg(t) & opts & tail

proc verbEnd(s: string; r: Regex): int =
  ## position just after the first match of `r`, or -1
  let (f, l) = findBounds(lc(s), r)
  result = if f >= 0: l+1 else: -1

proc buildReplace(s0: string): string =
  var s = s0
  let fn = has(s, fnRx)
  var tail = ""
  if fn:
    tail = " (filenames)"
    discard take(s, ev"\b(?:all\s+|every\s+|the\s+|any\s+)?(?:\*?\.?\w+\s+)?files?\s+(?:named|called|whose\s+names?\s+(?:contain|include|have)s?)\s+")
    discard take(s, ev",?\s*\b(?:in|of|within|across)\s+(?:the\s+|their\s+|all\s+)?(?:file\s*names?|filenames?|names\s+of\s+(?:the\s+)?files)\b|\b(?:the\s+)?(?:file\s*names?|filenames?)\b")
    tail.add takeExclude(s)
    tail.add takeExt(s)
    discard take(s, ev"\b(?:all\s+|every\s+|the\s+|any\s+)?files?\b")
  let opts = takeOpts(s, tabs = not fn, ask = true)
  let tg = if fn: "" else: takeTarget(s, allowBuffer = false, pronouns = false)
  var a = ""
  var b = ""
  var ok = false
  var c: seq[string] = @[]
  # 'old' to 'new'
  if take(s, ev"(@@\d+@@)\s*(?:to|with|by|into|->|=>|→)\s*(@@\d+@@)", c):
    a = c[0]; b = c[1]; ok = true
  # verb A sep B, split at the first separator after the verb
  template verbSplit(verb, sep: Regex) =
    if not ok:
      let e = verbEnd(s, verb)
      if e >= 0:
        let rest = substr(s, e)
        if splitFirst(rest, sep, a, b): ok = true
  verbSplit(ev"\b(?:replace|substitute|change|convert|turn)\s+(?:all\s+(?:the\s+)?(?:occurrences\s+of\s+|instances\s+of\s+|uses\s+of\s+)?|every\s+(?:occurrence\s+of\s+|instance\s+of\s+)?|each\s+(?:occurrence\s+of\s+)?|any\s+)?",
            ev"\s+(?:with|by|to|into)\s+")
  verbSplit(ev"\bswap\s+(?:all\s+|every\s+)?", ev"\s+(?:for|with|to|by)\s+")
  verbSplit(ev"\brename\s+(?:all\s+|every\s+)?", ev"\s+(?:to|into|as|with)\s+|\s*(?:->|=>)\s*")
  verbSplit(ev"\b(?:replace|rename|change|swap|substitute|convert|turn)\s+(?:all\s+|every\s+)?", ev"\s*(?:->|=>|→)\s*")
  if not ok and splitFirst(" " & s, ev"\s*(?:->|=>|→)\s*", a, b): ok = true
  if not ok:
    let x = grab(s, ev"(\S+)\s+(?:becomes|turns\s+into|is\s+replaced\s+(?:with|by))\s")
    if x.len > 0:
      a = x
      b = after(s, ev"\s(?:becomes|turns\s+into|is\s+replaced\s+(?:with|by))\s+")
      ok = b.len > 0
  if not ok:
    var y = ""
    var z = ""
    if splitFirst(s, ev"\s+instead\s+of\s+", y, z):
      a = z
      b = sub(y, ev"^\s*(?:use|put|write)\s+", "")
      ok = true
  if not ok: return fail("replace: what with what?")
  a = sub(a, ev"^\s*(?:all|every|each|any)\s+(?:(?:the\s+)?(?:instances?|occurrences?|uses)\s+of\s+)?", "")
  a = sub(a, ev"\s+(?:everywhere|globally|throughout)\s*[.!]?\s*$", "")
  b = sub(b, ev"\s+(?:everywhere|globally|throughout|in\s+(?:this|the)\s+(?:file|buffer))\s*[.!]?\s*$", "")
  result = "replace " & arg(a, true) & " " & arg(b, true) & opts & (if tg.len > 0: " " & tg else: "") & tail

proc buildInsert(s0: string): string =
  var s = s0
  var c: seq[string] = @[]
  var where = ""
  if take(s, ev"\b(?:at|on|before|above|into|in|as)\s+line\s+(\d+)\b", c) or take(s, ev"^\s*line\s+(\d+)\s*:", c) or
     take(s, ev"\bline\s+(\d+)\b", c):
    where = "(line " & firstNonEmpty(c) & ")"
  elif take(s, ev"\b(?:at|to|on|onto|in)\s+(?:the\s+)?(?:very\s+)?(?:top|beginning|start|head)(?:\s+of\s+(?:the\s+|this\s+)?(?:file|buffer|document))?\b|^\s*(?:the\s+)?(?:top|start|beginning)(?:\s+of\s+(?:the\s+)?file)?\s*:") or
       has(s, ev"\bprepend\b"):
    where = "(top)"
  else:
    discard take(s, ev"\b(?:at|to|on|onto|in)\s+(?:the\s+)?(?:very\s+)?(?:end|bottom)(?:\s+of\s+(?:the\s+|this\s+)?(?:file|buffer|document))?\b|^\s*(?:the\s+)?(?:end|bottom)(?:\s+of\s+(?:the\s+)?file)?\s*:")
    where = "(bottom)"
  var t = grab(s, ev"(@@\d+@@)")
  if t.len == 0:
    let e = verbEnd(s, ev"\b(?:insert|add|append|prepend|put|type)\s+")
    if e >= 0:
      t = substr(s, e)
      t = sub(t, ev"^(?:a\s+(?:new\s+)?line\s+|the\s+line\s+|the\s+text\s+)", "")
      t = sub(t, ev"^(?:saying\s+|that\s+says\s+|with\s+|containing\s+|reading\s+)", "")
  if t.len == 0: t = s
  if clean(t).len == 0: return fail("insert: no text")
  result = "insert " & arg(t) & " " & where

proc buildMove(s0: string): string =
  var s = s0
  var c: seq[string] = @[]
  var dest = ""
  if take(s, ev"(?:->|=>|→)\s*(?:line\s+)?(\d+)\b|\b(?:to|before|above|at|after|below|under)\s+(?:line\s+|position\s+|row\s+)?(\d+)\b", c):
    dest = firstNonEmpty(c)
  if dest.len == 0: return fail("move: to where?")
  let tg = takeTarget(s)
  result = "move " & (if tg.len == 0: "(current)" else: tg) & " " & dest

proc buildIndent(cmd, s0: string): string =
  var s = s0
  var c: seq[string] = @[]
  var n = ""
  if take(s, ev"\bby\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten|twenty)(?:\s+(?:levels?|steps?|tabs?|times|stops?))?\b", c) or
     take(s, ev"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|twenty)\s+(?:levels?|steps?|times|tab\s*stops?)\b", c) or
     take(s, ev"\b(twice|thrice|double|triple)\b", c):
    n = " " & toNum(firstNonEmpty(c))
  let tg = takeTarget(s)
  result = cmd & " " & (if tg.len == 0: "(current)" else: tg) & n

proc buildSort(s0: string): string =
  var s = s0
  var o = ""
  if take(s, ev"(?:,?\s*and\s+)?\b(?:unique|uniq|dedupe|deduplicate|(?:remove|drop|strip|eliminate)\s+(?:the\s+|any\s+|all\s+)?(?:duplicates?|dupes|repeated\s+lines)|get\s+rid\s+of\s+(?:the\s+|any\s+|all\s+)?(?:duplicates?|dupes)|without\s+duplicates?|no\s+duplicates?)\b"):
    o.add " (unique)"
  if take(s, ev"(?:,?\s*(?:and\s+|in\s+)?)\b(?:reversed?(?:\s+order)?|descending(?:\s+order)?|backwards|z\s+to\s+a)\b"):
    o.add " (reverse)"
  let tg = takeTarget(s)
  result = "sort " & (if tg.len == 0: "(buffer)" else: tg) & o

proc buildCase(s0: string): string =
  var s = s0
  let kind =
    if has(s, ev"\btitle|\bcapitali[sz]e\s+(?:each|every|all|the\s+first)"): "title"
    elif has(s, ev"\blower"): "lower"
    else: "upper"
  let tg = takeTarget(s)
  result = "case " & kind & " " & (if tg.len == 0: "(word)" else: tg)

proc build(cmd: string; s0: string): string =
  var s = s0
  case cmd
  of "cls", "defaults", "unsplit", "next", "prev": result = cmd
  of "cd": result = buildCd(s)
  of "theme": result = buildTheme(s)
  of "split":
    result = if has(s, ev"\b(?:down|below|under|underneath|beneath|bottom|horizontal(?:ly)?)\b"): "split down" else: "split right"
  of "undo", "redo": result = buildUndo(cmd, s)
  of "hunk":
    result = if has(s, ev"\b(?:previous|prev|last|back|earlier)\b"): "hunk prev" else: "hunk next"
  of "diff": result = buildDiff(s)
  of "run": result = buildRun(s)
  of "usages": result = buildUsages(s)
  of "decl": result = buildDecl(s)
  of "goto": result = buildGoto(s)
  of "open": result = buildOpen(s)
  of "save": result = buildSave(s)
  of "fnsearch", "find", "search": result = buildSearch(cmd, s)
  of "replace": result = buildReplace(s)
  of "insert": result = buildInsert(s)
  of "move": result = buildMove(s)
  of "indent", "dedent": result = buildIndent(cmd, s)
  of "sort": result = buildSort(s)
  of "case": result = buildCase(s)
  of "delete", "duplicate", "comment", "uncomment", "select":
    let tg = takeTarget(s)
    result = cmd & " " & (if tg.len == 0: "(current)" else: tg)
  else: result = fail("internal: " & cmd)

# ------------------------------------------------------------- driver

proc isAlnum(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9'}

proc extractQuotes(s: string): string =
  ## "..."  `...`  '...' (not apostrophes) -> @@i@@
  result = ""
  var i = 0
  while i < s.len:
    let ch = s[i]
    var close = '\0'
    if ch in {'"', '`'}: close = ch
    elif ch == '\'' and (i == 0 or not isAlnum(s[i-1])): close = '\''
    if close != '\0':
      var j = i + 1
      while j < s.len and not (s[j] == close and (close != '\'' or j+1 == s.len or not isAlnum(s[j+1]))):
        inc j
      if j < s.len:
        result.add " @@" & $quoted.len & "@@ "
        quoted.add substr(s, i+1, j-1)
        i = j + 1
        continue
    result.add ch
    inc i

proc sentenceBreaks(s: string): string =
  ## "word. Next" -> "word ; Next"
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '.' and i > 0 and (isAlnum(s[i-1]) or s[i-1] == '_') and i+1 < s.len and s[i+1] in {' ', '\t'}:
      var j = i + 1
      while j < s.len and s[j] in {' ', '\t'}: inc j
      if j < s.len:
        result.add " ; "
        i = j
        continue
    result.add s[i]
    inc i

proc normalize(s0: string): string =
  var s = " " & s0 & " "
  s = sub(s, ev"[()\[\]]", " ")
  s = sub(s, ev"\s&&?\s", " and then ")
  # "between lines 10 and 40" -> "10 to 40"
  while true:
    let (f, l) = findBounds(lc(s), ev"\d\s+and\s+\d")
    if f < 0: break
    s = substr(s, 0, f) & " to " & substr(s, l)
  s = sentenceBreaks(s)
  # politeness and framing
  s = sub(s, ev"^\s*(?:hey|ok|okay|so)\s*,?\s+", " ")
  s = sub(s, ev"^\s*(?:can|could|would|will)\s+you\s+", " ")
  s = sub(s, ev"^\s*(?:i\s+(?:want|need|would\s+like|'d\s+like)|i'd\s+like)\s+(?:you\s+)?to\s+", " ")
  s = sub(s, ev"\b(?:please|pls|plz|kindly)\b|\bfor\s+me\b|\bthanks?(?:\s+you)?\b", " ")
  # idioms
  s = sub(s, ev"\bfind\s+(?:and|&)\s+replace\b", "replace")
  block:   # "find X and replace it with" -> "replace X with"
    let (f, l) = findBounds(lc(s), ev"\s+and\s+replace\s+(?:it|them|those|each|all\s+of\s+them)\s+with\b")
    if f >= 0:
      let (vf, vl) = findBounds(lc(s), ev"\bfind\s+")
      if vf >= 0 and vl < f:
        s = substr(s, 0, vf-1) & "replace " & substr(s, vl+1, f-1) & " with" & substr(s, l+1)
  block:   # "cut X and paste at" -> "move X to"
    let (f, l) = findBounds(lc(s), ev"\s+and\s+paste\s+(?:it\s+|them\s+)?(?:at|to|before|on)\b")
    if f >= 0:
      let (vf, vl) = findBounds(lc(s), ev"\bcut\s+")
      if vf >= 0 and vl < f:
        s = substr(s, 0, vf-1) & "move " & substr(s, vl+1, f-1) & " to" & substr(s, l+1)
  block:   # "X after saving" -> "save and then X"
    let (f, l) = findBounds(lc(s), ev"\s+after\s+saving(?:\s+(?:the\s+|this\s+)?file)?\s*[.!]?\s*$")
    if f > 0: s = "save and then " & substr(s, 0, f-1)
  result = strip(s)

let optOnly = ev"^\s*(?:(?:remove|drop|delete|strip|eliminate)\s+(?:the\s+|any\s+|all\s+)?(?:duplicates?|dupes)|get\s+rid\s+of\s+(?:the\s+|any\s+|all\s+)?duplicates?|dedupe|deduplicate)\s*[.!]?\s*$"
let optStart = ev"^\s*(?:(?:remove|drop|delete|strip|eliminate)\s+(?:the\s+|any\s+|all\s+)?(?:duplicates?|dupes|repeated)|get\s+rid\s+of\s+(?:the\s+|any\s+|all\s+)?dup\w*|ask|confirm|prompt|match(?:ing)?\s+case|ignore|keep|only|reverse|in\s+reverse|case|whole|don't\s+include|do\s+not\s+include|except|exclude|skip)\b"

proc translate(input: string): seq[string] =
  result = @[]
  quoted = @[]
  let s = normalize(extractQuotes(input))
  # split into clauses; glue a piece back on when it has no verb of its own
  var seps: seq[string] = @[]
  var texts: seq[string] = @[]
  var prevSep = ""
  var start = 0
  let sep = ev"\s*,?\s*\b(?:and\s+then|and|then|after\s+that|afterwards)\b\s*|\s*;\s*"
  while start <= s.len:
    var caps: seq[Capture] = @[]
    let (f, l) = findBounds(lc(s), sep, caps, start)
    if f < 0 or l < f: break
    seps.add prevSep
    texts.add substr(s, start, f-1)
    prevSep = substr(s, f, l)
    start = l + 1
  seps.add prevSep
  texts.add substr(s, start)
  var pieces: seq[string] = @[]
  var pendingOpt = ""   # "remove duplicates and sort ..." -> option moves to the next clause
  for i in 0 ..< texts.len:
    let t = texts[i]
    if has(t, optOnly) and pieces.len == 0:
      pendingOpt.add " and " & t
    elif pieces.len > 0 and (detect(t).len == 0 or has(t, optStart)):
      pieces[pieces.len-1].add seps[i] & t   # option phrase like "and remove duplicates": keep it
    else:
      pieces.add t & pendingOpt
      pendingOpt = ""
  for p in pieces:
    if strip(p).len == 0: continue
    let cmd = detect(p)
    if cmd.len == 0:
      discard fail("no command recognized in: " & strip(restore(p)))
      return @[]
    let line = build(cmd, p)
    if failMsg.len > 0: return @[]
    result.add line

proc main() =
  var input = ""
  let args = commandLineParams()
  for i in 0 ..< args.len:
    if i > 0: input.add ' '
    input.add args[i]
  let res = translate(input)
  if failMsg.len > 0 or res.len == 0:
    if failMsg.len == 0: failMsg = "nothing to do"
    stderr.writeLine "nl2focim: " & failMsg
    quit 1
  echo join(res, "\n")

main()
