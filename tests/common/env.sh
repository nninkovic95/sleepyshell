# common/env.sh: the paths every script of the kit uses. Sourced, never run.
#
#   KIT        this kit (~/.config/quickshell/sleepyshell-tests)
#   REAL_LIVE  the live shell; the one folder deploy.sh writes to
#   LIVE       the deploy target: REAL_LIVE, or a scratch copy when SLEEPYSHELL_LIVE is set (deploy.sh
#              tests itself that way; it then never touches a running shell)
#   RUN        everything a test run creates: sandbox trees, logs, guard snapshots, one folder per run,
#              deleted when the run ends. cleanup.sh stops only processes started from a folder under
#              RUN, so the preview (KIT/candidate) and the live shell are never touched by it
#   BACKUPS    one folder per deploy (deploy.sh)
# Portable, so the kit runs on any machine: no user name, home
# folder or user id is written anywhere in the kit. The kit finds itself from this file's location, and
# every other place comes from the XDG variables with their standard fallbacks.
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp}
export XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_RUNTIME_DIR
KIT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
REAL_LIVE=$XDG_CONFIG_HOME/quickshell/sleepyshell
LIVE=${SLEEPYSHELL_LIVE:-$REAL_LIVE}
# on the runtime tmpfs: a run's files live in memory and are gone at logout even if a run is killed
RUN=$XDG_RUNTIME_DIR/sleepyshell-tests
BACKUPS=${SLEEPYSHELL_BACKUPS:-$KIT/backups}

# files that hold the user's state, not code: never deployed, never removed, never restored by a rollback
STATE_GLOBS=("sleepysettings.toml" "sleepysettings.toml.*" "settings.json" "settings.json.*")
# The shell folder is also the repository root. These belong to the repository, not to the shell: git
# manages them, the kit never copies, compiles, deploys, removes or backs them up. The same lists live
# in common/treediff.py and common/guard.py; change all three together.
REPO_DIRS=(".git" "tests" "docs" "__pycache__")
REPO_FILES=("README.md" "TASKS.md" "LICENSE" "SECURITY.md" "CLAUDE.md" "CLAUDE.local.md" ".gitignore")
# tar_excludes: the --exclude arguments for a tar of a shell tree
tar_excludes() {
    local x
    for x in "${REPO_DIRS[@]}"; do printf -- '--exclude=./%s\n' "$x"; done
    for x in "${REPO_FILES[@]}"; do printf -- '--exclude=./%s\n' "$x"; done
}
# copy_tree SRC DST: copy a shell tree without the repository's files (DST is created)
copy_tree() {
    mkdir -p -- "$2"
    tar -C "$1" $(tar_excludes) -cf - . | tar -C "$2" -xf -
}

# the live shell: running as `qs -c sleepyshell` (session autostart) or `qs -c sleepyshell -d` (after a deploy)
live_shell_pid() {
    pgrep -f '^qs -c sleepyshell( -d)?$' | head -1 || true
}

# a running preview: the shell started from a candidate folder of this kit (preview.sh)
preview_pid() {
    pgrep -f "^qs -p $KIT/[^ ]+ -d$" | head -1 || true
}

# the folder a running preview was started from
preview_dir() {
    local pid
    pid=$(preview_pid)
    [ -n "$pid" ] && tr '\0' ' ' < "/proc/$pid/cmdline" | awk '{ print $3 }'
}

# How many load results the log of the instance with this pid holds so far. A result is
# "Configuration Loaded" or "Failed to load configuration"; Quickshell writes one per start and per
# reload. By pid, never by config name: right after a restart the name still finds the old log.
load_count() {
    qs log --pid "$1" 2>/dev/null | grep -acE 'Configuration Loaded|Failed to load configuration' || true
}

# wait_loaded N PID: wait up to 20 s until that instance's log has more than N load results, then 1.5 s
# more (several saves in a row reload several times; the last result counts). Prints "loaded",
# "failed" or "timeout" and returns 0 only for "loaded".
wait_loaded() {
    local n=$1 pid=$2 last
    for _ in $(seq 100); do
        [ "$(load_count "$pid")" -gt "$n" ] && break
        sleep 0.2
    done
    if [ "$(load_count "$pid")" -le "$n" ]; then
        echo timeout
        return 1
    fi
    sleep 1.5
    last=$(qs log --pid "$pid" 2>/dev/null | grep -aoE 'Configuration Loaded|Failed to load configuration' | tail -1)
    if [ "$last" = "Configuration Loaded" ]; then
        echo loaded
    else
        echo failed
        return 1
    fi
}

# start_shell DIR|"": start the live shell (no argument) or a candidate folder as a daemon, wait for the
# new process and print its pid
start_shell() {
    local before pid
    if [ -z "${1:-}" ]; then
        qs -c sleepyshell -d >/dev/null 2>&1
        for _ in $(seq 50); do pid=$(live_shell_pid); [ -n "$pid" ] && break; sleep 0.1; done
    else
        qs -p "$1" -d >/dev/null 2>&1
        for _ in $(seq 50); do pid=$(pgrep -f "^qs -p $1 -d$" | head -1); [ -n "$pid" ] && break; sleep 0.1; done
    fi
    echo "$pid"
}

# stop_pid PID: SIGTERM, wait until it is gone (4 s), then SIGKILL
stop_pid() {
    kill "$1" 2>/dev/null || return 0
    for _ in $(seq 40); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done
    kill -9 "$1" 2>/dev/null
}
