# tests

The test kit for sleepyshell. It lives in the repository, in the shell's own folder, and the shell never
loads anything from here. It runs on any machine: every path comes from the kit's own location and the
XDG variables, never from a user name or a fixed home folder.

The shell folder is also the repository root, so the kit knows which files are the repository's and not
the shell's (`REPO_DIRS` and `REPO_FILES` in `common/env.sh`: `.git`, `.github/`, `tests/`, `docs/`,
`gallery/`, `assets/`, `tools/`, the root documents): it never copies, compiles, diffs, deploys, removes
or backs them up.

## Safety model

A test may read the system but never change it, and nothing it does reaches the user's session. Four
layers make sure of that:

1. **Sandbox** (`common/sandbox.sh`). Everything a test starts runs inside bubblewrap:
   - the whole file system is read-only, and only the run's own folder can be written (plus a private `/tmp`);
   - the home folder is a fresh one inside the run folder (`SANDBOX_HOME=real` keeps the real one,
     read-only, for the few script tests that need it);
   - the runtime folder is an empty private tmpfs: no live Wayland or Hyprland socket, so nothing a
     test starts can draw on the real screen or send a dispatch to the real compositor;
   - no system D-Bus (logind, NetworkManager, UPower, power profiles) and no session D-Bus, no PipeWire,
     no network and no view of outside processes;
   - `/dev` holds only the basic devices and the GPU's render node: no display card, no input device,
     no terminal.
2. **Checksum guard** (`common/guard.py`). A sha256 of every real file a test could reach (the live shell
   and its settings file, the Hyprland config, matugen's config and colours, the folder icon overlay, the
   default apps list) is taken before a run and compared after it. Any difference fails the run.
3. **Cleanup** (`common/cleanup.sh`). A run's processes die with its sandbox; cleanup then stops anything
   that still points into the run's folder, deletes the folder, and fails if a process or window is left.
   It only ever matches paths under the run folder: never the live shell, the live settings window or
   lock, or a preview.
4. **Run folders on tmpfs.** Runs live under `$XDG_RUNTIME_DIR/sleepyshell-tests/<run>`, in memory,
   one folder per run, so tests can run side by side and nothing survives a logout.

`bash common/selftest.sh` proves all of this on the current machine, and that the private test desktop
(below) starts inside the sandbox. `tests/run.sh` runs it first and stops if it fails.

### The private test desktop

Whole-window tests run the real entry files (`shell.qml`, `sleepysettings.qml`, `sleepylock.qml`,
`sleepykeys.qml`) on a desktop of their own, started inside the sandbox by `common/ui/session.sh`:

- **a headless sway** with one 2560×1440 output, drawn in software. It is a separate compositor on its
  own socket in the sandbox's runtime folder; nothing appears on the user's screen. (Hyprland cannot run
  headless here: its backend library needs the real display card or a parent compositor.) It provides
  real layer surfaces, a session lock, real input routing and screenshots;
