# Tasks

The work list for sleepyshell, kept in the repository so that anyone can see what is done, what is
next and what is deliberately not planned. `[x]` is done, `[ ]` is open, `[~]` is started. Items are
grouped by area, not by priority; the priority order is in "Next up" at the end.

## 1. Repository and documentation

- [x] One repository, three programs: the Quickshell config folder is the repository root, with
      `sleepybar/`, `sleepysettings/` and `sleepylock/` as the programs and `services/`, `components/`,
      `scripts/`, `themes/`, `templates/` and `data/` shared between them.
- [x] The test kit lives in `tests/` and ignores the repository's own files when it diffs, copies,
      compiles, deploys or backs up the shell (`REPO_DIRS` / `REPO_FILES` in `tests/common/env.sh`).
- [x] `.gitignore`: user state (`sleepysettings.toml` and its copies), Python bytecode, Claude Code
      files, the kit's per-machine folders (`backups/`, `jobs/`, `run/`, `candidate/`, `legacy/`).
- [x] `SECURITY.md` describes the shell's security: trust model, inputs, what it runs and writes, limits.
- [~] `README.md`: every feature listed (folded into dropdowns where long), dependencies split into
      required, per feature and good to have, install for the symlinked layout, demo recordings.
  - [x] Feature inventory taken from the code.
  - [ ] Recordings in `docs/demo/` (`tests/demo/record.sh`, assembled into animated WebP by `tests/demo/assemble.sh`):
    - [x] First run: wrong workspace (the `workspace` dispatcher must be written in Lua form), no cursor
          in the frames, the Wi-Fi tile shows the connection name. All frames discarded.
    - [ ] Record on an empty workspace: `hl.dsp.focus({ workspace = N })` through `hyprctl dispatch`,
          verified by `hyprctl activeworkspace` before the first frame; a shown special workspace is
          hidden first and shown again at the end.
    - [ ] The cursor in every frame (`grim -c`) and real clicks: hover with the cursor-move dispatcher,
          clicks through a virtual pointer tool (wlrctl) when it is installed, the bar's IPC otherwise.
    - [ ] Island clips: the centre island opening on hover into the control centre (stepped outline,
          uneven panel), a side island widening so the dropdown hangs flush ("Extend" fit) against the
          "Float" card, the workspace disc sliding, the audio pill's scroll and right click.
    - [ ] Every Sleepysettings tab in one clip (Ctrl+Tab through the window, a pause per tab), plus the
          search box, a staged change with its Apply bar, and Discard.
    - [ ] Notifications: three toasts, the bell dropdown, Clear all sweeping the cards out; the on-screen
          display for volume; calendar; session menu; wallpaper picker on the fallback wallpapers; the
          wallpaper and palette changing live.
    - [ ] Nothing personal in a frame: the Wi-Fi tile's connection name is covered in post, every clip's
          first, middle and last frame reviewed before the WebP is written.
    - [ ] Hyprland's three fallback wallpapers for every clip; the previous wallpaper and palette are
          put back from the recorded seed afterwards (verified identical on the first run).
  - [ ] Recordings that need a prepared desktop: theme preset switch (recolours every app), the lock
        screen, the Caps Lock on-screen display.
  - [ ] Re-record when the look changes.
- [ ] `docs/ARCHITECTURE.md`: the island host contract (SideIsland, GrowingIsland, IslandDropdown,
      Popouts), the motion tokens in `Theme.qml`, every message the three programs exchange (IPC,
      Hyprland events, the settings socket), the settings key life cycle (default, stage, preview, commit,
      file). This content exists only in per-machine notes today.
- [ ] `CONTRIBUTING.md`: how to run the compile gate and the suites, the comment rule (the reason,
      never the history), the settings conventions (every tab stages behind Apply, "!" hover tips, no
      info blocks, every popup themed), ask before adding a dependency.
- [ ] GitHub: repository description and topics, private vulnerability reporting switched on, issue
      templates for a bug and a feature.
- [ ] A `docs/SETTINGS.md` generated from `services/Settings.qml` (key, default, range, comment), so the
      file format is documented without reading QML.
