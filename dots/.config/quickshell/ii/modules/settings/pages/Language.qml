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

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    ContentSection {
        icon: "translate"
        title: Translation.tr("Interface language")

        ContentSubsection {
            title: Translation.tr("Interface Language")
            tooltip: Translation.tr("Select the language for the user interface.\n\"Auto\" will use your system's locale.")

            StyledComboBox {
                id: languageSelector
                buttonIcon: "language"
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
        ContentSubsection {
            title: Translation.tr("Generate translation with Gemini")
            tooltip: Translation.tr("You'll need to enter your Gemini API key first.\nType /key on the sidebar for instructions.")

            ConfigRow {
                MaterialTextArea {
                    id: localeInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN...")
                    text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                }
                RippleButtonWithIcon {
                    id: generateTranslationBtn
                    Layout.fillHeight: true
                    nerdIcon: ""
                    enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())
                    mainText: enabled ? Translation.tr("Generate\nTypically takes 2 minutes") : Translation.tr("Generating...\nDon't close this window!")
                    onClicked: {
                        translationProc.locale = localeInput.text.trim();
                        translationProc.running = false;
                        translationProc.running = true;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "g_translate"
        title: Translation.tr("Translator")
        description: Translation.tr("Used by the translate panel in the right sidebar. Backed by translate-shell.")

        ConfigTextField {
            buttonIcon: "dns"
            text: Translation.tr("Engine")
            placeholder: "auto"
            fieldWidth: 160
            value: Config.options.language.translator.engine
            onEdited: newValue => Config.options.language.translator.engine = newValue
            StyledToolTip {
                text: Translation.tr("Run 'trans -list-engines' for what is available. \"auto\" picks Google.")
            }
        }
        ConfigTextField {
            buttonIcon: "input"
            text: Translation.tr("Translate from")
            placeholder: "auto"
            fieldWidth: 160
            value: Config.options.language.translator.sourceLanguage
            onEdited: newValue => Config.options.language.translator.sourceLanguage = newValue
            StyledToolTip {
                text: Translation.tr("Run 'trans -list-all' for language codes. \"auto\" detects it from the text.")
            }
        }
        ConfigTextField {
            buttonIcon: "output"
            text: Translation.tr("Translate to")
            placeholder: "auto"
            fieldWidth: 160
            value: Config.options.language.translator.targetLanguage
            onEdited: newValue => Config.options.language.translator.targetLanguage = newValue
            StyledToolTip {
                text: Translation.tr("\"auto\" uses your interface language")
            }
        }
    }
}
