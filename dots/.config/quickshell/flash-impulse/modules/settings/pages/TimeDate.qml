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
        icon: "nest_clock_farsight_analog"
        title: Translation.tr("Clock")

        ConfigSwitch {
            buttonIcon: "pace"
            text: Translation.tr("Second precision")
            checked: Config.options.time.secondPrecision
            onCheckedChanged: {
                Config.options.time.secondPrecision = checked;
            }
            StyledToolTip {
                text: Translation.tr("Enable if you want clocks to show seconds accurately")
            }
        }

        ContentSubsection {
            title: Translation.tr("Format")
            tooltip: ""

            ConfigSelectionArray {
                currentValue: Config.options.time.format
                onSelected: newValue => {
                    if (newValue === "hh:mm") {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    } else {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    }

                    Config.options.time.format = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("24h"),
                        value: "hh:mm"
                    },
                    {
                        displayName: Translation.tr("12h am/pm"),
                        value: "h:mm ap"
                    },
                    {
                        displayName: Translation.tr("12h AM/PM"),
                        value: "h:mm AP"
                    },
                ]
            }
        }
    }

    ContentSection {
        icon: "calendar_month"
        title: Translation.tr("Date")
        description: Translation.tr("Qt date format strings — d/M/y for numbers, ddd/MMM for names")

        ConfigTextField {
            buttonIcon: "calendar_view_day"
            text: Translation.tr("Short date")
            placeholder: "dd/MM"
            fieldWidth: 180
            value: Config.options.time.shortDateFormat
            onEdited: newValue => Config.options.time.shortDateFormat = newValue
        }
        ConfigTextField {
            buttonIcon: "event"
            text: Translation.tr("Date")
            placeholder: "ddd, dd/MM"
            fieldWidth: 180
            value: Config.options.time.dateFormat
            onEdited: newValue => Config.options.time.dateFormat = newValue
        }
        ConfigTextField {
            buttonIcon: "calendar_month"
            text: Translation.tr("Date with year")
            placeholder: "dd/MM/yyyy"
            fieldWidth: 180
            value: Config.options.time.dateWithYearFormat
            onEdited: newValue => Config.options.time.dateWithYearFormat = newValue
        }
        ConfigTextField {
            buttonIcon: "public"
            text: Translation.tr("Calendar locale")
            placeholder: "en-GB"
            fieldWidth: 180
            value: Config.options.calendar.locale
            onEdited: newValue => Config.options.calendar.locale = newValue
            StyledToolTip {
                text: Translation.tr("Decides which day the week starts on, and how month names are spelled")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            spacing: 8

            MaterialSymbol {
                text: "preview"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                // Reading a format string is not the same as seeing what it does.
                text: Translation.tr("Now: %1 · %2 · %3").arg(DateTime.shortDate).arg(DateTime.longDate).arg(DateTime.date)
            }
        }
    }

    ContentSection {
        icon: "timer"
        title: Translation.tr("Pomodoro")
        description: Translation.tr("The timer in the right sidebar")

        ConfigSpinBox {
            icon: "target"
            text: Translation.tr("Focus (minutes)")
            value: Math.round(Config.options.time.pomodoro.focus / 60)
            from: 1
            to: 180
            stepSize: 1
            onValueChanged: {
                Config.options.time.pomodoro.focus = value * 60;
            }
        }
        ConfigSpinBox {
            icon: "coffee"
            text: Translation.tr("Break (minutes)")
            value: Math.round(Config.options.time.pomodoro.breakTime / 60)
            from: 1
            to: 120
            stepSize: 1
            onValueChanged: {
                Config.options.time.pomodoro.breakTime = value * 60;
            }
        }
        ConfigSpinBox {
            icon: "airline_seat_recline_extra"
            text: Translation.tr("Long break (minutes)")
            value: Math.round(Config.options.time.pomodoro.longBreak / 60)
            from: 1
            to: 180
            stepSize: 1
            onValueChanged: {
                Config.options.time.pomodoro.longBreak = value * 60;
            }
        }
        ConfigSpinBox {
            icon: "repeat"
            text: Translation.tr("Cycles before a long break")
            value: Config.options.time.pomodoro.cyclesBeforeLongBreak
            from: 1
            to: 12
            stepSize: 1
            onValueChanged: {
                Config.options.time.pomodoro.cyclesBeforeLongBreak = value;
            }
        }
    }
}
