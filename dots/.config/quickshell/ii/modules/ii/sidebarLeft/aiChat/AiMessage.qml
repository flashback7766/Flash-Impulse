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

    // Density is spacing only — type size stays put, since fitting more on
    // screen shouldn't cost legibility.
    readonly property bool compact: Ai.compactMessages
    property real messagePadding: root.compact ? 6 : 8
    // Author line to body, and the gap the action row sits behind.
    property real contentSpacing: root.compact ? 2 : 4
    // Between the pieces of one answer — a paragraph, a table, a snippet. Owned
    // here rather than by each block: quote, table and code each carried their
    // own margin, 3, 4 and 7 respectively, so the rhythm of an answer depended
    // on which kinds of block it happened to contain.
    readonly property real blockSpacing: root.compact ? 5 : 8
    // Between one exchange and the next. A question and its answer belong
    // together more than two answers do, so a new speaker gets more room than a
    // continuation, and pure machinery gets least.
    readonly property real turnSpacing: root.compact ? 8 : 14

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false
    property bool isContinuation: false
    // Whether this answer states which model produced it. Set by the list, which
    // is the only thing that can see what came before.
    property bool namesModel: true

    readonly property bool isUser: messageData?.role === "user"
    readonly property bool isAssistant: messageData?.role === "assistant"
    readonly property bool isInterface: messageData?.role === "interface"
    // An event marker rather than something someone said: no author, no body,
    // no controls — just the hairline saying what changed and where.
    readonly property bool isDivider: (messageData?.dividerText ?? "").length > 0
    // A HoverHandler rather than a MouseArea underneath: the controls are Qt
    // Quick Controls, they accept hover themselves, and a MouseArea stacked below
    // them stops seeing the pointer the moment it reaches a button. Which meant
    // the row vanished exactly as you went to click something in it.
    readonly property bool hovered: !root.isDivider && hoverHandler.hovered

    // A wide sidebar shouldn't stretch prose to the full window; long lines are
    // hard to track. Code and tables are exempt — they own their own width.
    readonly property real textColumnWidth: Math.min(width, 780)

    // A turn that only ran tools is machinery, not conversation. Given the same
    // breathing room as a paragraph, four commands in a row took half a screen
    // to say four things went fine.
    readonly property bool isMechanical: (root.messageData?.content ?? "").length === 0
        && (((root.messageData?.commandState ?? "").length > 0)
            || ((root.messageData?.toolCalls?.length ?? 0) > 0))

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

    // `messageData != null` first, and it is not redundant. The list pools and
    // reuses delegates, so one can briefly hold no message at all — and
    // `undefined ?? true` is true, which made a delegate with nothing in it
    // count as visible. With no role it falls through every branch to
    // "Interface", and with no `done` flag the typing indicator runs forever, so
    // an empty delegate drew an author line and three pulsing dots on top of
    // whatever was really there. That's the ghosting.
    //
    // Empty tool-call turns are dropped by Ai.hideIfEmpty when they finish, so
    // there is nothing else to filter here — a delegate that hides itself is
    // still an item in the list, and a zero-height item still moves the scroll.
    visible: messageData != null && (messageData.visibleToUser ?? true)
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

    HoverHandler {
        id: hoverHandler
        // Covers the whole message including the revealed row, and keeps
        // reporting while the pointer is over a control inside it.
    }

    ColumnLayout {
        id: columnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: root.isMechanical ? 2
            : root.isContinuation ? (root.compact ? 2 : 4)
            : root.turnSpacing
        spacing: root.contentSpacing

        ChatDivider { // Something about the conversation changed here
            Layout.fillWidth: true
            visible: root.isDivider
            text: root.messageData?.dividerText ?? ""
            icon: root.messageData?.dividerIcon ?? ""
        }

        RowLayout { // Authorship
            id: headerRow
            visible: !root.isContinuation && !root.isDivider
            // Height is reserved whether or not anything in it is showing: the
            // author line fades in on hover, and letting the row collapse made
            // every message jump down as the pointer crossed it.
            Layout.preferredHeight: 16
            Layout.fillWidth: true
            // Flush with the body beneath it: inset by two, the name sat a
            // couple of pixels right of the text it belongs to.
            spacing: 6

            // Explicit spacers rather than layoutDirection: the timestamp is hidden
            // until hover, and a RowLayout with no visible filler packs left either
            // way, which put the user's own name on the wrong side.
            Item { Layout.fillWidth: true; visible: root.isUser }

            Item {
                implicitWidth: 16
                implicitHeight: 16
                // The person icon goes with the name; an answer keeps its provider
                // mark always, because that one identifies something that varies.
                opacity: (!root.isUser || root.hovered) ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

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
                // A label earns its place by telling you something that varies.
                // Your own name above your own question never does — the bubble is
                // already on your side — so it waits for hover. Which model
                // answered does vary, but only when it changes, so it shows on the
                // first answer, on a switch, and on hover. The provider icon stays
                // either way and is what marks where an answer begins.
                //
                // This had drifted back to always-on while fixing something else;
                // namesModel was still being set by the list and read by nobody.
                opacity: root.isUser ? (root.hovered ? 1 : 0)
                    : (root.isInterface || root.namesModel || root.hovered) ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
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
                opacity: (root.hovered && text.length > 0) ? 1 : 0
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
            visible: !root.isDivider
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
                    // Ceil plus a few px of slack: contentWidth is fractional and
                    // the rendered block adds a little of its own, and being one
                    // pixel short wraps the last character onto its own line.
                    ? Math.max(48, Math.min(Math.ceil(userWidthProbe.contentWidth) + root.messagePadding * 2 + 6,
                        parent.width * 0.85))
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
                    spacing: root.blockSpacing

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
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            // Nothing to show yet and still streaming: the answer is
                            // being composed. Reasoning has its own header, so this is
                            // only ever the silence before the first token.
                            // Defaults to "done" when there's no message at all: a
                            // pooled delegate holding nothing is not a turn that's
                            // still being written, and treating it as one left three
                            // pulsing dots running over the conversation.
                            shown: (root.messageData != null)
                                && (root.messageBlocks.length < 1)
                                && !(root.messageData.done ?? true)
                                && !(root.messageData.reasoningActive ?? false)
                            sourceComponent: TypingDots {
                                color: Appearance.colors.colPrimary
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
            Layout.topMargin: root.isMechanical ? 0 : 4
            active: (root.messageData?.commandState ?? "").length > 0
            visible: active
            sourceComponent: MessageCommandBlock {
                messageData: root.messageData
            }
        }

        // Claude Code's tools, drawn as the same block. It runs several in one
        // turn under its own permission system, so these report rather than ask.
        Repeater {
            model: ScriptModel {
                values: root.messageData?.toolCalls ?? []
            }

            delegate: MessageCommandBlock {
                required property var modelData
                Layout.fillWidth: true
                Layout.maximumWidth: root.textColumnWidth
                Layout.topMargin: root.isMechanical ? 2 : 4
                messageData: root.messageData
                approvable: false
                title: modelData.tool
                showPrompt: modelData.tool === "Bash" 
                commandState: modelData.state
                commandText: modelData.text
                output: modelData.output
                // Its permission prompt lives in the CLI and can't be answered
                // from here, so the only useful thing to say is how to get past it.
                verdict: modelData.state === "denied"
                    ? Translation.tr("Claude Code asked for permission, and its prompt can't be answered from the sidebar. Shift+Tab to Yolo lets it run without asking.")
                    : ""
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
            // Not on a turn that only ran a command: there's no text to copy, no
            // answer to regenerate and nothing to edit, so the reserved strip was
            // 36 pixels of nothing under every command — the gap that made four
            // commands in a row take half a screen.
            visible: !root.isMechanical
            // The strip is always there, only its contents fade. Collapsing it
            // meant there was nothing to aim at: the buttons appeared under the
            // pointer only while the pointer was on the message above them, so
            // moving down to click one was a race against the row disappearing.
            // Reserving it also stops the list shifting as the pointer crosses it.
            implicitHeight: actionRow.implicitHeight
            clip: true

            RowLayout {
                id: actionRow
                anchors.right: root.isUser ? parent.right : undefined
                anchors.left: root.isUser ? undefined : parent.left
                opacity: root.hovered || root.editing ? 1 : 0
                // A transparent button is still a button as far as the mouse is
                // concerned; without this you could click one you couldn't see.
                enabled: root.hovered || root.editing
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

                // Which attempt you're looking at. Only there once there's more
                // than one, so a single answer carries no chrome for a choice
                // that doesn't exist.
                RowLayout {
                    visible: root.messageData?.hasVariants ?? false
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    spacing: 0

                    AiMessageControlButton {
                        implicitWidth: 24
                        buttonIcon: "chevron_left"
                        enabled: (root.messageData?.variantIndex ?? 0) > 0
                        onClicked: Ai.selectVariant(root.modelData, root.messageData.variantIndex - 1)
                        StyledToolTip { text: Translation.tr("Previous answer") }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                        text: `${(root.messageData?.variantIndex ?? 0) + 1}/${root.messageData?.variantCount ?? 1}`
                    }

                    AiMessageControlButton {
                        implicitWidth: 24
                        buttonIcon: "chevron_right"
                        enabled: (root.messageData?.variantIndex ?? 0) < (root.messageData?.variantCount ?? 1) - 1
                        onClicked: Ai.selectVariant(root.modelData, root.messageData.variantIndex + 1)
                        StyledToolTip { text: Translation.tr("Next answer") }
                    }
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
