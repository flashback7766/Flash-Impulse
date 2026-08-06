import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import Quickshell.Io

/**
 * Manual game mode.
 *
 * The button used to own the state and apply the hyprctl keywords itself,
 * reading its own toggled state back by asking Hyprland whether animations
 * happened to be enabled. That is why this had to become a service: Feral
 * GameMode now changes the same settings underneath it, and "are animations
 * off" cannot tell you *who* turned them off — so quitting a game would leave
 * the button lit with nothing behind it, or dark while the settings were still
 * stripped.
 */
QuickToggleButton {
    id: root
    buttonIcon: "gamepad"
    toggled: GameMode.active

    onClicked: {
        // Only the manual half is ours to flip. While a game is running the
        // service stays active regardless, which is the honest answer — turning
        // it off here would be undone the moment gamemoded next said anything.
        GameMode.requestManual(!GameMode.active);
    }

    StyledToolTip {
        text: GameMode.gameRunning ? Translation.tr("Game mode\nOn automatically — a game is running") : Translation.tr("Game mode")
    }
}
