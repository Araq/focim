# The config files

Two NIF files under `getConfigDir()/focim`, and each is a tab: `[config]` says
what the widgets look like and which compiler answers a Ctrl+click, `[layout]`
says where they go. Typing in either takes effect on the next frame.

`config.nif`:

```
(config
  (theme
    (bg "#15171B")
    (fg "#E6DFD1"
      (Keyword "#E5B94E")
      (Comment "#7A7365")))
  (track
    (compiler "nim")))
```

`layout.nif`:

```
(layout
  (toolbar (lines 2))
  (cols
    (sidebar (px 250))
    (divider (px 4))
    (editor))
  (status (lines 1)))
```

They were one file once, and a config written then still works: the
`(layout ...)` in it is moved to `layout.nif` the first time it is opened, the
file it came out of is kept as `config-backup.nif`, and the status bar says
so. Nothing is rewritten in the move -- both halves keep the comments and the
spacing they were written with.

The split is not tidiness. A theme is picked by replacing a whole lane (see
below), and while the two shared a file, picking one meant losing the layout
along with it -- your panel sizes were hostages of your colors. Two lanes, and
neither can spend the other.

# The layout

`layout.nif`, and the `[layout]` tab. One `(layout ...)` fills the file.

## Boxes

| Tag | Meaning |
|-----|---------|
| `(layout ...)` | The window. Its children are stacked top to bottom. Only allowed as the outermost tag. |
| `(rows ...)` | Children stacked top to bottom. |
| `(cols ...)` | Children placed left to right. |
| `(anything-else ...)` | A leaf, named by its own tag. |

`rows` and `cols` nest in each other.

```
(layout
  (cols
    (rows (px 200)      # a 200px wide column ...
      (tabs (lines 6))  # ... with two widgets in it
      (explorer))
    (editor (stretch 3))))
```

A misspelled `cols` therefore reads as a widget name, and the message says so,
pointing at the child that cannot be there:

```
3:10: 'col' names a widget, and a widget has no children; did you mean (rows ...) or (cols ...)?
```

The other side of that coin: a misspelled *widget* name is a perfectly good
layout for a widget nobody draws. Check for the cells you need after
resolving -- focim refuses a layout without an `editor` cell, since that is
where the layout itself gets typed.

## Sizes

A box may state its size along the axis its parent divides: a height inside
`rows`, a width inside `cols`. The outermost `(layout ...)` divides
vertically, so its children state heights.

| Size | Meaning |
|------|---------|
| `(px 250)` | 250 *logical* pixels: `resolve`'s `uiScale` turns them into the display's, so the same config gives the same window on a 4K laptop panel as on a 96 dpi monitor. |
| `(lines 5)` | `5 * lineHeight`, plus `padding` above and below. |
| `(stretch 2)` | Two shares of what the fixed sizes leave over. |

Leaving the size out means `(stretch 1)`, so `(editor)` fills what is
left. When a size is given it has to come before the children, so that it
cannot hide in the middle of a long list.

`resolve` hands the last stretching child the remainder of the division, so
children always fill their parent exactly instead of leaving a one pixel
seam: three `(stretch 1)` boxes in 100 pixels are 33, 33 and 34.

`gap` inserts pixels between adjacent boxes -- the background shows through
them, which is how focim draws its borders. Gaps come off the
stretching boxes, never off a `px` or `lines` one.

## Dragging the borders

The gaps between the panels are the borders, and the borders are grips: press
the left button on one and it follows the pointer until the button comes back
up. Nothing is drawn to mark them out until the pointer is on one, and then
the gap itself lights up in the color the theme gives a scrollbar grip.

What a drag moves is the two boxes on either side of the border. Everything
else in that container stays the size it is, so pushing one panel about does
not shuffle the rest of the window.

Each box is written back in the unit it was already written in, which is what
keeps the file readable after a drag:

| Written as | What a drag does to it |
|------------|------------------------|
| `(px N)` | follows the pointer to the pixel |
| `(lines N)` | snaps to whole lines, and the neighbour takes the remainder |
| `(stretch N)` | the weights of every stretching box in that container are rewritten from the pixels they now have |

A box cannot be dragged below twelve pixels: at nothing at all there would be
nothing left to catch hold of, and a panel that could only be brought back by
typing is not what a border is for.

The release writes the layout into the `[layout]` tab as one edit, so `Ctrl+Z`
there undoes the whole drag, and the tab is saved to `layout.nif` the way any
other edit of it is. What is written is the tree: a comment *inside* the
layout does not survive a drag, though the block of comment at the top of the
file does.

# The theme

`config.nif`, and the `[config]` tab, along with `(track ...)` below.

The tags inside `(theme ...)` are the field names of `Theme` and the tags
inside `(fg ...)` are the values of `TokenClass`, both spelled exactly as they
appear in `focim/theme.nim`. There is nothing to look up and nothing that
can fall out of sync when a field is added.

```
(theme
  (bg "#15171B")
  (fg "#E6DFD1"                     # the base color of every token class ...
    (Keyword "#E5B94E" (bold))      # ... and the ones that differ
    (StringLit "#2EC4B6")
    (Comment "#7A7365" (italics)))
  (selBg "#35474B"))
```

A color is `"#RRGGBB"` in a string literal.

focim's own config writes every token class out, so a class can be recolored
by editing its line instead of by first finding out that it exists. Delete the
ones you do not care about: what a config leaves unsaid keeps the color it
has.

