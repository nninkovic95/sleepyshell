# Tasks

The work list for sleepyshell, organised by goal: what each goal means when it is reached, then the
tasks that get there, with subtasks. `[x]` done, `[~]` started, `[ ]` open. The order inside a goal is
the order of work; "Next up" at the end is the order across goals.

## Goal 1: A repository anyone can install from, that shows and explains every feature

Reached when: a stranger with Hyprland and Quickshell can clone it, link it, start it and configure it
from the README alone; every feature is listed and the main ones are shown moving; the repository has
no personal data, no machine-specific state and no AI tooling files.

- [x] One repository, three programs: the Quickshell config folder is the root, `sleepybar/`,
      `sleepysettings/` and `sleepylock/` are the programs, `services/`, `components/`, `scripts/`,
      `themes/`, `templates/`, `data/` are shared, `tests/` is the kit, `docs/` the recordings.
- [x] The kit ignores the repository's own files wherever it copies, diffs, compiles, deploys or backs up
      the shell (`REPO_DIRS` / `REPO_FILES` in `tests/common/env.sh`, mirrored in `treediff.py` and
      `guard.py`); a deploy plan against a kept candidate shows zero differences.
- [x] `.gitignore`: user state (`sleepysettings.toml` and copies), bytecode, every Claude Code file
      (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/`), the kit's per-machine folders.
- [x] `SECURITY.md` describes the shell's security (trust model, inputs, what runs and is written,
      limits, reporting), not a review log.
- [x] README: "built to be modified" first, the complete feature list folded into dropdowns, dependencies
      as required / per feature / good to have, install for the linked layout, keybinds and scripting,
      repository layout, an AI disclaimer that says assisted, not generated.
- [~] Recordings, one feature per clip, animated WebP in `docs/demo/` with their own page.
  - [x] The page lists every clip and what it shows (`docs/demo/README.md`); the README links to it and
        embeds nothing until the files exist.
  - [x] Tooling in the kit for an automated run: `tests/demo/record.sh` (empty workspace checked,
        fallback wallpapers, the cursor through a virtual pointer so hover and tilt fire, one feature per
        clip, restores wallpaper, palette, settings lines, every sink, workspace), `lib.sh`,
        `settings_tour.sh` (tabs and live values through the settings window's IPC), `assemble.sh`
        (real frame timing, crop, blur, WebP), `record_updates.sh`.
  - [x] Shell changes the recordings needed: `clearNotifications`, `tab`, `stage` and `discard` IPC
        calls; a Wallpapers tool in the control centre; the Colour picker hidden by default.
  - [x] Six automated runs made and reviewed; the sixth is clean (twenty-four clips, nothing personal,
        every click landed, live changes in the settings tour) and is assembled into an ignored folder
        for comparison (`tests/jobs/2026-10-30-demo/webp/`), not published.
  - [ ] **The showcase is recorded by hand** (the automated cursor still reads as robotic); the clip
        list on the demo page is the shot list. Then the files go into `docs/demo/`, the README gets its
        hero and five embeds back (control-centre, island-extend, notifications, workspaces, settings,
        shuffle-wallpaper), and the Wi-Fi tile's name is blurred or the tile hidden while recording.
  - [ ] Not in the automated run either way: the terminal updater, drag and drop in the settings
        editors, the lock screen, a community theme preset, the Caps Lock peek, the polkit prompt, the
        Wi-Fi and Bluetooth lists.
  - [ ] Frame folders under `tests/jobs/` deleted once the showcase is in.
- [ ] Push: `gh repo create sleepyshell --public`, description and topics, private vulnerability reporting
      switched on, the README checked on GitHub (dropdowns, WebP playback, table layout).
- [ ] `docs/ARCHITECTURE.md`: the island host contract (SideIsland, GrowingIsland, IslandDropdown,
      Popouts), the motion tokens in `Theme.qml`, every message the three programs exchange (IPC,
      Hyprland events, the settings socket), a setting's life cycle (default, stage, preview, commit, file).
      Today this exists only in per-machine notes that are not in the repository.
- [ ] `docs/SETTINGS.md` generated from `services/Settings.qml` (key, default, range, comment).
- [ ] `CONTRIBUTING.md`: the compile gate and the suites, the comment rule (the reason, never the
      history), the settings conventions (every tab stages behind Apply, "!" hover tips, no info blocks,
      every popup themed), ask before adding a dependency.
- [ ] Issue templates (bug, feature); a first release tag once Goal 2 is reached.
- [ ] Packaging: a `PKGBUILD` for the AUR or an install script that creates the two symlinks and checks
      the dependencies.

## Goal 2: Confidence that the shell works, on this machine and on a clean one

Reached when: every file compiles, the three suites run green in the sandbox on this machine and headless
in CI, the current shell has been through the thorough test with every failure explained, and the
checksum guard proves no test touches a real file.

- [x] Isolation: bubblewrap sandbox, checksum guard, cleanup, run folders on tmpfs; `selftest.sh` proves
      them (9 checks, also through the symlinked layout).
- [x] Compile gate for every QML file; preview of a candidate as the real bar; deploy with backup,
      verification and automatic rollback.
- [ ] Thorough test of the current shell (the islands refactor plus the small changes since):
  - [x] Stage 0, pre-flight: selftest, checksum snapshot, log baseline (seven `Cannot close destroyed
        notification` errors noted).
  - [ ] Stage 1, static gates: compile; `py_compile` and `bash -n` for the scripts; the script checks in
        the sandbox (`idle.py --print` both power sources against the live `hypridle.conf`,
        `hyprconf.py discover` and `parse-binds --resolve`, `defaultapps.py` dry runs, `edid.py` on fake
        EDIDs, `theme.py --list-presets` and `--dry-run`, `sysinfo.py`, `filecheck.py`); the toml round
        trip against a copy of the live file.
  - [ ] Stage 2, the repaired legacy settings and lock suites on a silent workspace (names and paths only
        in the repair, stop after ten misses), every failure classified: stale expectation, real bug, timing.
  - [ ] Stage 3, adversarial read-only review of the risky surfaces: the notification service and cards,
        the lock and its launcher (flock, exit codes, the 3 s take-lock timeout, the sleep cover),
        `defaultapps.py` with the Apps tab and `idle.py` with the Idle and Power tabs, the island host
        contract, the settings writer (single writer while linked, `broken` makes writes no-ops, the
        migration guard, the draft re-sent on reconnect).
  - [ ] Stage 4, the live shell read-only: error and warning counts, layer surfaces, IPC listing, the
        settings file parses, `hypridle.conf` content, no stray lock process, checksum guard clean.
  - [ ] Stage 5, on real hardware one at a time: lock and unlock, a second lock request exits quietly,
        suspend and wake with the sleep cover, every popup, the tray right-click menu.
  - [ ] Stage 6, the report: one table per stage, confirmed findings with file and line, what was out of
        scope and why.
- [ ] `bar/` suite: islands open as one shape, a side island widens so the dropdown hangs flush, one
      dropdown at a time, geometry held while open, dropdown fit at both screen edges, the control
      centre's tiles and tools on fake data, every widget on fake data, every `sleepyshell:` event, every
      popup, notification popups and history (cap of 100, Clear all, do not disturb).
- [ ] `settings/` suite, driven through the window's own IPC (`tab`, `stage`, `discard`, added for the
      recordings): open every tab in turn and check it renders; stage every key of the schema through
      its range (min, max, each choice, both switch states) and check the bar's live preview took it
      (the bar answers over the socket; a sandboxed bar can report its live values); discard and check
      nothing was written; then the write path: Apply, the Apply bar lists exactly the files written; the
      toml round trip; a broken file refused with its line and never overwritten; the migration guard;
      the socket reconnect re-sends the draft; one flow per tab with every system command faked.
- [ ] `lock/` suite: starts, takes the lock within 3 s, unlocks through a kit-owned PAM service, exits;
      a second start exits quietly; the sleep cover lifts on the first key; never a wrong password
      against the real PAM stack.
- [ ] Headless mode for `sandbox.sh` (a nested compositor), then GitHub Actions: the compile gate on
      every push, the suites once headless works, a badge in the README.
- [ ] Legacy kit (`tests/legacy/`, not in git): keep what the new suites reuse, then delete the folder.
- [ ] Kit hygiene: `guard.py` snapshots to the runtime folder or documented as per-machine; `selftest.sh`
      checks the exit status of the sandboxed step and gets a window-placement guard; a
      `candidate.sh refresh` that copies the live tree without the repository's files and refuses a
      candidate with `.git` or `tests/`; a one-command self-check of `deploy.sh` on a scratch copy;
      screenshots of a settings lane for visual checks.

## Goal 3: No known defect left unexplained

Reached when: every item below is fixed, or recorded as accepted with the reason.

- [ ] `Cannot close destroyed notification` in the log (seven since the last restart). Suspect: a card's
      exit animation or the history cap calling `dismiss()` on a notification already closed.
- [ ] The temporary `[osd]` diagnostic in `OsdState.qml`; remove it once the cause is found. Volume keys
      reach the inaudible EasyEffects sink, so the volume flash is suppressed as a device switch.
- [ ] LibreWolf stops sending screensaver inhibits during long video, so the idle lock can fire
      mid-video; a stale "playing" inhibit can also block idle sleep. Check with the hypridle journal
      and the `inhibitingIdle` field of `hyprctl clients -j` during playback.
- [ ] `Popouts.toggle` with a name that is not a popup throws a caught error; refuse it cleanly.
- [ ] Two texts still use Qt's default text format instead of plain text: the polkit helper's
      supplementary message and the package names in the updates dropdown.
- [ ] Notification images and tray icons are not scheme-checked before the image loaders; settle whether
      a remote URL is fetched and refuse it if so.
- [ ] No timeout on the PAM check and on `checkupdates.sh`; Escape cannot cancel the polkit prompt while
      PAM is checking.
- [ ] `luaString()` escapes `\` and `"` but not newlines for custom bind commands (hardening; the input
      is one line today).
