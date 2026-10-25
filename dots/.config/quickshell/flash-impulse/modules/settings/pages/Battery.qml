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
    id: page
    forceWidth: true

    property string powerConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/flash-impulse/power-config.json`)
    property string activeProfile: "performance"
    property string defaultBatteryProfile: "power-saver"
    property string defaultAcProfile: "performance"
    property bool autoSwitchProfiles: true
    property int chargeThreshold: 100
    property bool adaptiveCharging: false
    // Guards the adaptive switch's handler: every programmatic write of
    // adaptiveCharging re-enters it through the checked binding, which used to
    // double-fire the threshold write and, on page load, force the limit to
    // the loaded mode before the user had touched anything.
    property bool adaptiveGuard: false

    /** The one path every writer of the adaptive switch takes. */
    function setAdaptive(on: bool) {
        adaptiveGuard = true;
        adaptiveCharging = on;
        if (on && chargeThreshold > 80)
            setChargeLimit(80);
        else if (!on)
            setChargeLimit(100);
        savePowerConfig();
        adaptiveGuard = false;
    }

    function loadPowerConfig() {
        queryProfileProc.running = true;
        queryThresholdProc.running = true;
    }

    Component.onCompleted: {
        page.loadPowerConfig();
    }

    function setPpdProfile(profileName) {
        page.activeProfile = profileName;
        Quickshell.execDetached(["powerprofilesctl", "set", profileName]);
    }

    function setChargeLimit(limit) {
        page.chargeThreshold = limit;
        Quickshell.execDetached(["/usr/local/bin/thinkpad-charge-threshold.sh", "set", limit.toString()]);
    }

    function savePowerConfig() {
        const data = {
            profiles: {
                ac: page.defaultAcProfile,
                battery: page.defaultBatteryProfile,
                autoSwitch: page.autoSwitchProfiles
            },
            battery: {
                chargeThreshold: page.chargeThreshold,
                adaptive: page.adaptiveCharging
            }
        };
        saveConfigProc.command = ["bash", "-c", `echo '${JSON.stringify(data, null, 2)}' > '${page.powerConfigPath}'`];
        saveConfigProc.running = true;
    }

    Process {
        id: saveConfigProc
    }

    Process {
        id: queryProfileProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (out.length > 0) page.activeProfile = out;
            }
        }
    }

    Process {
        id: queryThresholdProc
        command: ["/usr/local/bin/thinkpad-charge-threshold.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(text.trim());
                if (!isNaN(val) && val >= 40 && val <= 100) {
                    page.chargeThreshold = val;
                }
            }
        }
    }

    FileView {
        id: powerConfigFile
        path: Qt.resolvedUrl(page.powerConfigPath)
        onLoaded: {
            page.adaptiveGuard = true;
            try {
                const cfg = JSON.parse(powerConfigFile.text());
                if (cfg.profiles) {
                    if (cfg.profiles.ac) page.defaultAcProfile = cfg.profiles.ac;
                    if (cfg.profiles.battery) page.defaultBatteryProfile = cfg.profiles.battery;
                    if (cfg.profiles.autoSwitch !== undefined) page.autoSwitchProfiles = cfg.profiles.autoSwitch;
                }
                if (cfg.battery) {
                    if (cfg.battery.chargeThreshold) page.chargeThreshold = cfg.battery.chargeThreshold;
                    if (cfg.battery.adaptive !== undefined) page.adaptiveCharging = cfg.battery.adaptive;
                }
            } catch (e) {
            } finally {
                page.adaptiveGuard = false;
            }
        }
    }

    // 1. Power Profiles & AC/Battery switching
    ContentSection {
        icon: "bolt"
        title: Translation.tr("Power profiles & Cooling")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            StyledText {
                text: Translation.tr("Active profile:") + " " + (page.activeProfile === "power-saver" ? Translation.tr("Power Saver (Quiet fan)") : (page.activeProfile === "performance" ? Translation.tr("Performance (Turbo fan)") : Translation.tr("Balanced (Standard fan)")))
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SecondaryTabButton {
                    Layout.fillWidth: true
                    buttonIcon: "energy_savings_leaf"
                    text: Translation.tr("Power saver")
                    checked: page.activeProfile === "power-saver"
                    onClicked: page.setPpdProfile("power-saver")
                }
                SecondaryTabButton {
                    Layout.fillWidth: true
                    buttonIcon: "balance"
                    text: Translation.tr("Balanced")
                    checked: page.activeProfile === "balanced"
                    onClicked: page.setPpdProfile("balanced")
                }
                SecondaryTabButton {
                    Layout.fillWidth: true
                    buttonIcon: "speed"
                    text: Translation.tr("Performance")
                    checked: page.activeProfile === "performance"
                    onClicked: page.setPpdProfile("performance")
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
                Layout.topMargin: 4
                Layout.bottomMargin: 4
            }

            ConfigSwitch {
                buttonIcon: "sync"
                text: Translation.tr("Auto-switch profile when on Battery / AC")
                checked: page.autoSwitchProfiles
                onCheckedChanged: {
                    page.autoSwitchProfiles = checked;
                    page.savePowerConfig();
                }
            }

            ConfigRow {
                uniform: true
                visible: page.autoSwitchProfiles
                // ConfigSelectionArray reads displayName and fires `selected`;
                // the options used `name` and the handler listened for a signal
                // that does not exist, so both selectors rendered blank and no
                // click ever saved a default profile.
                ConfigSelectionArray {
                    options: [
                        { displayName: Translation.tr("Power saver"), value: "power-saver" },
                        { displayName: Translation.tr("Balanced"), value: "balanced" },
                        { displayName: Translation.tr("Performance"), value: "performance" }
                    ]
                    currentValue: page.defaultBatteryProfile
                    onSelected: (value) => {
                        page.defaultBatteryProfile = value;
                        page.savePowerConfig();
                    }
                }
                ConfigSelectionArray {
                    options: [
                        { displayName: Translation.tr("Power saver"), value: "power-saver" },
                        { displayName: Translation.tr("Balanced"), value: "balanced" },
                        { displayName: Translation.tr("Performance"), value: "performance" }
                    ]
                    currentValue: page.defaultAcProfile
                    onSelected: (value) => {
                        page.defaultAcProfile = value;
                        page.savePowerConfig();
                    }
                }
            }
        }
    }

    // 2. ThinkPad Adaptive & Optimized Charging
    ContentSection {
        icon: "battery_charging_full"
        title: Translation.tr("Adaptive charging & Battery health")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            ConfigSwitch {
                buttonIcon: "health_and_safety"
                text: Translation.tr("Adaptive battery health protection")
                checked: page.adaptiveCharging
                onCheckedChanged: {
                    if (page.adaptiveGuard) return;
                    page.setAdaptive(checked);
                }
                StyledToolTip {
                    text: Translation.tr("Limits charging to 80% to maximize ThinkPad battery lifespan. On reaching 80%, charger powers internal hardware directly (AC passthrough).")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SecondaryTabButton {
                    Layout.fillWidth: true
                    buttonIcon: "shield"
                    text: Translation.tr("80% (Preserve Lifespan)")
                    checked: page.chargeThreshold === 80
                    onClicked: page.setAdaptive(true)
                }

                SecondaryTabButton {
                    Layout.fillWidth: true
                    buttonIcon: "battery_full"
                    text: Translation.tr("100% (Full Capacity)")
                    checked: page.chargeThreshold === 100
                    onClicked: page.setAdaptive(false)
                }
            }

            ConfigSlider {
                buttonIcon: "tune"
                text: Translation.tr("Charge limit")
                textWidth: 120
                showValue: true
                valueDecimals: 0
                from: 50
                to: 100
                stepSize: 5
                value: page.chargeThreshold
                onValueChanged: {
                    const rounded = Math.round(value);
                    if (rounded !== page.chargeThreshold) {
                        page.setChargeLimit(rounded);
                        page.savePowerConfig();
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Hardware bypass: When charge limit is reached, ThinkPad Embedded Controller stops battery charging and routes all AC power directly to CPU, display, and components.")
            }
        }
    }

    // 3. Warnings & Limits
    ContentSection {
        icon: "battery_android_alert"
        title: Translation.tr("Warnings & limits")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("Low warning")
                value: Config.options.battery.low
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.low = value;
                }
            }
            ConfigSpinBox {
                icon: "dangerous"
                text: Translation.tr("Critical warning")
                value: Config.options.battery.critical
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.critical = value;
                }
            }
        }
        ConfigRow {
            uniform: false
            Layout.fillWidth: false
            ConfigSwitch {
                buttonIcon: "pause"
                text: Translation.tr("Automatic suspend")
                checked: Config.options.battery.automaticSuspend
                onCheckedChanged: {
                    Config.options.battery.automaticSuspend = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Automatically suspends the system when battery is low")
                }
            }
            ConfigSpinBox {
                enabled: Config.options.battery.automaticSuspend
                text: Translation.tr("at")
                value: Config.options.battery.suspend
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.suspend = value;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "charger"
                text: Translation.tr("Full warning")
                value: Config.options.battery.full
                from: 0
                to: 101
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.full = value;
                }
            }
        }
    }
}

