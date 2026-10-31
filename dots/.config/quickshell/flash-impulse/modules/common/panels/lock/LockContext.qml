import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Scope {
    id: root

    enum ActionEnum { Unlock, Poweroff, Reboot }

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    // These properties are in the context and not individual lock surfaces
    // so all surfaces can share the same state.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool fingerprintsConfigured: false
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    function resetClearTimer() {
        passwordClearTimer.restart();
    }

    function reset() {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
        // The idle timer calls this long after the lock, and the sensor used
        // to go deaf right here: stopFingerPam took the listener away and
        // nothing brought it back until the next lock. Only an unlock should.
        if (GlobalStates.screenLocked) {
            tryFingerUnlock();
        } else {
            stopFingerPam();
        }
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        onTriggered: {
            root.reset();
        }
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) {
            showFailure = false;
            GlobalStates.screenUnlockFailed = false;
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        passwordClearTimer.restart();
    }

    function tryUnlock(alsoInhibitIdle = false) {
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.unlockInProgress = true;
        pam.start();
    }

    function tryFingerUnlock() {
        if (root.fingerprintsConfigured && !fingerPam.active) {
            fingerPam.start();
        }
    }

    function stopFingerPam() {
        fingerRetryTimer.stop();
        if (fingerPam.active) {
            fingerPam.abort();
        }
    }

    Timer {
        id: fingerRetryTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (GlobalStates.screenLocked && root.fingerprintsConfigured && !root.unlockInProgress) {
                root.tryFingerUnlock();
            }
        }
    }

    Process {
        id: fingerprintCheckProc
        // The lock panel is constructed at shell startup and lives forever,
        // so running: true forked fprintd-list on every boot for an answer
        // nobody reads until locking. Re-check on each lock instead — which
        // is also correct when a finger gets enrolled mid-session.
        running: GlobalStates.screenLocked
        command: ["bash", "-c", "fprintd-list $(whoami)"]
        stdout: StdioCollector {
            id: fingerprintOutputCollector
            onStreamFinished: {
                root.fingerprintsConfigured = fingerprintOutputCollector.text.includes("Fingerprints for user");
                // The check and the arming race: both fire on the same state
                // change, and the arming reads a flag this check has not set
                // yet — the first lock after a shell start (or a reload)
                // found the sensor deaf until a password attempt. The check
                // finishing is the moment the answer exists; arm right here.
                if (root.fingerprintsConfigured && GlobalStates.screenLocked) {
                    root.tryFingerUnlock();
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // console.warn("[LockContext] fprintd-list command exited with error:", exitCode, exitStatus);
                root.fingerprintsConfigured = false;
            }
        }
    }
    
    PamContext {
        id: pam

        // pam_unix will ask for a response for the password prompt
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.currentText);
            }
        }

        // pam_unix won't send any important messages so all we need is the completion status.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                GlobalStates.screenUnlockFailed = true;
                root.showFailure = true;
            }
        }
    }

    PamContext {
        id: fingerPam

        configDirectory: "pam"
        config: "fprintd.conf"

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else if (GlobalStates.screenLocked) {
                // A wrong finger lands here as Failed, fprintd's cooldown as
                // MaxTries, a dead conversation as Error: whichever way the
                // attempt ended, the sensor goes back to listening after the
                // wait. Without the screenLocked guard the retry also fired
                // for the abort of an unlock — and the listener then spun
                // forever, claiming the reader every thirty seconds while
                // the desktop was in use.
                fingerRetryTimer.restart();
            }
        }
    }
}
