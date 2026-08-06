//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * First run.
 *
 * A linear wizard rather than the one long scroll this used to be. The old
 * version put language, bar layout, theme, policies and a pile of links on a
 * single page, which asks a first-time user to decide everything at once and
 * gives no signal about how much is left. One decision per screen, with the
 * step count visible, is the whole difference.
 */
ApplicationWindow {
    id: root
    property string firstRunFilePath: FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false

    readonly property var steps: [
        {
            name: Translation.tr("Welcome"),
            icon: "waving_hand",
            component: "modules/welcome/StepWelcome.qml"
        },
        {
            name: Translation.tr("Language"),
            icon: "language",
            component: "modules/welcome/StepLanguage.qml"
        },
        {
            name: Translation.tr("Look"),
            icon: "format_paint",
            component: "modules/welcome/StepLook.qml"
        },
        {
            name: Translation.tr("Layout"),
            icon: "dashboard",
            component: "modules/welcome/StepLayout.qml"
        },
        {
            name: Translation.tr("Performance"),
            icon: "speed",
            component: "modules/welcome/StepPerformance.qml"
        },
        {
            name: Translation.tr("Privacy"),
            icon: "shield_person",
            component: "modules/welcome/StepPrivacy.qml"
        },
        {
            name: Translation.tr("All set"),
            icon: "check_circle",
            component: "modules/welcome/StepDone.qml"
        }
    ]

    property int currentStep: 0
    readonly property bool onFirstStep: root.currentStep === 0
    readonly property bool onLastStep: root.currentStep === root.steps.length - 1

    function goTo(index: int): void {
        const clamped = Math.max(0, Math.min(root.steps.length - 1, index));
        if (clamped === root.currentStep)
            return;
        root.currentStep = clamped;
    }

    visible: true
    onClosing: {
        Quickshell.execDetached(["notify-send", Translation.tr("Welcome"), Translation.tr("You can reopen this any time with <tt>Super+Shift+Alt+/</tt>. Settings live under <tt>Super+I</tt>."), "-a", "Shell"]);
        Qt.quit();
    }
    title: Translation.tr("Flash-Impulse — first run")

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 0; // Welcome app always only sets one var at a time so delay isn't needed
    }

    minimumWidth: 700
    minimumHeight: 560
    width: 940
    height: 720
    color: Appearance.m3colors.m3background

    Shortcut {
        sequences: ["Alt+Right"]
        onActivated: root.goTo(root.currentStep + 1)
    }
    Shortcut {
        sequences: ["Alt+Left"]
        onActivated: root.goTo(root.currentStep - 1)
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }
        spacing: root.contentPadding

        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(welcomeText.implicitHeight, windowControlsRow.implicitHeight)

            StyledText {
                id: welcomeText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Setting up")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Show next time")
                }
                StyledSwitch {
                    id: showNextTimeSwitch
                    checked: root.showNextTime
                    scale: 0.6
                    Layout.alignment: Qt.AlignVCenter
                    onCheckedChanged: {
                        if (checked) {
                            Quickshell.execDetached(["rm", root.firstRunFilePath]);
                        } else {
                            Quickshell.execDetached(["bash", "-c", `echo '${StringUtils.shellSingleQuoteEscape(root.firstRunFileContent)}' > '${StringUtils.shellSingleQuoteEscape(root.firstRunFilePath)}'`]);
                        }
                    }
                }
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }

                    StyledToolTip {
                        text: Translation.tr("Tip: Close a window with Super+Q")
                    }
                }
            }
        }

        Rectangle { // Content container
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.windowRounding - root.contentPadding
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                ColumnLayout { // Step header
                    Layout.fillWidth: true
                    Layout.leftMargin: 28
                    Layout.rightMargin: 28
                    Layout.topMargin: 22
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        MaterialSymbol {
                            text: root.steps[root.currentStep].icon
                            iconSize: 28
                            fill: 1
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.steps[root.currentStep].name
                            color: Appearance.colors.colOnLayer1
                            font {
                                family: Appearance.font.family.title
                                pixelSize: Appearance.font.pixelSize.title
                                variableAxes: Appearance.font.variableAxes.title
                            }
                        }
                        StyledText {
                            text: Translation.tr("Step %1 of %2").arg(root.currentStep + 1).arg(root.steps.length)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    WizardStepIndicator {
                        Layout.fillWidth: true
                        count: root.steps.length
                        currentIndex: root.currentStep
                    }
                }

                Loader {
                    id: stepLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 4
                    active: Config.ready

                    Component.onCompleted: source = root.steps[0].component

                    Connections {
                        target: root
                        function onCurrentStepChanged(): void {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: stepLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        PropertyAction {
                            target: stepLoader
                            property: "source"
                            value: root.steps[root.currentStep].component
                        }
                        NumberAnimation {
                            target: stepLoader
                            properties: "opacity"
                            from: 0
                            to: 1
                            duration: 200
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                        }
                    }
                }

                Rectangle { // Footer
                    Layout.fillWidth: true
                    implicitHeight: footerRow.implicitHeight + 28
                    color: Appearance.colors.colSurfaceContainer

                    RowLayout {
                        id: footerRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 24
                            rightMargin: 24
                        }
                        spacing: 10

                        RippleButtonWithIcon {
                            // Hidden rather than disabled on the first step: a
                            // greyed-out Back is a control that looks broken.
                            visible: !root.onFirstStep
                            implicitHeight: 44
                            buttonRadius: Appearance.rounding.full
                            materialIcon: "arrow_back"
                            mainText: Translation.tr("Back")
                            onClicked: root.goTo(root.currentStep - 1)
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        RippleButtonWithIcon {
                            visible: !root.onLastStep
                            implicitHeight: 44
                            buttonRadius: Appearance.rounding.full
                            materialIcon: "arrow_forward"
                            mainText: Translation.tr("Next")
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            contentColor: Appearance.colors.colOnPrimary
                            onClicked: root.goTo(root.currentStep + 1)
                        }
                        RippleButtonWithIcon {
                            visible: root.onLastStep
                            implicitHeight: 44
                            buttonRadius: Appearance.rounding.full
                            materialIcon: "check"
                            mainText: Translation.tr("Finish")
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            contentColor: Appearance.colors.colOnPrimary
                            onClicked: root.close()
                        }
                    }
                }
            }
        }
    }
}
