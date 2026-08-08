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
            // Plus the feather, so that at the end of the animation it is the
            // *solid* part of the mask that has reached the furthest corner and
            // not the falloff. Without the extra margin the last frame leaves a
            // faint wash of the old theme in that corner, which then vanishes
            // when the overlay unmaps — a visible blink exactly where the eye
            // has been following the edge to.
            return 2 * Math.ceil(Math.sqrt(dx * dx + dy * dy) + revealMask.featherPx);
        }

        /**
         * The screen to capture, or nothing at all when no transition is running.
         *
         * This used to be bound straight to modelData, which meant every screen
         * held a live screencopy context for the entire session — this overlay
         * is a Variants over Quickshell.screens, so the windows exist all the
         * time and only their visibility is toggled. Unplugging a monitor then
         * segfaulted the shell inside
         * ScreencopyView::createContext -> captureOutput -> QScreen::handle(),
         * dereferencing a QScreen that Qt had already torn down.
         *
         * Two guards, and the second is the one that matters. Dropping the
         * source when modelData goes null closes the obvious hole; dropping it
         * whenever a transition is not running means that for virtually the
         * whole life of the process there is no capture context on any screen
         * for a hotplug to race against. OverviewWindow already does exactly
         * this — `captureSource: overviewOpen ? toplevel : null` — and the other
         * two ScreencopyViews in the tree live inside Loaders, so this was the
         * only one holding a context permanently.
         */
        readonly property var captureTarget: (ThemeTransition.covering && overlayWindow.modelData)
            ? overlayWindow.modelData : null

        ScreencopyView {
            id: frozen
            anchors.fill: parent
            captureSource: overlayWindow.captureTarget
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
                    // Deferred by one turn of the event loop. captureSource is
                    // now a binding on ThemeTransition.covering, which is
                    // derived from the very property this handler fires on —
                    // and the order of "dependent binding re-evaluates" versus
                    // "signal handler runs" is not guaranteed. Grabbing inline
                    // could therefore call captureFrame() while the source was
                    // still null. The transition already waits on framesReady
                    // before doing anything, so a frame of slack costs nothing.
                    if (ThemeTransition.phase === 1)
                        Qt.callLater(frozen.grab);
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

            // The edge is feathered rather than cut.
            //
            // A hard-edged circle makes the boundary itself the thing you
            // watch: a crisp ring sweeping over the desktop, with every icon
            // and letter it crosses flipping colour in one frame. Softening it
            // turns the boundary into a short cross-dissolve between the old
            // theme and the new one, so what reads is the new theme arriving
            // rather than a shape moving across the screen.
            //
            // The feather is a fixed width in pixels, not a fraction of the
            // radius. As a fraction it starts as a blur wider than the circle
            // itself and ends hundreds of pixels wide — soft at the start,
            // mushy at the end. Holding it constant means the edge looks the
            // same the whole way across, so the reveal keeps a consistent
            // character instead of changing texture as it expands.
            readonly property real featherPx: 140
            readonly property real r: overlayWindow.revealDiameter / 2
                * (ThemeTransition.phase === 2 ? ThemeTransition.reveal : 0)

            // Below this the hole is fully open; between it and 1.0 the old
            // desktop fades back in. Clamped so the very first frames, when the
            // radius is still smaller than the feather, are all falloff and no
            // hard core — that is what stops a hard dot appearing under the
            // cursor on the first frame.
            //
            // Lives on the mask rather than inside the gradient: a Gradient is
            // not an Item, so `parent` does not resolve from a GradientStop.
            readonly property real solidStop: revealMask.r > 0
                ? Math.max(0, Math.min(0.92, (revealMask.r - revealMask.featherPx) / revealMask.r))
                : 0

            RadialGradient {
                anchors.fill: parent
                horizontalOffset: overlayWindow.ox - width / 2
                verticalOffset: overlayWindow.oy - height / 2
                horizontalRadius: revealMask.r
                verticalRadius: revealMask.r
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "black" }
                    GradientStop { position: revealMask.solidStop; color: "black" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }
    }
}
