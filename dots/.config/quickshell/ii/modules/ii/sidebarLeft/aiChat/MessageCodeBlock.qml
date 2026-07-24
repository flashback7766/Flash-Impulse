pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import org.kde.syntaxhighlighting

ColumnLayout {
    id: root
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var segmentLang: "txt"
    property var messageData: {}
    property bool isCommandRequest: segmentLang === "command"
    property var displayLang: (isCommandRequest ? "bash" : segmentLang)
    property bool commandExpanded: true // Keep expanded to ensure visibility while running or when opened
    onCommandDoneChanged: {
        if (commandDone) commandExpanded = false;
    }

    // Detect command completion status from content
    readonly property bool commandDone: root.messageData?.done ?? false
    readonly property bool commandSucceeded: isCommandRequest && segmentContent.includes("✓")
    readonly property bool commandFailed: isCommandRequest && segmentContent.includes("✗")

    property real codeBlockBackgroundRounding: Appearance.rounding.small
    property real codeBlockHeaderPadding: 3
    property real codeBlockComponentSpacing: 2

    spacing: codeBlockComponentSpacing

    Rectangle { // Header bar
        id: codeBlockHeader
        Layout.fillWidth: true
        topLeftRadius: codeBlockBackgroundRounding
        topRightRadius: codeBlockBackgroundRounding
        bottomLeftRadius: root.isCommandRequest && !root.commandExpanded ? codeBlockBackgroundRounding : Appearance.rounding.unsharpen
        bottomRightRadius: root.isCommandRequest && !root.commandExpanded ? codeBlockBackgroundRounding : Appearance.rounding.unsharpen
        color: root.isCommandRequest && headerMouseArea.containsMouse
            ? Appearance.colors.colLayer2Hover
            : Appearance.colors.colSurfaceContainerHighest
        implicitHeight: codeBlockTitleBarRowLayout.implicitHeight + codeBlockHeaderPadding * 2

        Behavior on color { ColorAnimation { duration: 120 } }

        // Clickable area for command blocks
        MouseArea {
            id: headerMouseArea
            anchors.fill: parent
            enabled: root.isCommandRequest
            hoverEnabled: root.isCommandRequest
            cursorShape: root.isCommandRequest ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.commandExpanded = !root.commandExpanded
        }

        RowLayout {
            id: codeBlockTitleBarRowLayout
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: codeBlockHeaderPadding
            anchors.rightMargin: codeBlockHeaderPadding
            spacing: 5

            // Status text for command requests
            StyledText {
                visible: root.isCommandRequest
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                Layout.leftMargin: 10
                font.pixelSize: Appearance.font.pixelSize.small + 2
                font.weight: Font.DemiBold

                text: root.commandSucceeded ? "✅ " + Translation.tr("Command completed")
                    : root.commandFailed ? "❌ " + Translation.tr("Command failed")
                    : "⚡ " + Translation.tr("Running command") + "..."

                color: root.commandFailed ? Appearance.m3colors.m3error
                    : root.commandSucceeded ? "#4caf50"
                    : Appearance.colors.colSubtext

                SequentialAnimation on color {
                    running: root.isCommandRequest && !root.commandSucceeded && !root.commandFailed
                    loops: Animation.Infinite
                    ColorAnimation { from: Appearance.colors.colSubtext; to: Appearance.colors.colOnLayer2; duration: 900; easing.type: Easing.InOutSine }
                    ColorAnimation { from: Appearance.colors.colOnLayer2; to: Appearance.colors.colSubtext; duration: 900; easing.type: Easing.InOutSine }
                }
            }

            StyledText {
                id: codeBlockLanguage
                visible: !root.isCommandRequest
                Layout.alignment: Qt.AlignLeft
                Layout.fillWidth: false
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                Layout.leftMargin: 10
                font.pixelSize: Appearance.font.pixelSize.small + 2
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                text: root.displayLang ? Repository.definitionForName(root.displayLang).name : "plain"
            }

            Item { Layout.fillWidth: true }

            // Expand/collapse chevron for command blocks — animated rotation like ThinkBlock
            MaterialSymbol {
                visible: root.isCommandRequest
                Layout.rightMargin: 8
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.normal + 2
                color: Appearance.colors.colSubtext
                rotation: root.commandExpanded ? 180 : 0
                Behavior on rotation {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            ButtonGroup {
                visible: !root.isCommandRequest
                AiMessageControlButton {
                    id: copyCodeButton
                    buttonIcon: activated ? "inventory" : "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = segmentContent
                        copyCodeButton.activated = true
                        copyIconTimer.restart()
                    }
                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: copyCodeButton.activated = false
                    }
                    StyledToolTip { text: Translation.tr("Copy code") }
                }
                AiMessageControlButton {
                    id: saveCodeButton
                    buttonIcon: activated ? "check" : "save"
                    onClicked: {
                        const downloadPath = FileUtils.trimFileProtocol(Directories.downloads)
                        Quickshell.execDetached(["bash", "-c",
                            `echo '${StringUtils.shellSingleQuoteEscape(segmentContent)}' > '${downloadPath}/code.${segmentLang || "txt"}'`
                        ])
                        Quickshell.execDetached(["notify-send",
                            Translation.tr("Code saved to file"),
                            Translation.tr("Saved to %1").arg(`${downloadPath}/code.${segmentLang || "txt"}`),
                            "-a", "Shell"
                        ])
                        saveCodeButton.activated = true
                        saveIconTimer.restart()
                    }
                    Timer {
                        id: saveIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: saveCodeButton.activated = false
                    }
                    StyledToolTip { text: Translation.tr("Save to Downloads") }
                }
            }
        }
    }

    // Code body — hidden by default for command blocks
    // Use a Loader to ensure proper layout when the block is expanded (fixes 'invisible code' bug)
    Loader {
        id: codeBodyLoader
        Layout.fillWidth: true
        active: !root.isCommandRequest || root.commandExpanded
        visible: active

        sourceComponent: RowLayout {
            spacing: codeBlockComponentSpacing

            Rectangle { // Line numbers
                implicitWidth: 40
                implicitHeight: lineNumberColumnLayout.implicitHeight
                Layout.fillHeight: true
                Layout.fillWidth: false
                topLeftRadius: Appearance.rounding.unsharpen
                bottomLeftRadius: codeBlockBackgroundRounding
                topRightRadius: Appearance.rounding.unsharpen
                bottomRightRadius: Appearance.rounding.unsharpen
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: lineNumberColumnLayout
                    anchors {
                        left: parent.left
                        right: parent.right
                        rightMargin: 5
                        top: parent.top
                        topMargin: 6
                    }
                    spacing: 0
                    Repeater {
                        model: codeTextArea.text.split("\n").length
                        Text {
                            required property int index
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small + 2
                            color: Appearance.colors.colSubtext
                            horizontalAlignment: Text.AlignRight
                            text: index + 1
                        }
                    }
                }
            }

            Rectangle { // Code background
                Layout.fillWidth: true
                topLeftRadius: Appearance.rounding.unsharpen
                bottomLeftRadius: Appearance.rounding.unsharpen
                topRightRadius: Appearance.rounding.unsharpen
                bottomRightRadius: codeBlockBackgroundRounding
                color: Appearance.colors.colLayer2
                implicitHeight: codeColumnLayout.implicitHeight

                ColumnLayout {
                    id: codeColumnLayout
                    anchors.fill: parent
                    spacing: 0
                    ScrollView {
                        id: codeScrollView
                        Layout.fillWidth: true
                        implicitWidth: parent.width
                        implicitHeight: codeTextArea.implicitHeight + 1
                        contentWidth: codeTextArea.width - 1
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: (event) => {
                                if (event.angleDelta.y !== 0) {
                                    event.accepted = false;
                                }
                            }
                        }

                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                        ScrollBar.horizontal: ScrollBar {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            padding: 5
                            policy: ScrollBar.AsNeeded
                            opacity: visualSize == 1 ? 0 : 1
                            visible: opacity > 0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                            contentItem: Rectangle {
                                implicitHeight: 6
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2Active
                            }
                        }

                        TextArea {
                            id: codeTextArea
                            Layout.fillWidth: true
                            readOnly: !editing
                            selectByMouse: enableMouseSelection || editing
                            renderType: Text.NativeRendering
                            font.family: Appearance.font.family.monospace
                            font.hintingPreference: Font.PreferNoHinting
                            font.pixelSize: Appearance.font.pixelSize.small + 2
                            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                            selectionColor: Appearance.colors.colSecondaryContainer
                            color: messageData.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                            text: segmentContent
                            onTextChanged: { segmentContent = text }

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Tab) {
                                    const cursor = codeTextArea.cursorPosition;
                                    codeTextArea.insert(cursor, "    ");
                                    codeTextArea.cursorPosition = cursor + 4;
                                    event.accepted = true;
                                } else if ((event.key === Qt.Key_C) && event.modifiers == Qt.ControlModifier) {
                                    codeTextArea.copy();
                                    event.accepted = true;
                                }
                            }

                            SyntaxHighlighter {
                                id: highlighter
                                textEdit: codeTextArea
                                repository: Repository
                                definition: Repository.definitionForName(root.displayLang || "plaintext")
                                theme: Appearance.syntaxHighlightingTheme
                            }
                        }
                    }
                    Loader {
                        active: root.isCommandRequest && root.messageData.functionPending
                        visible: active
                        Layout.fillWidth: true
                        Layout.margins: 6
                        Layout.topMargin: 0
                        sourceComponent: RowLayout {
                            Item { Layout.fillWidth: true }
                            ButtonGroup {
                                GroupButton {
                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol { text: "close"; iconSize: 14; color: Appearance.colors.colOnLayer2 }
                                        StyledText {
                                            text: Translation.tr("Reject")
                                            font.pixelSize: Appearance.font.pixelSize.small + 2
                                            color: Appearance.colors.colOnLayer2
                                        }
                                    }
                                    onClicked: Ai.rejectCommand(root.messageData)
                                }
                                GroupButton {
                                    toggled: true
                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol { text: "check"; iconSize: 14; color: Appearance.colors.colOnPrimary }
                                        StyledText {
                                            text: Translation.tr("Approve")
                                            font.pixelSize: Appearance.font.pixelSize.small + 2
                                            color: Appearance.colors.colOnPrimary
                                        }
                                    }
                                    onClicked: Ai.approveCommand(root.messageData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
