import QtQuick
import Quickshell.Io
import qs.modules.common.models.hyprland
import qs.services

/**
 * Same story as the classic-style button: this used to apply the compositor
 * overrides itself and work out whether it was on by reading one of them back
 * (`animations:enabled`). Feral GameMode now changes the same settings, and
 * reading a setting cannot tell you who set it — so both toggles defer to the
 * GameMode service, which is the only thing that knows.
 */
QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    toggled: GameMode.active
    icon: "gamepad"

    mainAction: () => {
        GameMode.manualEnabled = !GameMode.manualEnabled;
    }

    tooltipText: GameMode.gamemodedActive ? Translation.tr("Game mode\nOn automatically — a game is running") : Translation.tr("Game mode")
}