- [ ] A notification pointing at an `.svg` is opened by whatever the system associates with it.
- [ ] The portal warning `Could not register app ID` on every start of the bar; harmless, find the cause.
- [ ] The settings window's size changes with the tab's height, so a floating window jumps when the tab
      changes; consider a fixed height once content fits.
- [ ] A cursor moved by Hyprland's `cursor.move` dispatcher (a warp) opens the control centre on hover
      but fires none of the shell's finer hover effects (tile and card Lift-and-tilt); a motion event from
      a real or virtual pointer does. Decide whether the hover handlers should also react to a warp.

## Goal 4: Improvements worth doing, in order of value

- [ ] Search results in Sleepysettings that jump to the row and flash it.
- [ ] Notification actions on the compact toast, not only on the card in the history.
- [ ] A "what changed" view in the Apply bar: the diff of each file that will be written.
- [ ] Export and import of the whole `sleepysettings.toml` from the settings sidebar.
- [ ] Bluetooth: battery level of connected devices where the device reports it.
- [ ] Multi-monitor: the on-screen display and notification popups on the focused monitor only.

## Not planned

Decisions taken to keep the shell small; a pull request for one of these is unlikely to be merged.

- A media player widget on the bar.
- An "idle lock" toggle or "lock before suspend" setting beyond what the Idle tab has: lock explicitly.
- Mouse battery on the bar, "update on reconnect", a click on the wallpaper that only opens the picker.
- Dimmed dots for empty workspaces (an empty workspace is a ring instead).
- An Audio section, a night-light schedule editor, named settings profiles or per-monitor RGB gains.
- Compositors other than Hyprland, or the old `hyprland.conf` format: Sleepysettings reads and writes
  the Lua config.
- Helper packages where a short script does the job (no `pacman-contrib`, `bluez-utils` or `hyprsunset`).

## Housekeeping

- [ ] Delete `tests/legacy/` once the new suites cover what it checked.
- [ ] Delete `tests/candidate/` after the next deploy; recreate it only for the next change.
- [ ] Remove `settings.json.bak` from the shell folder (state from the migration, already ignored).
- [ ] Review the licences in `themes/README.md` once more before a release tag.
- [ ] On the development machine: remove the recording aids (wlrctl, ydotool) once the recordings are final.

## Next up

1. Goal 1: review and assemble the recordings, push, switch on vulnerability reporting.
2. Goal 2: the thorough test in stage order, then the three suites, then headless mode and CI.
3. Goal 3, starting with the destroyed-notification error.
4. Goal 1 again: ARCHITECTURE.md, SETTINGS.md, CONTRIBUTING.md, a release tag.
