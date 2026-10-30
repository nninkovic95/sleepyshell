# Recordings

One feature per clip, as animated WebP, recorded by hand for the showcase. The automated run (an empty workspace with Hyprland's own fallback
wallpapers (`/usr/share/hypr/wall*.png`), the cursor driven through a virtual pointer) is kept as tooling:
[`tests/demo/record.sh`](../../tests/demo/record.sh) and cut by
[`tests/demo/assemble.sh`](../../tests/demo/assemble.sh); the settings clip is the automated tour in
[`tests/demo/settings_tour.sh`](../../tests/demo/settings_tour.sh), which drives the window through its
IPC.

## The centre island

| File | What it shows |
|---|---|
| `control-centre.webp` | **Control centre.** The centre island grows into the control centre when the cursor reaches the clock and closes when it leaves. |
| `tile-tilt.webp` | **Lift and tilt.** The hover effect on the quick-setting tiles as the cursor crosses them. |
| `tile-do-not-disturb.webp` | **Do not disturb**, on and off. |
| `tile-keep-awake.webp` | **Keep awake**, an idle inhibitor, on and off. |
| `tile-night-light.webp` | **Night light**, on and off. |
| `tile-bluetooth.webp` | **Bluetooth**, the adapter on and off. |
| `tile-power-profile.webp` | **Power profile**, cycled through the profiles and back. |
| `audio.webp` | **Audio panels.** A click on the pill opens the output and input panels; the slider moves the volume. |
| `pill-scroll.webp` | **Scroll on the pill** changes the volume. |
| `pill-mute.webp` | **Right click on the pill** mutes and unmutes. |
| `calendar.webp` | **Calendar** from the tools: a day, the next month, Today. |
| `session.webp` | **Session menu** from the Power button: Lock, Sleep, Log out, Reboot, Shut down; the last three must be held. |
| `wallpaper.webp` | **Wallpapers** from the tools: the thumbnails, a click sets the wallpaper and its palette. |
| `shuffle-wallpaper.webp` | **Shuffle wallpaper:** another wallpaper, every colour of the shell follows through matugen. |
| `shuffle-colours.webp` | **Shuffle colours:** a new palette for the same wallpaper. |

## The side islands

| File | What it shows |
|---|---|
| `island-extend.webp` | **Extend.** A side island widens so its dropdown hangs flush under it, as one shape. |
| `island-float.webp` | **Float.** The same dropdown as a floating card under the island. |
| `workspaces.webp` | **Workspaces.** Clicks on the dots; the accent disc slides, a filled dot has windows, a ring is empty. |
| `updates.webp` | **Updates.** The count on the bar and the dropdown with the packages. |
| `notifications.webp` | **Notifications.** Ten toasts arrive, the queue folds into a pill, one toast is held under the cursor. |
| `notification-list.webp` | **The list.** The bell opens it, it scrolls. |
| `card-tilt.webp` | **Lift and tilt** on the notification cards. |
| `clear-all.webp` | **Clear all** sweeps the cards out one by one. |

## Sleepysettings

| File | What it shows |
|---|---|
| `settings.webp` | **Sleepysettings.** Opened from the tools, then an automated tour through the window's IPC: corners, opacity, bar height, motion, dot shapes, the clock, the readouts, a hidden widget, test notifications, a palette shuffle, a look at every tab. Every change shows on the bar at once and is put back; nothing is written. |
| `wallpaper-settings.webp` | **Choose wallpaper.** The picker opened from the Theme tab. |

Not recorded yet: the terminal updater, drag and drop in the settings editors, the lock screen, a
community theme preset, the Caps Lock peek, the polkit prompt, the Wi-Fi and Bluetooth lists. See
[`TASKS.md`](../../TASKS.md).
