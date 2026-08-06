import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A Windows/KDE-style display page: drag to arrange, pick a mode and scale per
 * screen, apply, and get asked to keep it — see DisplayManager for the
 * revert-on-timeout safety net, which is the part that actually matters here.
 *
 * Nothing here touches a real monitor until Apply. Everything before that is
 * a draft, held as a plain QtObject per monitor so the canvas and the editors
 * below it can bind to it like any other model.
 */
ContentPage {
    id: page
    forceWidth: true

    component MonitorDraft: QtObject {
        property string output
        property string description
        property real x
        property real y
        property real width
        property real height
        property real scale
        property bool scaleAuto
        property int transform
        property bool disabled
        property var availableModes: []
        property string mode
        property int vrr
        property int bitdepth
        property string cm
        property string mirror
        // Rotated 90/270 swaps what reads as "width" on screen — the arrangement
        // canvas needs to know that or a portrait monitor draws sideways.
        readonly property bool rotated: transform === 1 || transform === 3 || transform === 5 || transform === 7
        readonly property real dispW: rotated ? height : width
        readonly property real dispH: rotated ? width : height
    }
    Component {
        id: draftComponent
        MonitorDraft {}
    }

    property var drafts: []
    property int selectedIndex: -1
    readonly property var selected: (selectedIndex >= 0 && selectedIndex < drafts.length) ? drafts[selectedIndex] : null

    function modeSummary(modeString) {
        // "1920x1200@60.00Hz" -> "1920 × 1200, 60 Hz"
        const m = modeString.match(/^(\d+)x(\d+)@([\d.]+)/);
        if (!m) return modeString;
        return `${m[1]} × ${m[2]}, ${Math.round(parseFloat(m[3]))} Hz`;
    }

    function seedDrafts() {
        // The outgoing drafts are *not* destroyed here. They are still the
        // Repeater delegates' `modelData` at this instant, and destroy() on a
        // QObject a live delegate holds is a use-after-free — it took the whole
        // settings app down a few seconds after this page opened, which read as
        // "the arrangement section doesn't render" because by the time a
        // screenshot landed the window was already gone. They are parented to
        // `page`, so dropping the last reference is enough; the engine collects
        // them once the Repeater has rebuilt.
        const list = [];
        for (const m of Hyprland.monitors.values) {
            const ipc = m.lastIpcObject ?? {};
            const modes = ipc.availableModes ?? [];
            const rr = (ipc.refreshRate ?? 60).toFixed(2);
            const currentGuess = `${m.width}x${m.height}@${rr}Hz`;
            const mode = modes.find(s => s.startsWith(`${m.width}x${m.height}@`)) ?? modes[0] ?? currentGuess;
            list.push(draftComponent.createObject(page, {
                "output": m.name,
                "description": ipc.description || m.name,
                "x": m.x,
                "y": m.y,
                "width": m.width,
                "height": m.height,
                "scale": m.scale,
                "scaleAuto": false,
                "transform": ipc.transform ?? 0,
                "disabled": ipc.disabled ?? false,
                "availableModes": modes,
                "mode": mode,
                "vrr": ipc.vrr ? 1 : 0,
                "bitdepth": (ipc.currentFormat ?? "").includes("2101010") ? 10 : 8,
                "cm": ipc.colorManagementPreset ?? "auto",
                "mirror": ipc.mirrorOf && ipc.mirrorOf !== "none" ? ipc.mirrorOf : ""
            }));
        }
        page.drafts = list;
        page.knownOutputs = list.map(d => d.output).sort().join(",");
        page.selectedIndex = list.length > 0 ? 0 : -1;
    }

    // Only the fields Apply actually writes — position/size churn a little on
    // their own between reads, and comparing those too would make the button
    // flicker enabled with nothing for the user to have changed.
    function draftsDiffer() {
        for (const d of page.drafts) {
            const m = Hyprland.monitors.values.find(mm => mm.name === d.output);
            if (!m) continue;
            const ipc = m.lastIpcObject ?? {};
            if (Math.round(d.x) !== m.x || Math.round(d.y) !== m.y) return true;
            if (d.scaleAuto) return true;
            if (Math.abs(d.scale - m.scale) > 0.001) return true;
            if (d.transform !== (ipc.transform ?? 0)) return true;
            if (d.disabled !== (ipc.disabled ?? false)) return true;
            if (d.vrr !== (ipc.vrr ? 1 : 0)) return true;
            if (d.bitdepth !== ((ipc.currentFormat ?? "").includes("2101010") ? 10 : 8)) return true;
            if (d.cm !== (ipc.colorManagementPreset ?? "auto")) return true;
            if (d.mirror !== (ipc.mirrorOf && ipc.mirrorOf !== "none" ? ipc.mirrorOf : "")) return true;
            if (!d.disabled && d.mode !== `${m.width}x${m.height}@${(ipc.refreshRate ?? 60).toFixed(2)}Hz`) return true;
        }
        return false;
    }
    // Re-evaluated on demand rather than bound: draftsDiffer() reads mutable
    // QtObject fields that don't emit their own change signals, so there is no
    // single property QML could bind this to. touchCounter below is nudged on
    // every edit to force the RowLayout's enabled check to re-read it.
    property int touchCounter: 0
    readonly property bool hasChanges: (touchCounter, page.draftsDiffer())

    function snap(d) {
        const threshold = 24;
        for (const other of page.drafts) {
            if (other === d)
                continue;
            // Horizontal: snap this edge to that edge when close.
            if (Math.abs(d.x - (other.x + other.dispW)) < threshold)
                d.x = other.x + other.dispW;
            else if (Math.abs((d.x + d.dispW) - other.x) < threshold)
                d.x = other.x - d.dispW;
            // Vertical
            if (Math.abs(d.y - (other.y + other.dispH)) < threshold)
                d.y = other.y + other.dispH;
            else if (Math.abs((d.y + d.dispH) - other.y) < threshold)
                d.y = other.y - d.dispH;
        }
        d.x = Math.round(d.x);
        d.y = Math.round(d.y);
        page.touchCounter++;
    }

    function apply() {
        const edited = page.drafts.map(d => ({
                    "output": d.output,
                    "modeStr": d.mode,
                    "x": Math.round(d.x),
                    "y": Math.round(d.y),
                    "scale": d.scale,
                    "scaleAuto": d.scaleAuto,
                    "transform": d.transform,
                    "disabled": d.disabled,
                    "vrr": d.vrr,
                    "bitdepth": d.bitdepth,
                    "cm": d.cm,
                    "mirror": d.mirror
                }));
        // Handed to the shell rather than done here: the settings app is a
        // separate process, so a countdown started in this one would tick in a
        // copy of DisplayManager that the confirmation overlay cannot see — and
        // would die with this window, which is exactly what a bad mode is
        // likely to take out.
        Quickshell.execDetached(["qs", "-c", "flash-impulse", "ipc", "call", "display", "apply", Qt.btoa(JSON.stringify(edited))]);
    }

    // Reseed whenever Hyprland has actually re-read its config, rather than on a
    // fixed delay after Apply. The delay version caught the compositor
    // mid-reconfigure and left the page showing a scale it had passed through on
    // the way — and it never noticed the automatic revert at all, so the page
    // went on claiming unapplied changes against settings that were no longer
    // there.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                reseedAfterReload.restart();
        }
    }
    Timer {
        id: reseedAfterReload
        // Hyprland emits the event as it starts applying; the monitor list is
        // not settled for another frame or two.
        interval: 400
        onTriggered: page.seedDrafts()
    }

    function identify() {
        identifyTimer.restart();
        // LazyLoader exposes `active`, not `visible` — assigning the latter is
        // silently a no-op at best and a warning at worst, so Identify did
        // nothing at all until this was corrected.
        identifyOverlay.active = true;
    }
    Timer {
        id: identifyTimer
        interval: 2500
        onTriggered: identifyOverlay.active = false
    }

    Component.onCompleted: page.seedDrafts()

    // Reseeding throws away whatever the user was in the middle of editing, so
    // it only happens when the set of monitors actually changed — a hotplug.
    // `values` also churns for reasons that are none of this page's business
    // (a monitor's active workspace changing, for one), and reseeding on those
    // would wipe a half-finished drag every time you switched workspace.
    property string knownOutputs: ""
    Connections {
        target: Hyprland.monitors
        function onValuesChanged() {
            const names = Hyprland.monitors.values.map(m => m.name).sort().join(",");
            if (names === page.knownOutputs)
                return;
            page.knownOutputs = names;
            page.seedDrafts();
        }
    }

    ContentSection {
        icon: "monitor"
        title: Translation.tr("Arrangement")
        description: Translation.tr("Drag a screen to match how it actually sits. Click one to edit it below.")

        Item {
            id: arrangementArea
            Layout.fillWidth: true
            implicitHeight: 240

            readonly property real minX: page.drafts.length ? Math.min(...page.drafts.map(d => d.x)) : 0
            readonly property real minY: page.drafts.length ? Math.min(...page.drafts.map(d => d.y)) : 0
            readonly property real maxX: page.drafts.length ? Math.max(...page.drafts.map(d => d.x + d.dispW)) : 1
            readonly property real maxY: page.drafts.length ? Math.max(...page.drafts.map(d => d.y + d.dispH)) : 1
            readonly property real totalW: Math.max(1, maxX - minX)
            readonly property real totalH: Math.max(1, maxY - minY)
            readonly property real fitScale: Math.max(0.02, Math.min((width - 48) / totalW, (height - 48) / totalH)) * 0.9

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHighest
            }

            RippleButtonWithIcon {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 10
                }
                materialIcon: "tag"
                mainText: Translation.tr("Identify")
                buttonRadius: Appearance.rounding.full
                onClicked: page.identify()
            }

            Item {
                id: canvasOrigin
                anchors.centerIn: parent
                width: arrangementArea.totalW * arrangementArea.fitScale
                height: arrangementArea.totalH * arrangementArea.fitScale

                Repeater {
                    model: page.drafts

                    delegate: Rectangle {
                        id: monitorRect
                        required property MonitorDraft modelData
                        required property int index
                        readonly property bool isSelected: page.selectedIndex === index
                        property real dragStartX: 0
                        property real dragStartY: 0

                        x: (modelData.x - arrangementArea.minX) * arrangementArea.fitScale
                        y: (modelData.y - arrangementArea.minY) * arrangementArea.fitScale
                        width: Math.max(28, modelData.dispW * arrangementArea.fitScale)
                        height: Math.max(28, modelData.dispH * arrangementArea.fitScale)
                        radius: Appearance.rounding.normal
                        opacity: modelData.disabled ? 0.4 : 1
                        color: isSelected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        border.width: isSelected ? 2 : 1
                        border.color: isSelected ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 0
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: monitorRect.modelData.output
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: monitorRect.isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                visible: monitorRect.width > 70
                                text: `${monitorRect.modelData.width}×${monitorRect.modelData.height}`
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }

                        TapHandler {
                            onTapped: page.selectedIndex = monitorRect.index
                        }

                        DragHandler {
                            id: dragHandler
                            target: null
                            onActiveChanged: {
                                if (active) {
                                    monitorRect.dragStartX = monitorRect.modelData.x;
                                    monitorRect.dragStartY = monitorRect.modelData.y;
                                    page.selectedIndex = monitorRect.index;
                                } else {
                                    page.snap(monitorRect.modelData);
                                }
                            }
                            onTranslationChanged: {
                                monitorRect.modelData.x = monitorRect.dragStartX + translation.x / arrangementArea.fitScale;
                                monitorRect.modelData.y = monitorRect.dragStartY + translation.y / arrangementArea.fitScale;
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        visible: page.selected !== null
        icon: "display_settings"
        title: page.selected ? (page.selected.description || page.selected.output) : ""
        description: page.selected ? page.selected.output : ""

        ContentSubsection {
            title: Translation.tr("Resolution & refresh rate")

            StyledComboBox {
                Layout.fillWidth: true
                // The last entry is the custom escape hatch, so the index has to
                // account for it rather than mapping straight onto availableModes.
                model: page.selected ? page.selected.availableModes.map(m => ({
                                "text": page.modeSummary(m),
                                "value": m
                            })).concat([
                            {
                                "text": Translation.tr("Custom…"),
                                "value": ""
                            }
                        ]) : []
                textRole: "text"
                enabled: page.selected && !page.selected.disabled
                currentIndex: {
                    if (!page.selected)
                        return -1;
                    const i = page.selected.availableModes.indexOf(page.selected.mode);
                    return i >= 0 ? i : page.selected.availableModes.length;
                }
                onActivated: idx => {
                    if (idx < page.selected.availableModes.length) {
                        page.selected.mode = page.selected.availableModes[idx];
                        page.touchCounter++;
                    } else {
                        customModeRow.seedFromCurrent();
                    }
                }
            }

            // Shown once the mode is one the panel didn't advertise — either
            // picked from "Custom…" or left over from a previous session.
            RowLayout {
                id: customModeRow
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                visible: page.selected && page.selected.availableModes.indexOf(page.selected.mode) < 0
                enabled: page.selected && !page.selected.disabled

                function seedFromCurrent() {
                    if (!page.selected)
                        return;
                    const m = page.selected.mode.match(/^(\d+)x(\d+)@([\d.]+)/);
                    customW.text = m ? m[1] : String(page.selected.width);
                    customH.text = m ? m[2] : String(page.selected.height);
                    customR.text = m ? String(Math.round(parseFloat(m[3]))) : "60";
                    customModeRow.commit();
                }

                function commit() {
                    const w = parseInt(customW.text);
                    const h = parseInt(customH.text);
                    const r = parseFloat(customR.text);
                    if (!(w > 0 && h > 0 && r > 0))
                        return;
                    page.selected.mode = `${w}x${h}@${r.toFixed(2)}Hz`;
                    page.touchCounter++;
                }

                MaterialTextField {
                    id: customW
                    Layout.preferredWidth: 90
                    placeholderText: Translation.tr("Width")
                    validator: IntValidator {
                        bottom: 1
                        top: 32768
                    }
                    onEditingFinished: customModeRow.commit()
                }
                StyledText {
                    text: "×"
                    color: Appearance.colors.colSubtext
                }
                MaterialTextField {
                    id: customH
                    Layout.preferredWidth: 90
                    placeholderText: Translation.tr("Height")
                    validator: IntValidator {
                        bottom: 1
                        top: 32768
                    }
                    onEditingFinished: customModeRow.commit()
                }
                MaterialTextField {
                    id: customR
                    Layout.preferredWidth: 90
                    placeholderText: Translation.tr("Hz")
                    validator: DoubleValidator {
                        bottom: 1
                        top: 1000
                    }
                    onEditingFinished: customModeRow.commit()
                }
                Item {
                    Layout.fillWidth: true
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Applied on Apply — reverts if the screen goes dark")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Scaling")

            ConfigSelectionArray {
                currentValue: page.selected ? (page.selected.scaleAuto ? "auto" : "manual") : "manual"
                onSelected: newValue => {
                    page.selected.scaleAuto = (newValue === "auto");
                    page.touchCounter++;
                }
                options: [
                    {
                        displayName: Translation.tr("Automatic"),
                        icon: "auto_fix",
                        value: "auto"
                    },
                    {
                        displayName: Translation.tr("Manual"),
                        icon: "tune",
                        value: "manual"
                    }
                ]
            }

            ConfigSlider {
                enabled: page.selected && !page.selected.disabled && !page.selected.scaleAuto
                buttonIcon: "photo_size_select_large"
                text: Translation.tr("Scale")
                textWidth: 100
                showValue: true
                valueDecimals: 0
                valueSuffix: "%"
                from: 100
                to: 250
                stepSize: 5
                value: page.selected ? Math.round(page.selected.scale * 100) : 100
                onValueChanged: {
                    if (page.selected && Math.round(page.selected.scale * 100) !== value) {
                        page.selected.scale = value / 100;
                        page.touchCounter++;
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                // Worth being explicit, because this is the one thing on the page
                // that a Windows display panel has and Hyprland genuinely does not.
                text: Translation.tr("Wayland scales by drawing at a different size, not by stretching the panel — so there is no \"centred\" or \"stretched\" mode to pick. A non-native resolution is always presented by the display itself.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Orientation")

            ConfigSelectionArray {
                currentValue: page.selected ? page.selected.transform : 0
                onSelected: newValue => {
                    page.selected.transform = newValue;
                    page.touchCounter++;
                }
                options: [
                    {
                        displayName: Translation.tr("Landscape"),
                        icon: "crop_landscape",
                        value: 0
                    },
                    {
                        displayName: Translation.tr("Portrait"),
                        icon: "crop_portrait",
                        value: 1
                    },
                    {
                        displayName: Translation.tr("Landscape (flipped)"),
                        icon: "crop_landscape",
                        value: 2
                    },
                    {
                        displayName: Translation.tr("Portrait (flipped)"),
                        icon: "crop_portrait",
                        value: 3
                    }
                ]
            }
        }

        ConfigSwitch {
            enabled: page.selected && (page.selected.disabled || page.drafts.filter(d => !d.disabled).length > 1)
            buttonIcon: "power_settings_new"
            text: Translation.tr("Enable this screen")
            checked: page.selected ? !page.selected.disabled : true
            onCheckedChanged: {
                if (page.selected) {
                    page.selected.disabled = !checked;
                    page.touchCounter++;
                }
            }
            StyledToolTip {
                text: Translation.tr("At least one screen has to stay on")
            }
        }
    }

    ContentSection {
        visible: page.selected !== null
        icon: "tune"
        title: Translation.tr("Advanced")
        description: Translation.tr("Left alone unless you know the panel supports it — a display that can't do what's asked here just shows nothing")

        ContentSubsection {
            title: Translation.tr("Variable refresh rate")

            ConfigSelectionArray {
                currentValue: page.selected ? page.selected.vrr : 0
                onSelected: newValue => {
                    page.selected.vrr = newValue;
                    page.touchCounter++;
                }
                options: [
                    {
                        displayName: Translation.tr("Off"),
                        icon: "close",
                        value: 0
                    },
                    {
                        displayName: Translation.tr("On"),
                        icon: "check",
                        value: 1
                    },
                    {
                        displayName: Translation.tr("Fullscreen only"),
                        icon: "fullscreen",
                        value: 2
                    },
                    {
                        displayName: Translation.tr("Fullscreen video"),
                        icon: "movie",
                        value: 3
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Colour depth")

            ConfigSelectionArray {
                currentValue: page.selected ? page.selected.bitdepth : 8
                onSelected: newValue => {
                    page.selected.bitdepth = newValue;
                    page.touchCounter++;
                }
                options: [
                    {
                        displayName: Translation.tr("8-bit"),
                        value: 8
                    },
                    {
                        displayName: Translation.tr("10-bit"),
                        value: 10
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Colour profile")

            ConfigSelectionArray {
                currentValue: page.selected ? page.selected.cm : "auto"
                onSelected: newValue => {
                    page.selected.cm = newValue;
                    page.touchCounter++;
                }
                options: [
                    {
                        displayName: Translation.tr("Auto"),
                        value: "auto"
                    },
                    {
                        displayName: "sRGB",
                        value: "srgb"
                    },
                    {
                        displayName: Translation.tr("Wide gamut"),
                        value: "wide"
                    },
                    {
                        displayName: Translation.tr("From EDID"),
                        value: "edid"
                    },
                    {
                        displayName: "HDR",
                        value: "hdr"
                    },
                    {
                        displayName: Translation.tr("HDR from EDID"),
                        value: "hdredid"
                    }
                ]
            }
        }

        ContentSubsection {
            visible: page.drafts.length > 1
            title: Translation.tr("Mirror another screen")

            StyledComboBox {
                Layout.fillWidth: true
                enabled: page.selected && !page.selected.disabled
                model: [
                    {
                        "text": Translation.tr("Don't mirror"),
                        "value": ""
                    }
                ].concat(page.drafts.filter(d => page.selected && d.output !== page.selected.output).map(d => ({
                            "text": d.output,
                            "value": d.output
                        })))
                textRole: "text"
                currentIndex: {
                    if (!page.selected)
                        return 0;
                    const others = page.drafts.filter(d => d.output !== page.selected.output);
                    const i = others.findIndex(d => d.output === page.selected.mirror);
                    return i >= 0 ? i + 1 : 0;
                }
                onActivated: idx => {
                    const others = page.drafts.filter(d => d.output !== page.selected.output);
                    page.selected.mirror = idx === 0 ? "" : others[idx - 1].output;
                    page.touchCounter++;
                }
            }
        }
    }

    // Hidden until something is actually pending, rather than sitting there
    // greyed out: with nothing edited the page is a picture of the current
    // setup, and a permanent dead "Apply" invites clicking it to find out what
    // it does. It slides in once there is a decision to make.
    Item {
        Layout.fillWidth: true
        Layout.topMargin: 4
        clip: true
        implicitHeight: page.hasChanges ? pendingRow.implicitHeight : 0
        opacity: page.hasChanges ? 1 : 0

        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            id: pendingRow
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            spacing: 10

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                text: Translation.tr("Unapplied changes")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            RippleButtonWithIcon {
                materialIcon: "undo"
                mainText: Translation.tr("Discard")
                buttonRadius: Appearance.rounding.full
                onClicked: page.seedDrafts()
            }
            RippleButtonWithIcon {
                materialIcon: "check"
                mainText: Translation.tr("Apply")
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                contentColor: Appearance.colors.colOnPrimary
                onClicked: page.apply()
            }
        }
    }

    // Identify: a big label dropped on every real screen for a couple of
    // seconds, the same trick Windows and KDE both use so a "which one is
    // DP-1" question never needs an answer.
    LazyLoader {
        id: identifyOverlay
        active: false
        component: Variants {
            model: Quickshell.screens

            PanelWindow {
                required property var modelData
                screen: modelData
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                Rectangle {
                    anchors.centerIn: parent
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer0
                    implicitWidth: label.implicitWidth + 60
                    implicitHeight: label.implicitHeight + 40
                    StyledText {
                        id: label
                        anchors.centerIn: parent
                        text: Hyprland.monitorFor(modelData)?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.title * 2
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }
}
