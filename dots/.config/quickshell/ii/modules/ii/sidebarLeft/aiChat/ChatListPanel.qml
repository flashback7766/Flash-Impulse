pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Chat history: a panel that slides in over the conversation.
 *
 * Titles are matched live from the store index, which is cheap. Matching message
 * *text* means opening every chat file, so that runs out of process and only
 * once the query is long enough to be worth it — results merge into the same
 * list rather than living in a separate popup.
 */
Item {
    id: root

    property bool shown: false
    property real panelWidth: Math.min(360, parent ? parent.width * 0.8 : 360)

    signal requestClose

    function open(focusSearch) {
        root.shown = true;
        if (focusSearch) Qt.callLater(() => searchField.forceActiveFocus());
    }

    function close() {
        root.shown = false;
        searchField.text = "";
        root.requestClose();
    }

    visible: opacity > 0
    enabled: root.shown

    opacity: root.shown ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // ---- searching ---------------------------------------------------------

    property string query: searchField.text.trim()
    // Ids whose message text matched, from the out-of-process search.
    property var contentMatches: []

    readonly property var results: {
        const q = root.query.toLowerCase();
        const index = Ai.chatIndex ?? [];
        if (q.length === 0) return index;
        const matched = root.contentMatches;
        return index.filter(e => {
            if ((e.title ?? "").toLowerCase().indexOf(q) !== -1) return true;
            if ((e.preview ?? "").toLowerCase().indexOf(q) !== -1) return true;
            return matched.indexOf(e.id) !== -1;
        });
    }

    onQueryChanged: {
        root.contentMatches = [];
        // One character matches nearly everything; don't spawn a scan for it.
        if (root.query.length >= 2) contentSearchDebounce.restart();
        else contentSearchDebounce.stop();
    }

    Timer {
        id: contentSearchDebounce
        interval: 200
        onTriggered: {
            contentSearch.running = false;
            contentSearch.buffer = "";
            contentSearch.running = true;
        }
    }

    Process {
        id: contentSearch
        property string buffer: ""
        command: ["python3", "-c", `
import glob, json, os, sys
needle = sys.argv[2].lower()
hits = []
for path in glob.glob(os.path.join(sys.argv[1], "chat_*.json")):
    try:
        with open(path) as f:
            chat = json.load(f)
    except Exception:
        continue
    for m in (chat.get("messages") or []):
        if needle in (m.get("rawContent") or "").lower():
            hits.append(chat.get("id") or os.path.basename(path)[5:-5])
            break
print(json.dumps(hits))
`, Directories.aiChats, root.query]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed)) root.contentMatches = parsed;
                } catch (e) {
                    // A failed scan just means title-only results; not worth surfacing.
                }
            }
        }
    }

    // ---- chrome ------------------------------------------------------------

    MouseArea { // Scrim; also swallows clicks meant for the chat underneath
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3scrim
        opacity: 0.32
    }

    Rectangle {
        id: panel
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: root.panelWidth
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal

        transform: Translate {
            x: root.shown ? 0 : -panel.width * 0.15
            Behavior on x {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        MouseArea { anchors.fill: parent } // Don't let clicks fall through to the scrim

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    text: Translation.tr("Chats")
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    onClicked: {
                        Ai.newChat();
                        root.close();
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("New chat") }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            MaterialTextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search chats")
                wrapMode: TextEdit.NoWrap

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.results.length > 0) root.openChat(root.results[0].id);
                        event.accepted = true;
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 20
                horizontalAlignment: Text.AlignHCenter
                visible: root.results.length === 0
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                text: root.query.length > 0 ? Translation.tr("Nothing matched") : Translation.tr("No chats yet")
            }

            StyledListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2

                model: ScriptModel {
                    values: root.results
                }

                delegate: Rectangle {
                    id: chatRow
                    required property var modelData

                    readonly property bool isCurrent: chatRow.modelData.id === Ai.currentChatId

                    width: ListView.view ? ListView.view.width : 0
                    implicitHeight: rowColumn.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: chatRow.isCurrent ? Appearance.colors.colSecondaryContainer
                        : rowMouseArea.containsMouse ? Appearance.colors.colLayer1Hover
                        : "transparent"

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MouseArea {
                        id: rowMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openChat(chatRow.modelData.id)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 4
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 4

                        ColumnLayout {
                            id: rowColumn
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                                text: (chatRow.modelData.title ?? "").length > 0
                                    ? chatRow.modelData.title
                                    : (chatRow.modelData.preview ?? Translation.tr("Untitled chat"))
                            }

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: root.describeEntry(chatRow.modelData)
                            }
                        }

                        RippleButton {
                            id: deleteButton
                            property bool armed: false
                            visible: rowMouseArea.containsMouse || deleteButton.armed
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            onClicked: {
                                if (deleteButton.armed) {
                                    Ai.deleteChat(chatRow.modelData.id);
                                } else {
                                    deleteButton.armed = true;
                                    deleteConfirmTimer.restart();
                                }
                            }
                            Timer {
                                id: deleteConfirmTimer
                                interval: 2000
                                onTriggered: deleteButton.armed = false
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: deleteButton.armed ? "delete_forever" : "delete"
                                iconSize: Appearance.font.pixelSize.normal
                                color: deleteButton.armed ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                            }
                            StyledToolTip {
                                text: deleteButton.armed ? Translation.tr("Click again to delete")
                                    : Translation.tr("Delete chat")
                            }
                        }
                    }
                }
            }
        }
    }

    function openChat(id) {
        if (id === Ai.currentChatId) {
            root.close();
            return;
        }
        Ai.persistCurrentChat();
        Ai.loadChatById(id);
        root.close();
    }

    function describeEntry(entry) {
        const parts = [];
        const stamp = entry.updatedAt ?? 0;
        if (stamp > 0) parts.push(root.relativeTime(stamp));
        if ((entry.messageCount ?? 0) > 0) parts.push(Translation.tr("%1 messages").arg(entry.messageCount));
        return parts.join(" · ");
    }

    function relativeTime(stamp) {
        const minutes = Math.floor((Date.now() - stamp) / 60000);
        if (minutes < 1) return Translation.tr("just now");
        if (minutes < 60) return Translation.tr("%1 min ago").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 24) return Translation.tr("%1 h ago").arg(hours);
        const days = Math.floor(hours / 24);
        if (days < 7) return Translation.tr("%1 d ago").arg(days);
        return new Date(stamp).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }
}