- **a virtual pointer and keyboard** (`common/ui/wlinput.py`, Wayland's virtual input protocols): the
  test's clicks and keys reach the windows the way a user's do, so a hidden, covered or greyed control
  does not answer. The user's cursor and keyboard are never involved;
- **a stand-in Hyprland** (`common/ui/fakehypr.py`): its two sockets answer from a small state (one
  monitor, workspaces 1–5), log every request and dispatch, apply a workspace switch and send the events
  Hyprland would, and take test-sent events such as `custom>>sleepyshell:toggle:session`;
- **a private session bus** with no service activation, so the bar can be the notification server;
- **logging stand-ins** for the programs the shell launches (`common/ui/fake.py`, linked under each
  program's name; `hyprctl` talks to the stand-in Hyprland): each call is logged to the run's
  `commands.log`, and nothing is really run.

The driver (`common/ui/driver.qml`) is added to a **run copy** of an entry file, never to the shell's own
files (`common/ui/prepare.py`, `inject.py`). It only reads: which windows exist, where an item is, what it
shows, and the values of the shell's services. In the copy every window registers itself in a small
registry, because Quickshell offers no list of windows to scripts.

Lock tests point the run copy's lock at a test PAM stack in the run folder (`ui.pam_stack`): a script that
accepts one test password and counts every check. The account's own PAM and `pam_faillock` are never
asked; `ui.py` refuses to start a lock without the test stack.

### Watch mode (opt-in)

`bash run.sh --watch …` shares the private test screen live in a VNC viewer on the user's desktop: wayvnc
runs inside the sandbox with input disabled, on a Unix socket in the run folder (the sandbox has no
network), and `vncviewer -ViewOnly` connects from outside. The viewer can only watch;
`kit/watch-view-only.test.py` proves that a click through the VNC connection reaches nothing. Without
`--watch` nothing listens, so the suite runs the same unattended and in CI. Needs `wayvnc` and
`tigervnc`.

## Commands

Run them from this folder.

| Command | What it does |
|---|---|
| `bash run.sh` | Selftest, then every test of every area. |
| `bash run.sh settings` | One area: `settings`, `keys`, `bar`, `lock`, `kit`, `install`. |
| `bash run.sh settings/export-asks.test.py` | One test. |
| `bash run.sh --twice …` | Each test twice; different results fail (determinism). |
| `bash run.sh --watch …` | Watch the test screen in a view-only VNC viewer. |
| `bash run.sh --update-refs …` | Keep screenshots as candidate references instead of comparing. |
| `bash common/selftest.sh` | Prove the isolation on this machine. |
| `bash common/compile.sh TREE` | Compile every `.qml` of a tree (entry files included) in the sandbox; nothing is instantiated. |
| `bash preview.sh start [TREE]` | Run a candidate as the real bar in place of the live shell; falls back to the live shell if it does not load. |
| `bash preview.sh stop` | Stop the preview and start the live shell again. |
| `bash preview.sh status` | What runs now. |
| `bash deploy.sh plan TREE` | What a deploy would add, change and remove. Writes nothing. |
| `bash deploy.sh apply TREE` | Compile gate, full backup, copy (new files first), remove what moved, verify, restart or reload, wait for the shell to load; rolls back by itself if it does not. |
| `bash deploy.sh rollback [BACKUP]` | Put the newest (or the named) backup back. |
| `bash deploy.sh list` | The backups. |
| `bash common/cleanup.sh [RUN]` | Stop and delete one run, or every run. |
| `python3 common/guard.py snapshot NAME` / `verify NAME` / `targets` | The checksum guard by hand. |

A *tree* is a copy of the shell: the live folder itself, or a candidate copied from it without the
repository's files. The user's state (`sleepysettings.toml`, `settings.json` and their copies) is never
deployed, removed or restored by a rollback. `deploy.sh` tests itself on a scratch copy when
`SLEEPYSHELL_LIVE` (and `SLEEPYSHELL_BACKUPS`) point elsewhere; it then never stops, starts or reloads a
shell. `preview.sh` and `deploy.sh` act on the live session by design; tests never do.

## Layout

```
tests/
├── run.sh          the runner
├── common/         the safety layers: env.sh, sandbox.sh, guard.py, cleanup.sh, compile.sh, treediff.py,
│   │               hypr.py, selftest.sh
│   └── ui/         the private test desktop and the driver: session.sh, wlinput.py, fakehypr.py,
│                   fakehyprctl.py, fake.py, prepare.py, inject.py, driver.qml, ui.py, run-ui.sh
├── settings/       the settings window: ask-first prompts, rows, Apply, Discard, leaving, reset, search
├── keys/           the Keybinds window
├── bar/            the bar: islands, session menu, notifications, the settings link, images
├── lock/           the lock screen
├── kit/            the kit itself (watch mode)
├── install/        the installer: every question, refusal and record, with stand-ins for pacman, sudo and the rest
├── fixtures/       a small Hyprland config every whole-window test starts with
├── refs/           reference images of the visual checks
├── preview.sh      run a candidate as the bar
├── deploy.sh       deploy, rollback
├── candidate/      (not in git) the tree being worked on, deleted after it is deployed
├── backups/        (not in git) one folder per deploy: live.tar.gz, plan.json, candidate.txt
├── jobs/           (not in git) work folders; jobs/failed/ keeps the images of failed visual checks
└── legacy/         (not in git) the previous kit, no longer used by any suite
```

## What we test and how to add a test

A failing test must always mean something a user would care about. The suite exists to catch security
holes and broken core functionality, nothing else.

### How to judge importance

Rank by impact if it breaks:

1. **Security**: leaking data, running untrusted input, writing or overwriting a user's files without
   asking, weakening the lock screen or polkit prompt, anything exposed over the socket or IPC.
2. **Data loss or a broken desktop**: corrupted settings file, Apply writing wrong values, the bar
   failing to load, lock or unlock failing.
3. **Core everyday functions**: settings stage, preview, Apply, Discard and revert; the socket link;
   notifications; the keybinds list.
4. **Cosmetic**: looks, animations, night light and similar.

Proportion: most tests on tiers 1–2, a handful on tier 3, at most one smoke test per cosmetic feature.

Every test names the concrete failure it protects against; if you can't name a realistic failure a user
would notice or be hurt by, don't write it. Prefer one test on a shared piece (for example the row types
every setting uses) over many per-setting tests; no variations that can't fail independently.

### Rules

- Everything runs inside the sandbox; nothing touches the live session: no windows on the real screen, no
  dispatches to the real compositor, never move or click the real cursor, no writes outside the run's
  folder. One exception: `lock/hypridle-restart.test.sh` needs the user's systemd (a transient stand-in
  unit for hypridle and the lock's scope), so it runs outside the sandbox, keeps its files in the run
  folder, never touches the real hypridle or lock file, and shows its units gone at the end.
- The installer's tests (`install/`) run install.sh against stand-ins of every program that installs, enables or
  starts something (`install/stub.py`): no package is ever installed and no service enabled, on the machine or
  in the sandbox.
- No new packages for the shell. The kit itself needs `sway` (the private test desktop), `grim`
  (screenshots) and `lua` (the key reporter's test), and for watch mode only `wayvnc` and `tigervnc`.
- Never test the lock against the account's PAM; lock tests use the test stack (`ui.pam_stack`).
- Deterministic: the same result every run (`run.sh --twice` checks it).
- A whole-window test acts like a user: clicks and keys through the virtual devices, scrolling with the
  wheel and opening a collapsed section to reach a row. Reading state through the driver is fine;
  changing it through the driver is not, except to set up what a user could not (a missing program
  through `Deps.fakeMissing`, a script-only IPC call).

### How to check results

In order of preference:

1. **State and files**: settings values, socket messages, the written settings file, `commands.log`
   (what would have run), the stand-in Hyprland's log.
2. **The UI's structure**: which dialog is open and the exact lines it shows, which row shows which value,
   what is enabled or greyed.
3. **Screenshots**: only for things that are truly visual, compared with a tolerance.

### Test architecture

Three kinds of test, all run by `run.sh`:

1. **Whole-window tests** (`<area>/<name>.test.py`, most new tests). The real entry file on the private
   test desktop, driven like a user drives it (`common/ui/ui.py`: `click`, `toggle`, `tab`, `apply`,
   `dialog`, `reveal`, `Input.type`, `Input.key`). They cover the click itself, the wiring between the
   window's parts (a tab that never received its confirm dialog), the question a user sees and what is
   written afterwards.
2. **Script and harness tests** (`<area>/<name>.test.sh`). A script or one service through a small QML
   harness, offscreen, for cases no window can set up (a check that hangs, a server that dies mid-Apply,
   a remote image URL in a notification).
3. **Visual checks**: a screenshot of the private desktop compared with a reference in `refs/`.

Approaches that were checked and are not used:

- Qt Quick Test (`qmltestrunner`) for the row types: it is installed, but it cannot load Quickshell's
  types, which live only inside the `qs` binary; every row would need stand-ins for `Settings`, `Theme`
  and `Deps`, so the test would check the stand-ins.
- A headless Hyprland inside bubblewrap: its backend library gets its buffers only from the real display
  card (with a seat) or from a parent compositor (the live one); there is no headless-only mode. While
  trying, it reached logind over the system bus, which is why the sandbox hides the system bus.
- The accessibility tree (AT-SPI): an offscreen window never registers on it, and the shell gives its
  controls no accessible names or actions.
- Offscreen Qt with simulated events: clicks work, but there are no layer surfaces (the bar, the lock and
  the popups cannot run) and grabbed images come back empty.

### Determinism for visual checks

The theme's built-in palette (the test home has no `colors.json`), the system's fonts, a fixed screen
size, the pointer parked away from the window, animations given time to end. Live values (the clock, this
machine's CPU and memory) are cropped out.

### Reference images

One per visual check, in `refs/`. A failing comparison keeps the actual image and a diff in
`jobs/failed/<run>/`. Updating references is an explicit step, never automatic:
`bash run.sh --update-refs <test>` keeps candidates in `jobs/failed/`, which are looked at and copied to
`refs/` by hand.

### Checked only by eye on the live session

The real Hyprland (its layer rules, binds and events as Hyprland sends them), the real PAM and polkit,
battery, lid and backlight hardware, the tray with real apps, audio through PipeWire.

### Adding a test, step by step

1. **Pick the tier and name the failure.** Write down the concrete failure the test protects against
   and its tier (above), in the test's first lines. No failure, no test.
2. **Pick the kind.** A whole-window test when a user's action is involved; a script test for what no
   window can set up; a visual check only for a look.
3. **Where it goes:** the area folder of the part of the shell, as `<name>.test.py` (whole window) or
   `<name>.test.sh` (script). Every other file in an area folder is a helper.
4. **A whole-window test** starts with `from ui import Shell, Input, check, done, RUN` and gets the run
   copy's path as `sys.argv[1]`. Fixtures go into the run folder before the launch (`RUN / "home"` is the
   test's home; `RUN / "s/sleepysettings.toml"` the copy's settings). `Shell.launch(tree, "sleepysettings.qml")`
   starts an entry file; `check(ok, what, detail)` prints one `PASS` or `FAIL` line; end with `done()`.
   `common/ui/run-ui.sh` does the rest: run folder, guard, run copy, sandbox, private desktop, cleanup.
5. **A script test** follows the pattern of `settings/ask-first-writers.test.sh`: a run folder
   `$RUN/<name>-$$` with an `EXIT` trap that calls `common/cleanup.sh`, a guard snapshot, the whole check
   inside one `common/sandbox.sh` call, one `PASS`/`FAIL` line per check, `guard.py verify` afterwards,
   exit 1 on any `FAIL`.
6. **Run it**: `bash run.sh <area>/<name>.test.py`, then `--twice`. Show it failing once against a tree
   with the bug (`bash common/ui/run-ui.sh <name> <test> <old tree>`), so it is known to catch it.
7. **A visual check**: `compare(shot(...), "<name>")`, then `--update-refs`, look at the candidate, copy
   it to `refs/`.
