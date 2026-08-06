import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    ContentSection {
        icon: "language"
        title: Translation.tr("Language")
        description: Translation.tr("Applies to the shell — your apps keep following the system locale")

        StyledComboBox {
            buttonIcon: "translate"
            textRole: "displayName"

            model: [
                {
                    displayName: Translation.tr("Auto (System)"),
                    value: "auto"
                },
                ...Translation.allAvailableLanguages.map(lang => {
                    return {
                        displayName: lang,
                        value: lang
                    };
                })]

            currentIndex: {
                const index = model.findIndex(item => item.value === Config.options.language.ui);
                return index !== -1 ? index : 0;
            }

            onActivated: index => {
                Config.options.language.ui = model[index].value;
            }
        }
    }

    ContentSection {
        icon: "auto_awesome"
        title: Translation.tr("Not listed?")
        description: Translation.tr("Gemini can generate a translation for any locale. You need a key first: open the left sidebar with Super+A, type /key and follow it.")

        ConfigRow {
            MaterialTextArea {
                id: localeInput
                Layout.fillWidth: true
                placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN…")
                text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
            }
            RippleButtonWithIcon {
                Layout.fillHeight: true
                materialIcon: "auto_awesome"
                enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())
                mainText: enabled ? Translation.tr("Generate\nTypically takes 2 minutes") : Translation.tr("Generating…\nDon't close this window!")
                onClicked: {
                    translationProc.locale = localeInput.text.trim();
                    translationProc.running = false;
                    translationProc.running = true;
                }
            }
        }
    }
}
