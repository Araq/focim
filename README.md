# focim

**focim** -- the Focussed Nim Editor. A code editor for focussed development,
highly opinionated: everything in the window is a text field, and the window
itself is one of them.

![focim](screenshots/focim.png)

Tab 0 is `[config]`, and its text *is* the `(config ...)` the editor is built
from -- the `(layout ...)` that places the widgets and the `(theme ...)` that
colors them. Editing it relayouts and recolors the window on the next frame,
so there is no settings dialog. A config that does not parse is reported in
the status bar with the line and column of the mistake and then ignored, so
the last good one keeps the window usable.

The same idea runs through the rest of it. There is no tab bar and no tree
view: the list of open tabs is an edit field whose lines are the tabs, so
deleting a line closes one, moving a line reorders them and `Ctrl+Z` reopens
the one just closed. The explorer is an edit field whose *first* line is the
path and the filter at once, so there is no open-file dialog either. Commands
are typed into the terminal or the status bar, and some of them act on the
buffer rather than on the machine.

## Download

Nightly binaries for Linux (x86_64 and ARM64), macOS (ARM64) and Windows
(x86_64) are published to
[Releases](https://github.com/Araq/focim/releases) by
[`nightly.yml`](.github/workflows/nightly.yml), one release per commit.
Extract and run `focim`, optionally with a file to open.

On Linux the binary links only libc: X11 is loaded at runtime, so
`libX11.so.6` and `libXft.so.2` have to be installed (`apt install libx11-6
libxft2`) along with at least one font fontconfig can find. macOS and Windows
need nothing.

## Building

focim is written with [uirelays](https://github.com/nim-lang/uirelays), which
gives it a window, a font and a mouse through the native API of each platform
-- WinAPI, Cocoa or X11, none of which needs a development package installed
to compile against. It is not on the Nimble package list yet, hence the URL:

```sh
nimble install https://github.com/nim-lang/uirelays
nimble build            # or: nim c -d:release --outdir:. src/focim.nim
./focim
```

`Ctrl+Space` completes out of a vocabulary that ships in `data/nimony.txt`,
which the editor looks for in `data/` next to its binary and one directory
above it -- so a `nimble build` in a checkout finds it as it stands. Without
it the editor starts out knowing the words in the open buffers alone.

## What it does

| | |
|---|---|
| [The config file](doc/config.md) | The layout and the theme, as the text of tab 0 |
| [Opening a file](doc/open.md) | `o synedit` finds `src/focim/synedit.nim` from anywhere in the project |
| [Completion](doc/completion.md) | `Ctrl+Space` offers the words that exist -- no compiler in the loop |
| [Tracking](doc/track.md) | `Ctrl+click` asks one: where a name is declared, and everywhere it is used |
| [Search and replace](doc/search.md) | `find`, `next`, `replaceall` -- no dialog, every match highlighted in place |
| [The clipboard panel](doc/clipboard.md) | The last thirty texts that entered the clipboard, `Ctrl+1` .. `Ctrl+9` to paste one |

The long version is the comment at the top of
[`src/focim.nim`](src/focim.nim), which is where the design notes live.

## Tests

```sh
nimble test             # or: nim c -r tests/tester.nim
```

Every test is a program that needs no window: the drawing path is watched
through stub relays, so what is checked is what the editor decided rather than
what a driver painted. The last step builds the editor itself.

## History

focim grew inside [uirelays](https://github.com/nim-lang/uirelays) as
`apps/focim.nim` plus most of what sat in `src/widgets/` -- of which only a
handful were widgets. It moved here with its commits; the paths were renamed
on the way, so `git log --follow` on a file still reaches back to the day it
was written.

## License

MIT
