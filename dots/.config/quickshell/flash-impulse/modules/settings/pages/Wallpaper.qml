import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "wallpaper"
        title: Translation.tr("Wallpaper")

        ConfigSwitch {
            buttonIcon: "brightness_6"
            text: Translation.tr('Match wallpaper to light/dark theme')
            checked: Config.options.background.themeWallpaper.enable
            onCheckedChanged: {
                Config.options.background.themeWallpaper.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Swaps between a light and a dark cut of the same wallpaper whenever the theme changes.\nOnly applies while one of the pair is set — pick a wallpaper of your own and the theme leaves it alone.")
            }
        }

        ContentSubsectionLabel {
            visible: Config.options.background.themeWallpaper.enable && !Wallpapers.themeWallpaperActive
            text: Translation.tr("Currently on a wallpaper of your own, so the theme isn't changing it.")
        }

        ConfigTextField {
            enabled: Config.options.background.themeWallpaper.enable
            buttonIcon: "light_mode"
            text: Translation.tr("Light wallpaper")
            fieldWidth: 300
            value: Config.options.background.themeWallpaper.light
            onEdited: newValue => Config.options.background.themeWallpaper.light = newValue
        }
        ConfigTextField {
            enabled: Config.options.background.themeWallpaper.enable
            buttonIcon: "dark_mode"
            text: Translation.tr("Dark wallpaper")
            fieldWidth: 300
            value: Config.options.background.themeWallpaper.dark
            onEdited: newValue => Config.options.background.themeWallpaper.dark = newValue
        }

        ConfigSwitch {
            buttonIcon: "fullscreen"
            text: Translation.tr("Hide when a window is fullscreen")
            checked: Config.options.background.hideWhenFullscreen
            onCheckedChanged: {
                Config.options.background.hideWhenFullscreen = checked;
            }
            StyledToolTip {
                text: Translation.tr("Stops the wallpaper and its widgets from being composited under a fullscreen window that already covers them")
            }
        }

        ConfigTextField {
            buttonIcon: "image"
            text: Translation.tr("Current wallpaper")
            fieldWidth: 300
            value: Config.options.background.wallpaperPath
            onEdited: newValue => Config.options.background.wallpaperPath = newValue
            StyledToolTip {
                text: Translation.tr("Normally set for you by the picker (Ctrl+Super+T). Editable here for scripts and for video wallpapers.")
            }
        }
        ConfigTextField {
            buttonIcon: "thumbnail_bar"
            text: Translation.tr("Video thumbnail")
            fieldWidth: 300
            value: Config.options.background.thumbnailPath
            onEdited: newValue => Config.options.background.thumbnailPath = newValue
            StyledToolTip {
                text: Translation.tr("A still frame used to derive colors when the wallpaper is a video — a video file has no single frame to quantize")
            }
        }
    }

    ContentSection {
        icon: "sync_alt"
        title: Translation.tr("Parallax")

        ConfigSwitch {
            buttonIcon: "unfold_more_double"
            text: Translation.tr("Vertical")
            checked: Config.options.background.parallax.vertical
            onCheckedChanged: {
                Config.options.background.parallax.vertical = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Vertical only when the wallpaper is taller than the screen")
            checked: Config.options.background.parallax.autoVertical
            onCheckedChanged: {
                Config.options.background.parallax.autoVertical = checked;
            }
            StyledToolTip {
                text: Translation.tr("A wallpaper that already fits vertically has nothing to pan, so panning it just crops the image")
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr("Depends on workspace")
                checked: Config.options.background.parallax.enableWorkspace
                onCheckedChanged: {
                    Config.options.background.parallax.enableWorkspace = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "side_navigation"
                text: Translation.tr("Depends on sidebars")
                checked: Config.options.background.parallax.enableSidebar
                onCheckedChanged: {
                    Config.options.background.parallax.enableSidebar = checked;
                }
            }
        }
        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Preferred wallpaper zoom (%)")
            value: Config.options.background.parallax.workspaceZoom * 100
            from: 10
            to: 200
            stepSize: 1
            onValueChanged: {
                Config.options.background.parallax.workspaceZoom = value / 100;
            }
        }
        ConfigSlider {
            buttonIcon: "widgets"
            text: Translation.tr("Widget parallax")
            textWidth: 170
            showValue: true
            from: 0
            to: 2
            value: Config.options.background.parallax.widgetsFactor
            onValueChanged: {
                Config.options.background.parallax.widgetsFactor = value;
            }
            StyledToolTip {
                text: Translation.tr("How far the desktop clock and weather move relative to the wallpaper. 0 pins them in place.")
            }
        }
    }

    ContentSection {
        icon: "wallpaper_slideshow"
        title: Translation.tr("Wallpaper selector")

        ConfigSwitch {
            buttonIcon: "ad"
            text: Translation.tr('Use system file picker')
            checked: Config.options.wallpaperSelector.useSystemFileDialog
            onCheckedChanged: {
                Config.options.wallpaperSelector.useSystemFileDialog = checked;
            }
        }
    }
}