| Tag | What it colors |
|-----|----------------|
| `(fg base? (Class "#RRGGBB" style*)*)` | text, per token class; the leading color is all of them at once |
| `(bg ...)` | the editor background |
| `(panelBg ...)` | the background of the panels around it: tabs, explorer, terminal, status bar |
| `(selBg ...)` | selection background |
| `(bracketBg ...)` | the matching bracket |
| `(cursorColor ...)` | the caret |
| `(lineNumColor ...)` | line numbers |
| `(markerBg ...)` | marker highlight, e.g. search hits |
| `(scrollBarColor ...)` | the scrollbar grip |
| `(scrollBarActiveColor ...)` | the grip while dragging |
| `(scrollTrackColor ...)` | the scrollbar track |
| `(activeLineBg ...)` | the line the cursor is on |
| `(actionColor ...)` | the frame around a line that acts on click |
| `(closeColor ...)` | the `(x)` on such a line |
| `(focusColor ...)` | the frame around the panel the keystrokes go to |

Anything left out keeps the value it has in the fallback theme, so a config
can change one color without restating the palette. The *base* color inside
`(fg ...)` is the exception, and the one to watch: it is every token class at
once, so a config that names one keeps nothing of the palette it was trimmed
down from. `(fg "#E6DFD1" (Keyword "#E5B94E"))` is an off-white editor with
gold keywords and nothing else -- `Green`, `Yellow` and `Red` included, which
is what the terminal colors its output by.

## The shipped themes

Three configs come with the editor, and the prompt hands them out:

| Typed in the prompt | What happens |
|---------------------|--------------|
| `theme` | lists the themes and says which one is up |
| `theme dusk` | dark, gold and turquoise -- the one a fresh config names |
| `theme mocha` | dark, Catppuccin Mocha |
| `theme paper` | light, ink on paper |
| `defaults` | both lanes back to what the app ships: `theme dusk` and the shipped layout |

A theme here is the whole `[config]` lane and not a palette painted over the
text that is there: what lands in the tab is that theme written out in full --
every field and every token class -- and the shipped tracking default. No
color of the previous theme is left standing in a corner of the window. The
`[layout]` lane is not touched at all: where the panels are has nothing to do
with what color they are.

Which means switching themes replaces a config that was edited. Two things
keep that from costing anything. It is an ordinary edit, so `Ctrl+Z` in the
`[config]` tab brings the old text straight back; and before the edit is made,
a config that is not one of the three verbatim is written to
`config-backup.nif` next to `config.nif`, so it outlives the session as well.
(`defaults` puts back both lanes, so it backs up an edited `layout.nif` the
same way, as `layout-backup.nif`.)
That file is never overwritten -- the next backup is `config-backup2.nif`,
then `config-backup3.nif` -- because the second theme switch of an afternoon
must not be what loses the config the first one was protecting. Open one with
`o ~/.config/focim/config-backup.nif` (or wherever `getConfigDir()` points on
your platform) to take pieces of it back.

The terminal knows none of these words: there `theme` and `defaults` are
programs' names, and macOS ships one of exactly the latter name.

## Writing a theme of your own

The shipped configs are written *out of* a `Theme` object by the same code
that writes any theme, so what they look like is what the format can say --
there is no field a theme has that the file cannot name. Start from the one
closest to what you want, change the colors that bother you, and stop; nothing
has to be complete, since what a config leaves unsaid keeps the color it has.

A theme whose text could not be read on its own background is refused: the
status bar says which color it was and by how much, and the window keeps the
theme it had, since the file that would have to be corrected is displayed in
those very colors. The bar is 3.0:1 for every token class, the caret, the line
numbers and the `(x)`, measured against the background each of them is drawn
on.

## Bold and italics

A token class may say how its text is cut, behind the color:

```
(fg
  (Keyword "#E5B94E" (bold))
  (Comment "#7A7365" (italics))
  (Directive "#1FA398" (bold) (italics)))
```

| Tag | Meaning |
|-----|---------|
| `(bold)` | the bold face of the same family |
| `(italics)` | the italic face |

Both are wishes. A family without the face -- and a driver that cannot ask for
one -- draws the regular face, so a style can never make text vanish. Nothing
here moves anything: the faces of a monospaced family share its advance width,
so a bold keyword sits on the same grid as the code around it.

A class that names its color also names its style, so a class listed *without*
`(bold)` or `(italics)` is upright, whatever the fallback theme does. The
style tags belong behind a color, inside the class -- `(bold)` on its own
directly under `(fg ...)` is refused, since "all classes bold" is not a thing
anyone means to say.

# Tracking

`(track ...)` says who answers "where is this name?" when a `.nim` file is
Ctrl+clicked, and what to run them by. See `track.md` for what the
answer looks like.

```
(track
  (compiler "nim")
  (exe "/home/me/nim/bin/nim"))
```

| Tag | Meaning |
|-----|---------|
| `(compiler "nim")` | `nim track PROJECT --defusages:FILE,LINE,COL` |
| `(compiler "nimony")` | `nimony check PROJECT --def:...`, then `--usages:...` |
| `(compiler "none")` | nobody; Ctrl+click says so instead of starting anything |
| `(exe "...")` | the binary to run |

Leaving `(exe ...)` out runs the compiler under its own name, found on the
`PATH` like any other command -- so `(track (compiler "nim"))` is enough for a
normal installation, and the setting is there for a checkout that wants to be
read by the compiler it is being built with. A config that says nothing about
tracking gets `nim`, which is what the shipped one writes out so that the line
is there to be edited rather than to be discovered.
