# Recordings

Short animated WebP clips of sleepyshell, one per feature, recorded on an empty workspace with
Hyprland's own fallback wallpapers (`/usr/share/hypr/wall*.png`). They are made by
[`tests/demo/record.sh`](../../tests/demo/record.sh), which drives the shell through its IPC, Hyprland's
dispatchers and a virtual pointer, and cut by [`tests/demo/assemble.sh`](../../tests/demo/assemble.sh).

## The bar

| Clip | What it shows |
|---|---|
| ![Control centre](control-centre.webp) | **Control centre.** The centre island grows into the control centre on hover: date and uptime, the system panel, the quick-setting tiles, the tools grid, the audio panels. It closes when the cursor leaves. |
| ![Islands](islands.webp) | **Islands.** A side island widens so its dropdown hangs flush under it as one shape ("Extend"), then the same dropdown as a floating card ("Float"). |
| ![Workspaces](workspaces.webp) | **Workspaces.** The accent disc slides between the dots; a filled dot has windows, a ring is empty. |
| ![Audio](audio.webp) | **Audio pill.** Output and input with their levels; scroll changes the volume, right click mutes. |

## Around it

| Clip | What it shows |
|---|---|
| ![Notifications](notifications.webp) | **Notifications.** Three toasts arrive, the bell shows their count, its dropdown lists the cards, Clear all sweeps them out one by one. |
| ![On-screen display](osd.webp) | **On-screen display.** The volume peek under the clock. |
| ![Calendar](calendar.webp) | **Calendar.** The month view with khal, opened from the control centre's tools. |
| ![Session menu](session.webp) | **Session menu.** Lock, Sleep, Log out, Reboot and Shut down; the last three must be held. |
| ![Wallpaper picker](wallpaper.webp) | **Wallpaper picker.** The thumbnails of the wallpaper folder; here the fallback wallpapers. |
| ![Theme](theme.webp) | **Theme.** The wallpaper changes and every colour of the shell follows through matugen. |

## Sleepysettings

| Clip | What it shows |
|---|---|
| ![Settings](settings.webp) | **Sleepysettings.** The window opened from the control centre, then every tab in turn: Sleepybar, Left island, Centre island, Right island, Apps, Notifications, Theme, Idle, Power, Display, Keybinds, Config, System. |

Not recorded yet: the lock screen, a community theme preset, the Caps Lock peek, the polkit prompt. See
[`TASKS.md`](../../TASKS.md).
