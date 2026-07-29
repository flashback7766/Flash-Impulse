pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * The settings you reach for mid-conversation, as a sheet over the chat.
 *
 * Everything here was previously a slash command and nothing else, which meant
 * the only way to discover any of it was to already know it existed. The rare
 * things — prompt editing, provider defaults — stay in the settings app.
 *
 * Keys are shown masked and only ever written to the system keyring; the panel
 * never renders one in full, because the chat it sits over is autosaved to a
 * plain file on disk.
 */
Item {
    id: root

    property bool shown: false
    // One side inset for the sheet, matching the history sheet next door.
    readonly property real inset: 12
    signal requestClose

    function open() {
        root.shown = true;
    }

    function close() {
        root.shown = false;
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
        function onSettingsRequested() {
            // Toggle: the same call that opened it should put it away again,
            // otherwise the only way out is the keyboard.
            if (root.shown) root.close();
            else root.open();
        }
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        // Opaque for the same reason the history sheet is: the layer colours are
        // semi-transparent by design and this has to hide the conversation.
        color: Appearance.m3colors.m3surfaceContainerLow
        radius: Appearance.rounding.normal

        transform: Translate {
            y: root.shown ? 0 : 12
            Behavior on y {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        // hoverEnabled matters as much as the fill: without it this only swallows
        // clicks, and hover still reaches whatever's underneath — a control the
        // panel is covering keeps reporting itself hovered and its tooltip sits
        // there, floating over the panel that's supposed to be in front of it.
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
                    text: Translation.tr("Assistant settings")
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

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: settingsColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 5
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer2Active
                    }
                }

                ColumnLayout {
                    id: settingsColumn
                    width: parent.width
                    spacing: 6

                    // ---- What it may do without asking ------------------------

                    SectionLabel { text: Translation.tr("Permission") }

                    Repeater {
                        model: Ai.permissionModes

                        delegate: Rectangle {
                            id: modeRow
                            required property var modelData
                            readonly property bool active: modeRow.modelData.id === Ai.permissionMode

                            Layout.fillWidth: true
                            implicitHeight: modeColumn.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: modeRow.active ? Appearance.colors.colSecondaryContainer
                                : modeArea.containsMouse ? Appearance.colors.colLayer2Hover
                                : "transparent"

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            MouseArea {
                                id: modeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Ai.setPermissionMode(modeRow.modelData.id)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                anchors.leftMargin: 10
                                spacing: 10

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: modeRow.modelData.id === "yolo" ? Appearance.colors.colError
                                        : modeRow.active ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colSubtext
                                    text: modeRow.modelData.icon
                                }

                                ColumnLayout {
                                    id: modeColumn
                                    Layout.fillWidth: true
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: modeRow.active ? Font.DemiBold : Font.Normal
                                        color: modeRow.active ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colOnLayer1
                                        text: modeRow.modelData.name
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        text: modeRow.modelData.hint
                                    }
                                }

                                MaterialSymbol {
                                    visible: modeRow.active
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colOnSecondaryContainer
                                    text: "check"
                                }
                            }
                        }
                    }

                    // ---- How it should answer ----------------------------------

                    SectionLabel { text: Translation.tr("Style") }

                    Flow {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.inset
                        Layout.rightMargin: root.inset
                        spacing: 6

                        Repeater {
                            model: Ai.promptProfiles

                            delegate: RippleButton {
                                id: profileChip
                                required property var modelData
                                readonly property bool active: profileChip.modelData.id === Ai.promptProfile

                                implicitHeight: 30
                                implicitWidth: profileRow.implicitWidth + 20
                                buttonRadius: Appearance.rounding.full
                                toggled: profileChip.active
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                onClicked: Ai.setPromptProfile(profileChip.modelData.id)

                                contentItem: RowLayout {
                                    id: profileRow
                                    spacing: 5
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: profileChip.active ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer2
                                        text: profileChip.modelData.icon
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: profileChip.active ? Font.DemiBold : Font.Normal
                                        color: profileChip.active ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer2
                                        text: profileChip.modelData.name
                                    }
                                }

                                StyledToolTip { text: profileChip.modelData.summary }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.inset
                        Layout.rightMargin: root.inset
                        Layout.topMargin: 4
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Ai.promptProfileInfo?.summary ?? ""
                    }

                    // ---- Temperature ------------------------------------------

                    SectionLabel { text: Translation.tr("Temperature") }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.inset
                        Layout.rightMargin: root.inset
                        spacing: 10

                        StyledSlider {
                            id: temperatureSlider
                            Layout.fillWidth: true
                            from: 0
                            to: 2
                            stepSize: 0.05
                            value: Ai.temperature
                            // Committed on release rather than on every move: the
                            // handle travels through dozens of values on the way to
                            // the one you meant, and each was a write to disk.
                            onPressedChanged: if (!pressed) Ai.setTemperature(temperatureSlider.value)
                            onMoved: if (!pressed) Ai.setTemperature(temperatureSlider.value)
                        }

                        StyledText {
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            // Follows the handle, so the number moves with your
                            // thumb even though nothing is committed until release.
                            text: temperatureSlider.value.toFixed(2)
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.inset
                        Layout.rightMargin: root.inset
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Low is literal and repeatable; high wanders. 0.5 suits most work.")
                    }

                    // ---- Display ----------------------------------------------

                    SectionLabel { text: Translation.tr("Display") }

                    ToggleRow {
                        Layout.fillWidth: true
                        label: Translation.tr("Compact spacing")
                        hint: Translation.tr("Fits more of the conversation on screen. Text size is unchanged.")
                        checked: Ai.compactMessages
                        onToggled: enabled => Ai.setCompactMessages(enabled)
                    }

                    // ---- Keys --------------------------------------------------

                    SectionLabel { text: Translation.tr("API keys") }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.inset
                        Layout.rightMargin: root.inset
                        Layout.bottomMargin: 2
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Stored in the system keyring, never in a config file. Shown masked.")
                    }

                    Repeater {
                        model: Ai.keyProviders

                        delegate: ColumnLayout {
                            id: providerRow
                            required property var modelData
                            readonly property string storedKey: Ai.apiKeys[providerRow.modelData.id] ?? ""
                            readonly property bool hasKey: providerRow.storedKey.length > 0
                            property bool editing: false

                            Layout.fillWidth: true
                            Layout.leftMargin: root.inset
                            Layout.rightMargin: root.inset
                            Layout.bottomMargin: 6
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                MaterialSymbol {
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: providerRow.hasKey ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    text: providerRow.hasKey ? "key" : "key_off"
                                }

                                StyledText {
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                    text: providerRow.modelData.name
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    text: providerRow.hasKey ? Ai.maskKey(providerRow.storedKey)
                                        : Translation.tr("not set")
                                }

                                Item {
                                    id: checkIndicator
                                    readonly property string checkState: Ai.keyCheckState[providerRow.modelData.id] ?? ""
                                    // StyledToolTip shows unconditionally when its parent
                                    // has no `hovered` property, so anything carrying one
                                    // has to provide it.
                                    property bool hovered: checkIndicatorArea.containsMouse

                                    visible: checkIndicator.checkState.length > 0
                                    implicitWidth: 18
                                    implicitHeight: 18

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: checkIndicator.checkState === "ok" ? Appearance.colors.colPrimary
                                            : checkIndicator.checkState === "checking" ? Appearance.colors.colSubtext
                                            : Appearance.colors.colError
                                        text: checkIndicator.checkState === "ok" ? "check_circle"
                                            : checkIndicator.checkState === "checking" ? "hourglass_top"
                                            : "error"

                                        SequentialAnimation on opacity {
                                            running: checkIndicator.checkState === "checking"
                                            loops: Animation.Infinite
                                            alwaysRunToEnd: true
                                            NumberAnimation { from: 1; to: 0.4; duration: 600 }
                                            NumberAnimation { from: 0.4; to: 1; duration: 600 }
                                        }
                                    }

                                    MouseArea {
                                        id: checkIndicatorArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                    }

                                    StyledToolTip {
                                        text: (Ai.keyCheckDetail[providerRow.modelData.id] ?? "").length > 0
                                            ? Ai.keyCheckDetail[providerRow.modelData.id]
                                            : Translation.tr("The provider accepted this key")
                                    }
                                }

                                AiMessageControlButton {
                                    visible: providerRow.hasKey
                                    buttonIcon: "wifi_tethering"
                                    onClicked: Ai.verifyProviderKey(providerRow.modelData.id)
                                    StyledToolTip { text: Translation.tr("Check the key works") }
                                }

                                AiMessageControlButton {
                                    visible: providerRow.modelData.keyGetLink.length > 0 && !providerRow.hasKey
                                    buttonIcon: "open_in_new"
                                    onClicked: Qt.openUrlExternally(providerRow.modelData.keyGetLink)
                                    StyledToolTip { text: Translation.tr("Where to get one") }
                                }

                                AiMessageControlButton {
                                    activated: providerRow.editing
                                    buttonIcon: providerRow.hasKey ? "edit" : "add"
                                    onClicked: providerRow.editing = !providerRow.editing
                                    StyledToolTip {
                                        text: providerRow.hasKey ? Translation.tr("Replace key") : Translation.tr("Add key")
                                    }
                                }

                                AiMessageControlButton {
                                    id: clearKeyButton
                                    property bool armed: false
                                    visible: providerRow.hasKey
                                    buttonIcon: clearKeyButton.armed ? "delete_forever" : "delete"
                                    onClicked: {
                                        if (clearKeyButton.armed) {
                                            Ai.setProviderKey(providerRow.modelData.id, "");
                                            clearKeyButton.armed = false;
                                        } else {
                                            clearKeyButton.armed = true;
                                            clearKeyTimer.restart();
                                        }
                                    }
                                    Timer {
                                        id: clearKeyTimer
                                        interval: 2000
                                        onTriggered: clearKeyButton.armed = false
                                    }
                                    StyledToolTip {
                                        text: clearKeyButton.armed ? Translation.tr("Click again to remove")
                                            : Translation.tr("Remove key")
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: providerRow.editing
                                spacing: 6

                                MaterialTextField {
                                    id: keyField
                                    Layout.fillWidth: true
                                    // The field is write-only: it starts empty even when a
                                    // key exists, so nothing puts the stored key on screen.
                                    placeholderText: Translation.tr("Paste key, then press Enter")
                                    echoMode: TextInput.Password
                                    wrapMode: TextEdit.NoWrap
                                    onAccepted: {
                                        if (keyField.text.trim().length === 0) return;
                                        Ai.setProviderKey(providerRow.modelData.id, keyField.text);
                                        keyField.text = "";
                                        providerRow.editing = false;
                                    }
                                }
                            }
                        }
                    }

                    // ---- Memory ------------------------------------------------

                    SectionLabel { text: Translation.tr("Memory") }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.inset
                        Layout.rightMargin: root.inset
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: (Ai.memory?.count ?? 0) > 0
                            ? Translation.tr("Facts the assistant keeps between chats. Past conversations are searched separately and only pulled in when they match what you asked.")
                            : Translation.tr("Nothing remembered yet. Ask the assistant to remember something and it lands here.")
                    }

                    Repeater {
                        model: Ai.memory?.entries ?? []

                        delegate: Rectangle {
                            id: memoryRow
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.leftMargin: root.inset
                            Layout.rightMargin: root.inset
                            Layout.topMargin: 4
                            implicitHeight: Math.max(memoryText.implicitHeight + 16, 36)
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 4
                                spacing: 6

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                    text: "bookmark"
                                }

                                StyledText {
                                    id: memoryText
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                    text: memoryRow.modelData.text
                                }

                                RippleButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    buttonRadius: Appearance.rounding.full
                                    onClicked: Ai.memory.forget(memoryRow.modelData.id)
                                    contentItem: MaterialSymbol {
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "delete"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledToolTip { text: Translation.tr("Forget this") }
                                }
                            }
                        }
                    }

                    RippleButton {
                        Layout.leftMargin: root.inset
                        Layout.topMargin: 4
                        visible: (Ai.memory?.count ?? 0) > 1
                        implicitHeight: 30
                        implicitWidth: forgetAllRow.implicitWidth + 20
                        buttonRadius: Appearance.rounding.full
                        onClicked: Ai.memory.forgetAll()
                        contentItem: RowLayout {
                            id: forgetAllRow
                            spacing: 5
                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.m3colors.m3error
                                text: "delete_sweep"
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.m3colors.m3error
                                text: Translation.tr("Forget everything")
                            }
                        }
                    }

                    // ---- MCP ---------------------------------------------------

                    SectionLabel { text: Translation.tr("MCP servers") }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.inset
                        Layout.rightMargin: root.inset
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: (Ai.mcp?.toolCount ?? 0) > 0
                            ? Translation.tr("%1 tools from %2 connected servers, offered to the model alongside the built-in ones.")
                                .arg(Ai.mcp.toolCount).arg(Ai.mcp.readyCount)
                            : Translation.tr("Programs that give the assistant extra tools. Started here, spoken to over stdio.")
                    }

                    Repeater {
                        model: Ai.mcp?.servers ?? []

                        delegate: Rectangle {
                            id: serverRow
                            required property var modelData

                            readonly property string state_: serverRow.modelData.status
                            readonly property color accent: serverRow.state_ === "ready" ? Appearance.colors.colPrimary
                                : serverRow.state_ === "failed" ? Appearance.colors.colError
                                : Appearance.colors.colSubtext

                            Layout.fillWidth: true
                            Layout.leftMargin: root.inset
                            Layout.rightMargin: root.inset
                            Layout.topMargin: 4
                            implicitHeight: serverColumn.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            ColumnLayout {
                                id: serverColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: serverRow.accent
                                        text: serverRow.state_ === "ready" ? "check_circle"
                                            : serverRow.state_ === "failed" ? "error"
                                            : serverRow.state_ === "starting" ? "hourglass_top"
                                            : "radio_button_unchecked"
                                        SequentialAnimation on opacity {
                                            running: serverRow.state_ === "starting"
                                            loops: Animation.Infinite
                                            alwaysRunToEnd: true
                                            NumberAnimation { from: 1; to: 0.4; duration: 600 }
                                            NumberAnimation { from: 0.4; to: 1; duration: 600 }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer2
                                        text: serverRow.modelData.name
                                    }

                                    StyledText {
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        text: serverRow.state_ === "ready"
                                            ? Translation.tr("%1 tools").arg(serverRow.modelData.tools.length) : ""
                                    }

                                    RippleButton {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        buttonRadius: Appearance.rounding.full
                                        onClicked: serverRow.modelData.start()
                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "refresh"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledToolTip { text: Translation.tr("Reconnect") }
                                    }

                                    RippleButton {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        buttonRadius: Appearance.rounding.full
                                        onClicked: Ai.removeMcpServer(serverRow.modelData.name)
                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "delete"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledToolTip { text: Translation.tr("Remove this server") }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    text: [serverRow.modelData.command, ...(serverRow.modelData.args ?? [])].join(" ")
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colError
                                    text: serverRow.state_ === "failed" ? (serverRow.modelData.detail ?? "") : ""
                                }
                            }
                        }
                    }

                    RowLayout { // Add a server
                        Layout.fillWidth: true
                        Layout.leftMargin: root.inset
                        Layout.rightMargin: root.inset
                        Layout.topMargin: 6
                        spacing: 6

                        MaterialTextField {
                            id: mcpNameField
                            Layout.preferredWidth: 100
                            placeholderText: Translation.tr("Name")
                            wrapMode: TextEdit.NoWrap
                        }

                        MaterialTextField {
                            id: mcpCommandField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Command, e.g. npx -y @foo/mcp")
                            wrapMode: TextEdit.NoWrap
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    addMcpButton.clicked();
                                    event.accepted = true;
                                }
                            }
                        }

                        RippleButton {
                            id: addMcpButton
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            enabled: mcpNameField.text.trim().length > 0 && mcpCommandField.text.trim().length > 0
                            onClicked: {
                                if (!enabled) return;
                                Ai.addMcpServer(mcpNameField.text.trim(), mcpCommandField.text.trim());
                                mcpNameField.text = "";
                                mcpCommandField.text = "";
                            }
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "add"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledToolTip { text: Translation.tr("Add server") }
                        }
                    }

                    // ---- Chat --------------------------------------------------

                    SectionLabel { text: Translation.tr("This chat") }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.inset
                        Layout.rightMargin: root.inset
                        Layout.bottomMargin: 10
                        spacing: 8

                        RippleButton {
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            enabled: Ai.messageIDs.length > 0
                            onClicked: {
                                Ai.exportChat();
                                root.close();
                            }
                            contentItem: RowLayout {
                                spacing: 5
                                MaterialSymbol {
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer2
                                    text: "download"
                                }
                                StyledText {
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                    text: Translation.tr("Export as Markdown")
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    component SectionLabel: StyledText {
        Layout.fillWidth: true
        // A section heading belongs to what follows it, so it sits closer to its
        // own content than to the section it ends. At 12 above and 2 below it
        // read as the tail of the section before.
        Layout.topMargin: 20
        Layout.bottomMargin: 6
        Layout.leftMargin: root.inset
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        color: Appearance.colors.colSubtext
    }

    component ToggleRow: Rectangle {
        id: toggleRoot
        property string label: ""
        property string hint: ""
        property bool checked: false
        signal toggled(bool enabled)

        implicitHeight: toggleColumn.implicitHeight + 16
        radius: Appearance.rounding.small
        color: toggleArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"

        MouseArea {
            id: toggleArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toggleRoot.toggled(!toggleRoot.checked)
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            anchors.leftMargin: 10
            spacing: 10

            ColumnLayout {
                id: toggleColumn
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: toggleRoot.label
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: toggleRoot.hint.length > 0
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: toggleRoot.hint
                }
            }

            StyledSwitch {
                checked: toggleRoot.checked
                onToggled: toggleRoot.toggled(checked)
            }
        }
    }
}
