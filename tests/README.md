# tests

The test kit for sleepyshell. It lives in the repository, in the shell's own folder, and the shell never
loads anything from here. It runs on any machine: every path comes from the kit's own location and the
XDG variables, never from a user name or a fixed home folder.

The shell folder is also the repository root, so the kit knows which files are the repository's and not
the shell's (`REPO_DIRS` and `REPO_FILES` in `common/env.sh`: `.git`, `.github/`, `tests/`, `docs/`,
`gallery/`, `assets/`, `tools/`, the root documents): it never copies, compiles, diffs, deploys, removes
or backs them up.

## Safety model

A test may read the system but never change it. Four layers make sure of that:

1. **Sandbox** (`common/sandbox.sh`). Every instance a test starts runs inside bubblewrap:
   - the whole file system is read-only, and only the run's own folder can be written (plus a private `/tmp`);
   - the runtime folder is a private tmpfs that holds only the Wayland socket and Hyprland's sockets, so
     instances draw on the real screen and hear Hyprland's events;
   - there is no session D-Bus (no notifications, `systemctl --user`, gsettings or portals), no PipeWire,
     no network and no view of outside processes;
   - `hyprctl` cannot reach the real compositor from inside; tests read Hyprland through `common/hypr.py`,
     which allows reading requests only.
2. **Checksum guard** (`common/guard.py`). A sha256 of every real file a test could reach (the live shell
   and its settings file, the Hyprland config, matugen's config and colours, the folder icon overlay, the
   default apps list) is taken before a run and compared after it. Any difference fails the run.
3. **Cleanup** (`common/cleanup.sh`). A run's processes die with its sandbox; cleanup then stops anything
   that still points into the run's folder, deletes the folder, and fails if a process or window is left.
   It only ever matches paths under the run folder: never the live shell, the live settings window or
   lock, or a preview.
4. **Run folders on tmpfs.** Runs live under `$XDG_RUNTIME_DIR/sleepyshell-tests/<run>`, in memory,
   one folder per run, so suites can run side by side and nothing survives a logout.

`bash common/selftest.sh` proves all of this on the current machine: home read-only, run folder
writable, Hyprland reachable on its socket, `hyprctl` not, no D-Bus, own process namespace, no real file
changed, nothing left behind.

## Commands

Run them from this folder.

| Command | What it does |
|---|---|
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
shell.

## Layout

