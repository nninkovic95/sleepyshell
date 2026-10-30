# Security

sleepyshell is a desktop shell for Hyprland, written in Quickshell (QML) with Python helpers. It runs
as the logged-in user, holds no extra privileges and never asks for root. Three processes share one
folder: the bar (`qs -c sleepyshell`, also the notification daemon and the polkit agent), the settings
app (Sleepysettings) and the lock screen (Sleepylock). This page describes what the shell trusts, what
reaches it from outside, what it can run and write, and where its limits are.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: open the **Security** tab of this repository and choose
**Report a vulnerability**. Please do not open a public issue for a security problem. Useful details:
what you sent to the shell (a notification, a tray menu, a socket message, a file), what you saw, and
the commit you tested. The project is maintained by one person on a best-effort basis; a report gets a
first answer as soon as it is seen.

## Trust model

The shell is a single-user desktop component. It trusts the user's own session: a process that already
runs as the same user can do anything the user can, and the shell does not try to stop it. What the shell
does defend against is being turned into a tool by text and files it did not write: notifications, tray
menus, device names, configuration files written by someone else.

## What reaches the shell from outside

| Input | Where it comes from | How it is handled |
|---|---|---|
| Notifications: summary, app name, body, action labels, an image or icon path | Any D-Bus client, including a browser relaying a web page | Rendered as plain text (`Text.PlainText`), never as markup; `<b>`, `<i>`, `<u>` are stripped from the body; the server reports `bodyMarkupSupported: false`. The history keeps the newest 100. |
| A click on a notification | The notification's own data | Goes to the app's default action, else its window found by class (app id, never title), else the image file it names, and only if that is an absolute local path with an image extension (`file://` decoded first). |
| Screenshot preview on a card | A sender named "hyprshot" or a path containing `/Screenshots/` | Decodes the local image for display only, nothing is sent anywhere. Any app can ask for a preview of an image the user can read; turn it off with the `shotPreview` setting. |
| System tray items: labels, icons, menu structure | Tray clients | Plain text. |
| Wi-Fi and Bluetooth names | Nearby access points and devices | Plain text. A Bluetooth device is marked trusted only after pairing has succeeded. |
| PipeWire application names, EDID monitor names, polkit request text, package names, QML error text | PipeWire, the monitors, the polkit helper, pacman and paru, Quickshell | Plain text. Two places still use Qt's default text format (the polkit helper's supplementary message and the package list); see Known limitations. |
| A keybind file imported in the Keybinds tab | Often written by someone else | Parsed as text, never evaluated: no `load`, `require`, variables, concatenation or function calls. Only `hl.bind("KEYS", hl.dsp.<action>(<literal>)[, { option = true }])` lines are accepted, with the action and the options from closed lists; the line written to `sleepybinds.lua` is rebuilt from the parsed values. Everything else is refused and listed with its line number. The file must be text and at most 256 KB. Nothing is written until Add and Apply, and the previous file is backed up first. |
| The user's Hyprland files | `~/.config/hypr` | Read as text for keybind discovery and the Config tab checks; never evaluated. |
| `sleepysettings.toml` | The shell's own settings file | Parsed by the shell's own `Toml.js`. Numbers are clamped to their ranges on read. A file that does not parse names the line, keeps the last good values and makes every write a no-op until it parses again; the damaged text is copied to `sleepysettings.toml.broken` first. |
| Clipboard contents | Never read | The clipboard button only starts the optional walker launcher in its clipboard mode. |
| Window titles and media players | Not used | The bar shows workspaces only and has no media widget. |

## What the shell can run

Every command the shell starts is an argument array with no outside string in it. The few `sh -c` uses
take fixed strings, or pass a path as a positional argument. The commands that do come from the user's
own input run with the same trust as a bind typed by hand:

- the editor named in the user's Hyprland `programs.lua`;
- commands typed into the Keybinds tab, and the custom control-centre tools (an app's desktop entry, a
  command through `sh -c`, or a link through `xdg-open`), on a click only;
- apps or commands set to start on a workspace at login, written to Hyprland as escaped Lua string
  literals (a blank row starts nothing);
- the custom commands for "When lid closes" and "Action at critical level" (`cmd:<command>` in
  `sleepysettings.toml`, one line of at most 300 characters). They run through `sh -c` in one place,
  only when the lid closes or the 60 s critical countdown ends, never while typed, staged or received.

Install hints for a missing program are shown with a copy button and never run. Whether a program
exists is probed with `command -v` and the name as an argument; whether a package exists is asked of the
local package database, read only. "Update now" opens a terminal running `scripts/update.sh` (`paru
-Syu`); the password prompt belongs to that terminal and the shell never sees it. The update check syncs
a private copy of the package databases under `$XDG_RUNTIME_DIR`. The shell itself makes no network
connections.

## Boundaries between the parts

