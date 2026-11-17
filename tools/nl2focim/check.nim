## Runs every case in `cases.json` through the nl2focim helper and compares the
## result with the expected commands.
##
##   nim c -r tools/nl2focim/check.nim [path/to/nl2focim]
##
## Written for host Nim, so checking the helper needs no Nimony; only building
## it does (see README.md). Two answers are the same when they are the same
## commands with the same arguments in order: options and targets -- the
## parenthesized parts -- may come in any order, and `tests/` and `"tests/"` are
## the same atom.

import std / [json, os, osproc, strutils, algorithm]

proc decode(s: string): string =
  ## the text of a NIF string literal without its quotes
  var i = 1
  while i < s.len - 1:
    if s[i] == '\\' and i + 1 < s.len - 1:
      case s[i+1]
      of '^': result.add '"'
      of '|': result.add '\\'
      of 't': result.add '\t'
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      else:
        result.add char(parseHexInt(s[i+1 .. i+2]))
        inc i
      inc i, 2
    else:
      result.add s[i]
      inc i

proc canon(s: string; i: var int): string =
  ## one node: an atom, or `(tag ...)` with its parenthesized children sorted
  while i < s.len and s[i] == ' ': inc i
  if s[i] == '(':
    inc i
    var atoms, subs: seq[string]
    while i < s.len and s[i] != ')':
      if s[i] == ' ': inc i
      elif s[i] == '(': subs.add canon(s, i)
      else: atoms.add canon(s, i)
    inc i
    subs.sort()
    result = "(" & atoms.join(" ") & " | " & subs.join(" ") & ")"
  elif s[i] == '"':
    let start = i
    inc i
    while i < s.len and s[i] != '"': inc i
    inc i
    result = "'" & decode(s[start ..< i])
  else:
    let start = i
    while i < s.len and s[i] notin {' ', '(', ')'}: inc i
    result = "'" & s[start ..< i]

proc canonAnswer(answer: string): string =
  ## every line is a command: its first word is the tag
  for line in answer.strip.splitLines:
    if line.strip.len == 0: continue
    var i = 0
    result.add canon("(" & line.strip & ")", i) & "\n"

proc main =
  let helper = if paramCount() >= 1: paramStr(1) else: currentSourcePath().parentDir / "nl2focim"
  if not fileExists(helper):
    quit "no helper at " & helper & "; build it first (see README.md)"
  let cases = parseFile(currentSourcePath().parentDir / "cases.json")
  var failed = 0
  for c in cases:
    let q = c["q"].getStr
    let (output, code) = execCmdEx(quoteShell(helper) & " " & quoteShell(q))
    let got = if code == 0: canonAnswer(output) else: ""
    var ok = false
    for e in c["expect"]:
      if got == canonAnswer(e.getStr): ok = true
    if not ok:
      inc failed
      echo "FAIL ", q, "\n  got:    ", output.strip.replace("\n", "; "),
           "\n  wanted: ", c["expect"][0].getStr.replace("\n", "; ")
  echo cases.len - failed, "/", cases.len, " cases pass"
  if failed > 0: quit 1

main()
