import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import QtQuick
import QtQuick.Layouts

/**
 * Light / Dark / Auto, as one segment of a three-up choice.
 *
 * Picking a side turns following-the-sun off — the choice you just made by hand
 * should be the one that sticks.
 */
RippleButton {
    id: root
    required property string mode
    readonly property bool isAuto: mode === "auto"
    readonly property color colText: toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2

    padding: 5
    Layout.fillWidth: true
    implicitHeight: 84
    buttonRadius: Appearance.rounding.large
    toggled: isAuto ? Config.options.appearance.autoTheme.enable : (!Config.options.appearance.autoTheme.enable && Appearance.m3colors.darkmode === (mode === "dark"))

    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    colBackgroundToggled: Appearance.colors.colPrimaryContainer
    colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
    colRippleToggled: Appearance.colors.colPrimaryContainerActive

    onClicked: {
        if (root.isAuto) {
            Config.options.appearance.autoTheme.enable = true;
            return;
        }
        Config.options.appearance.autoTheme.enable = false;
        // No origin: this lives in the settings window, and a Wayland client
        // is not told where it sits on screen, so there is no honest point to
        // grow from. Centre reveal instead of a made-up one.
        ThemeTransition.requestMode(root.mode, -1, -1);
    }

    contentItem: Item {
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 28
                fill: root.toggled ? 1 : 0
                text: root.isAuto ? "routine" : (root.mode === "dark" ? "dark_mode" : "light_mode")
                color: root.colText
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.isAuto ? Translation.tr("Auto") : (root.mode === "dark" ? Translation.tr("Dark") : Translation.tr("Light"))
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: root.toggled ? Font.DemiBold : Font.Normal
                color: root.colText
            }
        }
    }
}
