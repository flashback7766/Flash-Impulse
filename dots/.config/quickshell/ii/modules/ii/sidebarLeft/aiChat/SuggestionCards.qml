pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import "suggestionPool.js" as SuggestionPool

/**
 * What to ask, on an empty chat.
 *
 * A blank box with a list of keyboard shortcuts tells you how to operate the
 * thing but not what it's for. These are the questions this assistant is
 * unusually good at — it can read the machine it runs on — so they double as a
 * statement of what makes it different from a browser tab.
 */
ColumnLayout {
    id: root

    signal picked(string prompt)

    spacing: 6

    // What the machine is currently in a position to complain about. Read from
    // state the shell already keeps, so opening an empty chat costs nothing.
    function currentContext() {
        const hour = new Date().getHours();
        const windows = HyprlandData.windowList?.length ?? 0;
        return {
            batteryLow: (Battery.available ?? false) && (Battery.isLow ?? false) && !(Battery.isCharging ?? false),
            batteryCharging: (Battery.available ?? false) && (Battery.isCharging ?? false),
            memoryHigh: (ResourceUsage.memoryUsedPercentage ?? 0) > 0.85,
            swapUsed: (ResourceUsage.swapUsedPercentage ?? 0) > 0.15,
            updatesPending: (Updates.available ?? false) && (Updates.count ?? 0) > 0,
            multiMonitor: (Quickshell.screens?.length ?? 1) > 1,
            audioMuted: Audio.sink?.audio?.muted ?? false,
            networkDown: !(Network.wifi || Network.ethernet),
            manyWindows: windows > 12,
            morning: hour >= 5 && hour < 11,
            night: hour >= 22 || hour < 5
        };
    }

    // Re-rolled whenever the empty chat comes back into view, not on every
    // binding change — a set that reshuffled under the pointer would be worse
    // than one that never changes.
    property var suggestions: []
    function reroll() {
        root.suggestions = SuggestionPool.pick(root.currentContext(), 4,
            Ai.promptProfileInfo.cardCategories);
    }
    Component.onCompleted: root.reroll()

    // Re-rolled when the sidebar comes back, and when a new chat clears the
    // board. Not on every binding change: a set that reshuffled under the
    // pointer would be worse than one that never changes.
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) root.reroll();
        }
    }
    Connections {
        target: Ai
        function onChatOpened() { root.reroll(); }
        // Switching from Code & Linux to CTF & reversing mid-session should
        // offer CTF cards, not leave the previous persona's picks sitting there.
        function onPromptProfileChanged() { root.reroll(); }
    }

    Repeater {
        model: root.suggestions

        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index

            Layout.fillWidth: true
            implicitHeight: 42
            radius: Appearance.rounding.small
            color: cardArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            // Staggered so the set assembles rather than appearing all at once.
            opacity: 0
            Component.onCompleted: cardReveal.start()
            SequentialAnimation {
                id: cardReveal
                PauseAnimation { duration: card.index * 45 }
                NumberAnimation {
                    target: card
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 240
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                id: cardArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(card.modelData.prompt)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colPrimary
                    text: card.modelData.icon
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                    text: card.modelData.label
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    opacity: cardArea.containsMouse ? 1 : 0
                    text: "arrow_forward"
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
