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
    property string segmentFilename: ""
    property var messageData: {}
    property var displayLang: segmentLang

    readonly property int lineCount: String(root.segmentContent ?? "").split("\n").length
    property int collapseThreshold: 22
    readonly property bool collapsible: root.lineCount > root.collapseThreshold
    // Folded only once the answer is finished — collapsing a snippet mid-stream
    // hides the very thing you're watching arrive. Toggling replaces this
    // binding, so a block you opened by hand stays open.
    property bool collapsed: root.collapsible && (root.messageData?.done ?? false)
    // Off by default: code reads better with its original line breaks, and the
    // horizontal scrollbar is there for the occasional long line.
    property bool wrapCode: false

    readonly property real lineHeight: Math.round((Appearance.font.pixelSize.small + 2) * 1.35)
    readonly property real collapsedHeight: root.lineHeight * root.collapseThreshold

    readonly property string languageLabel: {
        if (!root.displayLang) return "plain";
        // KSyntaxHighlighting answers "None" for anything it doesn't know
        // (ini, toml, conf, ...) — showing the fence's own language beats
        // labelling a perfectly good snippet "None".
        const known = Repository.definitionForName(root.displayLang).name;
        return (known && known !== "None") ? known : root.displayLang;
    }

    property real codeBlockBackgroundRounding: Appearance.rounding.small
    property real codeBlockHeaderPadding: 3
    property real codeBlockComponentSpacing: 2

    spacing: codeBlockComponentSpacing

    Rectangle { // Header bar
        id: codeBlockHeader
        Layout.fillWidth: true
        topLeftRadius: codeBlockBackgroundRounding
        topRightRadius: codeBlockBackgroundRounding
        bottomLeftRadius: Appearance.rounding.unsharpen
        bottomRightRadius: Appearance.rounding.unsharpen
        color: Appearance.colors.colSurfaceContainerHighest
        implicitHeight: codeBlockTitleBarRowLayout.implicitHeight + codeBlockHeaderPadding * 2

        RowLayout {
            id: codeBlockTitleBarRowLayout
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: codeBlockHeaderPadding
            anchors.rightMargin: codeBlockHeaderPadding
            spacing: 5

            MaterialSymbol {
                Layout.leftMargin: 10
                visible: root.segmentFilename.length > 0
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
                text: "description"
            }

            StyledText {
                id: codeBlockTitle
                Layout.alignment: Qt.AlignLeft
                Layout.fillWidth: false
                Layout.maximumWidth: codeBlockTitleBarRowLayout.width * 0.55
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                Layout.leftMargin: root.segmentFilename.length > 0 ? 0 : 10
                font.pixelSize: Appearance.font.pixelSize.small + 2
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideLeft // A path's tail is the part that identifies it
                text: root.segmentFilename.length > 0 ? root.segmentFilename : root.languageLabel
            }

            StyledText { // Language, once the title is taken by a file name
                visible: root.segmentFilename.length > 0
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.languageLabel
            }

            StyledText {
                visible: root.collapsed
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("%1 lines").arg(root.lineCount)
            }

            Item { Layout.fillWidth: true }

            ButtonGroup {
                AiMessageControlButton {
                    id: wrapButton
                    activated: root.wrapCode
                    buttonIcon: "wrap_text"
                    onClicked: root.wrapCode = !root.wrapCode
                    StyledToolTip {
                        text: root.wrapCode ? Translation.tr("Don't wrap long lines") : Translation.tr("Wrap long lines")
                    }
                }
                AiMessageControlButton {
                    id: collapseButton
                    visible: root.collapsible
                    buttonIcon: root.collapsed ? "unfold_more" : "unfold_less"
                    onClicked: root.collapsed = !root.collapsed
                    StyledToolTip {
                        text: root.collapsed ? Translation.tr("Expand") : Translation.tr("Collapse")
                    }
                }
                AiMessageControlButton {
                    id: copyCodeButton
                    buttonIcon: activated ? "inventory" : "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = root.segmentContent
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
                        // A named fence already says what the file is called; only fall
                        // back to code.<lang> when the model didn't tell us.
                        const name = root.segmentFilename.length > 0
                            ? root.segmentFilename.split("/").pop()
                            : `code.${root.segmentLang || "txt"}`;
                        const target = `${downloadPath}/${name}`;
                        Quickshell.execDetached(["bash", "-c",
                            `printf '%s' '${StringUtils.shellSingleQuoteEscape(root.segmentContent)}' > '${StringUtils.shellSingleQuoteEscape(target)}'`
                        ])
                        Quickshell.execDetached(["notify-send",
                            Translation.tr("Code saved to file"),
                            Translation.tr("Saved to %1").arg(target),
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

    Item { // Body, clipped while collapsed
        id: bodyClip
        Layout.fillWidth: true
        clip: true
        implicitHeight: root.collapsed
            ? Math.min(codeBodyLoader.implicitHeight, root.collapsedHeight)
            : codeBodyLoader.implicitHeight

        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // Use a Loader to ensure proper layout (fixes 'invisible code' bug)
        Loader {
            id: codeBodyLoader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            sourceComponent: RowLayout {
                spacing: root.codeBlockComponentSpacing

                Rectangle { // Line numbers
                    implicitWidth: 40
                    implicitHeight: lineNumberColumnLayout.implicitHeight
                    Layout.fillHeight: true
                    Layout.fillWidth: false
                    topLeftRadius: Appearance.rounding.unsharpen
                    bottomLeftRadius: root.codeBlockBackgroundRounding
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
                            // Wrapped lines make the gutter drift out of step with the
                            // code, so it only numbers when the text isn't wrapping.
                            model: root.wrapCode ? 0 : codeTextArea.text.split("\n").length
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
                    bottomRightRadius: root.codeBlockBackgroundRounding
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
                                policy: root.wrapCode ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
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
                                // The block already paints its own surface; the
                                // control's default background sat on top of it and
                                // showed as a second panel on a dark theme.
                                background: null
                                readOnly: !root.editing
                                selectByMouse: root.enableMouseSelection || root.editing
                                renderType: Text.NativeRendering
                                font.family: Appearance.font.family.monospace
                                font.hintingPreference: Font.PreferNoHinting
                                font.pixelSize: Appearance.font.pixelSize.small + 2
                                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                                selectionColor: Appearance.colors.colSecondaryContainer
                                color: Appearance.colors.colOnLayer1
                                wrapMode: root.wrapCode ? TextEdit.WrapAnywhere : TextEdit.NoWrap
                                text: root.segmentContent
                                onTextChanged: { root.segmentContent = text }

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
                    }
                }
            }
        }

        Rectangle { // Fade over the cut, so a collapsed block doesn't look truncated by accident
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 36
            visible: root.collapsed
            gradient: Gradient {
                GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colLayer2, 1) }
                GradientStop { position: 1.0; color: Appearance.colors.colLayer2 }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.collapsed = false
            }
        }
    }
}
