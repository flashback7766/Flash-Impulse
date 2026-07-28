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
 * Chat history, as a sheet that covers the conversation.
 *
 * It covers it completely and opaquely: as a half-width drawer over a themed
 * translucent surface, the chat underneath stayed legible straight through the
 * panel — the input field and the empty-state artwork read as part of the list.
 *
 * Titles are matched live from the store index, which is cheap. Matching message
 * *text* means opening every chat file, so that runs out of process and only
 * once the query is long enough to be worth it — results merge into the same
 * list rather than living in a separate popup.
 */
Item {
    id: root

    property bool shown: false

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

    Connections {
        target: Ai
        function onChatListRequested() {
            root.open(true);
        }
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

    // Section headers folded into the same flat list, so one ListView renders
    // both and the sections scroll with their rows.
    readonly property var rows: {
        const out = [];
        let currentBucket = "";
        const list = root.results;
        for (let i = 0; i < list.length; i++) {
            const bucket = root.bucketFor(list[i].updatedAt ?? 0);
            if (bucket !== currentBucket) {
                currentBucket = bucket;
                out.push({ kind: "header", id: `header-${bucket}`, label: bucket });
            }
            out.push({ kind: "chat", id: list[i].id, entry: list[i] });
        }
        return out;
    }

    function bucketFor(stamp) {
        if (!stamp) return Translation.tr("Older");
        const now = new Date();
        const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        if (stamp >= midnight) return Translation.tr("Today");
        if (stamp >= midnight - 86400000) return Translation.tr("Yesterday");
        if (stamp >= midnight - 7 * 86400000) return Translation.tr("Previous 7 days");
        if (stamp >= midnight - 30 * 86400000) return Translation.tr("Previous 30 days");
        return Translation.tr("Older");
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

    Rectangle {
        id: panel
        anchors.fill: parent
        // Deliberately not colLayer1: the layer colours are semi-transparent by
        // design, and this one has to hide the conversation behind it.
        color: Appearance.m3colors.m3surfaceContainerLow
        radius: Appearance.rounding.normal

        // A short rise on open; the fade does most of the work.
        transform: Translate {
            y: root.shown ? 0 : 12
            Behavior on y {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        MouseArea { anchors.fill: parent } // Swallow clicks meant for the chat underneath

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    text: Translation.tr("Chats")
                }

                StyledText {
                    Layout.rightMargin: 4
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: (Ai.chatIndex?.length ?? 0) > 0 ? String(Ai.chatIndex.length) : ""
                }

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    onClicked: {
                        Ai.newChat();
                        root.close();
                    }
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "add"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("New chat") }
                }

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Close (Esc)") }
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

            ColumnLayout { // Empty state
                Layout.fillWidth: true
                Layout.topMargin: 40
                visible: root.rows.length === 0
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 48
                    color: Appearance.colors.colOnLayer1Inactive
                    text: root.query.length > 0 ? "search_off" : "forum"
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: root.query.length > 0 ? Translation.tr("Nothing matched") : Translation.tr("No chats yet")
                }
            }

            StyledListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 1

                model: ScriptModel {
                    values: root.rows
                }

                delegate: DelegateChooser {
                    role: "kind"

                    DelegateChoice {
                        roleValue: "header"
                        Item {
                            id: sectionHeader
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            implicitHeight: 30

                            StyledText {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 4
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                font.capitalization: Font.AllUppercase
                                color: Appearance.colors.colSubtext
                                text: sectionHeader.modelData.label
                            }
                        }
                    }

                    DelegateChoice {
                        roleValue: "chat"
                        Rectangle {
                            id: chatRow
                            required property var modelData

                            readonly property var entry: chatRow.modelData.entry
                            readonly property bool isCurrent: chatRow.entry.id === Ai.currentChatId

                            width: ListView.view ? ListView.view.width : 0
                            implicitHeight: rowColumn.implicitHeight + 18
                            radius: Appearance.rounding.small
                            color: rowMouseArea.containsMouse ? Appearance.colors.colLayer2Hover
                                : chatRow.isCurrent ? Appearance.colors.colLayer2
                                : "transparent"

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            Rectangle { // Marks the conversation you're in
                                anchors.left: parent.left
                                anchors.leftMargin: 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: chatRow.isCurrent ? parent.height - 16 : 0
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colPrimary
                                Behavior on height {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }

                            MouseArea {
                                id: rowMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openChat(chatRow.entry.id)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 4
                                anchors.topMargin: 9
                                anchors.bottomMargin: 9
                                spacing: 4

                                ColumnLayout {
                                    id: rowColumn
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: chatRow.isCurrent ? Font.DemiBold : Font.Normal
                                        color: chatRow.isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                        // ?? only catches null, and both fields are
                                        // empty strings on a chat with no user turn
                                        // in it — which drew a row with a blank gap
                                        // where the name should be.
                                        text: (chatRow.entry.title ?? "").length > 0 ? chatRow.entry.title
                                            : (chatRow.entry.preview ?? "").length > 0 ? chatRow.entry.preview
                                            : Translation.tr("Untitled chat")
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: text.length > 0
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer1Inactive
                                        // Already shown as the name when there's no
                                        // title; repeating it as the subtitle too
                                        // printed the same line twice.
                                        text: (chatRow.entry.title ?? "").length > 0
                                            ? (chatRow.entry.preview ?? "") : ""
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 1
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                        text: root.describeEntry(chatRow.entry)
                                    }
                                }

                                RippleButton {
                                    id: deleteButton
                                    property bool armed: false
                                    Layout.alignment: Qt.AlignVCenter
                                    opacity: rowMouseArea.containsMouse || deleteButton.armed ? 1 : 0
                                    visible: opacity > 0
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    buttonRadius: Appearance.rounding.full
                                    onClicked: {
                                        if (deleteButton.armed) {
                                            Ai.deleteChat(chatRow.entry.id);
                                        } else {
                                            deleteButton.armed = true;
                                            deleteConfirmTimer.restart();
                                        }
                                    }
                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                    Timer {
                                        id: deleteConfirmTimer
                                        interval: 2000
                                        onTriggered: deleteButton.armed = false
                                    }
                                    contentItem: MaterialSymbol {
                                        horizontalAlignment: Text.AlignHCenter
                                        text: deleteButton.armed ? "delete_forever" : "delete"
                                        iconSize: Appearance.font.pixelSize.large
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
        const count = entry.messageCount ?? 0;
        if (count > 0) parts.push(count === 1 ? Translation.tr("1 message")
            : Translation.tr("%1 messages").arg(count));
        if ((entry.model ?? "").length > 0) parts.push(Ai.models[entry.model]?.name ?? entry.model);
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
