pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Which permission mode is in force, next to the input where you're about to
 * commit to it. Click or Shift+Tab to cycle.
 *
 * It's always visible rather than tucked into a menu because the gap between
 * "will ask first" and "already ran it" is the one thing you must never have to
 * guess about.
 */
RippleButton {
    id: root

    readonly property var info: Ai.permissionModeInfo
    readonly property bool risky: Ai.permissionMode === "yolo"
    readonly property bool planning: Ai.permissionMode === "plan"

    implicitHeight: 30
    implicitWidth: chipRow.implicitWidth + 20
    buttonRadius: Appearance.rounding.full

    colBackground: root.risky ? Appearance.colors.colErrorContainer
        : root.planning ? Appearance.colors.colTertiaryContainer
        : Appearance.colors.colLayer2
    colBackgroundHover: root.risky ? Appearance.colors.colErrorContainerHover
        : root.planning ? Appearance.colors.colTertiaryContainerHover
        : Appearance.colors.colLayer2Hover

    readonly property color foreground: root.risky ? Appearance.colors.colOnErrorContainer
        : root.planning ? Appearance.colors.colOnTertiaryContainer
        : Appearance.colors.colOnLayer2

    onClicked: Ai.cyclePermissionMode()
    altAction: () => Ai.cyclePermissionMode(true)

    contentItem: RowLayout {
        id: chipRow
        spacing: 5

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            iconSize: Appearance.font.pixelSize.normal
            color: root.foreground
            text: root.info?.icon ?? "bolt"

            // Yolo gets a pulse: it's the one mode where nothing else will stop a
            // command, and it should never fade into the furniture.
            SequentialAnimation on opacity {
                running: root.risky
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { from: 1; to: 0.45; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.45; to: 1; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: root.foreground
            text: root.info?.name ?? ""
        }
    }

    StyledToolTip {
        text: `${root.info?.hint ?? ""}\n${Translation.tr("Shift+Tab to cycle")}`
    }
}
