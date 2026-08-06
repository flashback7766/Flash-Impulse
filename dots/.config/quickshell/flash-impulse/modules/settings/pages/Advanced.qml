import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The settings that exist because some other piece of software misbehaves.
 */
ContentPage {
    forceWidth: true

    ContentSection {
        icon: "web_asset"
        title: Translation.tr("Shell windows")
        description: Translation.tr("Titlebars drawn by the shell's own apps — this window included")

        ConfigSwitch {
            buttonIcon: "toolbar"
            text: Translation.tr("Show titlebar")
            checked: Config.options.windows.showTitlebar
            onCheckedChanged: {
                Config.options.windows.showTitlebar = checked;
            }
        }
        ConfigSwitch {
            enabled: Config.options.windows.showTitlebar
            buttonIcon: "format_align_center"
            text: Translation.tr("Center the title")
            checked: Config.options.windows.centerTitle
            onCheckedChanged: {
                Config.options.windows.centerTitle = checked;
            }
        }
    }

    ContentSection {
        icon: "block"
        title: Translation.tr("Conflicting programs")
        description: Translation.tr("Two notification daemons or two trays on one session fight over the same D-Bus name — one of them silently loses")

        ConfigSwitch {
            buttonIcon: "notifications_off"
            text: Translation.tr("Kill other notification daemons on startup")
            checked: Config.options.conflictKiller.autoKillNotificationDaemons
            onCheckedChanged: {
                Config.options.conflictKiller.autoKillNotificationDaemons = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "shelf_auto_hide"
            text: Translation.tr("Kill other system trays on startup")
            checked: Config.options.conflictKiller.autoKillTrays
            onCheckedChanged: {
                Config.options.conflictKiller.autoKillTrays = checked;
            }
        }
    }

    ContentSection {
        icon: "play_circle"
        title: Translation.tr("Media players")

        ConfigSwitch {
            buttonIcon: "filter_alt"
            text: Translation.tr("Filter duplicate players")
            checked: Config.options.media.filterDuplicatePlayers
            onCheckedChanged: {
                Config.options.media.filterDuplicatePlayers = checked;
            }
            StyledToolTip {
                text: Translation.tr("Browsers with Plasma integration announce themselves twice — once natively and once through the playerctl aggregator")
            }
        }
    }

    ContentSection {
        icon: "bug_report"
        title: Translation.tr("Timing hacks")

        ConfigSpinBox {
            icon: "hourglass"
            text: Translation.tr("Race condition delay (ms)")
            value: Config.options.hacks.arbitraryRaceConditionDelay
            from: 0
            to: 1000
            stepSize: 5
            onValueChanged: {
                Config.options.hacks.arbitraryRaceConditionDelay = value;
            }
            StyledToolTip {
                text: Translation.tr("Padding the shell waits out before reading state that another process has just written. Raise it if things occasionally come up with stale values.")
            }
        }
    }
}
