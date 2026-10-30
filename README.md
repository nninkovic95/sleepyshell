# sleepyshell

A desktop shell for [Hyprland](https://hypr.land), written in [Quickshell](https://quickshell.org) (QML)
with Python helpers. Floating islands on the top edge, a control centre, notifications, an on-screen
display, a polkit agent, a lock screen and a full settings app, all themed from your wallpaper or from a
community colour theme.

![The centre island opening into the control centre](docs/demo/control-centre.webp)

**Built to be modified.** sleepyshell is plain QML and Python with no build step: every widget is a
folder, every settings tab is a file, every setting is one line in a schema, and the bar reloads itself
when you save. A test kit in the repository lets you compile, preview and deploy a change with a backup
and an automatic rollback, so breaking your own desktop is hard. See [Make it yours](#make-it-yours).

## Contents

- [What it looks like](#what-it-looks-like)
- [Make it yours](#make-it-yours)
- [Features](#features)
- [Dependencies](#dependencies)
- [Install](#install)
- [Keybinds and scripting](#keybinds-and-scripting)
- [Repository layout](#repository-layout)
- [Development](#development)
- [Security, tasks, licence](#security-tasks-licence)
- [AI disclaimer](#ai-disclaimer)

## What it looks like

| | |
|---|---|
| ![Islands](docs/demo/islands.webp) A side island widens so its dropdown hangs flush under it ("Extend"), or the dropdown floats as a card | ![Notifications](docs/demo/notifications.webp) Toasts arrive, the bell shows, Clear all sweeps the cards out one by one |
| ![Workspaces](docs/demo/workspaces.webp) The accent disc slides between the workspace dots | ![Settings](docs/demo/settings.webp) Sleepysettings, one tab after another |
| ![Theme](docs/demo/theme.webp) Change the wallpaper and every colour follows | |

Eleven recordings in all, one per feature, in [`docs/demo/`](docs/demo/README.md). They use Hyprland's own
fallback wallpapers.

## Make it yours

Everything below is a normal edit of a text file, picked up by the running shell.

- **Settings without code.** `sleepysettings.toml` beside the shell has one `[section]` per tab and a
  comment above every key with its meaning, range and default. Edit it by hand or through Sleepysettings;
  the bar follows at once. Custom control-centre tools (an app, a command, a link), custom keybinds, apps
  that start on a workspace, and custom lid or battery commands are all settings, not code.
- **Add a setting.** One entry in the `schema` of `services/Settings.qml` (its tab, default and range),
  one sentence in `services/SettingsDocs.js` (it becomes the comment in the settings file) and one row in
  the tab's file (`NumberRow`, `ChoiceRow`, `SwitchRow`, each with a label, an info tip and search tags).
  Staging, live preview, Apply, Discard, revert-to-default, search and the file write come for free.
- **Add a widget.** A folder under `sleepybar/widgets/` with the piece that sits on the bar and its
  dropdown. Register it by name in `sleepybar/islands/Sleepyright.qml` and add the name and its label to
  `services/Settings.qml`; it then appears in the Right island tab where it can be reordered and hidden.
  A dropdown asks the island to widen through the host contract in `sleepybar/components/SideIsland.qml`,
  so it opens as one shape with the island without any layout code of its own.
- **Add a popup.** Register it with `services/Popouts.qml` and it can be opened with
  `sleepyshell:toggle:<name>` from a keybind and with `qs -c sleepyshell ipc call sleepybar toggle <name>`
  from a script; opening one closes the others.
- **Add a tab.** A `*Tab.qml` in `sleepysettings/` built from the rows in `sleepysettings/components/`, and
  an entry in the sidebar of `sleepysettings/Sleepysettings.qml`.
- **Change the look.** `Theme.qml` holds every colour role, the corner radii (Sharp, Standard, Rounded or a
  number), the fonts, the island geometry and the motion (duration and easing). Colours come from
  `colors.json`, which matugen renders from your wallpaper or which a community theme fills in.
- **Add a theme.** A TOML file in `themes/` that maps a palette onto the 22 Material roles;
  `scripts/theme.py --list-presets` and the Theme tab pick it up. Only variants the theme's authors publish
  belong there, with their licence listed in `themes/README.md`.
- **Scripts you can run alone.** Every helper in `scripts/` is standard-library Python or a short shell
  script with a usage text: theming, the hypridle config, the Hyprland Lua config, DDC/CI, default apps.
- **Hot reload and separate processes.** Quickshell reloads the bar when a file changes. Sleepysettings and
  Sleepylock are their own processes that never import from `sleepybar/`, so a mistake in the bar cannot
  break the settings window or unlock a locked session, and the bar never loads their files.
- **Try it safely.** `tests/compile.sh` compiles every file in a sandbox, `tests/preview.sh` runs a copy as
  the real bar and falls back if it does not load, and `tests/deploy.sh` copies a change into place with a
  backup, verifies it and rolls back by itself. See [Development](#development).

## Features

The bar is three islands on the top edge of every monitor. The centre one grows into the control centre;
a side island widens so a widget's dropdown hangs flush under it ("Extend"), or the dropdown floats as a
card ("Float"). How fast they open, how the motion eases, the centre island's stepped outline and the
islands' padding are settings.

<details>
<summary><b>Left island: workspaces</b></summary>

- Dots for this monitor's workspaces; 1 to N always shown (N is a setting), higher ones while they exist.
- A sliding accent disc that stretches into a pill while it moves; filled dot = has windows, ring =
  empty, urgent colour for an urgent window. Optional wave on a switch.
- Shapes: circles, squares, triangles, numbers or a glyph of your own.
- Click focuses (and creates) a workspace; the scroll wheel goes to the previous or next one. While a
  special workspace is shown a name pill appears; a click puts it away.
- No window title on the bar, by design.
</details>

<details>
<summary><b>Centre island: clock, readouts and the control centre</b></summary>

- The clock, with its own font (IBM 3270, CPMono, 0xProto, JetBrains Mono or any installed font), size
  and Qt time format, and an optional date line.
- Beside it: CPU and memory percentages from `/proc` every 2 s, and the audio pill with speaker and
  microphone halves (left click opens the audio panels, right click mutes, scroll changes by 5 %, middle
  click opens the mixer). Either side can be hidden or swapped.
- A peek row that slides out under the clock for a moment after a volume, microphone or Caps Lock change.
- Hover (optional, with a close delay) or click opens the **control centre**:
  - the full date, uptime and a system panel: CPU usage and load, memory and storage meters, CPU and GPU
    temperatures;
  - six quick-setting tiles you can reorder and hide: Wi-Fi (with the network list and a password prompt
    under it), Bluetooth (with the device list: connect, pair, forget), Do not disturb, Keep awake (an idle
    inhibitor that survives a reload), Power profile (cycles power-saver, balanced, performance) and Night
    light;
  - a tools grid: Shuffle wallpaper, Colour picker, Calendar, Audio mixer, Shuffle colours, Sleepysettings,
    plus your own tools (an installed app, a command with or without a terminal, or a link), each with a
    label and a Material icon picked by name. A tool whose program is missing is greyed with the reason;
  - output and input audio panels (mute, slider, device list; Easy Effects chains resolve to the hardware
    node) and a backlight slider on laptops;
  - a Power button that opens the session menu.
- The centre island can be stepped (a deeper outline under the clock) and the open panel uneven.
</details>

<details>
<summary><b>Right island: widgets</b></summary>

Reorder and hide them in the Right island tab. Default order:

- **Caps Lock** indicator, shown only while Caps Lock is on.
- **Package updates**: the count of repository and AUR updates, shown only when there are some. The
  dropdown lists up to 30 packages, refreshes, and starts the update in your terminal; right click
  re-checks. Checks every 30 min (a setting).
- **Network**: glyph plus Wi-Fi signal. The dropdown shows the connection, the network list (scans while
  open, sorted connected, saved, by signal; click to connect or disconnect; a password prompt inline;
  failure reasons), live download and upload speed, and a button to the terminal network settings.
- **Bluetooth**: the number of connected devices while the adapter is on.
- **Battery**: percentage and glyph on laptops, red under the low level while discharging, accent while
  charging; click opens the Power tab.
- **Privacy**: microphone, camera and screen-share indicators, only while something uses them (read from
  PipeWire; Easy Effects, meters and muted streams are ignored; portal screencasts are detected). The
  dropdown names the app and what it uses.
- **Notifications**: the bell with a count while notifications wait, muted under Do not disturb. The
  dropdown has a Do not disturb switch, Clear all (the cards swipe out one by one) and the cards, newest or
  oldest first.
- **Clipboard**: opens walker's clipboard mode; hidden unless walker is installed.
- **System tray**: StatusNotifier icons with a themed right-click menu (with submenus); middle click for
  the secondary action; the wheel scrolls the item. Hidden when empty.
</details>

<details>
<summary><b>Notifications</b></summary>

- The shell is the notification daemon. Toasts appear under the bar, top right, newest on top or at the
  bottom, up to a set number at once; a notification's own timeout else 5 s; hovering holds them.
- Arrivals during a hover queue as compact rows, then a "+N more" pill that opens the list.
- Critical notifications never time out and show even under Do not disturb.
- A card shows the icon, summary, app and age, the body as plain text, the app's action buttons and a
  close button. Clicking a card runs the app's default action, else focuses the app's window, then
  dismisses it.
- Screenshot notifications (Hyprshot, or a file in a Screenshots folder) show a large preview; click
  copies the image, with buttons to open it or show it in its folder.
- The history keeps the newest 100. Waiting notifications survive a hot reload without re-toasting.
- Low battery: a notification at the low level and a critical one at the critical level with a 60 s
  countdown to the chosen action; plugging in cancels it.
</details>

<details>
<summary><b>Popups and overlays</b></summary>

- **On-screen display**: volume, microphone and Caps Lock, as the peek under the clock, or as a pill at the
  bottom over a fullscreen window.
- **Idle dim**: a fading black layer per screen when hypridle says so.
- **Calendar** (with khal): a month grid with per-calendar colour dots and event chips, the selected day's
  events with times, Today, New event and Open in khal (both in your terminal), full keyboard navigation,
  the wheel changes month. Re-reads khal every 10 min while open.
- **Polkit agent**: a blurred full-screen prompt with the action, the message, a password field and
  Cancel and Authenticate. It replaces hyprpolkitagent.
- **Session menu**: Lock, Sleep, Log out, Reboot and Shut down, with letter keys; the last three must be
  held for 600 ms (a ring fills).
- **Wallpaper picker**: a thumbnail grid of your wallpaper folder (or Hyprland's fallbacks when it is
  empty), the current one marked; click sets the wallpaper and its palette; Shuffle picks one at random.
- **Reload toast**: a themed replacement for Quickshell's reload popups.
</details>

<details>
<summary><b>Sleepysettings: the settings app</b></summary>

Every option in one window, as its own process. Search over every row (Ctrl+F; hits inside closed
Advanced folds open them), a live preview on the bar while you change things, an Apply bar that lists
exactly which files will be written (Ctrl+S) with Discard, an unapplied mark and a revert-to-default arrow
on every row, "!" info tips, an Advanced fold per tab, and a warning before leaving a tab with unapplied
changes. Rows that need a missing program are greyed with the reason; tabs that cannot work are hidden
unless you show them. Values are clamped to their ranges; several rows take a custom value.

- **Sleepybar**: bar height, text and icon sizes; dropdown text and icon sizes; island opacity; corner
  roundness (Sharp, Standard, Rounded, custom radius); island open and close time and easing; Caps Lock on
  the bar and in the peek, peek duration. Advanced: icon vertical offset, tile hover effect.
- **Left island**: always-visible workspaces, dot shape. Advanced: switch wave, island padding.
- **Centre island**: clock size, date; CPU and memory, audio, which side; stepped island, uneven panel;
  hover to open; the quick-setting tiles and the tools grid as drag-to-reorder editors with an eye per
  item and a tool editor (label, icon by name, app, command, link). Advanced: clock font, time and date
  format with a live preview, hover close delay.
- **Right island**: the widget list, drag to reorder, eye to hide; dropdown fit (Extend or Float).
  Advanced: update check interval, island padding.
- **Apps**: default terminal, browser, file manager, text editor, image viewer, video player, music
  player, PDF viewer and mail (web mail services included), written through `xdg-mime` and `xdg-settings`
  on Apply; a note when Hyprland's `programs.lua` names other programs, with an offer to update it. Apps on
  workspaces: an app or command per workspace (or the special one), at login or on first visit, window
  state, delay, skip if running, Run now; the placements already in your Hyprland config are listed.
- **Notifications**: Do not disturb, popup position, screenshot preview, test notifications (normal,
  critical, screenshot). Advanced: max popups, preview height, list order.
- **Theme**: Sleepytheme (from the wallpaper) or a community theme and its variant, with colour strips;
  matugen scheme (Vibrant, Tonal spot, Expressive, Fidelity, Content, Fruit salad, Monochrome, Neutral,
  Rainbow), light or dark, text contrast; the palette as tiles (click copies the hex) and Shuffle colours;
  icon theme, folder colours matched to the theme, interface font and size; wallpaper: random or chosen,
  automatic change with interval and order, also on login. Advanced: cool colours only, wallpaper folder.
- **Idle**: dim, lock and sleep with their timers, separate timers on battery, lock before sleep. Apply
  writes `hypridle.conf` and restarts hypridle.
- **Power**: the current profile and screen brightness live; battery charge, state, time left, health and
  cycles; profile and lid action when plugged in and on battery (Lock, Sleep, Hibernate, Do nothing or a
  command); low battery warning and level; critical level and action.
- **Display**: one card per monitor: resolution, refresh rate, scale, applied to `monitors.lua` with a 15 s
  Keep or Revert countdown; brightness and contrast over DDC/CI with a setup guide when the bus is not
  reachable. Advanced: input source, colour preset, rotation, adaptive sync, 10-bit colour, HDR with SDR
  brightness and saturation (when the EDID advertises it). With several monitors: the main monitor and
  what the others show (full bar without tray and bell, workspaces and clock, or nothing). Night light
  warmth and strength.
- **Keybinds**: your own binds (press the keys, type the command), written to `sleepybinds.lua`; export
  (yours or all) and import from a Lua or conf file or from Hyprland's defaults, with a preview that marks
  new, existing and conflicting binds and lists what was not imported and why; nothing runs from an
  imported file. Every bind of every file Hyprland loads, grouped, searchable, with a jump to the file.
- **Config**: every file the shell reads or writes, its state (Not found, Not loaded, Read-only, Has an
  error) and a fix: Create, Set up (shows the exact line it will add to `hyprland.lua`, backs the file
  up), Run the theme now, change a file's location. A missing program is reported with its install
  command, shown and never run. Show unavailable tabs; Reset one tab or all settings.
- **System**: OS, machine, kernel, uptime, Hyprland and Quickshell versions, login shell; CPU, GPU,
  displays, memory and swap; storage per mount; Copy as text. Read-only.
</details>

<details>
<summary><b>Sleepylock: the lock screen</b></summary>

- Its own process, started by hypridle, `loginctl lock-session`, the session menu, a keybind or IPC. It
  locks on start, exits after the unlock, and exits with an error if the compositor does not confirm the
  lock within 3 s. One lock at a time; a new instance can take over a dead one.
- Every screen shows its own blurred wallpaper, the time and date, your name, a frosted password field
  with dots as you type, a Caps Lock notice, "Checking…" and a shake on a wrong password.
- A black cover while the system prepares for sleep, lifted on the first key after waking.
- PAM directly, so failed attempts count like a TTY login. Only this session's logind signals end the
  lock. `loginctl unlock-session` from a TTY is the way out without a password.
</details>

<details>
<summary><b>Theming</b></summary>

- By default the colours come from your wallpaper through matugen and change with it: the picker, the
  Shuffle tools, the automatic wallpaper timer and `scripts/theme.py` all go through the same path. The
  bar recolours live when `colors.json` changes.
- Or a community theme, with the exact colours its authors publish, written into the same templates so
  every themed app follows it: Ayu, Catppuccin, Cyberdream, Dracula, Everforest, Gruvbox, Kanagawa,
  Moonfly, Night Owl, Nightfox, Nord, One, Oxocarbon, Poimandres, Rosé Pine, Solarized and Tokyo Night, 34
  variants in all. Sources and licences are in [`themes/README.md`](themes/README.md).
- Folder icons recoloured to the theme (an overlay icon theme that inherits yours), the icon theme, the
  interface font, and light or dark for GTK apps through gsettings.
- The templates for your other apps (terminal, GTK, Hyprland, and so on) live in your own matugen config;
  the shell ships the folder-icon templates and the matugen snippet that enables them.
</details>

<details>
<summary><b>Scripts</b></summary>

All in `scripts/`, standard-library Python unless noted.

- `theme.py`: a random wallpaper and its palette; a given wallpaper; `--palette` for new colours on the
  current one; `--preset FAMILY[:VARIANT]`; `--list-presets`; `--dry-run`; `--auto` for the timer.
- `appearance.py`: icon themes, fonts, gsettings, the folder-icon overlay (`state`, `icons`, `fonts`,
  `apply`, `folders-state`, `folders-snippet`, `folders-setup`, `folders-preview`).
- `idle.py`: writes `hypridle.conf` from the idle settings and restarts hypridle (`--print`, `--path`,
  `--battery`, `--ac`).
- `hyprconf.py`: reads your Hyprland Lua config as text (`discover`, `programs`, `parse-binds`), adds a
  `require` line with a backup (`add-require`), updates `programs.lua` (`set-programs`).
- `ddc.py`: DDC/CI over `/dev/i2c-*` without ddcutil (`list`, `get`, `set`, `caps`, `probe`).
- `defaultapps.py`: default apps (`scan`, `apply`, `webmail`). `edid.py`: HDR capability from the EDID.
  `sysinfo.py`: the System tab's data. `filecheck.py`: file state for the Config tab. `gen_icons.py`:
  the Material icon index from the Nerd Font.
- `checkupdates.sh` (repository and AUR updates against a private database copy) and `update.sh` (the
  terminal updater, shell).
</details>

## Dependencies

sleepyshell targets Arch Linux and its derivatives.

**Required.** The bar does not run without these.

| Program | Why |
|---|---|
| Hyprland with the Lua config (`hyprland.lua`, 0.56 or newer) | The compositor. The old `hyprland.conf` format is not supported: Sleepysettings reads and writes Lua |
| Quickshell 0.3 | The runtime for all three programs |
| Python 3 | The scripts; standard library only |
| JetBrainsMono Nerd Font (with the Propo variant) | Text and icons |

**Per feature.** A missing one greys out its feature with the reason; everything else works.

| Feature | Needs |
|---|---|
| Theming from the wallpaper, wallpaper picker and shuffle | matugen, ImageMagick (`magick`), awww (or swww, its older name) |
| Idle dim, lock and sleep timers | hypridle |
| Audio pill, panels and privacy indicators | PipeWire with WirePlumber (`wpctl`) |
| Network widget and Wi-Fi tile | NetworkManager |
| Bluetooth tile and widget | BlueZ |
| Updates widget | pacman, paru, fakeroot |
| Copy a screenshot from its notification | wl-clipboard |
| External monitor brightness, contrast, input and colour preset | DDC/CI: the `i2c-dev` module and access to the display buses (the Display tab shows the steps) |
| Power profile tile and profiles per power source | power-profiles-daemon |
| Backlight slider, lid actions, lock and session actions | systemd (`busctl`, `systemd-inhibit`, `loginctl`, `systemctl`), `flock` from util-linux, `gdbus` from glib2 |
| Default apps and links | xdg-utils |
| Icon theme, fonts and light or dark for GTK apps | glib2 (`gsettings`), fontconfig (`fc-list`) |
| Test notifications and battery warnings | libnotify (`notify-send`) |
| Log out | uwsm |

**Good to have.** Not needed, used when present.

| Program | What it adds |
|---|---|
| walker with its elephant service | The clipboard button opens walker's clipboard mode (hidden without walker); a good launcher to bind next to it |
| khal | The calendar popup and the Calendar tool; hidden without it |
| pciutils | GPU names in the System tab instead of PCI ids |
| pwvucontrol, hyprpicker | The Audio mixer and Colour picker tools |
| A terminal, file manager, editor, browser | Your own choice, set in the Apps tab; a missing one is reported, never assumed |

## Install

Clone it anywhere and link it where Quickshell looks, or clone it straight into that folder:

```sh
git clone https://github.com/nninkovic95/sleepyshell ~/dev/sleepyshell
ln -s ~/dev/sleepyshell ~/.config/quickshell/sleepyshell
```

Start it with your session, in `hyprland.lua`:

```lua
hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")   -- the wallpaper daemon (or swww-daemon)
    hl.exec_cmd("qs -c sleepyshell")
end)
```

The shell is also your notification daemon and polkit agent, so stop any other you were running.

Then open **Sleepysettings** (the gear in the control centre, or
`qs -c sleepyshell ipc call sleepybar toggle settings`). Its Config tab checks every file the shell needs
and offers to set things up. Anything that would change a Hyprland file is shown first and asked for, with
a backup kept. Settings live in `sleepysettings.toml` beside the shell, ignored by git.

## Keybinds and scripting

Hyprland talks to the shell through custom events, so a key press starts no process:

```lua
-- session menu
hl.bind(mainMod .. " + ESCAPE", hl.dsp.event("sleepyshell:toggle:session"))
-- Caps Lock indicator (the key still reaches the app)
hl.bind("Caps_Lock", hl.dsp.event("sleepyshell:capslock"), { non_consuming = true, ignore_mods = true, locked = true })
-- lock screen: started directly, so it works even when the bar is down
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("qs -n -p ~/.config/quickshell/sleepyshell/sleepylock.qml"), { locked = true })
```

`sleepyshell:toggle:<name>` opens any popup: `clock`, `audio`, `network`, `privacy`, `wallpaper`,
`sysinfo`, `updates`, `notifications`, `settings`, `session`, `calendar`. Lid switches send
`sleepyshell:lid:closed` and `sleepyshell:lid:open`; hypridle sends `sleepyshell:dim` and `sleepyshell:undim`.

From scripts:

```sh
qs -c sleepyshell ipc call sleepybar toggle <name>
qs -c sleepyshell ipc call sleepybar sleepylock
qs -c sleepyshell ipc call sleepybar clearNotifications
scripts/theme.py                          # a random wallpaper from your folder, and its palette
scripts/theme.py ~/Pictures/wall.jpg      # that wallpaper and its palette
scripts/theme.py --palette                # a new palette for the current wallpaper
scripts/theme.py --preset tokyonight:storm
scripts/theme.py --preset nord --dry-run  # render into a temp folder, change nothing
```

## Repository layout

The repository is the Quickshell config folder itself. Three programs share it; what two of them use
lives at the top.

```
sleepyshell/
├── shell.qml              the bar: islands, popups, notification server, polkit agent  (qs -c sleepyshell)
├── sleepysettings.qml     the settings app, its own process
├── sleepylock.qml         the lock screen, its own process
├── Theme.qml              colours, corners, sizes and motion for all three
├── components/            pieces two or more programs use: buttons, switch, slider, highlight, toast
├── services/              system state and logic: settings, audio, network, power, monitors, keybinds
├── sleepybar/
│   ├── Sleepybar.qml      one bar per monitor; places the islands
│   ├── islands/           Sleepyleft, Sleepycentre, Sleepyright: each island and what sits on it
│   ├── components/        the island shapes (SideIsland, GrowingIsland, IslandDropdown)
│   ├── widgets/           one folder per widget, each with its dropdown
│   └── popups/            surfaces of their own: on-screen display, calendar, polkit, session, wallpapers
├── sleepysettings/
│   ├── Sleepysettings.qml the window: sidebar, search, Apply bar
│   ├── *Tab.qml           one file per tab
│   └── components/        rows, pickers, dialogs and page parts the tabs share
├── sleepylock/            the lock screen's surfaces
├── scripts/               Python and shell helpers
├── themes/, templates/    community colour themes, folder-icon templates
├── data/                  the Material icon index, Hyprland's default binds
├── tests/                 the test kit: sandbox, compile gate, preview, deploy, recordings
├── docs/demo/             the recordings above
├── TASKS.md               what is done, open and not planned
└── SECURITY.md            what the shell trusts, runs and writes
```

## Development

- Edit a file; Quickshell reloads the bar. Sleepysettings and Sleepylock are separate processes, so
  editing their files never touches the bar.
- `tests/` is the kit. Every check runs inside a bubblewrap sandbox in which the whole system is
  read-only, only the run's own folder can be written, and there is no session bus, audio server or
  network; when a run ends its processes die with it. A checksum of every real file the shell could touch
  is compared before and after a run. `bash tests/common/selftest.sh` proves the isolation on your
  machine; `bash tests/common/compile.sh .` compiles every file; `bash tests/preview.sh start <copy>` runs
  a copy as the bar; `bash tests/deploy.sh apply <copy>` puts it in place with a backup and an automatic
  rollback. The kit's own [README](tests/README.md) has the details.
- Comments say why, not what changed; the history is in git.
- Open work, known issues and what is deliberately not planned are in [`TASKS.md`](TASKS.md).

## Security, tasks, licence

[`SECURITY.md`](SECURITY.md) describes what the shell trusts, what reaches it from outside, what it can
run and write, and its known limits, and how to report a vulnerability. [`TASKS.md`](TASKS.md) is the work
list.

MIT, see [LICENSE](LICENSE). The community theme palettes keep their own licences, listed in
[`themes/README.md`](themes/README.md). Built on [Quickshell](https://quickshell.org),
[Hyprland](https://hypr.land) and [matugen](https://github.com/InioX/matugen).

## AI disclaimer

sleepyshell is built with AI assistance (Claude Code). The maintainer sets the direction and makes every
design decision; the code is written in scoped jobs that agents carry out in isolated copies of the shell,
and nothing reaches the desktop without the compile gate, a sandboxed run and a review. Expect prose in
comments and documents that reads as written with a model's help; expect the bugs to be the maintainer's.
If something in the code or the documentation is wrong, a bug report is welcome like for any other
project, and so are contributions, with or without AI.