```
tests/
├── common/         the safety layers and shared tools: env.sh, sandbox.sh, guard.py, cleanup.sh,
│                   compile.sh, treediff.py, hypr.py, selftest.sh
├── preview.sh      run a candidate as the bar
├── deploy.sh       deploy, rollback
├── candidate/      (not in git) the tree being worked on, deleted after it is deployed
├── backups/        (not in git) one folder per deploy: live.tar.gz, plan.json, candidate.txt
├── jobs/           (not in git) work folders of test runs and recordings
└── legacy/         (not in git) the previous kit, kept until the new suites replace it
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

- Everything runs inside the bubblewrap sandbox; nothing touches the live session: no virtual monitors
  on the running Hyprland, never move or click the real cursor, no writes outside the run's folder.
  One exception: `lock/hypridle-restart.sh` needs the user's systemd (a transient stand-in unit for
  hypridle and the lock's scope), so it runs outside the sandbox, keeps its files in the run folder,
  never touches the real hypridle or lock file, and shows its units gone at the end.
- No new packages.
- Never test the lock with a wrong password (`pam_faillock` can lock the account).
- Deterministic: the same result every run.

### How to check results

In order of preference:

1. **State and files**: settings values, socket messages, the written settings file, the commands log.
2. **The UI's structure**: which row shows which value, what is enabled or greyed.
3. **Screenshots**: only for things that are truly visual, compared with a tolerance.

### Test architecture

Three layers:

1. **Logic and state through IPC (most tests).** The test IPC targets drive the settings window and the
   shell without any cursor (stage, Apply, Discard, revert, switch tabs), and the test checks values,
   socket messages and files. This covers everything from the stage call onward, but not the click
   itself. The settings window already has the calls this needs (`tab`, `stage`, `discard`), so a test
   can open every tab and stage every key through its range without knowing where a row sits.
2. **Components in isolation (the click path and visuals).** The shared row and control types are tested
   with Qt Quick Test (`TestCase` sends simulated clicks and keys straight to QML items, no cursor);
   `Item.grabToImage` snapshots an item for visual checks. One click test per row type covers the
   click-to-stage step for every setting.
   **To verify (unconfirmed):** whether its runner is already installed, and whether the rows load
   outside Quickshell (singletons may need stubs).
3. **Whole window (a few checks only).** A separate headless Hyprland started inside the bubblewrap
   sandbox, with its own cursor and virtual monitor, driven only through its own `hyprctl` (never the
   live one) and captured with `grim` pointed at it. Nothing appears on the host screen and no input
   leaks out (the same pattern as KDE's `kwin_wayland --virtual` in a private D-Bus session).
   **To verify (unconfirmed):** whether Hyprland's headless mode works inside bubblewrap and accepts
   cursor moves and clicks with no real input device.

**Also to verify (unconfirmed):** checking UI state through the accessibility tree (AT-SPI), which
exposes each row's name, state and position, so a test can read a value without comparing pixels.

Today `common/sandbox.sh` hands instances the live compositor's Wayland and Hyprland sockets, so
anything a sandboxed instance shows appears on the real screen (see "Safety model"). Layer 3 is meant
to replace that for whole-window checks.

### Determinism for visual checks

A pinned colour palette (a fixed `colors.json`, no wallpaper-derived colours), fixed fonts, scale and
window size, animations off or finished, a fixed clock and fake data for anything live (CPU, network,
battery, notifications).

### Reference images

One per visual check, stored in the kit. A failing comparison saves the actual image and a diff in the
run folder. Updating references is an explicit step, never automatic.

### Checked only by eye on the live session

Real layer surfaces and input routing, Hyprland events and binds, the real lock and PAM, polkit,
battery, lid and backlight hardware, the tray.

### Adding a test, step by step

The kit has its safety layers and two checks so far (`common/selftest.sh`, `common/compile.sh`); the
suites, a test runner and the reference images do not exist yet. Steps marked **not in the kit yet**
are decided by the test plan that rebuilds the suites.

1. **Pick the tier and name the failure.** Write down the concrete failure the test protects against
   and its tier (above). No failure, no test.
2. **Pick the layer.** IPC and files first; a component test only for the click path or a visual; a
   whole-window check only when nothing smaller can see it.
3. **Where it goes:** one folder per part of the shell, `bar/`, `settings/` and `lock/` (planned:
   islands, dropdowns, control centre, widgets on fake data, events and popups; stage, Apply, the
   file written, file safety, one flow per tab; start, take the lock, unlock, exit). The file name
   pattern is **not in the kit yet**.
4. **Follow the pattern every check in the kit uses** (see `common/selftest.sh`):
   - make a run folder `$RUN/<name>-$$` and set an `EXIT` trap that calls `common/cleanup.sh` on it;
   - take a guard snapshot: `python3 -I common/guard.py snapshot <name>-$$`;
   - run the whole check inside one sandbox: `bash common/sandbox.sh "$D" <command>`. The folder must
     be under `$RUN`, and inside it only that folder (and a private `/tmp`) can be written;
   - print one `PASS <what>` or `FAIL <what>` line per check;
   - afterwards `guard.py verify <name>-$$` must pass and `cleanup.sh` must leave nothing running;
   - exit 1 on any `FAIL`.
5. **Run it.** Today: `bash common/selftest.sh` first (it proves the isolation), then your script. A
   runner that runs one test or one area is **not in the kit yet**.
6. **Reference images**, for a visual check: where they are stored in the kit, the tolerance and the
   explicit update command are **not in the kit yet**. The rule stands: a failing comparison writes
   the actual image and a diff into the run folder, and a reference is only ever updated by hand.
7. **Run it twice.** The same result both times, or it is not deterministic yet.
