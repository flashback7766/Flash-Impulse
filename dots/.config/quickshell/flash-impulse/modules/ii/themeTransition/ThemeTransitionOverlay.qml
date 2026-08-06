import qs.services
import qs.modules.common
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The frozen copy of the desktop that the theme change happens behind.
 *
 * One per screen: a multi-monitor setup that only covered the focused one would
 * show the relayout thrash on every other screen, which is the thing being
 * hidden.
 *
 * The reveal is a hole, not a fill. The overlay holds a still of the *old*
 * desktop and an expanding circle is punched out of it, so what appears inside
 * the circle is the live, already-finished new theme rather than a second image
 * of it — nothing has to be drawn twice and nothing can disagree at the seam.
 */
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: overlayWindow
        required property var modelData
        screen: modelData

        visible: ThemeTransition.covering
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:themeTransition"
        WlrLayershell.layer: WlrLayer.Overlay
        // Never takes focus: the desktop is meant to look paused, not to become
        // a thing you can interact with.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        // Swallow input for the half-second this is up, so a second click
        // during the transition can't land on whatever has moved underneath it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
        }

        // Only the focused screen gets the circular reveal; the others simply
        // stop covering when it ends. A circle centred on a click that happened
        // on another monitor would sweep across this one from an arbitrary edge,
        // which reads as a glitch rather than as a transition.
        readonly property bool isOrigin: overlayWindow.modelData?.name === Hyprland.focusedMonitor?.name
        readonly property real ox: (ThemeTransition.originX >= 0 && overlayWindow.isOrigin) ? ThemeTransition.originX : overlayWindow.width / 2
        readonly property real oy: (ThemeTransition.originY >= 0 && overlayWindow.isOrigin) ? ThemeTransition.originY : overlayWindow.height / 2

        // Sized to the furthest corner, not to half the diagonal: a circle big
        // enough for a centred reveal leaves the far corner still covered once
        // its centre is moved into a corner.
        readonly property real revealDiameter: {
            const w = overlayWindow.width;
            const h = overlayWindow.height;
            const dx = Math.max(overlayWindow.ox, w - overlayWindow.ox);
            const dy = Math.max(overlayWindow.oy, h - overlayWindow.oy);
            return 2 * Math.ceil(Math.sqrt(dx * dx + dy * dy));
        }

        ScreencopyView {
            id: frozen
            anchors.fill: parent
            captureSource: overlayWindow.modelData
            // Transparent until the frame is actually in hand. The window maps
            // a frame or two before the capture arrives, and painting an empty
            // view in that gap put a black flash on screen at the exact moment
            // this is supposed to make things look calm — measured at 30 points
            // of mean brightness, for one frame, every single switch.
            opacity: frozen.hasContent ? 1 : 0
            // One frame, held. A live capture would show the change happening
            // underneath, which is exactly what it is here to hide — and would
            // also be a compositor capturing itself capturing itself.
            live: false
            paintCursor: false

            // `live: false` does not mean "capture once and stop", it means
            // "do not capture at all until asked". Without this the view never
            // had a frame, every transition hit the capture timeout and switched
            // uncovered — the screen only looked frozen because it was showing
            // nothing at all.
            property bool reported: false

            function grab(): void {
                frozen.reported = false;
                frozen.captureFrame();
                // hasContent may already be true from the previous transition,
                // in which case there is no change signal to wait for.
                frozen.report();
            }

            function report(): void {
                if (frozen.reported || !frozen.hasContent)
                    return;
                frozen.reported = true;
                ThemeTransition.framesReady += 1;
            }

            onHasContentChanged: frozen.report()

            Connections {
                target: ThemeTransition
                function onPhaseChanged() {
                    if (ThemeTransition.phase === 1)
                        frozen.grab();
                }
            }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: revealMask
                // The circle marks what to *remove*.
                invert: true
            }
        }

        // The mask is screen-sized and the circle grows *inside* it, rather than
        // being a circle that is itself scaled up. layer.enabled bakes an item
        // into a texture at its own size before any transform is applied, so an
        // animated `scale` never reaches the texture OpacityMask samples — the
        // reveal snapped from nothing to everything in a single frame instead of
        // animating at all.
        Item {
            id: revealMask
            anchors.fill: parent
            visible: false
            layer.enabled: true

            Rectangle {
                readonly property real r: overlayWindow.revealDiameter / 2 * (ThemeTransition.phase === 2 ? ThemeTransition.reveal : 0)
                x: overlayWindow.ox - r
                y: overlayWindow.oy - r
                width: r * 2
                height: r * 2
                radius: r
                color: "black"
            }
        }
    }
}
