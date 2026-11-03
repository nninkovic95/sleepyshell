# Review checklist

Read by the automated reviewers (every push and the weekly audit). The project's own notes are not in the
repository, so the rules the reviewers need live here.

sleepyshell is a desktop shell for Hyprland built on Quickshell: QML and JavaScript for the bar, the
settings app, the lock screen and the Keybinds window, plus Python and shell helpers in `scripts/`. It runs
as the logged-in user. `SECURITY.md` describes what it trusts, runs and writes; `README.md` describes what
it does. Both are promises to users and are checked against the code.

## What to check, in priority order

### 1. Security

- Shell injection: a command line built from text by concatenation or interpolation, `sh -c` / `bash -c`
  with values inside, values that could start with `-` passed without `--`.
- Shell scripts: unquoted variables and command substitutions, word splitting and globbing on values,
  missing `set -euo pipefail` where a failure would go unnoticed, temp files at predictable paths.
- `eval`, `exec`, `Function(...)`, `Qt.createQmlObject` or a Lua `load` on text that is not a literal.
- Secrets, tokens or keys in the code, in logs, or written to world-readable files.
- The settings socket and the IPC targets (`IpcHandler` blocks): every message from outside must be
  validated (type, range, closed lists). No message may run a command, open an arbitrary path, or write a
  value the shell did not validate. Anything newly reachable over the socket or IPC is called out.
- Parsing of untrusted input (notification text and images, imported keybind files, tray data, file
  names, monitor data): length limits, no evaluation, no path traversal.
- File writes: atomic where a half-written file would break the user's session, a backup before replacing
  a user file, no symlink-following writes into places the shell does not own.
- Privilege: the shell never asks for root. Anything that adds `sudo`, `pkexec` or a polkit action, or
  installs system files, is called out.

### 2. Ask first

The shell never changes a user's existing file without asking first. Its own files (`sleepysettings.toml`,
the Hyprland files it owns such as `monitors.lua`, `nightlight.lua` and `sleepybinds.lua`, the matugen
colours, its icon overlay) are written on Apply or an explicit action, never in the background. A file it
does not own, above all the main `hyprland.lua`, is only changed after a confirmation that shows exactly
what will change, with a backup kept. Any change that writes to a file the user owns without such a
confirmation, writes in the background, or widens what an existing confirmation covers, is a breach.

One exception, decided by the owner: on a machine with a battery the bar rewrites `hypridle.conf` in the
background (at start and on a change of power source, for that source's idle timers), and only when the
file is the shell's own, that is, it starts with `scripts/idle.py`'s header line. A missing file is never
created in the background, and a file without the header is never touched there. Anything wider than
that is a breach.

### 3. Dev-only content on main

Paths listed in `.github/dev-only` exist only on the dev branch. On main: any such path, any code that
loads, imports, calls or documents something from them as part of the shell, or any shell behaviour that
depends on them, is a leak. On dev: the shell itself must not depend on them either (they are optional
tools beside the shell).

### 4. Personal paths and machine assumptions

No absolute home paths, user names, host names, machine IDs, monitor names or serials, network names or
addresses, or anything else specific to one machine. Paths come from the XDG variables or are relative to
the shell folder. Assumptions about one particular monitor layout, GPU, keyboard or installed program
without a check and a fallback are flagged.

### 5. Documentation that no longer matches the code

Claims in `README.md`, `SECURITY.md` and the tests' README that the change makes untrue: features,
settings, keybinds, dependencies, what is written where, what is validated, what is asked first.

## Severity

- **serious**: an exploitable security problem (injection, unvalidated socket or IPC input that reaches a
  command or a file write, a leaked secret), an ask-first breach, dev-only content on main. A serious
  finding marks the commit with a red X and blocks the release.
- **minor**: a real defect or risk that is not exploitable as it stands, a personal path, a docs claim
  that no longer holds.
- **note**: worth knowing, no action strictly needed.

## Category

- **security**: anything that could be used against a user (injection, untrusted input reaching a command,
  a parser or a file write, a leak, a weaker lock or prompt).
- **ask-first**: a user file written, appended to or overwritten without asking.
- **personal-path**: personal data or a machine-specific assumption in the code.
- **dev-only**: dev-only content or a dependency on it.
- **docs**: a claim in the docs that no longer holds.
- **other**: any other real defect.

Findings in security, ask-first and personal-path are filed only in a private draft security advisory;
the others are published with the check run. When a finding could be security or another category, choose
security. Keep the summary free of the details of security, ask-first and personal-path findings.

Report only real findings, each with the file and line it sits on and a concrete fix. Do not report style,
formatting or taste. When nothing is wrong, say so and return no findings.
