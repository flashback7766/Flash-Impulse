import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The landing page: the things people actually change, and nothing else.
 *
 * Everything here is duplicated from a dedicated page — deliberately. A first
 * screen that only points elsewhere makes you navigate before you can do
 * anything, and these four are what nearly every session is about.
 */
ContentPage {
    forceWidth: true

    ContentSection {
        icon: "format_paint"
        title: Translation.tr("Look")
        description: Translation.tr("Wallpaper and theme. Everything else in the shell takes its colors from here.")

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Item {
                implicitWidth: 300
                implicitHeight: 170

                StyledImage {
                    id: wallpaperPreview
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: Config.options.background.wallpaperPath
                    cache: false
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: wallpaperPreview.width
                            height: wallpaperPreview.height
                            radius: Appearance.rounding.normal
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "wallpaper"
                    onClicked: Quickshell.execDetached(`${Directories.wallpaperSwitchScriptPath}`)

                    StyledToolTip {
                        text: Translation.tr("Pick wallpaper image on your system")
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
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8
                    uniformCellSizes: true

                    ThemeModeButton {
                        Layout.fillHeight: true
                        mode: "light"
                    }
                    ThemeModeButton {
                        Layout.fillHeight: true
                        mode: "dark"
                    }
                    ThemeModeButton {
                        Layout.fillHeight: true
                        mode: "auto"
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "toast"
        title: Translation.tr("Bar")
        description: Translation.tr("Where the bar sits, and what shape it takes")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Position")

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
                title: Translation.tr("Style")

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue;
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
    }

    ContentSection {
        icon: "speed"
        title: Translation.tr("Performance")

        ConfigSwitch {
            buttonIcon: "speed"
            text: Translation.tr("Performance mode")
            // Same layout and colours, cheaper effects — for GPUs that struggle
            // with full-strength blur.
            enabled: !PerformanceMode.busy
            checked: PerformanceMode.enabled
            onCheckedChanged: PerformanceMode.setEnabled(checked)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Keeps the layout, shapes and colors, but uses cheaper blur, drops window shadows and shortens animations.")
        }
    }

    ContentSection {
        icon: "help"
        title: Translation.tr("Getting around")
        card: false

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                materialIcon: "keyboard_alt"
                mainText: Translation.tr("Keybinds")
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "cheatsheet", "toggle"])
            }
            RippleButtonWithIcon {
                materialIcon: "help"
                mainText: Translation.tr("Usage guide")
                onClicked: Qt.openUrlExternally("https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/")
            }
            RippleButtonWithIcon {
                materialIcon: "construction"
                mainText: Translation.tr("Configuration reference")
                onClicked: Qt.openUrlExternally("https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/03config/")
            }
        }

    }
}