**IPC and Hyprland events.** Anything running as the same user can call the bar's IPC (target
`sleepybar`: `toggle(name)`, `sleepylock()`, `clearNotifications()`) and can send the shell's custom
events through Hyprland's socket (`sleepyshell:toggle:<name>`, `sleepyshell:sleepylock`,
`sleepyshell:capslock`, `sleepyshell:lid:closed|open`, `sleepyshell:dim|undim`). This is Quickshell's and
Hyprland's normal model. These open a popup, start the lock screen, clear the notification list, re-read
an LED or dim the bar; they return no data and change no setting.

**The settings socket.** Sleepysettings and the bar talk over a Unix socket at
`$XDG_RUNTIME_DIR/sleepyshell-settings.sock`. The code does not authenticate the peer; the protection is
the per-user, mode 0700 runtime directory. The messages only stage, commit or toggle: `preview`, `commit`
(the bar writes `sleepysettings.toml`) and `toggle` (open a popup). No message can run a command or
write a Hyprland file; a commit may store a custom lid or battery command, which runs on that event,
never on receipt. Any process that can open the socket can change the shell's settings, which is why it
must stay in the private runtime directory: if `XDG_RUNTIME_DIR` is unset the fallback is
`/tmp/sleepyshell-settings.sock`, which is shared, so do not run the shell that way.

**Passwords.** Sleepylock checks the password with PAM directly, using the `login` service, so
`pam_faillock` counts wrong attempts like a TTY login. The polkit prompt answers through Quickshell's
polkit agent flow. A Wi-Fi key goes to NetworkManager over D-Bus. No password is put on a command line, in
a log line or in a stored property.

**The lock.** Sleepylock is its own process, so a crash or reload of the bar can never unlock a session.
It listens to logind's `Lock` and `Unlock` only for its own session (it asks logind for the session's
object path and fails closed until it has it), so another session being unlocked leaves it locked. A
flock allows one lock process at a time. If the compositor never confirms the lock, a watchdog gives up
and the lock exits, so the session is then not locked. Killing the lock process by hand leaves the
compositor's lock in place; a new lock process can take it over, and `loginctl unlock-session` from a TTY
is the supported way out.

## What the shell writes

Everything below is written on Apply, or on an explicit action, never in the background.

- Its own state: `sleepysettings.toml` beside the shell, and the matugen colours under
  `$XDG_STATE_HOME/quickshell/`.
- The Hyprland files it owns: `monitors.lua`, `nightlight.lua` with `nightlight.frag`, and
  `sleepybinds.lua`. They are written in place (Hyprland's file watcher needs a plain modification), from
  values the shell formatted or escaped itself (`\`, `"`, newline and carriage return in Lua strings;
  numbers through `toFixed`, clamped).
- The main `hyprland.lua`, only through the Config tab's "Set up", after a confirmation that shows the
  exact line. `scripts/hyprconf.py add-require` adds one `require` or `source` line after the last
  existing one, keeps a dated backup, writes atomically, is idempotent, refuses a file it cannot read,
  write or parse, and puts the file back if the config does not load afterwards.
- `hypridle.conf` from the idle settings (`scripts/idle.py`), `mimeapps.list` through `xdg-mime` and
  `xdg-settings`, and the folder-icon overlay under `$XDG_DATA_HOME/icons`.
- Over DDC/CI, only VCP codes on an allow-list (brightness, contrast, colour preset, input source) and
  only values the monitor lists in its capabilities. Factory reset and power mode are refused twice,
  once when asked and once before the write leaves the queue. The udev rule that grants access to the
  display buses is shown for the user to install and never installed by the shell.
- Night light's sunrise and sunset are computed locally from the coordinates the user typed; nothing is
  fetched.

## How changes are checked

Every change is compiled in a bubblewrap sandbox before it reaches a desktop: the whole system is
read-only inside it, only the run's own folder can be written, and there is no session bus, audio server
or network (see [`tests/`](tests/README.md)). A checksum of every real file the shell could touch is
compared before and after a run, and a deploy keeps a backup and rolls itself back when the shell does
not load.

## Known limitations

- Same-user processes are trusted: they can call the IPC, connect to the settings socket, and read or
  write the shell's files. The shell is not a sandbox boundary.
- Suspend does not lock the session by itself; lock explicitly (the keybind, the session menu, or
  `ipc call sleepybar sleepylock`).
- Notification images and tray icons are passed to the image loaders without a scheme check. Whether a
  remote URL would be fetched has not been settled; treat it as possible.
- Two texts are still rendered with Qt's default format instead of plain text: the polkit helper's
  supplementary message and the package names in the updates dropdown. Both come from local system
  components rather than from an unprivileged caller.
- The PAM check and the update check have no timeout, and Escape cannot cancel the polkit prompt while
  PAM is checking.
- An IPC `toggle` with a name that is not a popup raises a caught error and does nothing.
- The on-screen display still logs audio node names to the Quickshell log through a temporary diagnostic.
- The shell relies on trusted companions: Hyprland, matugen, ImageMagick, awww or swww, and the user's own
  launcher, terminal, file manager, editor and mixer. Their security is out of scope.