- [ ] Packaging: decide between a `PKGBUILD` for the AUR and an install script that creates the two
      symlinks and checks the dependencies.

## 2. Test kit (`tests/`)

- [x] Isolation layers: bubblewrap sandbox, checksum guard, cleanup, run folders on tmpfs; `selftest.sh`
      proves them (9 checks).
- [x] Compile gate for every QML file, preview of a candidate as the real bar, deploy with backup,
      verification and automatic rollback.
- [ ] `bar/` suite: islands open as one shape, a side island widens so the dropdown hangs flush, one
      dropdown at a time, geometry held while open, dropdown fit at both screen edges, the control
      centre's tiles and tools grid on fake data, every widget on fake data, every `sleepyshell:` event,
      every popup, notification popups and history (cap of 100, Clear all sweep, do not disturb).
- [ ] `settings/` suite: a key is staged, previewed on the bar and committed on Apply; the Apply bar
      lists exactly the files that will be written; `sleepysettings.toml` round trip (parse, render, parse
      equal); a broken file is refused with its line and never overwritten; the migration guard; the
      socket reconnect re-sends the draft; one flow per tab (Apps, Keybinds import and export, Display,
      Idle, Power, Config checks and fixes) with every system command faked.
- [ ] `lock/` suite: starts, takes the lock within 3 s, unlocks with the right password through a
      kit-owned PAM service, exits; a second start exits quietly (flock); the sleep cover lifts on the
      first key; never a wrong password against the real PAM stack.
- [ ] Script checks inside the sandbox: `idle.py --print` for mains and battery against the live
      `hypridle.conf`, `hyprconf.py discover` and `parse-binds --resolve`, `defaultapps.py` dry runs,
      `edid.py` on fake EDIDs, `theme.py --list-presets` and `--dry-run`, `sysinfo.py`, `filecheck.py`.
- [ ] Headless mode for `sandbox.sh`: a nested compositor inside the sandbox so the suites run without
      a real screen, on a server as well as on a desktop.
- [ ] GitHub Actions: the compile gate on every push and pull request; the suites once headless mode
      exists; a badge in the README.
- [ ] Legacy kit (`tests/legacy/`, not in git): repair the settings and lock builders (names and paths
      only, no change of what a check expects), run them once against the current tree, keep what the new
      suites can reuse, then delete the folder.
- [ ] `guard.py` writes its snapshots to `tests/run/guard`; decide whether they move to the runtime
      folder (they would then not survive a logout, which a long job may need).
