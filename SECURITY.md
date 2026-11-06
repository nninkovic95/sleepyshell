# Security policy

sleepyshell is a desktop shell for Hyprland, written in Quickshell (QML) with Python helpers. It runs as the
logged-in user, holds no extra privileges and never asks for root. Four processes share one folder: the bar
(`qs -c sleepyshell`, also the notification daemon and the polkit agent), the settings app (Sleepysettings),
the lock screen (Sleepylock) and the Keybinds window.

## Supported versions

| Version | Supported |
|---|---|
| The latest release and `main` | Yes: fixes land on `main` and go out with the next release |
| Older releases | No: update to the latest release |
| The `dev` branch and its development-only tools | Not a release; report what you find all the same |

## Reporting a vulnerability

Please report it privately: open the **Security** tab of this repository and choose **Report a
vulnerability**. Do not open a public issue for a security problem.

Useful details: what you sent to the shell (a notification, a tray menu, a socket message, a file), what you
saw, and the commit or release you tested.

What you can expect:

- The project is maintained by one person on a best-effort basis. A report gets a first answer as soon as it
  is seen, usually within a few days.
- The report stays private while it is worked on. You hear whether it is accepted, and if not, why.
- An accepted problem is fixed on `main` and released. The advisory is then published, with credit to you if
  you want it.
- There is no bug bounty.

How the code is checked before it reaches anyone, including the automated AI review, is described in the
README's [Security](README.md#security) section.

## Trust model

The shell is a single-user desktop component. It trusts the user's own session: a process that already runs
as the same user can do anything the user can, and the shell does not try to stop it. What the shell does
defend against is being turned into a tool by text and files it did not write: notifications, tray menus,
device names, configuration files written by someone else.

## What reaches the shell from outside

| Input | Where it comes from | How it is handled |
|---|---|---|
| Notifications: summary, app name, body, action labels, an image or icon path | Any D-Bus client, including a browser relaying a web page | Rendered as plain text (`Text.PlainText`), never as markup; `<b>`, `<i>`, `<u>` are stripped from the body; the server reports `bodyMarkupSupported: false`. The history keeps the newest 100. An image or icon loads only from a local source: a file, the icon theme, or image data the app sent over D-Bus. A remote URL (`http`, `https` or any other scheme) is never fetched; the card falls back to the app's icon, else to the bell. |
| A click on a notification | The notification's own data | Goes to the app's default action, else its window found by class (app id, never title), else the image file it names, and only if that is an absolute local path with an image extension (`file://` decoded first). |
| Screenshot preview on a card | A sender named "hyprshot" or a path containing `/Screenshots/` | Decodes the local image for display only; nothing is sent anywhere. Any app can ask for a preview of an image the user can read; turn it off with the `shotPreview` setting. |
| System tray items: labels, icons, menu structure | Tray clients | Plain text. Icons load only from the icon theme, image data the app sent, or a file in an absolute icon folder; a remote URL is never fetched. |
| Wi-Fi and Bluetooth names | Nearby access points and devices | Plain text. A Bluetooth device is marked trusted only after pairing has succeeded. |
| PipeWire application names, EDID monitor names, polkit request text, package names, QML error text | PipeWire, the monitors, the polkit helper, pacman and paru, Quickshell | Plain text, everywhere. |
| A keybind file imported in the Keybinds tab | Often written by someone else | Parsed as text, never evaluated: no `load`, `require`, variables, concatenation or function calls. Only `hl.bind("KEYS", hl.dsp.<action>(<literal>)[, { option = true }])` lines are accepted, with the action and the options from closed lists; the line written to `sleepybinds.lua` is rebuilt from the parsed values. Everything else is refused and listed with its line number. The file must be text and at most 256 KB. Nothing is written until Add and Apply, and the previous file is backed up first. |
| The user's Hyprland files | `~/.config/hypr` | Read as text for keybind discovery and the Config tab checks; never evaluated. |
| How hypridle is started | The user's own running `hypridle` process (`/proc`; processes of other users, and ones not readable as the user's, are ignored), a launch in the Hyprland files, `hypridle.service` | Read only to find the `-c` file hypridle reads. Before writing, `idle.py` resolves the file once and, while holding its lock, refuses it (nothing written) unless the folder holding its name and the folder holding the real file (a symlink's target) both lie inside the home or config folder (links resolved; an empty or relative `XDG_CONFIG_HOME` counts as unset), belong to the user and are writable by no one else (group write only for the user's own private group), and the file and the link belong to the user. Create checks the place before it makes any folder. The backup and the temporary file are made beside the real file, never through a name that already exists. The lock is in `$XDG_RUNTIME_DIR` (else a per-user name in the temporary folder), opened without following links and refused if it is not the user's. Create and Replace pass the path and the real file the user confirmed; anything else at write time writes nothing. |
| `sleepysettings.toml` | The shell's own settings file | Parsed by the shell's own `Toml.js`. Numbers are clamped to their ranges on read. A file that does not parse names the line, keeps the last good values and makes every write a no-op until it parses again; the damaged text is copied to `sleepysettings.toml.broken` first. |
| Keybind reports | Hyprland, from the shell's `data/keyreport.lua`, which `hyprland.lua` loads | Only while the keybind overlay is on: the modifier mask and key name of a keybind that fired, as a custom event; a key that is not a keybind (typing) is never reported. Shown as plain text in the overlay's pill, kept only until the next one. The click circles get only "left" or "right" from their own pass-through binds and ask Hyprland for the pointer's place. Any program running as the user can read Hyprland's event socket, as for every other event; while the overlay is on, that includes which keybind was used. |
| Clipboard contents | Never read | The clipboard button only starts the optional walker launcher in its clipboard mode. |
| Window titles and media players | Not used | The bar shows workspaces only and has no media widget. |

