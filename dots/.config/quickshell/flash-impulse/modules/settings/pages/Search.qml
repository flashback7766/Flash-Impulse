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
        icon: "search"
        title: Translation.tr("Behaviour")

        ConfigSwitch {
            text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
            checked: Config.options.search.sloppy
            onCheckedChanged: {
                Config.options.search.sloppy = checked;
            }
            StyledToolTip {
                text: Translation.tr("Could be better if you make a ton of typos,\nbut results can be weird and might not work with acronyms\n(e.g. \"GIMP\" might not give you the paint program)")
            }
        }

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Delay before non-app results (ms)")
            value: Config.options.search.nonAppResultDelay
            from: 0
            to: 500
            stepSize: 10
            onValueChanged: {
                Config.options.search.nonAppResultDelay = value;
            }
            StyledToolTip {
                text: Translation.tr("Apps come from a list already in memory; everything else costs a query. Waiting a moment keeps typing from firing one per keystroke.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Prefixes")

            ConfigSwitch {
                buttonIcon: "bolt"
                text: Translation.tr("Show default actions without a prefix")
                checked: Config.options.search.prefix.showDefaultActionsWithoutPrefix
                onCheckedChanged: {
                    Config.options.search.prefix.showDefaultActionsWithoutPrefix = checked;
                }
            }

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("App")
                    text: Config.options.search.prefix.app
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.app = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Action")
                    text: Config.options.search.prefix.action
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.action = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Clipboard")
                    text: Config.options.search.prefix.clipboard
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.clipboard = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Emojis")
                    text: Config.options.search.prefix.emojis
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.emojis = text;
                    }
                }
            }

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Math")
                    text: Config.options.search.prefix.math
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.math = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Shell command")
                    text: Config.options.search.prefix.shellCommand
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.shellCommand = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Web search")
                    text: Config.options.search.prefix.webSearch
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.webSearch = text;
                    }
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Web search")
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Base URL")
                text: Config.options.search.engineBaseUrl
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.search.engineBaseUrl = text;
                }
            }

            ConfigStringList {
                title: Translation.tr("Excluded sites")
                tooltip: Translation.tr("Appended to the query as -site:… so these never come back in results")
                placeholder: "quora.com"
                values: Config.options.search.excludedSites
                onEdited: newValues => Config.options.search.excludedSites = newValues
            }
        }

        ContentSubsection {
            title: Translation.tr("Image search")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Image search base URL")
                text: Config.options.search.imageSearch.imageSearchEngineBaseUrl
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.search.imageSearch.imageSearchEngineBaseUrl = text;
                }
            }
        }
    }
}
