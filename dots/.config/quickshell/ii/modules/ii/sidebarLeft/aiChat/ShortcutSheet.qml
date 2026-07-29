pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * What the keyboard can do here, on Ctrl+/.
 *
 * The shortcuts were only ever discoverable by reading the source or the
 * placeholder text, which between them named three of them.
 */
Item {
    id: root

    property bool shown: false

    visible: opacity > 0
    enabled: root.shown
    opacity: root.shown ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    readonly property var groups: [
        {
            label: Translation.tr("Conversation"),
            items: [
                ["Enter", Translation.tr("Send · approve a waiting command")],
                ["Shift+Enter", Translation.tr("New line")],
                ["Esc", Translation.tr("Reject a waiting command · close a panel")],
                ["Ctrl+E", Translation.tr("Reword your last question")],
                ["Ctrl+Shift+C", Translation.tr("Copy the last answer")],
                ["↑ / ↓", Translation.tr("Walk back through what you've asked")]
            ]
        },
        {
            label: Translation.tr("Getting around"),
            items: [
                ["Ctrl+K", Translation.tr("Chat history")],
                ["Ctrl+Shift+O", Translation.tr("New chat")],
                ["Ctrl+M", Translation.tr("Model picker")],
                ["Ctrl+,", Translation.tr("Assistant settings")],
                ["Ctrl+/  ·  F1", Translation.tr("This list")],
                ["PgUp / PgDn", Translation.tr("Scroll the conversation")]
            ]
        },
        {
            label: Translation.tr("Behaviour"),
            items: [
                ["Shift+Tab", Translation.tr("Cycle permission mode")],
                ["Ctrl+1…9", Translation.tr("Switch model by position")],
                ["/", Translation.tr("Commands")]
            ]
        },
        {
            label: Translation.tr("The sidebar itself"),
            items: [
                ["Ctrl+O", Translation.tr("Expand")],
                ["Ctrl+P", Translation.tr("Pin")],
                ["Ctrl+D", Translation.tr("Detach")],
                [Translation.tr("Drag the edge"), Translation.tr("Resize · double-click resets")]
            ]
        }
    ]

    MouseArea {
        anchors.fill: parent
        onClicked: root.shown = false
    }

    Rectangle {
        anchors.fill: parent
        // Opaque for the same reason the history sheet is: a list of key names
        // over a conversation is unreadable against it.
        color: Appearance.m3colors.m3surfaceContainerLow
        radius: Appearance.rounding.normal

        // hoverEnabled too: without it this swallows clicks but not hover, and a
        // hovered control underneath keeps its tooltip floating over the sheet.
        MouseArea { anchors.fill: parent; hoverEnabled: true }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    text: Translation.tr("Keyboard")
                }

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.shown = false
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            // No Flickable: inside one, children are parented to contentItem,
            // whose width is contentWidth — zero unless set — so `width:
            // parent.width` collapsed the entire list to nothing. The list is
            // short and fixed, and the sheet is full height, so it just fits.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop

                ColumnLayout {
                    id: shortcutColumn
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 2

                    Repeater {
                        model: root.groups

                        delegate: ColumnLayout {
                            id: group
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.topMargin: 8
                                Layout.leftMargin: 4
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                font.capitalization: Font.AllUppercase
                                color: Appearance.colors.colSubtext
                                text: group.modelData.label
                            }

                            Repeater {
                                model: group.modelData.items

                                delegate: RowLayout {
                                    id: shortcut
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.topMargin: 3
                                    spacing: 10

                                    Rectangle {
                                        Layout.alignment: Qt.AlignTop
                                        // One column width for every chip, so the
                                        // descriptions line up instead of stepping
                                        // in and out with the length of each key.
                                        implicitWidth: 110
                                        implicitHeight: 22
                                        radius: Appearance.rounding.verysmall
                                        color: Appearance.colors.colLayer2

                                        StyledText {
                                            id: keyLabel
                                            anchors.centerIn: parent
                                            width: parent.width - 10
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnLayer2
                                            text: shortcut.modelData[0]
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        wrapMode: Text.Wrap
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer1
                                        text: shortcut.modelData[1]
                                    }
                                }
                            }
                        }
                    }

                }

                Item { Layout.fillWidth: true; Layout.fillHeight: true }
            }
        }
    }
}
