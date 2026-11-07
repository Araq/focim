# Opening a file

`o <name>` / `open <name>`, in the terminal or on the prompt. `Ctrl+P` is the
prompt with `open ` already typed into it.

`Ctrl+N` opens a new tab onto a new file: `untitled-1.txt`, `untitled-2.txt`
and so on, in an `untitled` directory under the config dir. It is a file from
the first keystroke, so nothing typed into it can be lost -- it saves itself as
it is typed, it comes back with the session, and closing it leaves the file
where it is. `s <name>` moves it to where it belongs: the text goes to the new
name, and the untitled file is removed. The number is the lowest one free; an
untitled file that is empty and not open is used again rather than counted
past.

There is no file dialog and no fuzzy-finder window. What there is instead is a
name, typed with as much of it left out as one can get away with:

```
o xelim.nim        -> src/hexer/xelim.nim
o xelim            -> src/hexer/xelim.nim
o hexer/xelim.nim  -> src/hexer/xelim.nim
o hexer            -> the explorer, showing src/hexer
```

A relative path means what it would mean where it was typed: in the terminal,
relative to the directory the terminal is in; on the prompt, relative to the
file being edited (or the directory focim was started in, for a buffer with no
file). That same directory is "where the command was typed" below, and decides
which of two files is nearer. An absolute path is itself and nothing is
guessed about it.

## Three questions, cheapest first

Each is asked only because the one before it said no.

1. **The path as given**, against the directory the command was typed in.
   This is the file one was just looking at, and it costs a `fileExists`.
2. **The listing of that directory**, for a name with pieces missing. One
   `walkDir`.
3. **The projects of that directory and of every open tab**, walked, and
   ranked by nearness to where the command was typed before nearness to any
   tab.

The first two only look where the command was typed: a tab open in another
project must not answer before the project one is standing in was asked. In a
Nimony checkout `o strutils.nim` means Nimony's `lib/std/strutils.nim`, even
with Nim's `lib/pure` open in a tab. (The open tabs' own directories get the
cheap questions too, but only after the walk found nothing -- a tab in a
directory too big to walk is still a place to look.)

The first two answer instantly. What they
cannot answer is a project that has any shape to it: with only
`nimony/README.md` open, `xelim.nim` is three directories away in `src/hexer/`
and no list of open directories will ever hold it. That is what the walk is
for, and why it is last.

Steps 2 and 3 rank their candidates the same way, so the quick search and the
thorough one can never disagree about which of two files was meant.

## Where the walk starts, and where it stops

The project of a directory is the nearest directory above it that a version
control system or a package manager has claimed -- a `.git`, `.hg`, `.svn` or
`.jj`, or a `*.nimble`. That is what "the project" means to everybody who is
not a build system. A directory that nothing above it claims is its own
project, which is the right answer for a directory of loose files.

The walk never starts at the home directory, at the root of the file system,
or at anything either of them is inside of: a mistyped name must not turn into
a walk over everything one owns. It is bounded at 200,000 directory entries as
well, and says so when it stopped there rather than reporting the name as
missing:

```
cannot open: xelim.nim -- and the tree was too big to search all of it
```

Nothing is cached and no index is built. A file created a second ago is one of
the answers, and a walk over a checkout with its dependencies and three build
directories in it -- thirty thousand files -- takes about ten milliseconds,
which is less than the keystrokes that asked for it.

Left out of the walk: dotted directories, anything whose name starts with
`nimcache`, `node_modules`, `__pycache__`, build output (`.o`, `.exe`, `.so`
and the rest), and files with no extension at all -- far more often a binary
that got built here than the source anybody meant.

## Which of two files was meant

In this order:

1. **How exactly the name matches.** The whole path tail (`hexer/xelim.nim`),
   then the same ignoring case, then the name without its extension (`xelim`),
   then a prefix of the name, then a fragment from the middle of it. Only a
   *bare* name is guessed at that far: `sub/dir/thing` was meant to be a path,
   and answering it with a file from somewhere else would be a surprise.
2. **How near it is to where the command was typed** -- how many directories
   one has to climb out of that directory before the file is below it: none
   for anything inside it, one for a sibling, many for another project. Ties
   there are decided the same way by the directory of every open tab, in tab
   order.
3. **What kind of thing it is.** `.nim` before `.c` before `.md` before
   something an editor has no business with, and a file before a directory.
   This is what makes `o hastur` mean `src/hastur.nim` and not
   `icons/hastur.rc`, the two being otherwise the same match.
4. **How shallow it is**, so `src/hexer/xelim.nim` beats a vendored copy of it
   six directories down.
5. **Alphabetically**, so that the answer never depends on the order the file
   system happened to hand things out in.

A directory is only ever matched by its whole name, never by a fragment, and a
directory that matches is shown in the explorer rather than opened -- a
directory is not a buffer.
