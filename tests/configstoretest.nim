## Tests for the config directory: the file the editor reads and writes, and
## the copy it takes of one that was written by hand before a shipped config
## replaces it. Needs no window -- but it does touch a directory, so it points
## the config dir at a temporary one of its own and takes that away again.

import std/[os, strutils]
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
  let first = backupConfig(Mine)
  check("an edited config goes to a file", first.len > 0 and fileExists(first),
        first)
  equals("named for what it is", first.extractFilename, "config-backup.nif")
  equals("holding what it was handed", readFile(first), Mine)
  check("beside the config it was taken from",
        first.parentDir == configPath("config.nif").parentDir, first)

  let second = backupConfig(Mine2)
  equals("a second backup is numbered behind the first",
         second.extractFilename, "config-backup2.nif")
  equals("and the first still says what it said", readFile(first), Mine)
  equals("while the second says its own thing", readFile(second), Mine2)
  equals("a third goes on counting",
         backupConfig(Mine).extractFilename, "config-backup3.nif")

block:
  # A `.nif` extension because the file is one, and because that is what makes
  # `o config-backup.nif` open it colored like the config it came from.
  check("backups are config files by their name",
        backupConfig("(config)").endsWith(".nif"))

removeDir sandbox

echo(if failures == 0: "ALL PASS" else: $failures & " FAILURE(S)")
if failures > 0: quit 1
