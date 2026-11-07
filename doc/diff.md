# Diff mode

`diff` in the prompt shows where the tab differs from a revision -- on the
file itself. The tab stays the file: it is edited, saved and searched as
always, and the diff is drawn around the text, never in it.

| | |
|---|---|
| `diff` | diff mode for this tab, against `HEAD`; typed again, off |
| `diff <rev>` | against any revision -- `diff master`, `diff HEAD~3`; in diff mode, moves it there |
| `diff branch` | against where this branch forked from the default branch |
| `hunk next`, `hunk prev` | to the next or the previous hunk, round the file |
| `Alt+Down`, `Alt+Up` | the same, while the tab is in diff mode |

A bare `diff` toggles; one that names a revision never turns the mode off,
so `diff master` and then `diff HEAD` compare twice without leaving. A
revision that does not exist is reported and changes nothing.

In the terminal `diff` is the program of that name, as it should be: diff
mode is the prompt's.

## What it shows

The colors are the ones a `git diff` has in the terminal, so the two read
the same:

- a line the base does not have: a green bar at its edge, and a green tint
- a line that replaces lines of the base: the same, in yellow
- lines of the base that are gone: shown where they stood, on a red band,
  dimmed -- and for a change, the old lines above the ones that replaced
  them, so old and new read top to bottom

The same colors mark the scroll bar, at the height each hunk has in the whole
file, so the hunks of a long file can be seen at a glance and gone to by
dragging the grip there.

The status bar says what the tab is compared with -- `diff vs HEAD: 3 hunks`
-- and the tab list marks every tab in diff mode with a bar of its own.

The hunks follow the typing: every edit is diffed again before the next
frame. An unchanged file says `no changes` and stays in diff mode, so the
first hunk appears as it is typed.

## When HEAD moves

A commit, a checkout, a branch switch: the disk check notices that HEAD
moved and reads the base again, so `HEAD` keeps meaning what was last
committed and `branch` the fork of the branch that is checked out now.

## Branch switches

The files a switch in the branches panel opens come up in `diff branch` mode
-- a switch lands in a review of the branch. A tab in `branch` mode that
stays open across a later switch is compared with the new branch's fork, and
on the default branch itself, which has no fork, it leaves diff mode.

## Deleted lines

The lines the base had are drawn between the lines of the file, but they
are not text: the caret does not go into them, a selection does not take
them, and saving, searching and the word index never see them. A click on
one puts the caret on the line below it.

A block of them is shown up to about a third of the panel's height, and
then a row that says how many more there are -- `… 180 more deleted lines`.
A click on that row prints the whole hunk in the terminal, as `git diff`
would, with a `path:line:` above it that goes back to it.

## Not yet

Reverting a hunk and staging one are the next steps.
