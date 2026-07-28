pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Collapsible "thinking" section shown above an assistant message.
 *
 * Reasoning is deliberately not part of the answer text: it lives in
 * AiMessageData.reasoning, filled either by the provider's own stream field or,
 * for models that inline <think> tags, by StringUtils.extractThinkTags. This
 * block is the only place it is rendered.
 *
 * While thoughts are still arriving the section stays collapsed and the header
 * tickers the latest line, so a long chain doesn't push the answer off-screen;
 * once the model starts answering it settles into "Thought for Ns".
 */
Rectangle {
    id: root

    property var messageData
    property bool expanded: false
    property bool enableMouseSelection: false

    readonly property string reasoning: messageData?.reasoning ?? ""
    readonly property bool active: messageData?.reasoningActive ?? false
    readonly property list<string> steps: StringUtils.splitReasoningSteps(root.reasoning)

    // Latest line of the newest step — the ticker text while thinking.
    readonly property string tickerText: {
        if (root.steps.length === 0) return "";
        const lines = root.steps[root.steps.length - 1].split("\n").filter(l => l.trim().length > 0);
        return lines.length > 0 ? lines[lines.length - 1].trim() : "";
    }

    readonly property string summary: {
        // Fenced code first: a peek at the thinking that opens with "py" or a
        // half-line of a snippet says nothing about what the model was working
        // out. Prose is what makes the collapsed header worth reading.
        const prose = root.reasoning
            .replace(/```[\s\S]*?(?:```|$)/g, " ")
            .replace(/[#*`>_\[\]]/g, "");
        const words = prose.split(/\s+/).filter(w => w.length > 0);
        if (words.length === 0) return "";
        return words.slice(0, 6).join(" ") + (words.length > 6 ? "…" : "");
    }

    readonly property string durationText: {
        const s = messageData?.reasoningSeconds ?? 0;
        if (s <= 0) return Translation.tr("Thought");
        if (s < 60) return Translation.tr("Thought for %1s").arg(s < 10 ? s.toFixed(1) : Math.round(s));
        return Translation.tr("Thought for %1m %2s").arg(Math.floor(s / 60)).arg(Math.round(s % 60));
    }

    readonly property string tokenText: {
        const t = messageData?.reasoningTokens ?? 0;
        if (t <= 0) return "";
        return t >= 1000 ? (t / 1000).toFixed(1) + "k " + Translation.tr("tokens") : t + " " + Translation.tr("tokens");
    }

    // Thoughts land while the user is reading the previous answer; auto-collapsing
    // the moment the model starts talking is what every chat client does and it
    // keeps the transcript from jumping. Manual expansion is never overridden.
    property bool userToggled: false
    onActiveChanged: if (!active && !userToggled) expanded = false

    Layout.fillWidth: true
    implicitHeight: contentColumn.implicitHeight
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.small

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        Item { // Header
            Layout.fillWidth: true
            implicitHeight: Math.max(headerRow.implicitHeight + 10, 32)

            Rectangle { // Hover state layer
                anchors.fill: parent
                radius: root.radius
                color: Appearance.colors.colOnLayer1
                opacity: headerMouseArea.containsMouse ? 0.08 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            MouseArea {
                id: headerMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.userToggled = true;
                    root.expanded = !root.expanded;
                }
            }

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 6
                spacing: 8

                MaterialSymbol {
                    id: brainIcon
                    text: "neurology"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colSubtext

                    // Slow breathing pulse marks "still thinking" without a spinner
                    // competing with the message's own loading indicator.
                    SequentialAnimation on opacity {
                        running: root.active
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: root.active ? Translation.tr("Thinking…")
                            : [root.durationText, root.tokenText, root.expanded ? "" : root.summary]
                                .filter(s => s.length > 0).join(" · ")
                    }

                    StyledText { // Ticker
                        Layout.fillWidth: true
                        visible: root.active && !root.expanded && text.length > 0
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: root.tickerText
                    }
                }

                StyledText {
                    visible: root.steps.length > 1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: root.steps.length
                }

                MaterialSymbol {
                    text: "expand_more"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colSubtext
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }

        Revealer {
            Layout.fillWidth: true
            vertical: true
            reveal: root.expanded

            ColumnLayout {
                width: contentColumn.width
                spacing: 6

                Repeater {
                    model: ScriptModel {
                        values: root.steps
                    }

                    delegate: RowLayout {
                        id: stepRow
                        required property int index
                        required property string modelData

                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.bottomMargin: stepRow.index === root.steps.length - 1 ? 8 : 0
                        spacing: 8

                        StyledText { // Step number
                            Layout.alignment: Qt.AlignTop
                            visible: root.steps.length > 1
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                            text: String(stepRow.index + 1).padStart(2, "0")
                        }

                        TextArea {
                            Layout.fillWidth: true
                            padding: 0
                            readOnly: true
                            selectByMouse: root.enableMouseSelection
                            renderType: Text.NativeRendering
                            font.family: Appearance.font.family.reading
                            font.hintingPreference: Font.PreferNoHinting
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                            selectionColor: Appearance.colors.colSecondaryContainer
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.MarkdownText
                            text: stepRow.modelData
                            background: null

                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }
                }
            }
        }
    }
}
