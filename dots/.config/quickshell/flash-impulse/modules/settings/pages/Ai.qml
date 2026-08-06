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
        icon: "chat_paste_go"
        title: Translation.tr("System prompt")
        description: Translation.tr("Prepended to every conversation in the left sidebar")

        MaterialTextArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 260
            placeholderText: Translation.tr("System prompt")
            text: Config.options.ai.systemPrompt
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.ai.systemPrompt = text;
                });
            }
        }
    }

    ContentSection {
        icon: "handyman"
        title: Translation.tr("Tools")
        description: Translation.tr("What the assistant is allowed to reach for while answering")

        ConfigSelectionArray {
            currentValue: Config.options.ai.tool
            onSelected: newValue => {
                Config.options.ai.tool = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Functions"),
                    icon: "function",
                    value: "functions"
                },
                {
                    displayName: Translation.tr("Search"),
                    icon: "travel_explore",
                    value: "search"
                },
                {
                    displayName: Translation.tr("None"),
                    icon: "block",
                    value: "none"
                }
            ]
        }

        ConfigTextField {
            buttonIcon: "shield"
            text: Translation.tr("Claude Code permission mode")
            placeholder: Translation.tr("default")
            value: Config.options.ai.claudeCodePermissionMode
            onEdited: newValue => Config.options.ai.claudeCodePermissionMode = newValue
            StyledToolTip {
                text: Translation.tr("Passed through to the claude CLI for the Claude Code models: default, acceptEdits, plan or bypassPermissions. Empty leaves the CLI's own default alone.")
            }
        }
    }

    ContentSection {
        icon: "cable"
        title: Translation.tr("MCP servers")
        description: Translation.tr("Spoken to over stdio. The server name prefixes the tools it offers, so two servers can both have a \"search\".")

        ConfigJsonField {
            tooltip: Translation.tr("A list of { name, command, args, env, enabled }")
            value: Config.options.ai.mcpServers
            onEdited: newValue => Config.options.ai.mcpServers = newValue
        }
    }

    ContentSection {
        icon: "add_circle"
        title: Translation.tr("Extra models")
        description: Translation.tr("Any OpenAI-compatible endpoint, including one running on this machine")

        ConfigJsonField {
            minimumLines: 10
            tooltip: Translation.tr("A list of { api_format, name, model, endpoint, key_get_link, description, icon, requires_key }")
            value: Config.options.ai.extraModels
            onEdited: newValue => Config.options.ai.extraModels = newValue
        }
    }
}
