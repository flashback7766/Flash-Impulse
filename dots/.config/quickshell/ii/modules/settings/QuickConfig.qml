import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    forceWidth: true


    // Light / Dark / Auto. Picking a side turns following the sun off — the
    // choice you just made by hand should be the one that sticks.
    component SmallLightDarkPreferenceButton: RippleButton {
        id: smallLightDarkPreferenceButton
        required property string mode
        readonly property bool isAuto: mode === "auto"
        property color colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        padding: 5
        Layout.fillWidth: true
        toggled: isAuto ? Config.options.appearance.autoTheme.enable : (!Config.options.appearance.autoTheme.enable && Appearance.m3colors.darkmode === (mode === "dark"))
        colBackground: Appearance.colors.colLayer2
        onClicked: {
            if (isAuto) {
                Config.options.appearance.autoTheme.enable = true;
                return;
            }
            Config.options.appearance.autoTheme.enable = false;
            Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${mode} --noswitch`]);
        }
        contentItem: Item {
            anchors.centerIn: parent
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 30
                    text: smallLightDarkPreferenceButton.isAuto ? "routine" : (smallLightDarkPreferenceButton.mode === "dark" ? "dark_mode" : "light_mode")
                    color: smallLightDarkPreferenceButton.colText
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: smallLightDarkPreferenceButton.isAuto ? Translation.tr("Auto") : (smallLightDarkPreferenceButton.mode === "dark" ? Translation.tr("Dark") : Translation.tr("Light"))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: smallLightDarkPreferenceButton.colText
                }
            }
        }
    }

    // Wallpaper selection
    ContentSection {
        icon: "format_paint"
        title: Translation.tr("Wallpaper & Colors")
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true

            Item {
                implicitWidth: 340
                implicitHeight: 200
                
                StyledImage {
                    id: wallpaperPreview
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: Config.options.background.wallpaperPath
                    cache: false
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: 360
                            height: 200
                            radius: Appearance.rounding.normal
                        }
                    }
                }
            }

            ColumnLayout {
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "wallpaper"
                    StyledToolTip {
                        text: Translation.tr("Pick wallpaper image on your system")
                    }
                    onClicked: {
                        Quickshell.execDetached(`${Directories.wallpaperSwitchScriptPath}`);
                    }
                    mainContentComponent: Component {
                        RowLayout {
                            spacing: 10
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                text: Translation.tr("Choose file")
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            RowLayout {
                                spacing: 3
                                KeyboardKey {
                                    key: "Ctrl"
                                }
                                KeyboardKey {
                                    key: Config.options.cheatsheet.superKey ?? "󰖳"
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "+"
                                }
                                KeyboardKey {
                                    key: "T"
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    uniformCellSizes: true

                    SmallLightDarkPreferenceButton {
                        Layout.fillHeight: true
                        mode: "light"
                    }
                    SmallLightDarkPreferenceButton {
                        Layout.fillHeight: true
                        mode: "dark"
                    }
                    SmallLightDarkPreferenceButton {
                        Layout.fillHeight: true
                        mode: "auto"
                    }
                }
            }
        }

        // Only worth showing once Auto is picked; collapses out of the way again.
        // Not the Revealer widget: it sizes itself from childrenRect, and a child
        // that fills the width would then be defining the width it reads back.
        Item {
            id: autoThemeOptions
            Layout.fillWidth: true
            clip: true
            readonly property bool shown: Config.options.appearance.autoTheme.enable
            implicitHeight: shown ? autoThemeColumn.implicitHeight : 0
            visible: implicitHeight > 0
            opacity: shown ? 1 : 0
            Behavior on implicitHeight {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: autoThemeColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                spacing: 10

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.autoTheme.mode
                    onSelected: newValue => {
                        Config.options.appearance.autoTheme.mode = newValue;
                    }
                    options: [
                        {
                            value: "sun",
                            icon: "wb_twilight",
                            displayName: Translation.tr("Sunset")
                        },
                        {
                            value: "schedule",
                            icon: "schedule",
                            displayName: Translation.tr("Schedule")
                        }
                    ]
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: Config.options.appearance.autoTheme.mode === "sun"

                    MaterialSymbol {
                        text: AutoTheme.hasLocation ? "location_on" : "location_off"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                        text: AutoTheme.hasLocation ? Translation.tr("%1 — sunrise %2, sunset %3").arg(AutoTheme.locationName).arg(AutoTheme.sunriseText).arg(AutoTheme.sunsetText) : Translation.tr("No coordinates for this timezone — using the schedule below")
                    }
                    MaterialTextField {
                        Layout.preferredWidth: 200
                        placeholderText: Translation.tr("Timezone or lat,lon")
                        text: Config.options.appearance.autoTheme.location
                        onEditingFinished: {
                            Config.options.appearance.autoTheme.location = text.trim();
                        }
                        StyledToolTip {
                            text: Translation.tr("Leave empty to follow the system timezone. Otherwise a zone name like Europe/Moscow, or coordinates like 40.18,44.51")
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: Config.options.appearance.autoTheme.mode !== "sun" || !AutoTheme.hasLocation

                    StyledText {
                        text: Translation.tr("Light at")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    MaterialTextField {
                        Layout.preferredWidth: 90
                        text: Config.options.appearance.autoTheme.lightTime
                        inputMask: "99:99"
                        onEditingFinished: {
                            Config.options.appearance.autoTheme.lightTime = text;
                        }
                    }
                    StyledText {
                        Layout.leftMargin: 10
                        text: Translation.tr("Dark at")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    MaterialTextField {
                        Layout.preferredWidth: 90
                        text: Config.options.appearance.autoTheme.darkTime
                        inputMask: "99:99"
                        onEditingFinished: {
                            Config.options.appearance.autoTheme.darkTime = text;
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }

        ConfigSelectionArray {
            currentValue: Config.options.appearance.palette.type
            onSelected: newValue => {
                Config.options.appearance.palette.type = newValue;
                Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`]);
            }
            options: [
                {
                    "value": "auto",
                    "displayName": Translation.tr("Auto")
                },
                {
                    "value": "scheme-content",
                    "displayName": Translation.tr("Content")
                },
                {
                    "value": "scheme-expressive",
                    "displayName": Translation.tr("Expressive")
                },
                {
                    "value": "scheme-fidelity",
                    "displayName": Translation.tr("Fidelity")
                },
                {
                    "value": "scheme-fruit-salad",
                    "displayName": Translation.tr("Fruit Salad")
                },
                {
                    "value": "scheme-monochrome",
                    "displayName": Translation.tr("Monochrome")
                },
                {
                    "value": "scheme-neutral",
                    "displayName": Translation.tr("Neutral")
                },
                {
                    "value": "scheme-rainbow",
                    "displayName": Translation.tr("Rainbow")
                },
                {
                    "value": "scheme-tonal-spot",
                    "displayName": Translation.tr("Tonal Spot")
                }
            ]
        }

        ConfigSwitch {
            buttonIcon: "ev_shadow"
            text: Translation.tr("Transparency")
            checked: Config.options.appearance.transparency.enable
            onCheckedChanged: {
                Config.options.appearance.transparency.enable = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "speed"
            text: Translation.tr("Performance mode")
            // Same layout and colours, cheaper effects — for GPUs that struggle
            // with full-strength blur.
            enabled: !PerformanceMode.busy
            checked: PerformanceMode.enabled
            onCheckedChanged: PerformanceMode.setEnabled(checked)
        }
    }

    ContentSection {
        icon: "screenshot_monitor"
        title: Translation.tr("Bar & screen")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")
                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Bar style")

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        }
                    ]
                }
            }
        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Screen round corner")

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.fakeScreenRounding
                    onSelected: newValue => {
                        Config.options.appearance.fakeScreenRounding = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("When not fullscreen"),
                            icon: "fullscreen_exit",
                            value: 2
                        }
                    ]
                }
            }
            
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        text: Translation.tr('Not all options are available in this app. You should also check the config file by hitting the "Config file" button on the topleft corner or opening %1 manually.').arg(Directories.shellConfigPath)

        Item {
            Layout.fillWidth: true
        }
        RippleButtonWithIcon {
            id: copyPathButton
            property bool justCopied: false
            Layout.fillWidth: false
            buttonRadius: Appearance.rounding.small
            materialIcon: justCopied ? "check" : "content_copy"
            mainText: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy path")
            onClicked: {
                copyPathButton.justCopied = true
                Quickshell.clipboardText = FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                revertTextTimer.restart();
            }
            colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive

            Timer {
                id: revertTextTimer
                interval: 1500
                onTriggered: {
                    copyPathButton.justCopied = false
                }
            }
        }
    }
}
