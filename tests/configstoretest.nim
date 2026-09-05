## Tests for the config directory: the file the editor reads and writes, and
## the copy it takes of one that was written by hand before a shipped config
## replaces it. Needs no window -- but it does touch a directory, so it points
## the config dir at a temporary one of its own and takes that away again.

import std/[os, strutils]
import uirelays/layout
import focim/[config, configstore]

# Before anything asks where the config lives. `getConfigDir` reads the first
# of these on Windows and the second everywhere else, so both are set and the
# test is the same test on every platform.
let sandbox = getTempDir() / "focim-configstore-test"
removeDir sandbox
createDir sandbox
putEnv("APPDATA", sandbox)
putEnv("XDG_CONFIG_HOME", sandbox)

var failures = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc equals(name: string; got, want: string) =
  check(name, got == want, "got '" & got & "' want '" & want & "'")

# ---------------------------------------------------------------------------
echo "the config directory:"
# ---------------------------------------------------------------------------

block:
  check("it is under the config dir the platform names",
        configPath("config.nif").isRelativeTo(sandbox),
        configPath("config.nif"))
  equals("with the app's own directory in between",
         configPath("config.nif").parentDir.lastPathPart, ConfigDirName)

block:
  # Writing one before there is a directory to write it into is the first
  # thing that ever happens on a new machine.
  saveConfig("config.nif", defaultConfig)
  equals("what was written is what is read back",
         loadConfig("config.nif"), defaultConfig)
  equals("a file that is not there reads as nothing",
         loadConfig("no-such-file.nif"), "")

# ---------------------------------------------------------------------------
echo "recognizing a shipped config:"
# ---------------------------------------------------------------------------

block:
  for it in ShippedThemes:
    var t = default(Theme)
    doAssert findTheme(it.name, t), it.name
    equals(it.name & " is known by what it says",
           shippedName(shippedConfig(t)), it.name)
  equals("the default config is the first of them",
         shippedName(defaultConfig), ShippedThemes[0].name)
  # Which is the whole question the backup turns on: anything that is not one
  # of them verbatim is somebody's own work and is kept.
  equals("one color changed makes it the user's",
         shippedName(defaultConfig.replace("#15171B", "#101010")), "")
  equals("so does a comment added to it",
         shippedName(defaultConfig & "# mine\n"), "")
  equals("and nothing at all is nobody's", shippedName(""), "")

# ---------------------------------------------------------------------------
echo "backing one up:"
# ---------------------------------------------------------------------------

block:
  const Mine = "(config # mine\n  (layout (editor)))\n"
  const Mine2 = "(config # mine, a week later\n  (layout (editor)))\n"
  let first = backupConfig("config", Mine)
  check("an edited config goes to a file", first.len > 0 and fileExists(first),
        first)
  equals("named for what it is", first.extractFilename, "config-backup.nif")
  equals("holding what it was handed", readFile(first), Mine)
  check("beside the config it was taken from",
        first.parentDir == configPath("config.nif").parentDir, first)

  let second = backupConfig("config", Mine2)
  equals("a second backup is numbered behind the first",
         second.extractFilename, "config-backup2.nif")
  equals("and the first still says what it said", readFile(first), Mine)
  equals("while the second says its own thing", readFile(second), Mine2)
  equals("a third goes on counting",
         backupConfig("config", Mine).extractFilename, "config-backup3.nif")

block:
  # A `.nif` extension because the file is one, and because that is what makes
  # `o config-backup.nif` open it colored like the config it came from.
  check("backups are config files by their name",
        backupConfig("config", "(config)").endsWith(".nif"))

block:
  # The other lane is counted apart: it is a different file, and a layout
  # saved off must not land on top of somebody's colors.
  let first = backupConfig("layout", "(layout (editor))")
  equals("a layout backup is named for its own lane",
         first.extractFilename, "layout-backup.nif")
  equals("and is numbered apart from the config's",
         backupConfig("layout", "(layout (a))").extractFilename,
         "layout-backup2.nif")

# ---------------------------------------------------------------------------
echo "the shipped layout:"
# ---------------------------------------------------------------------------

block:
  let l = parseLayout(defaultLayout)
  equals("it parses", l.error, "")
  check("and has the editor the app cannot do without", l.cell("editor"))
  check("along with the panels around it",
        l.cell("tabs") and l.cell("explorer") and l.cell("terminal") and
        l.cell("status"))
  check("its comment does not disturb the parser",
        defaultLayout.startsWith("#"), defaultLayout.substr(0, 20))
  check("no shipped config carries a layout of its own",
        not defaultConfig.contains("(layout"))

# ---------------------------------------------------------------------------
echo "moving a layout out of a config:"
# ---------------------------------------------------------------------------

const OldStyle = """
(config
  (layout
    (cols
      (rows (px 260)          # a comment inside the layout
        (tabs (lines 6))
        (explorer))
      (editor (stretch 4))))
  # mine, and it stays mine
  (theme
    (bg "#101014"))
  (track
    (compiler "nim")))
"""

block:
  var lay = ""
  let rest = takeLayout(OldStyle, lay)
  check("the layout comes out", lay.startsWith("(layout"), lay)
  check("with the size that was typed in it", lay.contains("(px 260)"), lay)
  check("and the comment that was in it too",
        lay.contains("# a comment inside the layout"), lay)
  check("dedented to the margin of a file of its own",
        lay.contains("\n  (cols\n"), lay)
  check("the config keeps its own comment",
        rest.contains("# mine, and it stays mine"), rest)
  check("and its colors", rest.contains("#101014"), rest)
  check("but not a word of the layout", not rest.contains("(cols"), rest)
  check("nor an empty line where it was",
        not rest.contains("\n\n"), rest.replace("\n", "\\n"))
  # Both halves are files in their own right afterwards. This is the whole
  # point: a config nobody can read again is worse than one with a layout in
  # it, and it would be found out one startup too late.
  let l = parseLayout(lay)
  equals("the layout half parses", l.error, "")
  check("as the window it was", l.cell("editor") and l.cell("tabs"))
  let c = parseConfig(rest)
  equals("and so does the config half", c.error, "")
  equals("with the color that was in it", $c.theme.bg.r, "16")

block:
  var lay = ""
  var once = ""
  let rest = takeLayout(OldStyle, once)
  check("what comes out has nothing left to take",
        takeLayout(rest, lay) == rest and lay.len == 0, lay)

block:
  var lay = ""
  const NoLayout = "(config (theme (bg \"#101014\")))"
  check("a config with no layout is handed back as it is",
        takeLayout(NoLayout, lay) == NoLayout and lay.len == 0, lay)
  check("and a config that is not one is not damaged",
        takeLayout("(nonsense", lay) == "(nonsense" and lay.len == 0, lay)

block:
  # The tag is only the layout when it *is* the layout: a widget of that name
  # is a cell like any other, and lives in the other file.
  var lay = ""
  const Bare = "(layout (editor))"
  check("a layout that is the whole file is left alone",
        takeLayout(Bare, lay) == Bare and lay.len == 0, lay)

removeDir sandbox

echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
