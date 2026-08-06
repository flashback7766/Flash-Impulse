import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "contrast"
        title: Translation.tr("Light or dark")
        description: Translation.tr("Auto follows sunrise and sunset for your timezone. The coordinates come from the zone name, so there is no network call and nothing to configure.")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            uniformCellSizes: true

            ThemeModeButton {
                mode: "light"
            }
            ThemeModeButton {
                mode: "dark"
            }
            ThemeModeButton {
                mode: "auto"
            }
        }
    }

    ContentSection {
        icon: "wallpaper"
        title: Translation.tr("Wallpaper")
        description: Translation.tr("Everything else takes its colors from whatever you pick")

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Item {
                implicitWidth: 280
                implicitHeight: 158

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
                spacing: 8

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "wallpaper"
                    mainText: Translation.tr("Choose file")
                    onClicked: Quickshell.execDetached(`${Directories.wallpaperSwitchScriptPath}`)
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Later on: Ctrl+Super+T, or /wallpaper in the launcher.")
                }
            }
        }
    }
}
