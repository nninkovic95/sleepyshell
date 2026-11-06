# showoff

A small tool for recording demos of sleepyshell. It is **not part of the shell**: the shell never loads it, the
test kit never deploys it, and it only exists on the `dev` branch.

- **Screen recorder** (SUPER + SHIFT + R): records the focused monitor with
  [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder/about/), H.264 in MP4 at 60 fps, to
  `~/Videos/Recordings/Recording_<date>_<time>.mp4`. Sound is what you hear; the microphone is off. While it
  records, sleepyshell's right island shows a recording dot (showoff tells the shell over its IPC:
  `qs -c sleepyshell ipc call sleepybar recording true|false`); SUPER + SHIFT + R again stops it. On stop, a notification
  offers **Open** and **Show in folder**. It records the monitor, not a window, so workspace switches are
  recorded too.

The keybind overlay and the click circles that used to live here are features of the shell now (the right
island's switches, `services/InputShow.qml`).

## Install

```sh
# the recorder (Arch / CachyOS)
sudo pacman -S gpu-screen-recorder
# make it a Quickshell config named "showoff"
ln -s "$PWD/tools/showoff" ~/.config/quickshell/showoff
```

The bind for `~/.config/hypr` (Lua config):

```lua
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("~/.config/quickshell/showoff/showoff.sh record"))
```

`showoff.sh record` starts the instance (`qs -c showoff`) when it is not running and sends the action over IPC:
`qs -c showoff ipc call showoff record`.

## Files

| File | What it is |
|---|---|
| `shell.qml` | the instance: the IPC target, and the call that tells sleepyshell a recording runs |
| `Recorder.qml` | starts and stops gpu-screen-recorder |
| `Opener.qml` | the "Recording saved" notification; Show in folder runs a terminal file manager (yazi) in the terminal chosen in sleepyshell's settings, since xdg-open cannot start one |
| `Terminal.js` | a link to the shell's `services/Terminal.js`: how each terminal runs a program (Quickshell imports nothing from outside a config's folder) |
| `showoff.sh` | the launcher the bind calls |