## What the shell can run

Every command the shell starts is an argument array with no outside string in it. The few `sh -c` uses take
fixed strings, or pass a path as a positional argument. The commands that do come from the user's own input
run with the same trust as a bind typed by hand:

- the editor, file manager and terminal chosen in the Apps tab;
- commands typed into the Keybinds tab, and the custom control-centre tools (an app's desktop entry, a
  command through `sh -c`, or a link through `xdg-open`), on a click only;
- apps or commands set to start on a workspace at login, written to Hyprland as escaped Lua string literals (a
  blank row starts nothing);
- the custom commands for "When lid closes" and "Action at critical level" (`cmd:<command>` in
  `sleepysettings.toml`, one line of at most 300 characters). They run through `sh -c` in one place, only when
  the lid closes or the 60 s critical countdown ends, never while typed, staged or received.

The keybind overlay and the click circles switch Hyprland's side on and off through `hyprctl eval` with fixed Lua
code (a flag, and two pass-through click binds kept in a table and removed through their own handles, so a bind of
the user's is never touched); both are cleared when the bar starts and when it ends.

Install hints for a missing program are shown with a copy button and never run. Whether a program exists is
probed with `command -v` and the name as an argument; whether a package exists is asked of the local package
database, read only. "Update now" opens a terminal running `scripts/update.sh` (`paru -Syu`); the password
prompt belongs to that terminal and the shell never sees it. The update check syncs a private copy of the
package databases under `$XDG_RUNTIME_DIR` (without it, in a fresh `mktemp -d` folder removed after the check).
The shell itself makes no network connections.

## Boundaries between the parts

**IPC and Hyprland events.** Anything running as the same user can call the bar's IPC (target `sleepybar`:
`toggle(name)`, `sleepylock()`, `clearNotifications()`) and can send the shell's custom events through
Hyprland's socket (`sleepyshell:toggle:<name>`, `sleepyshell:sleepylock`, `sleepyshell:capslock`,
`sleepyshell:lid:closed|open`, `sleepyshell:dim|undim`). This is Quickshell's and Hyprland's normal model. These
open a popup, start the lock screen, clear the notification list, re-read an LED or dim the bar; they return no
data and change no setting.

**The settings socket.** Sleepysettings and the bar talk over a Unix socket at
`$XDG_RUNTIME_DIR/sleepyshell-settings-<hash>.sock`, where the hash comes from the shell's folder (links
resolved): each copy of the shell has its own socket, so a second copy (a test copy) never reaches the running
bar. The code does not authenticate the peer; the protection is the per-user, mode 0700 runtime directory. The
messages only stage, commit or toggle: `preview`, `commit` (the bar writes `sleepysettings.toml`) and `toggle`
(open a popup). No message can run a command or write a Hyprland file; a commit may store a custom lid or
battery command, which runs on that event, never on receipt. Every `preview` and `commit` is checked against the
settings schema before anything is applied: an unknown key or a value of the wrong kind refuses the whole
message, and numbers are clamped to their range. Any process that can open the socket can change the shell's
settings, which is why it must stay in the private runtime directory: if `XDG_RUNTIME_DIR` is unset the
fallback is `/tmp/sleepyshell-settings-<hash>.sock`, which is shared, so do not run the shell that way. The
lock's flock file has no such fallback: it is used only inside a runtime directory the user owns, and without
one the lock starts without it rather than not at all.

**Passwords.** Sleepylock checks the password with PAM directly, using the `login` service, so `pam_faillock`
counts wrong attempts like a TTY login. PAM is answered with the password as it was when the check started, so
Escape or more typing during the check never changes it. A check that takes longer than 30 seconds is stopped
and the lock says so; the field then takes a new password. The polkit prompt answers through Quickshell's polkit
agent flow; Escape cancels it at any time, also while PAM is checking, and a check that takes longer than 30
seconds is cancelled with a notification. A Wi-Fi key goes to NetworkManager over D-Bus. No password is put on
a command line, in a log line or in a stored property.

**The lock.** Sleepylock is its own process, so a crash or reload of the bar can never unlock a session. It
listens to logind's `Lock` and `Unlock` only for its own session (it asks logind for the session's object path
and fails closed until it has it), so another session being unlocked leaves it locked. A flock allows one lock
process at a time. If the compositor never confirms the lock, a watchdog gives up and the lock exits, so the
session is then not locked. Killing the lock process by hand leaves the compositor's lock in place; a new lock
process can take it over, and `loginctl unlock-session` from a TTY is the supported way out. When hypridle runs
as a systemd service, its `lock_cmd` starts the lock in a systemd scope of its own (`systemd-run --user
--scope`), so a restart of `hypridle.service` (the bar does one on every charger change) does not stop the lock
with it.

