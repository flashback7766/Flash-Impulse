//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"
import "panelFamilies"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Stuff for every panel family
    ReloadPopup {}

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        AutoTheme.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
        IdleManager.apply()
        // Touching the singleton is what constructs it, and constructing it is
        // what registers its IPC target — without this the settings app's
        // "apply display settings" call has nothing listening on the other end.
        // A bare property read would do it, but reads that exist for their side
        // effects are exactly the kind of line someone deletes as dead code.
        DisplayManager.ensureLoaded()
        // Same reason, plus one of its own: this singleton reconciles a
        // leftover game-mode state at startup, which has to happen whether or
        // not anything ever looks at a game-mode toggle this session.
        GameMode.ensureLoaded()
    }


    LazyLoader {
        active: Config.ready
        component: IllogicalImpulseFamily {}
    }
}

