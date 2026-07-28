import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * One message in the chat.
 *
 * Asymmetric on purpose: a question is a short aside and sits in a compact
 * bubble on the right, an answer is the content you came for and runs the full
 * width with no container around it. The old design put both in identical
 * cards under a heavy coloured header bar with five buttons always showing,
 * which made a conversation read as a stack of forms.
 *
 * Controls live under the message and only on hover; authorship is a small
 * icon and a label, and the model is named on every answer rather than only
 * when it changes.
 */
Item {
    id: root
    property int messageIndex
    property var messageData
    property var messageInputField

    property real messagePadding: 7
    property real contentSpacing: 4

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false
    property bool isContinuation: false

    readonly property bool isUser: messageData?.role === "user"
    readonly property bool isAssistant: messageData?.role === "assistant"
    readonly property bool isInterface: messageData?.role === "interface"
    readonly property bool hovered: hoverArea.containsMouse || actionRowHover.containsMouse

    // A wide sidebar shouldn't stretch prose to the full window; long lines are
    // hard to track. Code and tables are exempt — they own their own width.
    readonly property real textColumnWidth: Math.min(width, 780)

    property list<var> messageBlocks: StringUtils.splitMessageBlocks(root.messageData?.content ?? "")

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: columnLayout.implicitHeight

    function saveMessage() {
        if (!root.editing) return;
        let newContent = "";
        const children = messageContentColumnLayout.children;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (child["segmentContent"] === undefined) continue;
            const content = child["segmentContent"] ?? "";
            const lang = child["segmentLang"];
            if (child["isQuoteBlock"] === true) {
                // The markers were stripped for rendering; put them back.
                newContent += content.split("\n").map(line => "> " + line).join("\n");
            } else if (lang !== undefined) {
                const cleanCode = content.replace(/\n+$/, "");
                // Keep a labelled file name on the fence; dropping it would lose
                // which file the snippet belongs to on the next render.
                const filename = child["segmentFilename"] ?? "";
                const info = (lang ?? "") + (filename.length > 0 ? `:${filename}` : "");
                newContent += "```" + info + "\n" + cleanCode + "\n```";
            } else {
                newContent += content;
            }
        }
        root.editing = false;
        root.messageData.content = newContent;
        root.messageData.rawContent = newContent;
    }

    Keys.onPressed: (event) => {
        if ( // Prevent de-select
            event.key === Qt.Key_Control ||
            event.key == Qt.Key_Shift ||
            event.key == Qt.Key_Alt ||
            event.key == Qt.Key_Meta
        ) {
            event.accepted = true
        }
        // Ctrl + S to save
        if ((event.key === Qt.Key_S) && event.modifiers == Qt.ControlModifier) {
            root.saveMessage();
            event.accepted = true;
        }
    }

    ListView.onReused: {
        root.editing = false;
        root.renderMarkdown = true;
        root.enableMouseSelection = false;
    }

    visible: messageData?.visibleToUser ?? true
    height: visible ? implicitHeight : 0
    opacity: visible ? 1 : 0

    Behavior on height {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.InOutQuad
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: columnLayout
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
    }

    ColumnLayout {
        id: columnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: root.isContinuation ? 2 : 10
        spacing: root.contentSpacing

        RowLayout { // Authorship
            id: headerRow
            visible: !root.isContinuation
            Layout.fillWidth: true
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            spacing: 6

            // Explicit spacers rather than layoutDirection: the timestamp is hidden
            // until hover, and a RowLayout with no visible filler packs left either
            // way, which put the user's own name on the wrong side.
            Item { Layout.fillWidth: true; visible: root.isUser }

            Item {
                implicitWidth: 16
                implicitHeight: 16

                CustomIcon {
                    id: modelIcon
                    anchors.centerIn: parent
                    visible: root.isAssistant && (Ai.models[root.messageData?.model]?.icon ?? "").length > 0
                    width: 15
                    height: 15
                    source: Ai.models[root.messageData?.model]?.icon ?? ""
                    colorize: true
                    color: Appearance.colors.colPrimary
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !modelIcon.visible
                    iconSize: 16
                    color: root.isUser ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                    text: root.isUser ? "person" : root.isInterface ? "settings" : "neurology"
                }
            }

            StyledText {
                // Named on every answer: with model switching mid-chat, "which one
                // said this" is a question you ask constantly otherwise.
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.isUser ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                text: root.isAssistant ? (Ai.models[root.messageData?.model]?.name ?? root.messageData?.model ?? Translation.tr("Assistant"))
                    : root.isUser ? (SystemInfo.username || Translation.tr("You"))
                    : Translation.tr("Interface")
            }

            Item { // Not sent to the model
                visible: root.isInterface
                implicitWidth: 14
                implicitHeight: 14
                // StyledToolTip shows unconditionally when its parent has no `hovered`
                // property, so anything carrying one has to provide it.
                property bool hovered: interfaceIconArea.containsMouse

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: "visibility_off"
                }
                MouseArea {
                    id: interfaceIconArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
                StyledToolTip { text: Translation.tr("Not visible to model") }
            }

            StyledText { // Timestamp, on hover only
                visible: opacity > 0 && text.length > 0
                opacity: root.hovered ? 1 : 0
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: root.messageData?.timestamp > 0
                    ? new Date(root.messageData.timestamp).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                    : ""
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Item { Layout.fillWidth: true; visible: !root.isUser }
        }

        Loader { // Attached file
            Layout.fillWidth: true
            Layout.maximumWidth: root.textColumnWidth
            Layout.alignment: root.isUser ? Qt.AlignRight : Qt.AlignLeft
            active: (root.messageData?.localFilePath ?? "").length > 0
            sourceComponent: AttachedFileIndicator {
                filePath: root.messageData?.localFilePath
                canRemove: false
            }
        }

        Loader { // Reasoning / thinking
            Layout.fillWidth: true
            Layout.maximumWidth: root.textColumnWidth
            active: root.messageData?.hasReasoning ?? false
            visible: active
            sourceComponent: ReasoningBlock {
                messageData: root.messageData
                enableMouseSelection: root.enableMouseSelection
            }
        }

        Item { // Content, bubbled for the user and bare for everyone else
            id: contentWrapper
            Layout.fillWidth: true
            implicitHeight: bubble.implicitHeight

            // The bubble can't be sized from the content column: that column is
            // anchored to the bubble, so its implicitWidth would depend on the very
            // width we're trying to derive and the layout collapses to nothing.
            // Measuring the unwrapped text separately breaks the cycle — contentWidth
            // of a NoWrap Text is the widest line.
            StyledText {
                id: userWidthProbe
                visible: false
                wrapMode: Text.NoWrap
                font.family: Appearance.font.family.reading
                font.pixelSize: Appearance.font.pixelSize.small
                text: root.isUser ? (root.messageData?.content ?? "") : ""
            }

            Rectangle {
                id: bubble
                anchors.right: root.isUser ? parent.right : undefined
                anchors.left: root.isUser ? undefined : parent.left
                width: root.isUser
                    ? Math.max(48, Math.min(userWidthProbe.contentWidth + root.messagePadding * 2 + 2, parent.width * 0.85))
                    : Math.min(parent.width, root.textColumnWidth)
                implicitHeight: messageContentColumnLayout.implicitHeight + (root.isUser ? root.messagePadding * 2 : 0)

                // The answer needs no container; the question is an aside and reads
                // better as a compact neutral bubble.
                color: root.isUser ? Appearance.colors.colLayer2 : "transparent"
                radius: Appearance.rounding.normal

                ColumnLayout {
                    id: messageContentColumnLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.isUser ? root.messagePadding : 0
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                        implicitWidth: loadingIndicatorLoader.implicitWidth
                        visible: implicitHeight > 0

                        Behavior on implicitHeight {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        FadeLoader {
                            id: loadingIndicatorLoader
                            anchors.centerIn: parent
                            shown: (root.messageBlocks.length < 1) && (!root.messageData?.done ?? false)
                            sourceComponent: MaterialLoadingIndicator {
                                loading: true
                            }
                        }
                    }
                    Repeater {
                        model: ScriptModel {
                            values: root.messageBlocks
                        }
                        delegate: DelegateChooser {
                            id: messageDelegate
                            role: "type"

                            DelegateChoice { roleValue: "code"; MessageCodeBlock {
                                editing: root.editing
                                renderMarkdown: root.renderMarkdown
                                enableMouseSelection: root.enableMouseSelection
                                segmentContent: modelData.content
                                segmentLang: modelData.lang
                                segmentFilename: modelData.filename ?? ""
                                messageData: root.messageData
                            } }
                            DelegateChoice { roleValue: "table"; MessageTableBlock {
                                editing: root.editing
                                renderMarkdown: root.renderMarkdown
                                enableMouseSelection: root.enableMouseSelection
                                segmentContent: modelData.content
                                header: modelData.header
                                aligns: modelData.aligns
                                rows: modelData.rows
                                messageData: root.messageData
                            } }
                            DelegateChoice { roleValue: "quote"; MessageQuoteBlock {
                                editing: root.editing
                                renderMarkdown: root.renderMarkdown
                                enableMouseSelection: root.enableMouseSelection
                                segmentContent: modelData.content
                                messageData: root.messageData
                            } }
                            DelegateChoice { roleValue: "text"; MessageTextBlock {
                                editing: root.editing
                                renderMarkdown: root.renderMarkdown
                                enableMouseSelection: root.enableMouseSelection
                                segmentContent: modelData.content
                                messageData: root.messageData
                                done: root.messageData?.done ?? false
                                forceDisableChunkSplitting: /```\w*\n/.test(root.messageData?.content ?? "")
                            } }
                        }
                    }
                }
            }
        }

        Loader { // Shell command the model asked to run
            Layout.fillWidth: true
            Layout.maximumWidth: root.textColumnWidth
            Layout.topMargin: 4
            active: (root.messageData?.commandState ?? "").length > 0
            visible: active
            sourceComponent: MessageCommandBlock {
                messageData: root.messageData
            }
        }

        Flow { // Annotations
            visible: root.messageData?.annotationSources?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.maximumWidth: root.textColumnWidth
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.annotationSources || []
                }
                delegate: AnnotationSourceButton {
                    required property var modelData
                    displayText: modelData.text
                    url: modelData.url
                }
            }
        }

        Flow { // Search queries
            visible: root.messageData?.searchQueries?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.maximumWidth: root.textColumnWidth
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.searchQueries || []
                }
                delegate: SearchQueryButton {
                    required property var modelData
                    query: modelData
                }
            }
        }

        Item { // Actions, revealed on hover
            Layout.fillWidth: true
            implicitHeight: root.hovered || root.editing ? actionRow.implicitHeight : 0
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            MouseArea {
                id: actionRowHover
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
            }

            RowLayout {
                id: actionRow
                anchors.right: root.isUser ? parent.right : undefined
                anchors.left: root.isUser ? undefined : parent.left
                opacity: root.hovered || root.editing ? 1 : 0
                spacing: 2

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                AiMessageControlButton {
                    id: copyButton
                    buttonIcon: activated ? "inventory" : "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = root.messageData?.content
                        copyButton.activated = true
                        copyIconTimer.restart()
                    }
                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        onTriggered: copyButton.activated = false
                    }
                    StyledToolTip { text: Translation.tr("Copy") }
                }

                AiMessageControlButton {
                    id: regenButton
                    buttonIcon: "refresh"
                    visible: root.isAssistant
                    onClicked: Ai.regenerateById(root.modelData)
                    StyledToolTip { text: Translation.tr("Regenerate") }
                }

                AiMessageControlButton {
                    id: editButton
                    activated: root.editing
                    enabled: root.messageData?.done ?? false
                    buttonIcon: "edit"
                    onClicked: {
                        root.editing = !root.editing
                        if (!root.editing) root.saveMessage()
                    }
                    StyledToolTip { text: root.editing ? Translation.tr("Save") : Translation.tr("Edit") }
                }

                AiMessageControlButton {
                    id: toggleMarkdownButton
                    activated: !root.renderMarkdown
                    buttonIcon: "code"
                    onClicked: root.renderMarkdown = !root.renderMarkdown
                    StyledToolTip { text: Translation.tr("View Markdown source") }
                }

                AiMessageControlButton {
                    id: selectButton
                    activated: root.enableMouseSelection
                    buttonIcon: "text_select_start"
                    onClicked: root.enableMouseSelection = !root.enableMouseSelection
                    StyledToolTip { text: Translation.tr("Select text with the mouse") }
                }

                AiMessageControlButton {
                    id: deleteButton
                    buttonIcon: activated ? "delete_forever" : "delete"
                    onClicked: {
                        if (activated) {
                            Ai.removeMessageById(root.modelData);
                        } else {
                            activated = true;
                            deleteConfirmTimer.restart();
                        }
                    }
                    Timer {
                        id: deleteConfirmTimer
                        interval: 2000
                        onTriggered: deleteButton.activated = false
                    }
                    StyledToolTip {
                        text: deleteButton.activated ? Translation.tr("Click again to confirm delete") : Translation.tr("Delete message")
                    }
                }
            }
        }
    }
}