## What the shell writes

A file the user owns is changed only after a question that shows exactly what will change, with a backup
kept; everything else is written on Apply or on an explicit action. The one thing written in the background is
named under `hypridle.conf`.

- Its own files: `sleepysettings.toml` beside the shell; the colours under `$XDG_STATE_HOME/quickshell/`; the
  folder-icon overlay under `$XDG_DATA_HOME/icons`; hidden desktop entries for the web mail services chosen in
  the Apps tab; previews in the cache folder.
- The Hyprland files it owns: `monitors.lua`, `nightlight.lua` with `nightlight.frag`, and `sleepybinds.lua` (a
  dated backup before every write that changes it). They are written in place (Hyprland's file watcher needs a plain
  modification), from values the shell formatted or escaped itself (`\`, `"`, newline, carriage return and
  every other control character in Lua strings, one escaper for every Lua writer and Hyprland dispatch; numbers
  through `toFixed`, clamped).
- The main `hyprland.lua`, only through the Config tab's "Set up", after a question that shows the exact line.
  `scripts/hyprconf.py add-require` adds one `require` or `source` line after the last existing one, keeps a
  dated backup, writes atomically, is idempotent, refuses a file it cannot read, write or parse, and puts the
  file back if the config does not load afterwards. For the keybind overlay, `hyprconf.py add-keyreport` adds the
  one line that loads `data/keyreport.lua` above the first statement (it must load before the binds), only when
  the line is the one the question showed (its hash), with the same backup, atomic write and checks; a
  `hyprland.conf` is refused.
- `modules/programs.lua`, only after the Apps tab's question shows the exact changed lines; existing entries
  only, a dated backup, an atomic write, and the file is put back when the values do not read back as asked.
- The matugen config, only through the Theme tab's folder-icon "Set up", after a question that shows every
  line it adds; a dated backup is kept, and the script writes nothing if the lines differ from the ones shown.
- The keybinds file, when the Config tab points it at a file Sleepysettings did not create: the Keybinds tab's
  Apply shows every line it would remove and add and asks first; after the yes the file is marked as managed by
  Sleepysettings (a header line), backed up and written, and later Applies write it with a backup. The script
  writes nothing unless the change is the one that was shown.
- A keybind export, to the file the user picks. A file that already exists is replaced only after a question
  that names it, with a dated backup beside it, written atomically.
- `hypridle.conf` from the idle settings (`scripts/idle.py`): the file hypridle reads, found from how it is
  started (the `-c` of the running hypridle, of a launch in `hyprland.lua` or a file it requires, or of
  `hypridle.service`; else `~/.config/hypr/hypridle.conf`), unless the Config tab names another. The shell
  never creates it on its own: when it is missing, Create in Sleepysettings shows the path and the content and
  asks first. The shell's own file starts with `idle.py`'s header line; on a machine with a battery the bar
  rewrites that file in the background at start and on every charger change (the plugged-in or the on-battery
  timers), and only that file. A file the shell did not write is replaced only by the Idle tab's Apply, after it
  asks, with a dated backup beside it (`hypridle.conf.bak-YYYYMMDD-HHMMSS`). The shell never changes how
  hypridle is started. While `sleepysettings.toml` does not parse, nothing is written from it: `idle.py`,
  `theme.py` and `appearance.py` refuse to run on the default values, and the bar and Sleepysettings say why.
- On Apply, the desktop's own settings the user chose: default apps in `mimeapps.list` through `xdg-mime` and
  `xdg-settings` (Apps tab), and the icon theme, interface font and light or dark style through `gsettings`
  (Theme tab). The Apply bar names these before anything is written.
- Theming writes the colour files the user's own matugen config lists as outputs: matugen does this for the
  wallpaper's colours, and for a community theme the shell renders the same templates into the same files.
- Over DDC/CI, only VCP codes on an allow-list (brightness, contrast, colour preset, input source) and only
  values the monitor lists in its capabilities. Factory reset and power mode are refused twice, once when asked
  and once before the write leaves the queue. The udev rule that grants access to the display buses is shown
  for the user to install and never installed by the shell.
- Night light's sunrise and sunset are computed locally from the coordinates the user typed; nothing is
  fetched.

## Known limitations

- Same-user processes are trusted: they can call the IPC, connect to the settings socket, and read or write the
  shell's files. The shell is not a sandbox boundary.
- Suspend does not lock the session by itself; lock explicitly (the keybind, the session menu, or `ipc call
  sleepybar sleepylock`).
- The update check has no timeout.
- An IPC `toggle` with a name that is not a popup raises a caught error and does nothing.
- The shell relies on trusted companions: Hyprland, matugen, ImageMagick, awww or swww, and the user's own
  launcher, terminal, file manager, editor and mixer. Their security is out of scope.
