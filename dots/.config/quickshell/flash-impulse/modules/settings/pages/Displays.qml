import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
        // Explicit, not inferred from "mode isn't in availableModes". Picking
        // Custom… seeds the fields from the mode that is currently set, which is
        // normally one the panel does advertise — so an inferred flag switched
        // itself straight back off and the fields never appeared.
        property bool customMode
        property int vrr
        property int bitdepth
        property string cm
        property string mirror
        // Rotated 90/270 swaps what reads as "width" on screen — the arrangement
        // canvas needs to know that or a portrait monitor draws sideways.
        readonly property bool rotated: transform === 1 || transform === 3 || transform === 5 || transform === 7

        /**
         * The space this monitor actually occupies in the layout.
         *
         * Hyprland positions monitors in *logical* coordinates, so a 3840x2160
         * panel at scale 2 takes up 1920x1080 and its neighbour sits at x=1920,
         * not x=3840. These used to be the raw resolution, which meant the
         * arrangement drew a scaled monitor at several times its real size and,
         * worse, snapped its neighbours to the wrong edge — the layout the page
         * showed and the layout Hyprland applied disagreed for anyone not on
         * scale 1.
         */
        readonly property real effectiveScale: scale > 0 ? scale : 1
        readonly property real dispW: (rotated ? height : width) / effectiveScale
        readonly property real dispH: (rotated ? width : height) / effectiveScale
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

    /**
     * The advertised mode that best matches what the monitor is actually doing.
     *
     * Returns null when the panel advertises nothing at this resolution, so the
     * caller can fall back to describing the live mode instead.
     */
    function closestMode(modes, width, height, rate) {
        const prefix = `${width}x${height}@`;
        let best = null;
        let bestDiff = Infinity;
        for (const s of modes) {
            if (!s.startsWith(prefix))
                continue;
            const advertised = parseFloat(s.slice(prefix.length));
            if (isNaN(advertised))
                continue;
            const diff = Math.abs(advertised - rate);
            if (diff < bestDiff) {
                bestDiff = diff;
                best = s;
            }
        }
        return best;
    }

    /**
     * Scales this monitor can actually take, rather than a fixed step.
     *
     * Hyprland refuses a scale that does not divide the resolution into a whole
     * number of logical pixels — it reports "failed to find a clean divisor" and
     * keeps the old value, which from the page looks like the setting silently
     * not applying. A plain 0.2 step walks straight into that: 1920/1.4 is
     * 1371.43. So the control offers the divisors that exist for this panel and
     * nothing else, and everything shown is guaranteed to apply.
     */
    function validScalesFor(width, height) {
        const out = [];
        // 1/120 steps covers every scale Hyprland and the common HiDPI advice
        // use (1.25, 1.2, 4/3, 1.5, 1.75, 2, 2.4 ...) without inventing values
        // nobody wants at three decimal places.
        for (let i = 60; i <= 360; i++) {
            const s = i / 120;
            const w = width / s;
            const h = height / s;
            if (Math.abs(w - Math.round(w)) < 1e-6 && Math.abs(h - Math.round(h)) < 1e-6)
                out.push(Math.round(s * 1000) / 1000);
        }
        return out;
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
            // Matched on refresh rate as well as resolution.
            //
            // This used to be `modes.find(s => s.startsWith("WxH@"))`, which
            // takes whichever entry for that resolution happens to come first.
            // On this HDMI panel the list starts 1920x1080@60.00Hz,
            // 1920x1080@144.00Hz, ... — so after setting 144 and applying, the
            // monitor ran at 144 and the dropdown snapped back to 60. The
            // setting was right and only the page was lying about it.
            //
            // Nearest rather than exact: the compositor reports the live rate as
            // 144.00101, and the mode string says 144.00.
            const mode = page.closestMode(modes, m.width, m.height, ipc.refreshRate ?? 60) ?? currentGuess;
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
                "customMode": modes.indexOf(mode) < 0,
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

    // {x, y, w, h} in layout coordinates while a drag is in progress, or null.
    property var dragPreview: null

    /**
     * What each panel says about itself, keyed by connector name.
     *
     * hyprctl reports what a monitor is currently doing and nothing about what
     * it can do, so the only source for this is the EDID. Read once at load and
     * again whenever the set of connected outputs changes.
     *
     * A missing entry, or a null field inside one, means the display did not say
     * — which is not the same as "cannot", and is never treated as one. The
     * controls below stay usable either way and only gain a line saying the
     * monitor did not advertise it, so a display that under-reports its EDID
     * cannot cost a feature that would have worked.
     */
    property var capabilities: ({})

    function capsFor(output) {
        return page.capabilities[output] ?? {};
    }

    Process {
        id: capabilitiesProc
        running: true
        command: [Quickshell.shellPath("scripts/hyprland/display_capabilities.py")]
        stdout: StdioCollector {
            id: capabilitiesOut
            onStreamFinished: {
                try {
                    page.capabilities = JSON.parse(capabilitiesOut.text);
                } catch (e) {
                    // No edid-decode, or an EDID nothing could read. Everything
                    // then reports "not stated", which is the honest answer.
                    page.capabilities = ({});
                }
            }
        }
    }

    /**
     * Where a monitor should land, given where it was dropped.
     *
     * The old version nudged an edge when it happened to be within 24px of
     * another, independently per axis, and left the result alone otherwise. That
     * let you build layouts Hyprland does not cope with: two monitors overlapping,
     * or separated by a gap the pointer then has to cross in one jump because
     * there is nothing in between.
     *
     * This one is exhaustive instead of incremental. Every position that puts
     * the monitor flush against one of its neighbours is enumerated — four sides,
     * and for each side the three alignments people actually want (flush at the
     * near edge, flush at the far edge, centred) — anything that would overlap a
     * third monitor is discarded, and the survivor closest to where the pointer
     * let go wins. So the result is always touching something and never on top of
     * anything, and dragging still feels like it goes where you aimed.
     *
     * Returns null for the only monitor in the layout: with nothing to be flush
     * against, any position is as good as another.
     */
    function snapTarget(d, fromX, fromY) {
        const others = page.drafts.filter(o => o !== d && !o.disabled);
        if (others.length === 0)
            return null;

        const overlaps = (x, y) => others.some(o =>
            x < o.x + o.dispW && x + d.dispW > o.x &&
            y < o.y + o.dispH && y + d.dispH > o.y);

        let best = null;
        let bestDist = Infinity;
        for (const o of others) {
            // Alignments along the shared edge, for a side-by-side placement and
            // for a stacked one.
            const ys = [o.y, o.y + o.dispH - d.dispH, o.y + (o.dispH - d.dispH) / 2];
            const xs = [o.x, o.x + o.dispW - d.dispW, o.x + (o.dispW - d.dispW) / 2];
            const candidates = [];
            for (const y of ys) {
                candidates.push({ x: o.x + o.dispW, y: y });   // to its right
                candidates.push({ x: o.x - d.dispW, y: y });   // to its left
            }
            for (const x of xs) {
                candidates.push({ x: x, y: o.y + o.dispH });   // below it
                candidates.push({ x: x, y: o.y - d.dispH });   // above it
            }
            for (const c of candidates) {
                if (overlaps(c.x, c.y))
                    continue;
                const dx = c.x - fromX;
                const dy = c.y - fromY;
                const dist = dx * dx + dy * dy;
                if (dist < bestDist) {
                    bestDist = dist;
                    best = c;
                }
            }
        }
        return best;
    }

    function snap(d) {
        const target = page.snapTarget(d, d.x, d.y);
        if (target) {
            d.x = target.x;
            d.y = target.y;
        }
        d.x = Math.round(d.x);
        d.y = Math.round(d.y);
        page.touchCounter++;
    }

    /**
     * Put every enabled monitor in a row or a column, in their current order.
     *
     * Dragging is fine for two screens and tedious for more, and "just put them
     * side by side, aligned, touching" is what most rearranging is actually
     * after.
     */
    function autoArrange(direction) {
        const list = page.drafts.filter(d => !d.disabled);
        if (list.length === 0)
            return;
        // Left-to-right or top-to-bottom by where they already are, so the
        // arrangement keeps the order the user has in their head rather than
        // whatever order the compositor happened to enumerate them in.
        list.sort((a, b) => direction === "row" ? (a.x - b.x) : (a.y - b.y));

        let cursor = 0;
        for (const d of list) {
            if (direction === "row") {
                d.x = cursor;
                d.y = 0;
                cursor += d.dispW;
            } else {
                d.x = 0;
                d.y = cursor;
                cursor += d.dispH;
            }
            d.x = Math.round(d.x);
            d.y = Math.round(d.y);
        }
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
            implicitHeight: 320
            // The toolbar sits in its own strip along the top rather than
            // floating over the canvas. Anchored to the corner it overlapped the
            // monitors as soon as the layout was wide enough to fill the box,
            // and no amount of extra height fixes that on its own — a wider
            // arrangement just scales up to meet the buttons again.
            readonly property real toolbarStrip: 48

            readonly property real minX: page.drafts.length ? Math.min(...page.drafts.map(d => d.x)) : 0
            readonly property real minY: page.drafts.length ? Math.min(...page.drafts.map(d => d.y)) : 0
            readonly property real maxX: page.drafts.length ? Math.max(...page.drafts.map(d => d.x + d.dispW)) : 1
            readonly property real maxY: page.drafts.length ? Math.max(...page.drafts.map(d => d.y + d.dispH)) : 1
            readonly property real totalW: Math.max(1, maxX - minX)
            readonly property real totalH: Math.max(1, maxY - minY)
            readonly property real fitScale: Math.max(0.02, Math.min((width - 48) / totalW,
                (height - 48 - toolbarStrip) / totalH)) * 0.9

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHighest
            }

            RowLayout {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 10
                }
                spacing: 6

                // Only worth offering with something to arrange.
                RippleButtonWithIcon {
                    visible: page.drafts.filter(d => !d.disabled).length > 1
                    materialIcon: "view_column"
                    mainText: Translation.tr("Row")
                    buttonRadius: Appearance.rounding.full
                    onClicked: page.autoArrange("row")
                }
                RippleButtonWithIcon {
                    visible: page.drafts.filter(d => !d.disabled).length > 1
                    materialIcon: "table_rows"
                    mainText: Translation.tr("Column")
                    buttonRadius: Appearance.rounding.full
                    onClicked: page.autoArrange("column")
                }
                // Throws away the draft and re-reads what Hyprland is actually
                // running, without having to leave the page and come back.
                RippleButtonWithIcon {
                    visible: page.hasChanges
                    materialIcon: "undo"
                    mainText: Translation.tr("Reset")
                    buttonRadius: Appearance.rounding.full
                    onClicked: page.seedDrafts()
                }
                RippleButtonWithIcon {
                    materialIcon: "tag"
                    mainText: Translation.tr("Identify")
                    buttonRadius: Appearance.rounding.full
                    onClicked: page.identify()
                }
            }

            Item {
                id: canvasOrigin
                anchors.centerIn: parent
                // Pushed below the toolbar strip so the two never share space.
                anchors.verticalCenterOffset: arrangementArea.toolbarStrip / 2
                width: arrangementArea.totalW * arrangementArea.fitScale
                height: arrangementArea.totalH * arrangementArea.fitScale

                // Where the monitor being dragged will actually land. Drawn under
                // the monitors so it never hides the one you are moving.
                Rectangle {
                    id: snapGhost
                    visible: page.dragPreview !== null
                    x: page.dragPreview ? (page.dragPreview.x - arrangementArea.minX) * arrangementArea.fitScale : 0
                    y: page.dragPreview ? (page.dragPreview.y - arrangementArea.minY) * arrangementArea.fitScale : 0
                    width: page.dragPreview ? Math.max(28, page.dragPreview.w * arrangementArea.fitScale) : 0
                    height: page.dragPreview ? Math.max(28, page.dragPreview.h * arrangementArea.fitScale) : 0
                    radius: Appearance.rounding.normal
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                    border.width: 2
                    border.color: Appearance.colors.colPrimary
                }

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
                                    page.dragPreview = null;
                                }
                            }
                            onTranslationChanged: {
                                const nx = monitorRect.dragStartX + translation.x / arrangementArea.fitScale;
                                const ny = monitorRect.dragStartY + translation.y / arrangementArea.fitScale;
                                monitorRect.modelData.x = nx;
                                monitorRect.modelData.y = ny;
                                // Where releasing right now would put it. Since
                                // the drop is always snapped, showing the free
                                // position alone would be showing the one place
                                // it definitely will not end up.
                                const t = page.snapTarget(monitorRect.modelData, nx, ny);
                                page.dragPreview = t ? {
                                    "x": t.x,
                                    "y": t.y,
                                    "w": monitorRect.modelData.dispW,
                                    "h": monitorRect.modelData.dispH
                                } : null;
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
                    if (page.selected.customMode)
                        return page.selected.availableModes.length;
                    const i = page.selected.availableModes.indexOf(page.selected.mode);
                    return i >= 0 ? i : page.selected.availableModes.length;
                }
                onActivated: idx => {
                    if (idx < page.selected.availableModes.length) {
                        page.selected.customMode = false;
                        page.selected.mode = page.selected.availableModes[idx];
                        page.touchCounter++;
                    } else {
                        page.selected.customMode = true;
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
                visible: page.selected && page.selected.customMode
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
                id: scaleSlider
                enabled: page.selected && !page.selected.disabled && !page.selected.scaleAuto
                buttonIcon: "photo_size_select_large"
                text: Translation.tr("Scale")
                textWidth: 100
                showValue: true
                valueDecimals: 0
                valueSuffix: "%"
                from: 100
                to: 250
                // 1, not 5. The value is snapped to a real divisor anyway, and a
                // step of 5 cannot represent most of them — the handle sat at
                // 135% while the monitor was actually on 133%, so the control
                // and the line under it disagreed about the same number.
                stepSize: 1
                value: page.selected ? Math.round(page.selected.scale * 100) : 100

                // The divisors this panel actually has, recomputed when the
                // selection changes.
                readonly property var options: page.selected
                    ? page.validScalesFor(page.selected.width, page.selected.height) : [1]

                onValueChanged: {
                    if (!page.selected)
                        return;
                    // Snapped to the nearest scale that divides the resolution
                    // into whole logical pixels. A free 5% step mostly does not:
                    // Hyprland answers "failed to find a clean divisor", keeps
                    // the previous value, and from here that looks like the
                    // setting quietly refusing to take.
                    const wanted = value / 100;
                    let best = wanted;
                    let bestDiff = Infinity;
                    for (const s of scaleSlider.options) {
                        const diff = Math.abs(s - wanted);
                        if (diff < bestDiff) {
                            bestDiff = diff;
                            best = s;
                        }
                    }
                    if (Math.abs(page.selected.scale - best) > 0.0005) {
                        page.selected.scale = best;
                        page.touchCounter++;
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                visible: page.selected && !page.selected.scaleAuto
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: page.selected
                    ? Translation.tr("Snaps to scales this screen can take — %1 logical pixels wide at %2%.")
                        .arg(Math.round(page.selected.width / page.selected.effectiveScale))
                        .arg(Math.round(page.selected.scale * 100))
                    : ""
            }

            // A Windows display panel has centred/stretched/aspect here. That is
            // the DRM connector's "scaling mode" property, and this panel does
            // expose it (None/Full/Center/Full aspect) — but only the DRM master
            // may set it, that is the compositor, and neither Hyprland nor
            // aquamarine touches it. So there is nothing honest to put in this
            // spot except where the working answer actually lives.
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.topMargin: 4
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("Scaling here changes how large things are drawn, not how the panel presents them — Hyprland has no centred/stretched mode to set. For a stretched resolution in a single app (a 1080×1080 game filling a 16:10 screen, say), launch it through gamescope:")
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.topMargin: 4
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerHighest
                implicitHeight: gamescopeHint.implicitHeight + 16

                StyledText {
                    id: gamescopeHint
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                        rightMargin: 10
                    }
                    wrapMode: Text.Wrap
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                    text: "gamescope -W 1920 -H 1200 -w 1080 -h 1080 -S stretch -- <app>"
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("-W/-H is the real screen, -w/-h what the app renders at. -S takes stretch, fit, fill or integer — the same set a monitor OSD calls stretched, aspect, full and 1:1.")
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

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: {
                    if (!page.selected)
                        return "";
                    const caps = page.capsFor(page.selected.output);
                    if (caps.vrr !== true)
                        return Translation.tr("This screen doesn't advertise adaptive sync. It may still work — the setting is left available.");
                    if (caps.vrrMin && caps.vrrMax)
                        return Translation.tr("Adaptive sync supported, %1–%2 Hz.").arg(caps.vrrMin).arg(caps.vrrMax);
                    return Translation.tr("Adaptive sync supported.");
                }
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

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: {
                    if (!page.selected)
                        return "";
                    const depth = page.capsFor(page.selected.output).bitDepth;
                    if (!depth)
                        return Translation.tr("This screen doesn't state a colour depth. 10-bit is left available in case it works.");
                    if (depth < 10)
                        return Translation.tr("This screen reports %1 bits per channel, so 10-bit will most likely be ignored.").arg(depth);
                    return Translation.tr("This screen reports %1 bits per channel.").arg(depth);
                }
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

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: {
                    if (!page.selected)
                        return "";
                    const caps = page.capsFor(page.selected.output);
                    if (caps.hdr === true)
                        return Translation.tr("This screen advertises HDR.");
                    return Translation.tr("This screen doesn't advertise HDR, so the HDR profiles will probably do nothing. They're left available anyway.");
                }
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
