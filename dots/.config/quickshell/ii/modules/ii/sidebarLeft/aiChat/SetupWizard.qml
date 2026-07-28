pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * First run: pick a provider, paste a key, check it works.
 *
 * Before this, a fresh install answered the first message with an API error and
 * left the user to work out that `/key` existed. It appears only while no
 * provider has a key at all, and it can be dismissed — a local model through
 * Ollama needs none of this.
 */
Item {
    id: root

    property bool dismissed: false
    readonly property bool shown: Ai.needsSetup && !root.dismissed

    property string chosenProvider: ""
    readonly property var provider: Ai.keyProviders.find(p => p.id === root.chosenProvider) ?? null
    readonly property string checkState: Ai.keyCheckState[root.chosenProvider] ?? ""
    readonly property string checkDetail: Ai.keyCheckDetail[root.chosenProvider] ?? ""

    // Descriptions live here rather than in the model catalogue: this is about
    // choosing a provider, not a model, and the catalogue's blurbs are per-model.
    readonly property var providerBlurbs: ({
        "gemini": Translation.tr("Generous free tier. The easiest place to start."),
        "anthropic": Translation.tr("Strongest at code and long reasoning. Paid."),
        "openai": Translation.tr("Broad and dependable. Paid."),
        "openrouter": Translation.tr("One key for many providers' models. Paid.")
    })

    visible: opacity > 0
    enabled: root.shown
    opacity: root.shown ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onShownChanged: if (!root.shown) root.chosenProvider = ""

    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3surfaceContainerLow
        radius: Appearance.rounding.normal

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            anchors.topMargin: 40
            spacing: 10

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 44
                color: Appearance.colors.colPrimary
                text: "auto_awesome"
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: root.provider ? Translation.tr("Connect %1").arg(root.provider.name)
                    : Translation.tr("Pick a provider")
            }

            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: root.provider
                    ? Translation.tr("Paste the key below. It goes into the system keyring, not into any config file.")
                    : Translation.tr("The assistant needs a key from one of these. You can add the others later.")
            }

            // ---- step 1: provider ------------------------------------------

            Repeater {
                model: root.provider ? [] : Ai.keyProviders

                delegate: Rectangle {
                    id: providerCard
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: providerColumn.implicitHeight + 20
                    radius: Appearance.rounding.small
                    color: providerArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MouseArea {
                        id: providerArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.chosenProvider = providerCard.modelData.id
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        anchors.leftMargin: 14
                        spacing: 10

                        ColumnLayout {
                            id: providerColumn
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer2
                                text: providerCard.modelData.name
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: root.providerBlurbs[providerCard.modelData.id] ?? ""
                            }
                        }

                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                            text: "chevron_right"
                        }
                    }
                }
            }

            // ---- step 2: key -----------------------------------------------

            MaterialTextField {
                id: keyField
                Layout.fillWidth: true
                visible: root.provider !== null
                placeholderText: Translation.tr("Paste your API key")
                echoMode: TextInput.Password
                wrapMode: TextEdit.NoWrap
                onAccepted: root.saveAndCheck()
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.provider !== null
                spacing: 8

                RippleButton {
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    visible: (root.provider?.keyGetLink ?? "").length > 0
                    onClicked: Qt.openUrlExternally(root.provider.keyGetLink)
                    contentItem: RowLayout {
                        spacing: 5
                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                            text: "open_in_new"
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            text: Translation.tr("Get a key")
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    toggled: true
                    enabled: keyField.text.trim().length > 0 && root.checkState !== "checking"
                    onClicked: root.saveAndCheck()
                    contentItem: RowLayout {
                        spacing: 5
                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimary
                            text: root.checkState === "checking" ? "hourglass_top" : "check"
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnPrimary
                            text: root.checkState === "checking" ? Translation.tr("Checking…") : Translation.tr("Save and check")
                        }
                    }
                }
            }

            // ---- step 3: verdict --------------------------------------------

            Rectangle {
                Layout.fillWidth: true
                visible: root.provider !== null && root.checkState.length > 0 && root.checkState !== "checking"
                implicitHeight: verdictRow.implicitHeight + 16
                radius: Appearance.rounding.small
                color: root.checkState === "ok" ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colErrorContainer

                RowLayout {
                    id: verdictRow
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.leftMargin: 12
                    spacing: 8

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        iconSize: Appearance.font.pixelSize.large
                        color: root.checkState === "ok" ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnErrorContainer
                        text: root.checkState === "ok" ? "check_circle" : "error"
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.checkState === "ok" ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnErrorContainer
                        text: root.checkState === "ok"
                            ? Translation.tr("Key works. You're set up.")
                            : root.checkDetail
                    }
                }
            }

            // ---- footer ------------------------------------------------------

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8

                RippleButton {
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    visible: root.provider !== null
                    onClicked: root.chosenProvider = ""
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Back")
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.dismissed = true
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        // Local models need no key at all, so this can't be a wall.
                        text: Translation.tr("Skip — I'll use a local model")
                    }
                }
            }
        }
    }

    function saveAndCheck() {
        if (!root.provider || keyField.text.trim().length === 0) return;
        Ai.setProviderKey(root.provider.id, keyField.text);
        keyField.text = "";
        Ai.verifyProviderKey(root.provider.id);
    }

    Connections {
        target: Ai
        function onKeyChecked(providerId, state) {
            if (providerId !== root.chosenProvider || state !== "ok") return;
            // Land on a model the new key can actually drive.
            const model = root.provider?.exampleModel;
            if (model) Ai.setModel(model, false, true);
            dismissTimer.restart();
        }
    }

    Timer {
        id: dismissTimer
        // Long enough to read "Key works" before the wizard gets out of the way.
        interval: 1400
        onTriggered: root.dismissed = true
    }
}
