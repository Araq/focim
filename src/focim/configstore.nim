## configstore.nim -- where a config lives on this machine, and the configs
## the editor hands out.
##
## The parsing is `config.nim`'s; this is the other half of it. A config file
## is read at startup, written back on every edit that parses, and -- when a
## shipped one replaces one that was written by hand -- moved out of the way
## first. All of it is best effort: an unwritable config directory must not
## take an editor down, so nothing here raises and a caller that cares is told
## by an empty answer.

import std/os
import config

const
  ConfigDirName* = "focim"

proc configPath*(name: string): string =
  getConfigDir() / ConfigDirName / name

proc saveConfig*(name, text: string) =
  ## Best effort: an unwritable config dir must not take the editor down.
  try:
    createDir(configPath(name).parentDir)
    writeFile(configPath(name), text)
  except CatchableError:
    discard

proc loadConfig*(name: string): string =
  try:
    result = readFile(configPath(name))
  except CatchableError:
    result = ""

# ---------------------------------------------------------------------------
# The config the app ships with. Its layout and its tracking default are text,
# because they are the same whichever theme is picked; the theme in the middle
# is written out of a `Theme` by `themeText`, so a theme has to be a thing the
# program can *hold* before it can be a thing the file offers -- and the file
# can never fall behind the object it came from. `ShippedThemes` in `theme.nim`
# is the list; the first of them is what a fresh config says.
# ---------------------------------------------------------------------------

const configHead = """
(config
  (layout
    (cols
      (rows (px 200)
        (tabs (lines 6))
        (explorer))
      (editor (stretch 4))
      (rows (stretch 2)
        (clipboard (lines 9))
        (history (lines 5))
        (terminal)))
    (status (lines 1)))
  # Anything left out keeps the color it has; `doc/config.md` lists the
  # fields. Every token class is written out below, so any of them can be
  # recolored by editing its line rather than by first finding out that the
  # class exists. A color may be followed by (bold), by (italics), or by both.
"""

const configTail = """
  # Who answers a Ctrl+click on a name: "nim", "nimony", or "none" for nobody.
  # (exe "...") names the binary when it is not simply on the PATH.
  (track
    (compiler "nim")))
"""

proc shippedConfig*(t: Theme): string =
  ## One whole config file: the layout, `t`, and the tracking default.
  configHead & themeText(t) & "\n" & configTail

const ShippedConfigs* = block:
  # Made once, at compile time, so that recognizing the config in the tab as
  # one of them is a handful of string comparisons and not a re-render.
  var res: seq[string] = @[]
  for it in ShippedThemes:
    var t = default(Theme)
    doAssert findTheme(it.name, t), it.name
    res.add shippedConfig(t)
  res

const defaultConfig* = ShippedConfigs[0]

proc shippedName*(text: string): string =
  ## Which shipped config `text` is, "" for one that has been edited. Nothing
  ## more is asked of it than that: a config with a color changed in it is
  ## somebody's own, whichever theme it started life as.
  for i in 0 ..< ShippedThemes.len:
    if text == ShippedConfigs[i]: return ShippedThemes[i].name
  result = ""

proc backupConfig*(text: string): string =
  ## Put `text` where it can be found again and answer with the path it went
  ## to; "" when the config dir could not be written, which is the same
  ## silence `saveConfig` keeps.
  ##
  ## Numbered rather than overwritten: switching themes twice is a normal
  ## thing to do, and the second switch must not be what loses the config the
  ## first one was protecting. The hundredth reuses the last name, by which
  ## point the directory has said everything it has to say.
  var name = "config-backup.nif"
  var n = 2
  while fileExists(configPath(name)) and n <= 99:
    name = "config-backup" & $n & ".nif"
    inc n
  result = configPath(name)
  try:
    createDir(result.parentDir)
    writeFile(result, text)
  except CatchableError:
    result = ""