- [ ] `selftest.sh`: check the exit status of the sandboxed step, not only the lines it prints; add a
      window-placement guard (a sandbox window must never land on the user's workspace).
- [ ] Candidate handling: a `candidate.sh refresh` that copies the live tree without the repository's
      files, and a check that a candidate never contains `.git` or `tests/`.
- [ ] A kit self-check that runs `deploy.sh` against a scratch copy (plan, apply, rollback hash-identical,
      broken candidate refused) as one command.
- [ ] Screenshots of a settings lane for visual checks: one spot per lane on a larger virtual monitor
      (a window grab is impossible, the content is split over root-level siblings).

## 3. Thorough test of the current shell

The current shell is the islands refactor plus small changes since (webmail handlers, Suspend shown as
Sleep, one lock at a time, the black sleep cover, notification click focuses the sender). None of it has
been through a full suite.

- [x] Stage 0, pre-flight: isolation selftest, checksum snapshot of the live tree, baseline of the log
      (seven `Cannot close destroyed notification` errors noted), no sandbox instances or windows.
- [ ] Stage 1, static gates: compile every file; `py_compile` and `bash -n` for the scripts; the
      script checks above; the toml round trip against a copy of the live file.
- [ ] Stage 2, the repaired legacy settings and lock suites on a silent workspace, every failure
      classified (stale expectation, real bug, timing) with file and line.
- [ ] Stage 3, adversarial read-only review of the risky surfaces: the notification service and cards
      (the destroyed-notification error), the lock and its launcher (flock semantics, exit codes, the
      3 s take-lock timeout, the sleep cover), `defaultapps.py` with the Apps tab and `idle.py` with the
      Idle and Power tabs, the island host contract, the settings writer (single writer while linked,
      `broken` makes writes no-ops, the migration guard, the draft re-sent on reconnect).
- [ ] Stage 4, the live shell read-only: error and warning counts, layer surfaces, IPC listing, the
      settings file parses, `hypridle.conf` content, no stray lock process, checksum guard clean.
- [ ] Stage 5, on real hardware, one at a time: lock and unlock, a second lock request exits quietly,
      suspend and wake with the sleep cover, every popup from IPC in turn, the tray right-click menu.
- [ ] Stage 6, the report: one table per stage, the confirmed findings with file and line, what was out
      of scope and why.

## 4. Known issues

- [ ] `Cannot close destroyed notification` is logged (seven times since the last restart). Suspect: a
      card's exit animation or the history cap calling `dismiss()` on a notification already closed.
- [ ] The on-screen display keeps a temporary `[osd]` diagnostic in `OsdState.qml`; remove it once the
      cause is found. Volume keys reach the inaudible EasyEffects sink, so the volume flash is suppressed
      as a device switch.
- [ ] LibreWolf stops sending screensaver inhibits during long video playback, so the idle lock can fire
      mid-video; a stale "playing" inhibit can also block idle sleep. Check with the hypridle journal and
      the `inhibitingIdle` field of `hyprctl clients -j` during playback.
- [ ] `Popouts.toggle` with a name that is not a popup throws a caught error; refuse it cleanly instead.
- [ ] Two texts still use Qt's default text format: the polkit helper's supplementary message and the
      package names in the updates dropdown. One `textFormat: Text.PlainText` line each.
- [ ] Notification images and tray icons are not scheme-checked before they reach the image loaders;
      settle whether a remote URL is fetched and refuse it if so.
- [ ] The PAM check has no timeout; `checkupdates.sh` has no timeout; Escape cannot cancel the polkit
      prompt while PAM is checking.
- [ ] `luaString()` escapes `\` and `"` but not newlines for custom bind commands; the input is a single
      line today, so this is hardening.
- [ ] A notification pointing at an `.svg` is opened by whatever the system associates with it.
- [ ] The portal warning `Could not register app ID` on every start of the bar; harmless, find the
      cause (the QApplication pragma and the portal registering twice).

## 5. Shell improvements under consideration

- [ ] Per-feature settings search results that jump to the row and flash it.
- [ ] Notification actions on the compact toast, not only on the card in the history.
- [ ] A "what changed" view in the Apply bar: the diff of each file that will be written.
- [ ] An export and import of the whole `sleepysettings.toml` from the settings sidebar.
- [ ] Bluetooth: battery level of connected devices where the device reports it.
- [ ] Multi-monitor: the on-screen display and notification popups on the focused monitor only.

## 6. Not planned

Decisions taken to keep the shell small; a pull request for one of these is unlikely to be merged.

- A media player widget on the bar.
- An "idle lock" toggle or "lock before suspend" setting: lock explicitly instead.
- Mouse battery on the bar, "update on reconnect", a click on the wallpaper that only opens the picker.
- Dimmed dots for empty workspaces (an empty workspace is a ring instead).
- An Audio section, a night-light schedule editor, named settings profiles or per-monitor RGB gains in
  Sleepysettings.
- Support for compositors other than Hyprland, or for the old `hyprland.conf` format: Sleepysettings
  reads and writes the Lua config.
- Helper packages where a short script does the job (no `pacman-contrib`, `bluez-utils` or `hyprsunset`
  dependency).

## 7. Housekeeping

- [ ] Delete `tests/legacy/` once the new suites cover what it checked.
- [ ] Delete `tests/candidate/` after the next deploy; recreate it only for the next change.
- [ ] Remove `settings.json.bak` from the shell folder (state from the migration, already ignored).
- [ ] Review the licences listed in `themes/README.md` once more before a release tag.
- [ ] Tag a first release once the suites in section 2 exist and section 3 is green.

## Next up

1. Finish the README (section 1), push, then switch on private vulnerability reporting.
2. Section 3 in stage order: static gates, the repaired legacy suites, the review, the live checks.
3. The three new suites (section 2), bar first, then headless mode and CI.
4. Known issues in section 4, starting with the destroyed-notification error.
