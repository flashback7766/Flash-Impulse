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
        icon: "toast"
        title: Translation.tr("The bar")
        description: Translation.tr("Where it sits and what shape it takes")

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
                        value: 0
                    },
                    {
                        displayName: Translation.tr("Left"),
                        icon: "arrow_back",
                        value: 2
                    },
                    {
                        displayName: Translation.tr("Bottom"),
                        icon: "arrow_downward",
                        value: 1
                    },
                    {
                        displayName: Translation.tr("Right"),
                        icon: "arrow_forward",
                        value: 3
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

    ContentSection {
        icon: "rounded_corner"
        title: Translation.tr("Screen corners")
        description: Translation.tr("Rounds the corners of the display itself, for panels that hug the edge")

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
