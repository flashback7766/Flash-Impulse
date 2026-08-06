pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One model in the picker.
 *
 * Extracted because the built-in and custom lists were two near-identical
 * copies of fifty lines, which is how the two drifted apart — only one of them
 * ever learned to fall back to a guessed icon.
 */
RippleButton {
    id: root

    required property string modelId
    property bool pendingDelete: false

    signal chosen

    readonly property bool removable: Ai.isRemovableModel(root.modelId)
    readonly property bool current: Ai.currentModelId === root.modelId
    readonly property bool favourite: Ai.isFavouriteModel(root.modelId)
    readonly property var model: Ai.models[root.modelId] ?? null

    Layout.fillWidth: true
    implicitHeight: 52
    buttonRadius: Appearance.rounding.normal
    toggled: root.current
    colBackground: root.current ? Qt.alpha(Appearance.m3colors.m3primaryContainer, 0.85) : "transparent"
    colBackgroundHover: Qt.alpha(Appearance.colors.colLayer2Hover, 0.8)

    onClicked: {
        if (root.pendingDelete) {
            root.pendingDelete = false;
            return;
        }
        Ai.setModel(root.modelId, false);
        root.chosen();
    }

    Timer {
        id: deleteResetTimer
        interval: 2500
        onTriggered: root.pendingDelete = false
    }

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 12

        Rectangle {
            width: 32
            height: 32
            radius: 8
            color: Qt.alpha(Appearance.colors.colSubtext, 0.1)

            CustomIcon {
                anchors.centerIn: parent
                visible: (root.model?.icon ?? "").length > 0
                width: 20
                height: 20
                source: root.model?.icon ?? ""
                colorize: true
                color: root.current ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurface
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: (root.model?.icon ?? "").length === 0
                text: Ai.guessModelLogo(root.modelId)
                iconSize: 20
                color: root.current ? Appearance.m3colors.m3primary : Appearance.colors.colSubtext
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small + 2
                font.weight: Font.DemiBold
                color: root.current ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface
                text: root.model?.name ?? root.modelId
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                font.pixelSize: Appearance.font.pixelSize.smaller + 1
                color: root.current ? Qt.alpha(Appearance.m3colors.m3onPrimaryContainer, 0.75)
                    : Appearance.colors.colSubtext
                text: (root.model?.description ?? "").split("\n")[0] ?? ""
                elide: Text.ElideRight
            }
        }

        // Always there, dim until used. Hiding it until hover makes pinning
        // undiscoverable, and unreachable entirely without a pointer that
        // hovers — which is most ways of driving this.
        MaterialSymbol {
            visible: !root.pendingDelete
            text: root.favourite ? "star" : "star_outline"
            iconSize: 18
            color: root.favourite ? Appearance.m3colors.m3primary : Appearance.colors.colSubtext
            opacity: root.favourite ? 1 : (root.hovered ? 0.7 : 0.35)
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: Ai.toggleFavouriteModel(root.modelId)
            }
        }

        // No separate check mark for the current model: the row is already
        // filled and bold, and a fourth fixed item pushed the star off the end.

        RowLayout { // Delete confirmation, custom models only
            visible: root.pendingDelete
            spacing: 8
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
                text: Translation.tr("Remove?")
            }
            MaterialSymbol {
                text: "delete_forever"
                iconSize: 20
                color: Appearance.m3colors.m3error
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Ai.removeModel(root.modelId)
                }
            }
        }

        MaterialSymbol {
            visible: root.removable && !root.pendingDelete && !root.current
            text: "close"
            iconSize: 18
            color: Appearance.colors.colSubtext
            opacity: 0.5
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.pendingDelete = true;
                    deleteResetTimer.restart();
                }
            }
        }
    }
}
