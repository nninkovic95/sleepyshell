// Harness of tests/lock/pam-timeout.sh, copied into the root of the tree under test and run offscreen: the tree's
// real sleepylock/Sleepylock.qml (its copy given the aliases testPam and testTimeout by the test), never locked
// (lock() is never called, so no session lock is requested). Its
// PamContext is pointed at test PAM stacks in the run folder (T3_PAM; no pam_unix, no pam_faillock: no real password
// is ever checked), and the check timeout is shortened to 3 s for the run (its own value is reported). In order:
//   permit   pam_permit: a check that succeeds
//   record   pam_exec expose_authtok saves the password PAM got; the field is emptied right after the check
//            starts, as Escape does, and the check must still get "secret1"
//   hang     pam_exec runs a script that sleeps: the check must be given up and say so
//   retry    pam_permit again: the lock must accept a new check after the one given up
// Prints one line "RESULT <json>" and quits.
import QtQuick
import Quickshell
import qs.sleepylock

Scope {
    id: h
    readonly property string pamDir: Quickshell.env("T3_PAM") ?? ""
    property var pam: null
    property var timeout: null
    property int timeoutWas: 0
    property var results: ({})
    property string step: ""
    property var completions: []

    Sleepylock {
        id: lock
    }

    function state() {
        return {
            inProgress: lock.unlockInProgress,
            failure: lock.showFailure,
            failureText: lock.failureText ?? null,
            field: lock.currentText,
            pamActive: h.pam ? h.pam.active : null,
            completions: h.completions.slice()
        };
    }

    function start(config, text) {
        h.pam.config = config;
        h.completions = [];
        lock.currentText = text;
        lock.tryUnlock();
    }

    Connections {
        target: h.pam
        function onCompleted(result) {
            h.completions = h.completions.concat([result === 0 ? "success" : "failure:" + result]);
        }
        ignoreUnknownSignals: true
    }

    // the steps, one after another
    Timer {
        id: steps
        interval: 500
        running: true
        property int n: 0
        onTriggered: {
            n++;
            if (n === 1) {
                // aliases the test adds to its copy of the lock (a Scope's children cannot be reached from QML)
                h.pam = lock.testPam ?? null;
                h.timeout = lock.testTimeout ?? null;
                if (!h.pam) {
                    console.log("RESULT " + JSON.stringify({ error: "no PamContext found" }));
                    quitTimer.start();
                    return;
                }
                h.pam.configDirectory = h.pamDir;
                if (h.timeout) {
                    h.timeoutWas = h.timeout.interval;
                    h.timeout.interval = 3000;
                }
                h.start("permit", "x");
                restart(2000);
            } else if (n === 2) {
                h.results.permit = h.state();
                h.start("record", "secret1");
                // Escape in the field: SleepylockSurface empties currentText
                lock.currentText = "";
                restart(3000);
            } else if (n === 3) {
                h.results.record = h.state();
                h.start("hang", "y");
                restart(1500);
            } else if (n === 4) {
                h.results.hangEarly = h.state();
                restart(3500);
            } else if (n === 5) {
                h.results.hang = h.state();
                h.start("permit", "z");
                restart(2000);
            } else if (n === 6) {
                h.results.retry = h.state();
                h.results.timeoutWas = h.timeoutWas;
                console.log("RESULT " + JSON.stringify(h.results));
                quitTimer.start();
            }
        }
        function restart(ms) {
            interval = ms;
            start();
        }
    }

    Timer {
        id: quitTimer
        interval: 300
        onTriggered: Qt.exit(0)
    }
}
