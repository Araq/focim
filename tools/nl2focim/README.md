# nl2focim

A helper that turns a request in plain English into focim commands, written
in NIF line syntax:

```
$ nl2focim "replace all foobar with Foobar, whole words only, in every open tab"
replace foobar Foobar (word) (tabs)
$ nl2focim "save the file and then run nimble test"
save
run "nimble test"
$ nl2focim "rename every .txt file so that draft becomes final"
replace draft final (filenames) (ext txt)
```

It is not wired into the editor yet, and focim does not depend on it: nothing
in `focim.nimble` builds it. The idea is that the prompt hands a line it does
not recognize as a command to this helper, shows what came back -- `→ replace
foo bar (ask)` -- and runs it when the user confirms. The helper never runs
anything itself.

There is no language model in it. It is about 750 lines of rules: a table of
verbs and their synonyms, patterns for targets (`lines 10 to 40`, `the
selection`, `this word`) and options (`case sensitive`, `whole words`, `ask me
first`), and some normalization (politeness, `find X and replace it with Y`,
`X after saving`). A request it cannot read is refused with a reason rather
than guessed at. On paraphrases it had never seen it was right about three
times in four, which beat the 1--4B models we measured with the same
vocabulary even with grammar-constrained decoding, at a millisecond per call
instead of 0.1--0.7 seconds and with nothing to download.

## Building

It is a Nimony program, because the patterns are compiled by `std/rex` while
the program is compiled: the binary contains finished automata and no regex
engine, and a call costs about 1 ms including starting the process.

```sh
cd tools/nl2focim
~/projects/nimony/bin/nimony c -d:release --out:./nl2focim nl2focim.nim
```

The patterns use the non-deterministic mode (`reAllowEvil`), via the `ev`
template: most of them only answer "does it match, and where", and the
leftmost-longest match is what is wanted there. Where a capture would be
ambiguous -- the `A` and `B` of `replace A with B` -- the split is made in code
at the first separator instead. rex has no case-insensitive flag, so the
patterns are lowercase and run on a lowercased copy of the request; arguments
are then cut out of the original, which keeps `Foobar` intact.

## Checking

```sh
nim c -r tools/nl2focim/check.nim [path/to/nl2focim]
```

runs the cases in `cases.json` with host Nim. Options and targets may come in
any order, and `tests/` and `"tests/"` count as the same atom.

## The commands

The output is a proposal for the prompt's vocabulary. Some of it is what
focim already has, some of it is not there yet -- the editing commands and
`(filenames)` in particular -- and one thing differs on purpose: `replace`
replaces every match without asking unless `(ask)` is given, since "replace
all foobar with Foobar" is the common request.

| | |
|---|---|
| `open PATH`, `save`, `save PATH` | |
| `goto N`, `goto (top)`, `goto (bottom)`, `goto (decl NAME)` | |
| `usages NAME`, `select TARGET` | |
| `find TEXT OPTS`, `next`, `prev` | OPTS: `(case)` `(word)` `(tabs)` |
| `replace TEXT WITH OPTS` | as for find, plus `(ask)`, plus a TARGET to limit it to |
| `search TEXT OPTS` | the project's files; `(case)` `(word)` `(ext E)` `(exclude PATH)` |
| `search TEXT (filenames)` | the files whose *name* contains TEXT |
| `replace TEXT WITH (filenames)` | rename files; takes `(ext E)` `(exclude PATH)` too |
| `delete`, `duplicate`, `comment`, `uncomment TARGET` | |
| `move TARGET N` | move it to line N |
| `insert TEXT (line N)`, `(top)`, `(bottom)` | |
| `indent TARGET [N]`, `dedent TARGET [N]` | |
| `sort TARGET (unique) (reverse)` | |
| `case upper`, `lower`, `title TARGET` | |
| `undo [N]`, `redo [N]` | |
| `diff [REV]`, `hunk next`, `hunk prev` | |
| `split right`, `split down`, `unsplit` | |
| `theme NAME`, `defaults`, `cd DIR`, `cls` | |
| `run "COMMAND"` | anything else, as a shell command |

A TARGET is `(line N)`, `(lines A B)`, `(current)` for the caret's line,
`(selection)`, `(word)` for the word at the caret, or `(buffer)`. Several steps
are several lines.

## What it gets wrong

Mostly phrasing it has no rule for yet: ranges written as "the first 30
lines", "move this line left" for `dedent`, "place X at the very top". File
names are the weakest part, partly because the requests are ambiguous: "find
nim files containing 'test'" may be about their names or their contents. A
rule found wanting is usually one more synonym or one more pattern; the cases
in `cases.json` are the ones it must keep getting right.
