import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root
    implicitWidth: 864
    Layout.fillWidth: true
    Layout.minimumWidth: 576

    property real padding: 6
    property var inputField: messageInputField
    property string commandPrefix: "/"

    property var suggestionQuery: ""
    property var suggestionList: []

    onFocusChanged: focus => {
        if (focus) {
            root.inputField.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        // Escape closes any open popup
        if (event.key === Qt.Key_Escape) {
            if (modelPickerPopup.isOpen) { modelPickerPopup.close(); event.accepted = true; return; }
            if (functionsPopup.isOpen) { functionsPopup.close(); event.accepted = true; return; }
        }
        messageInputField.forceActiveFocus();
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                event.accepted = true;
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            Ai.newChat();
        }
        // Ctrl+1..9 to switch models
        if ((event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier)) {
            const num = event.key - Qt.Key_1;
            if (num >= 0 && num < 9 && num < Ai.modelList.length) {
                Ai.setModel(Ai.modelList[num]);
                event.accepted = true;
            }
        }
    }

    property var allCommands: [
        {
            name: "attach",
            description: Translation.tr("Attach a file (image, PDF, text, code, etc.). Supported by Gemini (full), OpenAI and Anthropic (images). Usage: /attach /path/to/file"),
            execute: args => {
                Ai.attachFile(args.join(" ").trim());
            }
        },
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: args => {
                if (args.length === 0 || !args[0]) {
                    Ai.addMessage(Translation.tr("Usage: %1model MODEL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                if (Ai.modelList.indexOf(args[0]) < 0) {
                    Ai.addMessage(Translation.tr("Unknown model: '%1'. Use /model with one of: %2").arg(args[0]).arg(Ai.modelList.join(", ")), Ai.interfaceRole);
                    return;
                }
                Ai.setModel(args[0]);
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "key",
            description: Translation.tr("Set API key"),
            execute: args => {
                if (args[0] == "get") {
                    Ai.printApiKey();
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "save",
            description: Translation.tr("Save chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs);
            }
        },
        {
            name: "load",
            description: Translation.tr("Load chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.loadChat(joinedArgs);
            }
        },
        {
            name: "new",
            description: Translation.tr("Start new chat (saves current to history buffer)"),
            execute: () => {
                Ai.newChat();
            }
        },
        {
            name: "clear",
            description: Translation.tr("Clear chat without saving to history"),
            execute: () => {
                Ai.resetSessionState();
                Ai.saveChat("lastSession");
            }
        },
        {
            name: "copy",
            description: Translation.tr("Copy last AI response to clipboard"),
            execute: () => {
                const ids = Ai.messageIDs;
                for (let i = ids.length - 1; i >= 0; i--) {
                    const msg = Ai.messageByID[ids[i]];
                    if (msg && msg.role === "assistant" && msg.rawContent && msg.rawContent.length > 0) {
                        Quickshell.clipboardText = msg.rawContent;
                        Ai.addMessage(Translation.tr("Last response copied to clipboard ✓"), Ai.interfaceRole);
                        return;
                    }
                }
                Ai.addMessage(Translation.tr("No AI response to copy"), Ai.interfaceRole);
            }
        },
        {
            name: "stop",
            description: Translation.tr("Stop all running AI processes"),
            execute: () => {
                Ai.abortAll();
                Ai.addMessage(Translation.tr("All AI processes stopped"), Ai.interfaceRole);
            }
        },
        {
            name: "addlocal",
            description: Translation.tr("Add a local model. Usage: /addlocal MODEL [ENDPOINT]\nDefaults: Ollama (localhost:11434). For LM Studio use /addlocal MODEL http://localhost:1234/v1/chat/completions"),
            execute: args => {
                if (args.length === 0) {
                    Ai.addMessage(Translation.tr("**Usage:** `/addlocal MODEL_NAME [ENDPOINT]`\n\n**Examples:**\n- `/addlocal llama3.3` — Ollama (default)\n- `/addlocal deepseek-r1:32b` — Ollama with tag\n- `/addlocal my-model http://localhost:1234/v1/chat/completions` — LM Studio\n- `/addlocal model http://192.168.1.10:8000/v1/chat/completions` — Remote vLLM"), Ai.interfaceRole);
                    return;
                }
                const modelName = args[0];
                const endpoint = args.length > 1 ? args[1] : "";
                Ai.addLocalModel(modelName, endpoint, modelName);
            }
        },
        {
            name: "export",
            description: Translation.tr("Export chat to markdown file in Downloads"),
            execute: () => {
                Ai.exportChat();
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set temperature (randomness) of the model. Values range between 0 to 2 for Gemini, 0 to 1 for other models. Default is 0.5."),
            execute: args => {
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature();
                    return;
                }
                const temp = parseFloat(args[0]);
                if (isNaN(temp)) {
                    Ai.addMessage(Translation.tr("Invalid temperature: '%1'. Must be a number in [0, 2].").arg(args[0]), Ai.interfaceRole);
                    return;
                }
                if (temp < 0 || temp > 2) {
                    Ai.addMessage(Translation.tr("Temperature %1 out of range. Must be in [0, 2].").arg(temp), Ai.interfaceRole);
                    return;
                }
                Ai.setTemperature(temp);
            }
        },
        {
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.addMessage(`
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)
- Arch lincox icon <img src="${Quickshell.shellPath("assets/icons/arch-symbolic.svg")}" height="${Appearance.font.pixelSize.small}"/>

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = \"UwU\";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)
`, Ai.interfaceRole);
            }
        },
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            // Handle special commands
            const parts = inputText.trim().split(/\s+/);
            const command = parts[0].substring(root.commandPrefix.length);
            const args = parts.slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === command);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
            }
        } else {
            Ai.sendUserMessage(inputText);
        }

        // Always scroll to bottom when user sends a message
        if (messageListView.isNearBottom) messageListView.positionViewAtEnd();
    }

    // Click-away overlay to close popups when clicking outside
    Rectangle {
        id: popupDismissOverlay
        parent: root
        anchors.fill: parent
        visible: modelPickerPopup.isOpen || functionsPopup.isOpen
        color: "transparent"
        z: 999
        MouseArea {
            anchors.fill: parent
            onClicked: {
                modelPickerPopup.close();
                functionsPopup.close();
            }
        }
    }

    // Model picker popup — lives at root level to escape inputWrapper's clip:true
    Rectangle {
        id: modelPickerPopup
        parent: root
        visible: opacity > 0
        enabled: opacity > 0
        z: 1000

        // Custom models first, then built-ins
        property var sortedModelList: {
            const custom  = Ai.modelList.filter(id =>  Ai.isRemovableModel(id));
            const builtin = Ai.modelList.filter(id => !Ai.isRemovableModel(id));
            return [...custom, ...builtin];
        }
        property bool hasCustomModels: sortedModelList.some(id => Ai.isRemovableModel(id))

        property bool isOpen: false

        function open() {
            functionsPopup.close();
            var pos = modelPickerButton.mapToItem(root, 0, 0);
            x = pos.x;
            y = pos.y - implicitHeight - 6;
            isOpen = true;
        }
        function close() {
            isOpen = false;
        }
        function toggle() {
            if (isOpen) close(); else open();
        }

        // Opacity + translate animation (Google-style: fade + slide up)
        opacity: isOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        // Y offset spring-in
        property real yOffset: isOpen ? 0 : 10
        Behavior on yOffset {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        transform: [
            Translate { y: modelPickerPopup.yOffset },
            Scale {
                origin.x: modelPickerPopup.width / 2
                origin.y: modelPickerPopup.height
                xScale: modelPickerPopup.isOpen ? 1 : 0.96
                yScale: modelPickerPopup.isOpen ? 1 : 0.96
                Behavior on xScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on yScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        ]

        width: 240
        readonly property real maxPopupHeight: 300
        readonly property real naturalHeight: modelPickerColumn.implicitHeight + 16
        implicitHeight: Math.min(naturalHeight, maxPopupHeight)
        radius: Appearance.rounding.large ?? 16
        color: Appearance.colors.colLayer2Base
        border.width: 1
        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.8)
        clip: true

        // Close when clicking outside
        Connections {
            target: messageInputField
            function onActiveFocusChanged() {
                if (messageInputField.activeFocus && modelPickerPopup.isOpen)
                    modelPickerPopup.close();
            }
        }

        Flickable {
            id: modelPickerFlickable
            anchors.fill: parent
            anchors.margins: 6
            contentHeight: modelPickerColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            // Smooth deceleration for touch/flick
            flickDeceleration: 1500
            maximumFlickVelocity: 1500

            // Smooth scroll animation for wheel input
            Behavior on contentY {
                id: scrollBehavior
                enabled: false
                SmoothedAnimation {
                    duration: 200
                    velocity: -1
                }
            }

            // Scroll bar
            Rectangle {
                id: modelPickerScrollbar
                parent: modelPickerFlickable
                visible: modelPickerFlickable.contentHeight > modelPickerFlickable.height
                anchors.right: parent.right
                anchors.rightMargin: -2
                width: 3
                radius: 1.5
                color: Appearance.colors.colSubtext
                opacity: modelPickerFlickable.moving ? 0.5 : 0.15
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                y: modelPickerFlickable.contentY / modelPickerFlickable.contentHeight * modelPickerFlickable.height
                height: Math.max(20, modelPickerFlickable.height / modelPickerFlickable.contentHeight * modelPickerFlickable.height)
                z: 10
            }

            // Mouse wheel support with smooth scrolling
            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: true
                onWheel: (wheel) => {
                    scrollBehavior.enabled = true;
                    const step = wheel.angleDelta.y * 1.2;
                    modelPickerFlickable.contentY = Math.max(0,
                        Math.min(modelPickerFlickable.contentHeight - modelPickerFlickable.height,
                            modelPickerFlickable.contentY - step));
                    wheel.accepted = true;
                    scrollResetTimer.restart();
                }
                Timer {
                    id: scrollResetTimer
                    interval: 300
                    onTriggered: scrollBehavior.enabled = false
                }
                onClicked: (mouse) => mouse.accepted = false
                onPressed: (mouse) => mouse.accepted = false
                onReleased: (mouse) => mouse.accepted = false
            }

            ColumnLayout {
                id: modelPickerColumn
                width: modelPickerFlickable.width
                spacing: 4

                Item { Layout.fillWidth: true; implicitHeight: 4 }
                StyledText {
                    Layout.leftMargin: 12
                    Layout.topMargin: 2
                    font.pixelSize: Appearance.font.pixelSize.smaller + 2
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3primary
                    text: Translation.tr("Select Model")
                }

                // Custom models section (only shown when custom models exist)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    visible: modelPickerPopup.hasCustomModels

                    StyledText {
                        Layout.leftMargin: 8
                        Layout.topMargin: 2
                        font.pixelSize: Appearance.font.pixelSize.smaller + 2
                        color: Appearance.colors.colSubtext
                        opacity: 0.6
                        text: Translation.tr("Custom")
                    }

                    Repeater {
                        model: modelPickerPopup.sortedModelList.filter(id => Ai.isRemovableModel(id))
                        delegate: RippleButton {
                            required property var modelData
                            property bool pendingDelete: false
                            Layout.fillWidth: true
                            implicitHeight: 52
                            buttonRadius: Appearance.rounding.normal
                            toggled: Ai.currentModelId === modelData
                            colBackground: toggled ? Qt.alpha(Appearance.m3colors.m3primaryContainer, 0.85) : "transparent"
                            colBackgroundHover: Qt.alpha(Appearance.colors.colLayer2Hover, 0.8)
                            onClicked: {
                                if (pendingDelete) { pendingDelete = false; return; }
                                Ai.setModel(modelData, false); modelPickerPopup.close();
                            }
                            Timer {
                                id: deleteResetTimer
                                interval: 2500
                                onTriggered: parent.pendingDelete = false
                            }
                            contentItem: RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                spacing: 12
                                Rectangle {
                                    width: 32; height: 32; radius: 8
                                    color: Qt.alpha(Appearance.colors.colSubtext, 0.1)
                                    CustomIcon {
                                        anchors.centerIn: parent
                                        visible: Ai.models[modelData]?.icon?.length > 0
                                        width: 20; height: 20
                                        source: Ai.models[modelData]?.icon ?? ""; colorize: true
                                        color: parent.parent.parent.toggled ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurface
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: !Ai.models[modelData]?.icon
                                        text: "smart_toy"
                                        iconSize: 20
                                        color: parent.parent.parent.toggled ? Appearance.m3colors.m3primary : Appearance.colors.colSubtext
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true;
                                        font.pixelSize: Appearance.font.pixelSize.small + 2;
                                        font.weight: Font.DemiBold;
                                        color: parent.parent.parent.toggled ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface
                                        opacity: parent.parent.parent.toggled ? 1.0 : 0.85
                                        text: Ai.models[modelData]?.name ?? modelData;
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true;
                                        font.pixelSize: Appearance.font.pixelSize.smaller + 1;
                                        color: parent.parent.parent.toggled ? Qt.alpha(Appearance.m3colors.m3onPrimaryContainer, 0.75) : Appearance.colors.colSubtext;
                                        text: (Ai.models[modelData]?.description ?? "").split("\n")[0] ?? "";
                                        elide: Text.ElideRight
                                    }
                                }
                                MaterialSymbol {
                                    visible: parent.parent.toggled && !parent.parent.pendingDelete
                                    text: "check_circle"; iconSize: 18; color: Appearance.m3colors.m3primary
                                }
                                // Delete controls
                                RowLayout {
                                    visible: parent.parent.pendingDelete
                                    spacing: 8
                                    StyledText {
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.m3colors.m3error
                                        text: Translation.tr("Remove?")
                                    }
                                    MaterialSymbol {
                                        text: "delete_forever"; iconSize: 20; color: Appearance.m3colors.m3error
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Ai.removeModel(modelData) }
                                    }
                                }
                                MaterialSymbol {
                                    visible: !parent.parent.pendingDelete && !parent.parent.toggled
                                    text: "close"; iconSize: 18; color: Appearance.colors.colSubtext; opacity: 0.5
                                    MouseArea { 
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                        onClicked: { parent.parent.parent.pendingDelete = true; deleteResetTimer.restart(); } 
                                    }
                                }
                            }
                        }
                    }

                    // Divider
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            Layout.rightMargin: 6
                            implicitHeight: 1
                            color: Appearance.colors.colOutlineVariant
                            opacity: 0.5
                        }
                    }
                }

                // Built-in models section label (only when custom models exist)
                StyledText {
                    visible: modelPickerPopup.hasCustomModels
                    Layout.leftMargin: 8
                    Layout.topMargin: 2
                    font.pixelSize: Appearance.font.pixelSize.smaller + 2
                    color: Appearance.colors.colSubtext
                    opacity: 0.6
                    text: Translation.tr("Built-in")
                }

                Repeater {
                    model: modelPickerPopup.sortedModelList.filter(id => !Ai.isRemovableModel(id))
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 52
                        buttonRadius: Appearance.rounding.normal
                        toggled: Ai.currentModelId === modelData
                        colBackground: toggled ? Qt.alpha(Appearance.m3colors.m3primaryContainer, 0.85) : "transparent"
                        colBackgroundHover: Qt.alpha(Appearance.colors.colLayer2Hover, 0.8)
                        onClicked: { Ai.setModel(modelData, false); modelPickerPopup.close(); }
                        contentItem: RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 12
                            Rectangle {
                                width: 32; height: 32; radius: 8
                                color: Qt.alpha(Appearance.colors.colSubtext, 0.1)
                                CustomIcon {
                                    anchors.centerIn: parent
                                    visible: Ai.models[modelData]?.icon?.length > 0
                                    width: 20; height: 20
                                    source: Ai.models[modelData]?.icon ?? ""; colorize: true
                                    color: parent.parent.parent.toggled ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurface
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !Ai.models[modelData]?.icon
                                    text: Ai.guessModelLogo(modelData)
                                    iconSize: 20
                                    color: parent.parent.parent.toggled ? Appearance.m3colors.m3primary : Appearance.colors.colSubtext
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                StyledText {
                                    Layout.fillWidth: true;
                                    font.pixelSize: Appearance.font.pixelSize.small + 2;
                                    font.weight: Font.DemiBold;
                                    color: parent.parent.parent.toggled ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface
                                    opacity: 1.0
                                    text: Ai.models[modelData]?.name ?? modelData;
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true;
                                    font.pixelSize: Appearance.font.pixelSize.smaller + 1;
                                    color: parent.parent.parent.toggled ? Qt.alpha(Appearance.m3colors.m3onPrimaryContainer, 0.75) : Appearance.colors.colSubtext;
                                    text: (Ai.models[modelData]?.description ?? "").split("\n")[0] ?? "";
                                    elide: Text.ElideRight
                                }
                            }
                            MaterialSymbol {
                                visible: parent.parent.toggled
                                text: "check_circle"; iconSize: 18; color: Appearance.m3colors.m3primary
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true; implicitHeight: 4 }
            }
        }
    }



    // Functions & Thinking popup
    Rectangle {
        id: functionsPopup
        parent: root
        visible: opacity > 0
        enabled: opacity > 0
        z: 1000

        property bool isOpen: false

        function open() {
            modelPickerPopup.close();
            var pos = functionsButton.mapToItem(root, 0, 0);
            x = pos.x - (width - functionsButton.width) + 30; // Shifted right from right-aligned state
            y = pos.y - implicitHeight - 6;
            // Clamp to not go off-screen left/right
            if (x < 6) x = 6;
            if (x + width > root.width - 6) x = root.width - width - 6;
            isOpen = true;
        }
        function close() {
            isOpen = false;
        }
        function toggle() {
            if (isOpen) close(); else open();
        }

        opacity: isOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        property real yOffset: isOpen ? 0 : 10
        Behavior on yOffset {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        transform: [
            Translate { y: functionsPopup.yOffset },
            Scale {
                origin.x: functionsPopup.width / 2
                origin.y: functionsPopup.height
                xScale: functionsPopup.isOpen ? 1 : 0.96
                yScale: functionsPopup.isOpen ? 1 : 0.96
                Behavior on xScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on yScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        ]

        width: 300
        implicitHeight: functionsPopupColumn.implicitHeight + 16
        clip: true
        radius: Appearance.rounding.large ?? 16
        color: Appearance.colors.colLayer2Base
        border.width: 1
        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.8)

        // Close when clicking outside
        Connections {
            target: messageInputField
            function onActiveFocusChanged() {
                if (messageInputField.activeFocus && functionsPopup.isOpen)
                    functionsPopup.close();
            }
        }

        ColumnLayout {
            id: functionsPopupColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // --- Tools section ---
            StyledText {
                Layout.leftMargin: 4
                Layout.topMargin: 2
                font.pixelSize: Appearance.font.pixelSize.smaller + 2
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3primary
                text: Translation.tr("Tool Mode")
            }

            Repeater {
                model: Ai.availableTools
                delegate: RippleButton {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 52
                    buttonRadius: Appearance.rounding.normal
                    toggled: Ai.currentTool === modelData
                    colBackground: toggled ? Qt.alpha(Appearance.m3colors.m3primaryContainer, 0.85) : "transparent"
                    colBackgroundHover: Qt.alpha(Appearance.colors.colLayer2Hover, 0.8)
                    onClicked: {
                        Ai.setTool(modelData);
                        functionsPopup.close();
                    }
                    contentItem: RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                        spacing: 12
                        // Colored icon pill
                        Rectangle {
                            width: 34; height: 34; radius: 10
                            color: {
                                if (modelData === "functions") return Qt.alpha(Appearance.m3colors.m3primary, 0.12);
                                if (modelData === "search") return Qt.alpha("#34A853", 0.12);
                                return Qt.alpha(Appearance.colors.colSubtext, 0.08);
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: modelData === "functions" ? "build" : modelData === "search" ? "search" : "block"
                                iconSize: 18
                                color: {
                                    if (modelData === "functions") return Appearance.m3colors.m3primary;
                                    if (modelData === "search") return "#34A853";
                                    return Appearance.colors.colSubtext;
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                Layout.maximumWidth: 280
                                font.pixelSize: Appearance.font.pixelSize.small + 2
                                font.weight: Font.DemiBold
                                color: parent.parent.parent.toggled ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface
                                opacity: 1.0
                                text: modelData === "functions" ? Translation.tr("All Tools") : 
                                      modelData === "search" ? Translation.tr("Search Only") : 
                                      Translation.tr("No Tools")
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.smaller + 1
                                color: parent.parent.parent.toggled ? Qt.alpha(Appearance.m3colors.m3onPrimaryContainer, 0.85) : Appearance.colors.colSubtext
                                text: (Ai.toolDescriptions[modelData] ?? "").split("\n")[0] ?? ""
                                elide: Text.ElideRight
                                opacity: parent.parent.parent.toggled ? 1.0 : 0.8
                            }
                        }
                        MaterialSymbol {
                            visible: parent.parent.toggled
                            text: "check_circle"; iconSize: 18; color: Appearance.m3colors.m3primary
                        }
                    }
                }
            }


            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 12; Layout.bottomMargin: 6
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small + 2
                        color: Appearance.m3colors.m3onSurface
                        text: Translation.tr("Prompt Caching")
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller + 2
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Save credits by reusing context")
                    }
                }

                Rectangle {
                    width: 44; height: 24; radius: 12
                    color: Ai.promptCaching ? Appearance.m3colors.m3primary : Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Ai.promptCaching ? Appearance.m3colors.m3primary : Appearance.colors.colOutlineVariant
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: Ai.promptCaching ? parent.width - width - 3 : 3
                        color: Ai.promptCaching ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                        Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Ai.promptCaching = !Ai.promptCaching;
                            Ai.savePersistentState("promptCaching", Ai.promptCaching);
                        }
                    }
                }
            }


        }
    }


    Process {
        id: decodeImageAndAttachProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry: string) {
            imageDecodeFileName = parseInt(entry.match(/^(\d+)\t/)[1]);
            decodeImageAndAttachProc.exec(["bash", "-c", `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`]);
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Ai.attachFile(imageDecodeFilePath);
            } else {
                console.error("[AiChat] Failed to decode image in clipboard content");
            }
        }
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string statusText
        property string description
        hoverEnabled: true
        implicitHeight: statusItemRowLayout.implicitHeight
        implicitWidth: statusItemRowLayout.implicitWidth

        RowLayout {
            id: statusItemRowLayout
            spacing: 0
            MaterialSymbol {
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small + 2
                text: statusItem.statusText
                color: Appearance.colors.colSubtext
                animateChange: true
            }
        }

        StyledToolTip {
            text: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
        }
    }

    component StatusSeparator: Rectangle {
        implicitWidth: 4
        implicitHeight: 4
        radius: implicitWidth / 2
        color: Appearance.colors.colOutlineVariant
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item {
            // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: swipeView.width
                    height: swipeView.height
                    radius: Appearance.rounding.small
                }
            }

            StyledRectangularShadow {
                z: 1
                target: statusBg
                opacity: messageListView.atYBeginning ? 0 : 1
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            Rectangle {
                id: statusBg
                z: 2
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: 4
                }
                implicitWidth: statusColumnLayout.implicitWidth + 10 * 2
                implicitHeight: Math.max(statusColumnLayout.implicitHeight + 8, 38)
                radius: Appearance.rounding.normal - root.padding
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                ColumnLayout {
                    id: statusColumnLayout
                    anchors.centerIn: parent
                    spacing: 4

                    RowLayout {
                        id: statusBarRow1
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10

                        StatusItem {
                            icon: Ai.currentModelHasApiKey ? "key" : "key_off"
                            statusText: ""
                            description: Ai.currentModelHasApiKey ? Translation.tr("API key is set\nChange with /key YOUR_API_KEY") : Translation.tr("No API key\nSet it with /key YOUR_API_KEY")
                        }
                        StatusSeparator {}
                        StatusItem {
                            icon: "device_thermostat"
                            statusText: Ai.temperature.toFixed(1)
                            description: Translation.tr("Temperature\nChange with /temp VALUE")
                        }
                        StatusSeparator {
                            visible: Ai.tokenCount.total > 0
                        }
                        StatusItem {
                            visible: Ai.tokenCount.total > 0
                            icon: "token"
                            statusText: Ai.tokenCount.total
                            description: Translation.tr("Tokens used in last request\nInput: %1 (%2 cached)\nOutput: %3").arg(Ai.tokenCount.input).arg(Ai.tokenCount.cacheRead).arg(Ai.tokenCount.output)
                        }
                    }

                    RowLayout {
                        id: statusBarRow2
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10
                        visible: Ai.generationSpeed > 0 || Ai.sessionCost > 0.0001 || Ai.sessionSummary.length > 0

                        StatusItem {
                            visible: Ai.generationSpeed > 0
                            icon: "speed"
                            statusText: Ai.generationSpeed.toFixed(1)
                            description: Translation.tr("Generation speed (tokens/sec)")
                        }
                        StatusSeparator {
                            visible: Ai.generationSpeed > 0 && (Ai.sessionCost > 0.0001 || Ai.sessionSummary.length > 0)
                        }
                        StatusItem {
                            visible: Ai.sessionCost > 0.0001
                            icon: "payments"
                            statusText: "$" + Ai.sessionCost.toFixed(4)
                            description: Translation.tr("Estimated session cost (accumulated)")
                        }
                        StatusSeparator {
                            visible: Ai.sessionCost > 0.0001 && Ai.sessionSummary.length > 0
                        }
                        StatusItem {
                            visible: Ai.sessionSummary.length > 0
                            icon: "history_edu"
                            statusText: Translation.tr("Condensed")
                            description: Translation.tr("History has been semantically condensed to save space.\n\nSummary:\n%1").arg(Ai.sessionSummary)
                        }
                    }
                }
            }

            ScrollEdgeFade {
                z: 1
                target: messageListView
                vertical: true
            }

            StyledListView { // Message list
                id: messageListView
                z: 0
                anchors.fill: parent
                spacing: 0
                popin: false
                topMargin: statusBg.implicitHeight + statusBg.anchors.topMargin * 2

                // Pre-render off-screen items for smoother scrolling
                cacheBuffer: 600
                reuseItems: true

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                property int lastResponseLength: 0
                property bool userScrolledUp: false
                property bool initialLoadDone: false
                // Only auto-scroll if user is near the bottom (within 150px)
                property bool isNearBottom: (contentHeight - contentY - height) < 150
                onContentYChanged: isNearBottom = (contentHeight - contentY - height) < 150

                Component.onCompleted: Qt.callLater(() => { initialLoadDone = true; })

                onContentHeightChanged: {
                    if (isNearBottom && !userScrolledUp)
                        Qt.callLater(positionViewAtEnd);
                }
                onCountChanged: {
                    if (initialLoadDone && !userScrolledUp)
                        Qt.callLater(positionViewAtEnd);
                }
                onMovementStarted: {
                    if (verticalVelocity < 0)
                        userScrolledUp = true;
                }
                onAtYEndChanged: {
                    if (atYEnd) userScrolledUp = false;
                }

                // Smooth fade-in for new messages — no y animation: ListView's `from: 14`
                // is a literal content-y, which made the new delegate fly from the top of
                // the chat down to its natural position, momentarily overlaying every
                // message it passed through.
                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                }

                model: ScriptModel {
                    values: Ai.messageIDs.filter(id => {
                        const message = Ai.messageByID[id];
                        return message?.visibleToUser ?? true;
                    })
                }
                delegate: AiMessage {
                    required property var modelData
                    required property int index
                    messageIndex: index
                    messageData: Ai.messageByID[modelData] ?? null

                    property var prevMessageData: index > 0 ? Ai.messageByID[messageListView.model.values[index - 1]] : null
                    isContinuation: prevMessageData != null 
                        && messageData != null
                        && messageData.role === prevMessageData?.role 
                        && messageData.model === prevMessageData?.model
                        && messageData.role === "assistant"

                    messageInputField: root.inputField
                }
            }

            PagePlaceholder {
                z: 2
                shown: Ai.messageIDs.length === 0
                icon: "chat_bubble"
                title: Translation.tr("AI Assistant")
                description: Translation.tr("Type /key to get started with online models\nCtrl+O to expand sidebar\nCtrl+P to pin sidebar\nCtrl+D to detach sidebar\nCtrl+Shift+O to start a new chat")
                shape: MaterialShape.Shape.PixelCircle
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }
        }

        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        FlowButtonGroup { // Suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0;
                    return root.suggestionList.slice(0, 10);
                }
                delegate: ApiCommandButton {
                    id: commandButton
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: RowLayout {
                        spacing: 2
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small + 2
                            color: Appearance.m3colors.m3onSurface
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.displayName ?? modelData.name
                        }
                        // Show × button for removable (custom/local) models
                        Rectangle {
                            visible: modelData.removable ?? false
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8
                            color: commandButton.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                            StyledText {
                                anchors.centerIn: parent
                                text: "×"
                                font.pixelSize: Appearance.font.pixelSize.small + 2
                                color: Appearance.colors.colSubtext
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.modelId) {
                                        Ai.removeModel(modelData.modelId);
                                        messageInputField.text = "";
                                    }
                                }
                            }
                        }
                    }

                    onHoveredChanged: {
                        if (commandButton.hovered) {
                            suggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        suggestions.acceptSuggestion(modelData.name);
                    }
                }
            }

            function acceptSuggestion(word) {
                const words = messageInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = word;
                } else {
                    words.push(word);
                }
                const updatedText = words.join(" ") + " ";
                messageInputField.text = updatedText;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord() {
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                    const word = root.suggestionList[suggestions.selectedIndex].name;
                    suggestions.acceptSuggestion(word);
                }
            }
        }

        Rectangle { // Input area
            id: inputWrapper
            property real spacing: 6
            Layout.fillWidth: true
            radius: 28
            color: Appearance.colors.colLayer2
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + spacing, 50) + (attachedFileIndicator.implicitHeight + spacing + attachedFileIndicator.anchors.topMargin)
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            // Focus glow ring
            Rectangle {
                anchors.fill: parent
                // Draw inside the parent to avoid being clipped by parent's bounding box
                radius: parent.radius
                color: "transparent"
                border.color: Appearance.m3colors.m3primary
                border.width: 2
                opacity: messageInputField.activeFocus ? 1.0 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
                z: 10
            }

            AttachedFileIndicator {
                id: attachedFileIndicator
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: visible ? 10 : 0
                }
                filePath: Ai.pendingFilePath
                onRemove: Ai.attachFile("")
            }

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors {
                    bottom: commandButtonsRow.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: 10
                }
                spacing: 0

                ScrollView {
                    id: inputScrollView
                    Layout.fillWidth: true
                    Layout.minimumHeight: 58
                    Layout.preferredHeight: Math.min(root.height * 3/5, messageInputField.height)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea { // The actual TextArea (inside ScrollView to enable scrolling)
                        id: messageInputField
                        anchors.fill: parent
                        wrapMode: TextArea.Wrap
                        padding: 16
                        leftPadding: 20
                        rightPadding: 16
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        placeholderText: Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix)

                        background: null

                        // Chat history navigation (Up/Down when suggestions popup is not visible).
                        // _historyIndex: -1 means "not navigating, current text is the user's live draft".
                        // 0..n-1 walks backwards through prior user messages (0 = most recent).
                        property int _historyIndex: -1
                        property string _historyDraft: ""

                        function _userPromptHistory() {
                            const ids = Ai.messageIDs || [];
                            const out = [];
                            for (let i = ids.length - 1; i >= 0; i--) {
                                const m = Ai.messageByID ? Ai.messageByID[ids[i]] : null;
                                if (m && m.role === "user" && typeof m.content === "string" && m.content.length > 0) {
                                    out.push(m.content);
                                }
                            }
                            return out;
                        }

                        function _resetHistoryNav() {
                            _historyIndex = -1;
                            _historyDraft = "";
                        }

                        onTextChanged: {
                            // Handle suggestions
                            if (messageInputField.text.length === 0) {
                                root.suggestionQuery = "";
                                root.suggestionList = [];
                                return;
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const modelResults = Fuzzy.go(root.suggestionQuery, Ai.modelList.map(model => {
                                    return {
                                        name: Fuzzy.prepare(model),
                                        obj: model
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = modelResults.map(model => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.target}`,
                                        displayName: `${Ai.models[model.target].name}`,
                                        description: `${Ai.models[model.target].description}`,
                                        removable: Ai.isRemovableModel(model.target),
                                        modelId: model.target,
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                        displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                        description: Translation.tr("Load prompt from %1").arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}save`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "save ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr("Save chat to %1").arg(chatName)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr(`Load chat from %1`).arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                    return {
                                        name: Fuzzy.prepare(tool),
                                        obj: tool
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = toolResults.map(tool => {
                                    const toolName = tool.target;
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                        displayName: toolName,
                                        description: Ai.toolDescriptions[toolName]
                                    };
                                });
                            } else if (messageInputField.text.startsWith(root.commandPrefix)) {
                                root.suggestionQuery = messageInputField.text;
                                root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                    return {
                                        name: `${root.commandPrefix}${cmd.name}`,
                                        description: `${cmd.description}`
                                    };
                                });
                            }
                        }

                        function accept() {
                            root.handleInput(text);
                            text = "";
                            _resetHistoryNav();
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Tab) {
                                suggestions.acceptSelectedWord();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(Math.max(0, root.suggestionList.length - 1), suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && event.modifiers === Qt.NoModifier) {
                                // Walk back through prior user prompts
                                const hist = messageInputField._userPromptHistory();
                                if (hist.length === 0) { event.accepted = false; return; }
                                if (messageInputField._historyIndex === -1) {
                                    messageInputField._historyDraft = messageInputField.text;
                                }
                                const next = Math.min(hist.length - 1, messageInputField._historyIndex + 1);
                                if (next !== messageInputField._historyIndex) {
                                    messageInputField._historyIndex = next;
                                    messageInputField.text = hist[next];
                                    messageInputField.cursorPosition = messageInputField.text.length;
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && event.modifiers === Qt.NoModifier) {
                                // Come forward; at the end, restore the draft
                                if (messageInputField._historyIndex < 0) { event.accepted = false; return; }
                                const hist = messageInputField._userPromptHistory();
                                const next = messageInputField._historyIndex - 1;
                                messageInputField._historyIndex = next;
                                if (next < 0) {
                                    messageInputField.text = messageInputField._historyDraft;
                                    messageInputField._historyDraft = "";
                                } else {
                                    messageInputField.text = hist[next];
                                }
                                messageInputField.cursorPosition = messageInputField.text.length;
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Insert newline
                                    messageInputField.insert(messageInputField.cursorPosition, "\n");
                                    event.accepted = true;
                                } else if (Ai.isGenerating) {
                                    // Stop generation instead of sending
                                    Ai.abortAll();
                                    event.accepted = true;
                                } else {
                                    // Accept text
                                    const inputText = messageInputField.text;
                                    messageInputField.clear();
                                    root.handleInput(inputText);
                                    event.accepted = true;
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                // Intercept Ctrl+V to handle image/file pasting
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Let Shift+Ctrl+V = plain paste at cursor position
                                    messageInputField.insert(messageInputField.cursorPosition, Quickshell.clipboardText);
                                    event.accepted = true;
                                    return;
                                }
                                // Try image paste first
                                const currentClipboardEntry = Cliphist.entries[0];
                                const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) {
                                    // First entry = currently copied entry = image?
                                    decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                    event.accepted = true;
                                    return;
                                } else if (cleanCliphistEntry.startsWith("file://")) {
                                    // First entry = currently copied entry = image?
                                    const fileName = decodeURIComponent(cleanCliphistEntry);
                                    Ai.attachFile(fileName);
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false; // No image, let text pasting proceed
                            } else if (event.key === Qt.Key_Escape) {
                                // Esc precedence: open popup -> abort generation -> detach file
                                if (modelPickerPopup.isOpen) {
                                    modelPickerPopup.close();
                                    event.accepted = true;
                                } else if (functionsPopup.isOpen) {
                                    functionsPopup.close();
                                    event.accepted = true;
                                } else if (Ai.isGenerating) {
                                    Ai.abortAll();
                                    event.accepted = true;
                                } else if (Ai.pendingFilePath.length > 0) {
                                    Ai.attachFile("");
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Period) {
                                // Ctrl+Shift+. to force stop everything
                                Ai.abortAll();
                                event.accepted = true;
                            }
                        }
                    }
                }
                
                RippleButton { // Quick Attach Button
                    id: attachButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.rightMargin: 4
                    Layout.bottomMargin: 6
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: 20
                    colBackground: "transparent"
                    colBackgroundHover: Qt.alpha(Appearance.colors.colLayer2Hover, 0.7)
                    onClicked: {
                        const attachCmd = root.commandPrefix + "attach ";
                        if (messageInputField.text.length === 0 || !messageInputField.text.startsWith(attachCmd)) {
                            messageInputField.text = attachCmd;
                        }
                        messageInputField.cursorPosition = messageInputField.text.length;
                        messageInputField.forceActiveFocus();
                    }
                    StyledToolTip { text: Translation.tr("Attach file") }
                    
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                        text: "attach_file"
                    }
                }

                RippleButton { // Send button / Stop button
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.rightMargin: 8
                    Layout.bottomMargin: 6
                    implicitWidth: 44
                    implicitHeight: 44
                    buttonRadius: 22  // Full circle (FAB style)
                    enabled: messageInputField.text.length > 0 || Ai.isGenerating
                    toggled: enabled

                    // Micro-scale animation on press
                    scale: sendButton.down ? 0.92 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    onClicked: {
                        if (Ai.isGenerating) {
                            Ai.abortAll();
                        } else {
                            const inputText = messageInputField.text;
                            root.handleInput(inputText);
                            messageInputField.clear();
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: Ai.isGenerating ? "stop" : "arrow_upward"
                        Behavior on text { PropertyAnimation { duration: 0 } }
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                anchors.leftMargin: 14
                anchors.rightMargin: 10
                spacing: 10


                // Commands shortcut button
                RippleButton {
                    id: commandsShortcutButton
                    implicitWidth: commandsShortcutRow.implicitWidth + 22
                    implicitHeight: 36
                    buttonRadius: 18
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        messageInputField.text = root.commandPrefix;
                        messageInputField.cursorPosition = messageInputField.text.length;
                        messageInputField.forceActiveFocus();
                    }
                    StyledToolTip { text: Translation.tr("Open commands") }
                    contentItem: RowLayout {
                        id: commandsShortcutRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "terminal"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onSurface
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller + 2
                            font.weight: Font.Medium
                            color: Appearance.m3colors.m3onSurface
                            text: "/"
                        }
                    }
                }

                RippleButton {
                    // Model picker button
                    id: modelPickerButton
                    implicitWidth: modelPickerRow.implicitWidth + 26
                    implicitHeight: 36
                    buttonRadius: 18
                    colBackground: Qt.alpha(Appearance.m3colors.m3primary, 0.10)
                    colBackgroundHover: Qt.alpha(Appearance.m3colors.m3primary, 0.18)

                    Behavior on implicitWidth {
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutQuint }
                    }

                    onClicked: modelPickerPopup.toggle()

                    contentItem: RowLayout {
                        id: modelPickerRow
                        anchors.centerIn: parent
                        spacing: 5
                        CustomIcon {
                            visible: Ai.models[Ai.currentModelId]?.icon?.length > 0
                            width: 14
                            height: 14
                            source: Ai.models[Ai.currentModelId]?.icon ?? ""
                            colorize: true
                            color: Appearance.m3colors.m3primary
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller + 2
                            font.weight: Font.Medium
                            color: Appearance.m3colors.m3primary
                            text: Ai.getModel()?.name ?? ""
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            text: modelPickerPopup.isOpen ? "expand_less" : "expand_more"
                            iconSize: 14
                            color: Appearance.m3colors.m3primary
                            Behavior on text { PropertyAnimation { duration: 0 } }
                        }
                    }
                }

                RippleButton {
                    // Functions & Thinking popup button
                    id: functionsButton
                    implicitWidth: functionsButtonRow.implicitWidth + 22
                    implicitHeight: 36
                    buttonRadius: 18
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover

                    Behavior on implicitWidth {
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutQuint }
                    }

                    onClicked: functionsPopup.toggle()

                    contentItem: RowLayout {
                        id: functionsButtonRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "service_toolbox"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onSurface
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller + 2
                            color: Appearance.m3colors.m3onSurface
                            text: Ai.currentTool.charAt(0).toUpperCase() + Ai.currentTool.slice(1)
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            text: "expand_more"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }


            }
        }
    }
}
