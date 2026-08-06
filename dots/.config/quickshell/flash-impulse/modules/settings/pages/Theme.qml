import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
        description: Translation.tr("Auto follows sunrise and sunset for your timezone — no network call, no API key")

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

        // Only worth showing once Auto is picked; collapses out of the way again.
        // Not the Revealer widget: it sizes itself from childrenRect, and a child
        // that fills the width would then be defining the width it reads back.
        Item {
            id: autoThemeOptions
            readonly property bool shown: Config.options.appearance.autoTheme.enable

            Layout.fillWidth: true
            Layout.topMargin: shown ? 8 : 0
            clip: true
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
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Palette")
        description: Translation.tr("How Material colors are derived from the wallpaper")

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

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 6
            spacing: 10

            MaterialSymbol {
                text: "colorize"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Accent color")
                color: Appearance.colors.colOnSecondaryContainer
            }
            // The swatch is the only way to tell a typo'd hex from a valid one
            // before the whole shell recolors around it.
            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: Appearance.rounding.full
                color: accentField.acceptableInput && accentField.text.length > 0 ? accentField.text : "transparent"
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
            }
            MaterialTextField {
                id: accentField
                Layout.preferredWidth: 160
                placeholderText: Translation.tr("Follow wallpaper")
                text: Config.options.appearance.palette.accentColor
                validator: RegularExpressionValidator {
                    regularExpression: /^(#[0-9a-fA-F]{6})?$/
                }
                onEditingFinished: {
                    Config.options.appearance.palette.accentColor = text.trim();
                    Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`]);
                }
                StyledToolTip {
                    text: Translation.tr("A #rrggbb color to build the palette around. Leave empty to take it from the wallpaper instead.")
                }
            }
        }
    }


    ContentSection {
        icon: "deployed_code"
        title: Translation.tr("Surfaces")

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Animate theme changes")
            checked: Config.options.appearance.themeTransition
            onCheckedChanged: {
                Config.options.appearance.themeTransition = checked;
            }
            StyledToolTip {
                text: Translation.tr("Freezes the screen while the new palette is generated and reveals it from where you clicked. Off switches live, relayout and all.")
            }
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
            enabled: Config.options.appearance.transparency.enable
            buttonIcon: "auto_fix"
            text: Translation.tr("Pick the amount automatically")
            checked: Config.options.appearance.transparency.automatic
            onCheckedChanged: {
                Config.options.appearance.transparency.automatic = checked;
            }
            StyledToolTip {
                text: Translation.tr("Derives it from how vibrant the wallpaper is — a busy wallpaper gets less transparency so text stays readable")
            }
        }

        ConfigSlider {
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            buttonIcon: "layers"
            text: Translation.tr("Background")
            textWidth: 150
            showValue: true
            usePercentTooltip: true
            from: 0
            to: 1
            value: Config.options.appearance.transparency.backgroundTransparency
            onValueChanged: {
                Config.options.appearance.transparency.backgroundTransparency = value;
            }
        }
        ConfigSlider {
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            buttonIcon: "content_copy"
            text: Translation.tr("Content")
            textWidth: 150
            showValue: true
            usePercentTooltip: true
            from: 0
            to: 1
            value: Config.options.appearance.transparency.contentTransparency
            onValueChanged: {
                Config.options.appearance.transparency.contentTransparency = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "invert_colors"
            text: Translation.tr("Tint backgrounds with the accent")
            checked: Config.options.appearance.extraBackgroundTint
            onCheckedChanged: {
                Config.options.appearance.extraBackgroundTint = checked;
            }
            StyledToolTip {
                text: Translation.tr("Mixes a trace of the primary color into flat backgrounds instead of leaving them neutral grey")
            }
        }

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
