# Tasks

The work list for sleepyshell, by goal (`docs/tasks_page.py` renders it as a page). Each goal says what "reached" means, then the tasks that get
there, with subtasks. `[x]` done, `[~]` started, `[ ]` open. Inside a goal the order is the order of
work; "Next up" at the end is the order across goals. Ticked items stay until the next release tag, then
move to the changelog. The same list is published as a page for reading away from the repository.

## Goal 1: A repository anyone can install from, that shows and explains every feature

Reached when a stranger with Hyprland and Quickshell can clone it, link it, start it and configure it
from the README alone; every feature is listed and the main ones are shown moving; the repository has
no personal data, no machine state and no AI tooling files; a release can be installed by name.

- [x] One repository, three programs: the Quickshell config folder is the root, `sleepybar/`,
      `sleepysettings/` and `sleepylock/` are the programs, `services/`, `components/`, `scripts/`,
      `themes/`, `templates/`, `data/` are shared, `tests/` is the kit, `docs/` the recordings.
- [x] The kit ignores the repository's own files wherever it copies, diffs, compiles, deploys or backs up
      the shell (`REPO_DIRS` / `REPO_FILES` in `tests/common/env.sh`, mirrored in `treediff.py` and
      `guard.py`); a deploy plan against a kept candidate shows zero differences.
- [x] `.gitignore`: user state (`sleepysettings.toml` and copies), bytecode, every Claude Code file,
      the kit's per-machine folders.
- [x] `SECURITY.md` describes the shell's security (trust model, inputs, what runs and is written,
      limits, reporting), not a review log.
- [x] README: "built to be modified" first, the complete feature list folded into dropdowns, dependencies
      as required / per feature / good to have, install for the linked layout, keybinds and scripting,
      repository layout, an AI-assisted (not generated) disclaimer.
- [x] Published: https://github.com/nninkovic95/sleepyshell, public, branch `main`, topics set.
- [~] Recordings, one feature per clip, animated WebP in `docs/demo/` with their own page.
  - [x] The page lists every clip and what it shows (`docs/demo/README.md`); the README links to it and
        embeds nothing until the files exist.
  - [x] Tooling for an automated run (`tests/demo/`): recorder on an empty workspace with the fallback
        wallpapers and the cursor through a virtual pointer, settings tour over IPC, WebP assembler,
        full restore of wallpaper, palette, settings lines, sinks and workspace.
  - [x] Shell changes the recordings needed: `clearNotifications`, `tab`, `stage` and `discard` IPC
        calls; a Wallpapers tool in the control centre; the Colour picker hidden by default.
  - [x] Six automated runs made and reviewed; the sixth is clean and assembled into an ignored folder
        for comparison (`tests/jobs/2026-10-30-demo/webp/`), not published.
  - [ ] **The showcase is recorded by hand**; the clip list on the demo page is the shot list. Then the
        files go into `docs/demo/`, the README gets its hero and five embeds (control-centre,
        island-extend, notifications, workspaces, settings, shuffle-wallpaper), and the Wi-Fi tile's name
        is hidden or blurred.
  - [ ] Clips no automation covers: the terminal updater, drag and drop in the settings editors, the
        lock screen, a community theme preset, the Caps Lock peek, the polkit prompt, the Wi-Fi and
        Bluetooth lists.
  - [ ] Frame folders under `tests/jobs/` deleted once the showcase is in.
- [ ] A logo: one mark that reads as sleepyshell (the islands, a crescent, a sleeping shell: sketch three
      directions and pick one), as SVG in `docs/logo/`, legible at 16 px (tab icon, the settings
      sidebar) and at 512 px (the README header, the GitHub social preview), in the theme's accent on
      light and dark, with a one-colour variant; the README header and the System tab carry it.
- [ ] GitHub settings: private vulnerability reporting switched on (the Security tab), the README checked
      on GitHub (dropdowns, table layout, relative links), a short "About" with the website field empty.
