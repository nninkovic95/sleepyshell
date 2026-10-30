# tests

The test kit for sleepyshell. It lives in the repository, in the shell's own folder, and the shell never
loads anything from here. It runs on any machine: every path comes from the kit's own location and the
XDG variables, never from a user name or a fixed home folder.

The shell folder is also the repository root, so the kit knows which files are the repository's and not
the shell's (`REPO_DIRS` and `REPO_FILES` in `common/env.sh`: `.git`, `tests/`, `docs/`, the root
documents): it never copies, compiles, diffs, deploys, removes or backs them up.

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
| `bash demo/record.sh FRAMES` | Record the README's demo clips as frame folders; the script's header says what it changes on the desktop and restores. |
| `bash demo/assemble.sh FRAMES OUT` | Turn the frame folders into the animated WebP files in `docs/demo/`. |

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
├── demo/           record.sh and assemble.sh for the README's recordings
├── preview.sh      run a candidate as the bar
├── deploy.sh       deploy, rollback
├── candidate/      (not in git) the tree being worked on, deleted after it is deployed
├── backups/        (not in git) one folder per deploy: live.tar.gz, plan.json, candidate.txt
├── jobs/           (not in git) work folders of test runs and recordings
└── legacy/         (not in git) the previous kit, kept until the new suites replace it
```

## Suites

Planned, one per part of the shell, each a short run that checks what is seen and what happens rather
than every row: `bar/` (islands open as one shape, dropdown fit, control centre, widgets on fake data,
events, popups), `settings/` (stage, Apply, the file written, file safety, one flow per tab) and
`lock/` (starts, takes the lock, unlocks, exits; never a wrong password, which counts against
pam_faillock). The list is in [`TASKS.md`](../TASKS.md).
