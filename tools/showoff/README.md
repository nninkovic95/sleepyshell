# showoff

Two small tools for recording demos of sleepyshell. They are **not part of the shell**: the shell never
loads them, the test kit never deploys them, and they only exist on the `dev` branch.

- **Screen recorder** (SUPER + SHIFT + R): records the focused monitor with
  [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder/about/), H.264 in MP4 at 60 fps, to
  `~/Videos/Recordings/Recording_<date>_<time>.mp4`. Sound is what you hear; the microphone is off. A red
  `REC m:ss` pill shows under the left island while it records (click it to stop). On stop, a notification
  offers **Open** and **Show in folder**. It records the monitor, not a window, so workspace switches are
  recorded too.
- **Click rings and shortcuts** (SUPER + SHIFT + K): an expanding ring at the pointer on every left and
  right click, and a pill at the bottom of the screen naming the Hyprland shortcut you used
  (`Super + Shift + R`) or the click (`Right click`). A `KEYS` pill shows under the left island while it
  is on (click it to switch off).

## Install

```sh
# the recorder (Arch / CachyOS)
sudo pacman -S gpu-screen-recorder
# make it a Quickshell config named "showoff"
ln -s "$PWD/tools/showoff" ~/.config/quickshell/showoff
```

Binds for `~/.config/hypr` (Lua config):

```lua
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("~/.config/quickshell/showoff/showoff.sh record"))
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.exec_cmd("~/.config/quickshell/showoff/showoff.sh keys"))
```

For the shortcuts, one line near the top of `hyprland.lua`, before the file that makes your binds:

```lua
pcall(dofile, os.getenv("HOME") .. "/.config/quickshell/showoff/showoff.lua")
```

`showoff.sh <record|keys>` starts the instance (`qs -c showoff`) when it is not running and sends the
action over IPC: `qs -c showoff ipc call showoff record`.

## Where the shortcuts and clicks come from

Nothing reads your keyboard or mouse, and nothing runs as root. Hyprland reports them itself:

- `showoff.lua` wraps `hl.bind`, so every bind made after it first sends a custom event naming its keys
  (`showoff:bind:<modmask>:<r|p>:<key>`, `r` for a bind that repeats while held) and then does what it
  always did; that includes the scroll-wheel binds. A drag or resize bind (SUPER + drag) is left as it is:
  a pass-through bind made just before it on the same keys reports it, so SUPER + drag shows
  `Super + Left click` with its ring. Nothing is sent while the display is off.
- Switching the display on adds pass-through bindings for the mouse buttons through `hyprctl eval`
  (clicks still reach the window); switching off removes exactly those again.

So the pill shows only what Hyprland handles: your shortcuts, plain clicks and the clicks you bound with a
modifier. Typing, shortcuts inside an app (`Ctrl + T` in a browser) and unbound clicks with a modifier held
are not shown. The words (`Left click`, `Mute`, `Scroll down`) are the shell's own, the same as in its
Keybinds window. Anything running as your user
can read Hyprland's event socket, as for every other event; while the display is on, that includes which
shortcut you used. A Hyprland config reload while it is on clears the click bindings; switch it off and on
again.

## Files

| File | What it is |
|---|---|
| `shell.qml` | the instance: colours from matugen's `colors.json`, the IPC target, the pills |
| `Recorder.qml` | starts and stops gpu-screen-recorder |
| `Opener.qml` | the "Recording saved" notification; Show in folder runs a terminal file manager (yazi) in the terminal chosen in sleepyshell's settings, since xdg-open cannot start one |
| `InputOverlay.qml` | the rings and the shortcuts pill |
| `showoff.lua` | the Hyprland side: reports each shortcut while the display is on |
| `KeyNames.js`, `Terminal.js` | links to the shell's `services/` files: key names in words, and how each terminal runs a program (Quickshell imports nothing from outside a config's folder) |
| `showoff.sh` | the launcher the binds call |