- [ ] `docs/ARCHITECTURE.md`: the three processes and what each may import; the island host contract
      (SideIsland, GrowingIsland, IslandDropdown, Popouts); the motion tokens in `Theme.qml`; every
      message the programs exchange (IPC, Hyprland events, the settings socket, its JSON); a setting's
      life cycle (schema default, stage, preview, commit, file, migration); where each service gets its
      data (D-Bus, PipeWire, sysfs, scripts).
- [ ] `docs/SETTINGS.md` generated from `services/Settings.qml` and `SettingsDocs.js` (key, tab,
      default, range, sentence), with a script in `tools/` or `scripts/` that regenerates it.
- [ ] `CONTRIBUTING.md`: how to run the compile gate and the suites, the comment rule (the reason, never
      the history), the settings conventions (every tab stages behind Apply, "!" hover tips, no info
      blocks, every popup themed), the dependency rule (ask before adding one; prefer a script), how a
      widget, a setting, a popup, a tab and a theme are added (the README's "Make it yours" in full).
- [ ] Issue templates (bug with the shell version, Hyprland and Quickshell versions and the log lines;
      feature) and a pull request template that asks for the compile gate and a run of the suite.
- [ ] A `CHANGELOG.md` kept from the first tag on, one line per user-visible change.
- [ ] Release: version in one place (`Theme.qml` or a `VERSION` file shown in the System tab), a tag
      `v0.1.0` once Goal 2's suites exist and Goal 3 is clear, GitHub release notes from the changelog.
- [ ] Packaging: a `PKGBUILD` for the AUR (depends from the README's required list, optdepends from the
      per-feature list, installs to `/usr/share/sleepyshell` and documents the symlink) or an install
      script that creates the two symlinks and checks the dependencies; decide after the first tag.

## Goal 2: Confidence that the shell works, on this machine and on a clean one

Reached when every file compiles, the three suites run green in the sandbox here and headless in CI,
the current shell has been through the thorough test with every failure explained, and the checksum
guard proves no test touches a real file.

- [x] Isolation: bubblewrap sandbox, checksum guard, cleanup, run folders on tmpfs; `selftest.sh` proves
      them (9 checks, also through the symlinked layout).
- [x] Compile gate for every QML file; preview of a candidate as the real bar; deploy with backup,
      verification and automatic rollback.
- [ ] Thorough test of the current shell (the islands refactor plus the small changes since).
  - [x] Stage 0, pre-flight: selftest, checksum snapshot, log baseline (seven `Cannot close destroyed
        notification` errors noted).
  - [x] Stage 1, static gates: compile 154 files, 0 failed; every script compiles and parses; in the
        sandbox: `idle.py --print` for both power sources (identical to the live `hypridle.conf` apart
        from the lock command's folder path, see Goal 3), `hyprconf.py discover` and `parse-binds
        --resolve`, `defaultapps.py scan`, `edid.py` on fake EDIDs, `theme.py --list-presets` and a
        `--dry-run` render, `sysinfo.py`, `filecheck.py`; the legacy script tests: theme scripts 66
        passed, workspace apps 10 passed; the checksum guard clean afterwards.
  - [ ] Stage 1 leftover: the toml round trip through the legacy toml root (parse, render, parse equal;
        a broken file refused with its line), to run with Stage 2's sandboxed instances.
  - [ ] Stage 2, the repaired legacy settings and lock suites on a silent workspace (names and paths only
        in the repair, stop after ten misses), every failure classified: stale expectation, real bug,
        timing.
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
      popup, notification popups and history (cap of 100, Clear all, do not disturb), the multi-monitor
      policy (full, lean, none) on virtual outputs.
- [ ] `settings/` suite, driven through the window's own IPC (`tab`, `stage`, `discard`): every tab
      renders; every key of the schema staged through its range (min, max, each choice, both switch
      states) and the bar's live preview checked over the socket; discard writes nothing; then the write
      path: Apply, the Apply bar lists exactly the files written, the toml round trip, a broken file
      refused with its line and never overwritten, the migration guard, the socket reconnect re-sends the
      draft, one flow per tab with every system command faked (keybind import of hostile files, Display's
      15 s revert, Config's Set up with its backup).
- [ ] `lock/` suite: starts, takes the lock within 3 s, unlocks through a kit-owned PAM service, exits;
      a second start exits quietly; the sleep cover lifts on the first key; only this session's logind
      signals end the lock; never a wrong password against the real PAM stack.
- [ ] Script tests without a compositor: every `scripts/*.py` with fixtures (fake sysfs trees, fake
      EDIDs, a fake Hyprland config tree, a fake matugen config), runnable with plain `python3 -m
      unittest` so CI can start before headless mode exists.
- [ ] Headless mode for `sandbox.sh` (a nested compositor), then GitHub Actions: the compile gate and
      the script tests on every push, the suites once headless works, a badge in the README.
- [ ] Legacy kit (`tests/legacy/`, not in git): keep what the new suites reuse, then delete the folder.
- [ ] Kit hygiene: `guard.py` snapshots to the runtime folder or documented as per-machine; `selftest.sh`
      checks the exit status of the sandboxed step and gets a window-placement guard; a
      `candidate.sh refresh` that copies the live tree without the repository's files and refuses a
      candidate with `.git` or `tests/`; a one-command self-check of `deploy.sh` on a scratch copy;
      backups pruned to the newest ten; screenshots of a settings lane for visual checks.

## Goal 3: No known defect left unexplained

Reached when every item below is fixed, or recorded as accepted with the reason.

- [ ] `Cannot close destroyed notification` in the log (seven since the last restart). Suspect: a card's
      exit animation or the history cap calling `dismiss()` on a notification already closed.
- [ ] The temporary `[osd]` diagnostic in `OsdState.qml`; remove it once the cause is found. Volume keys
      reach the inaudible EasyEffects sink, so the volume flash is suppressed as a device switch; the
      pill's own scroll moves the hardware sink and does flash.
- [ ] LibreWolf stops sending screensaver inhibits during long video, so the idle lock can fire
      mid-video; a stale "playing" inhibit can also block idle sleep. Check with the hypridle journal
      and the `inhibitingIdle` field of `hyprctl clients -j` during playback.
- [ ] `Popouts.toggle` with a name that is not a popup throws a caught error; refuse it cleanly.
- [ ] The portal warning `Could not register app ID` on every start of the bar and of the settings
      window; harmless, find the cause.
- [ ] The settings window's size changes with the tab's height, so a floating window re-centres and
      jumps when the tab changes; consider a fixed height once content fits.
- [ ] A cursor moved by Hyprland's `cursor.move` dispatcher (a warp) opens the control centre on hover
      but fires none of the finer hover effects (tile and card Lift-and-tilt); a motion event from a real
      or virtual pointer does. Decide whether the hover handlers should also react to a warp.
- [ ] `scripts/idle.py` (and any script that derives the shell folder from its own location) writes the
      real folder into Hyprland files when the config folder is a symlink (`lock_cmd` now says the real
      path where the live file says the config path). Prefer the XDG config path when the script lives
      under it, so written paths stay stable across a move of the repository.
- [ ] The right island's items shift when a conditional widget (bell, updates, Caps Lock) appears, so
      everything left of it moves; consider reserving the slot or anchoring from the left.
- [ ] A click on the pill's slider or a scroll on the pill leaves the control centre pinned open until a
      click elsewhere; decide whether a scroll should pin it.

## Goal 4: Every open point in the security notes closed

Reached when `SECURITY.md`'s "Known limitations" lists only the items accepted by design.

- [ ] Two texts still use Qt's default text format instead of plain text: the polkit helper's
      supplementary message and the package names in the updates dropdown.
- [ ] Notification images and tray icons are passed to the image loaders without a scheme check; settle
      whether a remote URL is fetched and refuse anything but local files.
- [ ] A timeout on the PAM check and on `checkupdates.sh`; Escape cancels the polkit prompt while PAM is
      checking.
- [ ] `luaString()` escapes `\` and `"` but not newlines for custom bind commands (hardening; the input
      is one line today).
- [ ] A notification pointing at an `.svg` is opened by whatever the system associates with it; decide
      whether SVG counts as an image for the click.
- [ ] The settings socket relies on the runtime directory's mode; consider checking the peer's uid with
      `SO_PEERCRED` where Quickshell exposes it, and refusing to start the socket under `/tmp`.
- [ ] A review of what the test-kit's own scripts can reach when run by hand outside the sandbox
      (`deploy.sh`, `record.sh` write real files by design; say so in their headers, done for
      `record.sh`).

## Goal 5: The shell survives its dependencies moving

Reached when a Hyprland or Quickshell release that changes an API is noticed by a check, not by a
broken desktop, and the upgrade path is written down.

- [ ] A compatibility note in the README and `docs/ARCHITECTURE.md`: tested Hyprland and Quickshell
      versions, the Lua dispatcher forms the shell relies on (`hl.dsp.focus`, `event`, `exec_cmd`,
      `workspace.toggle_special`), the Quickshell modules in use.
- [ ] A version probe in the Config tab: the running Hyprland and Quickshell versions against the tested
      ones, with a plain note when newer.
- [ ] An upgrade checklist in `CONTRIBUTING.md`: compile gate, selftest, the suites, a preview before a
      deploy, what to look at in the log.
- [ ] The `data/hyprland-default-binds.lua` and the import parser's closed action list kept in step with
      Hyprland's dispatcher names; a script test that parses the current default config.
- [ ] `theme.py` and the matugen call checked against the matugen version in the repositories (flags
      `--type`, `--mode`, `--contrast`, `color hex`); the fallback wallpaper path `/usr/share/hypr`
      confirmed per Hyprland release.

## Goal 6: Comfortable for everyone who uses it

Reached when the shell is usable without a mouse where that makes sense, respects reduced motion, stays
legible at every contrast setting, and costs little while idle.

- [ ] Reduced motion: one setting (or `prefers-reduced-motion` from the portal) that shortens island,
      card and toast animations to a fade.
- [ ] Keyboard: Escape closes any dropdown; Tab moves through the control centre's tiles and tools; the
      notification list is navigable; the session menu already is.
- [ ] Contrast: the "Max" text contrast checked on every surface (tiles, cards, sliders, the lock's
      field); minimum sizes for the bar text respected at 1x scale.
- [ ] Idle cost: CPU of the bar at rest (the 2 s sysinfo poll, the 30 s notification tick, the temperature
      reads) measured and, where useful, slowed when no popup is open.
- [ ] Startup: time from `qs -c sleepyshell` to the bar on screen measured; the icon index
      (`data/icons.json`, 186 KB) loaded lazily by the tool editor only.

## Goal 7: Improvements worth doing, in order of value

- [ ] Search results in Sleepysettings that jump to the row and flash it.
- [ ] Notification actions on the compact toast, not only on the card in the history.
- [ ] A "what changed" view in the Apply bar: the diff of each file that will be written.
- [ ] Export and import of the whole `sleepysettings.toml` from the settings sidebar.
- [ ] Bluetooth: battery level of connected devices where the device reports it.
- [ ] Multi-monitor: the on-screen display and notification popups on the focused monitor only.
- [ ] The updates dropdown: a "changes" link per package to the Arch package page.
- [ ] The calendar: a week view, and events created from the selected day without leaving the popup.

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
- A window title on the bar.

## Housekeeping

- [ ] Delete `tests/legacy/` once the new suites cover what it checked.
- [ ] Delete `tests/candidate/` after the next deploy; recreate it only for the next change.
- [ ] Remove `settings.json.bak` from the shell folder (state from the migration, already ignored).
- [ ] Review the licences in `themes/README.md` once more before a release tag.
- [ ] On the development machine: remove the recording aid `wlrctl` (AUR) now that the automated
      recordings are parked; `ydotool` was never installed.
- [ ] Prune the kit's backups to the newest ten.

## Next up

1. Goal 2, Stage 1 onward: the static gates, the repaired legacy suites, the review, the live checks,
   the report.
2. Goal 3, starting with the destroyed-notification error, and Goal 4's one-line fixes.
3. Goal 1 again: the hand-made showcase into `docs/demo/`, ARCHITECTURE.md, SETTINGS.md,
   CONTRIBUTING.md, the first tag.
4. Goal 2's three suites, script tests, headless mode, CI.
