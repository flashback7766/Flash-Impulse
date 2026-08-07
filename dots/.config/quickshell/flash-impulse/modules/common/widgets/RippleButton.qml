import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls

/**
 * A button with ripple effect similar to in Material Design.
 */
Button {
    id: root
    property bool toggled
    property string buttonText
    property bool pointingHandCursor: true
    property real buttonRadius: Appearance?.rounding?.small ?? 4
    property real buttonRadiusPressed: buttonRadius
    property real buttonEffectiveRadius: root.down ? root.buttonRadiusPressed : root.buttonRadius
    property int rippleDuration: 1200
    property bool rippleEnabled: true
    property var downAction // When left clicking (down)
    property var releaseAction // When left clicking (release)
    property var altAction // When right clicking
    property var middleClickAction // When middle clicking

    property color colBackground: ColorUtils.transparentize(Appearance?.colors.colLayer1Hover, 1) || "transparent"
    property color colBackgroundHover: Appearance?.colors.colLayer1Hover ?? "#E5DFED"
    property color colBackgroundToggled: Appearance?.colors.colPrimary ?? "#65558F"
    property color colBackgroundToggledHover: Appearance?.colors.colPrimaryHover ?? "#77699C"
    property color colRipple: Appearance?.colors.colLayer1Active ?? "#D6CEE2"
    property color colRippleToggled: Appearance?.colors.colPrimaryActive ?? "#D6CEE2"

    opacity: root.enabled ? 1 : 0.4

    /**
     * The button gives under the press and springs back when let go.
     *
     * The ripple says "that click landed somewhere"; it does not say "this
     * thing moved". A press that only changes colour reads as a state change,
     * a press that dips reads as a physical object — and 122 call sites go
     * through this component, so the whole shell answers the same way.
     *
     * Asymmetric on purpose. Going down is quick and has no overshoot: it has
     * to keep up with the finger, and a bounce on the way *in* feels loose.
     * Coming back rides expressiveFastSpatial, whose second control point sits
     * at 1.67 — past the target and back — so the button overshoots a hair on
     * release. That overshoot is the whole effect; without it this is a resize.
     *
     * 0.96 rather than something more obvious: the smallest bar icons are about
     * 22px across, and anything deeper reads as the icon glitching rather than
     * as the button responding.
     */
    property real pressScale: Appearance?.animation.press.scale ?? 0.96
    scale: root.down ? root.pressScale : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: root.down ? 90 : (Appearance?.animationCurves.expressiveFastSpatialDuration ?? 350)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.down
                ? (Appearance?.animationCurves.expressiveEffects ?? [0.34, 0.80, 0.34, 1.00, 1, 1])
                : (Appearance?.animationCurves.expressiveFastSpatial ?? [0.42, 1.67, 0.21, 0.90, 1, 1])
        }
    }

    property color buttonColor: ColorUtils.transparentize(root.toggled ?
        (root.hovered ? colBackgroundToggledHover : 
            colBackgroundToggled) :
        (root.hovered ? colBackgroundHover : 
            colBackground), root.enabled ? 0 : 1)
    property color rippleColor: root.toggled ? colRippleToggled : colRipple

    function startRipple(x, y) {
        const stateY = buttonBackground.y;
        rippleAnim.x = x;
        rippleAnim.y = y - stateY;

        const dist = (ox,oy) => ox*ox + oy*oy
        const stateEndY = stateY + buttonBackground.height
        rippleAnim.radius = Math.sqrt(Math.max(dist(0, stateY), dist(0, stateEndY), dist(width, stateY), dist(width, stateEndY)))

        rippleFadeAnim.complete();
        rippleAnim.restart();
    }

    component RippleAnim: NumberAnimation {
        duration: rippleDuration
        easing.type: Appearance?.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance?.animationCurves.standardDecel
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: (event) => { 
            if(event.button === Qt.RightButton) {
                if (root.altAction) root.altAction(event);
                return;
            }
            if(event.button === Qt.MiddleButton) {
                if (root.middleClickAction) root.middleClickAction();
                return;
            }
            root.down = true
            if (root.downAction) root.downAction();
            if (!root.rippleEnabled) return;
            const {x,y} = event
            startRipple(x, y)
        }
        onReleased: (event) => {
            root.down = false
            if (event.button != Qt.LeftButton) return;
            if (root.releaseAction) root.releaseAction();
            root.click() // Because the MouseArea already consumed the event
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
        onCanceled: (event) => {
            root.down = false
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
    }

    RippleAnim {
        id: rippleFadeAnim
        duration: rippleDuration * 2
        target: ripple
        property: "opacity"
        to: 0
    }

    SequentialAnimation {
        id: rippleAnim

        property real x
        property real y
        property real radius

        PropertyAction {
            target: ripple
            property: "x"
            value: rippleAnim.x
        }
        PropertyAction {
            target: ripple
            property: "y"
            value: rippleAnim.y
        }
        PropertyAction {
            target: ripple
            property: "opacity"
            value: 1
        }
        ParallelAnimation {
            RippleAnim {
                target: ripple
                properties: "implicitWidth,implicitHeight"
                from: 0
                to: rippleAnim.radius * 2
            }
        }
    }

    background: Rectangle {
        id: buttonBackground
        radius: root.buttonEffectiveRadius
        implicitHeight: 30

        color: root.buttonColor
        Behavior on color {
            animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Only while there is a ripple to clip.
        //
        // This was unconditionally true, so every RippleButton in the shell —
        // 122 call sites, many instantiated per item in a list and again per
        // monitor — held its own framebuffer for as long as it existed, purely
        // to round off a ripple that is on screen for a fraction of a second
        // and absent the rest of the session. Measured at 6 MB of VRAM across
        // the shell at rest (561768 KiB -> 555660 KiB), plus the per-button
        // render-to-texture pass that came with it.
        //
        // Safe to switch off in between: the mask exists only to keep the
        // expanding circle inside the button's corners, and at opacity 0 there
        // is no circle to escape. The PropertyAction that starts a ripple sets
        // opacity to 1 before the animation runs, and QML bindings evaluate
        // synchronously, so the layer is back on in the same frame the ripple
        // becomes visible.
        layer.enabled: ripple.opacity > 0
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: buttonBackground.width
                height: buttonBackground.height
                radius: root.buttonEffectiveRadius
            }
        }

        Item {
            id: ripple
            width: ripple.implicitWidth
            height: ripple.implicitHeight
            opacity: 0
            visible: width > 0 && height > 0

            property real implicitWidth: 0
            property real implicitHeight: 0

            Behavior on opacity {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RadialGradient {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.rippleColor }
                    GradientStop { position: 0.3; color: root.rippleColor }
                    GradientStop { position: 0.5; color: Qt.rgba(root.rippleColor.r, root.rippleColor.g, root.rippleColor.b, 0) }
                }
            }

            transform: Translate {
                x: -ripple.width / 2
                y: -ripple.height / 2
            }
        }
    }

    contentItem: StyledText {
        text: root.buttonText
    }
}
