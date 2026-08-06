import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Which program the shell launches when a panel offers to open one.
 *
 * These default to KDE's kcmshell modules, which is wrong on any install
 * without Plasma — and until now the only way to change them was config.json.
 */
ContentPage {
    forceWidth: true

    ContentSection {
        icon: "terminal"
        title: Translation.tr("Shell & system")
        description: Translation.tr("Commands, not desktop-entry names. They run through your shell, so quoting matters.")

        ConfigTextField {
            buttonIcon: "terminal"
            fieldWidth: 330
            text: Translation.tr("Terminal")
            placeholder: "kitty -1"
            value: Config.options.apps.terminal
            onEdited: newValue => Config.options.apps.terminal = newValue
            StyledToolTip {
                text: Translation.tr("Used whenever the shell needs to run something visibly")
            }
        }
        ConfigTextField {
            buttonIcon: "monitor_heart"
            fieldWidth: 330
            text: Translation.tr("Task manager")
            value: Config.options.apps.taskManager
            onEdited: newValue => Config.options.apps.taskManager = newValue
        }
        ConfigTextField {
            buttonIcon: "deployed_code_update"
            fieldWidth: 330
            text: Translation.tr("System update")
            value: Config.options.apps.update
            onEdited: newValue => Config.options.apps.update = newValue
        }
    }

    ContentSection {
        icon: "settings_input_antenna"
        title: Translation.tr("Connectivity")

        ConfigTextField {
            buttonIcon: "wifi"
            fieldWidth: 330
            text: Translation.tr("Wi-Fi settings")
            value: Config.options.apps.network
            onEdited: newValue => Config.options.apps.network = newValue
        }
        ConfigTextField {
            buttonIcon: "lan"
            fieldWidth: 330
            text: Translation.tr("Ethernet settings")
            value: Config.options.apps.networkEthernet
            onEdited: newValue => Config.options.apps.networkEthernet = newValue
        }
        ConfigTextField {
            buttonIcon: "bluetooth"
            fieldWidth: 330
            text: Translation.tr("Bluetooth settings")
            value: Config.options.apps.bluetooth
            onEdited: newValue => Config.options.apps.bluetooth = newValue
        }
        ConfigTextField {
            buttonIcon: "volume_up"
            fieldWidth: 330
            text: Translation.tr("Volume mixer")
            value: Config.options.apps.volumeMixer
            onEdited: newValue => Config.options.apps.volumeMixer = newValue
        }
    }

    ContentSection {
        icon: "manage_accounts"
        title: Translation.tr("Account")

        ConfigTextField {
            buttonIcon: "password"
            fieldWidth: 330
            text: Translation.tr("Change password")
            value: Config.options.apps.changePassword
            onEdited: newValue => Config.options.apps.changePassword = newValue
        }
        ConfigTextField {
            buttonIcon: "group"
            fieldWidth: 330
            text: Translation.tr("Manage users")
            value: Config.options.apps.manageUser
            onEdited: newValue => Config.options.apps.manageUser = newValue
        }
    }
}
