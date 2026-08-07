import qs.modules.common
import QtQuick

StyledText {
    id: root
    property real iconSize: Appearance?.font.pixelSize.small ?? 16
    property real fill: 0
    property real truncatedFill: fill.toFixed(1) // Reduce memory consumption spikes from constant font remapping

    /**
     * Optical size, clamped to the axis's own range and snapped to 4pt buckets.
     *
     * Qt builds a separate font engine for every distinct set of variable-axis
     * values it is asked for, each one mapping the font file again, and it does
     * not release them. This axis was being handed the raw iconSize — which
     * across the shell includes animated expressions like `20 + 10 * value` and
     * `80 * scaleFactor`. Those are continuous, so every frame of every icon
     * scaling animation minted another engine that then stayed for the life of
     * the process.
     *
     * Measured before this: 44 live mappings of MaterialSymbolsRounded holding
     * 310 MB resident after three rounds of toggling the sidebars, with total
     * RSS at 968 MB and still climbing the longer the session ran.
     *
     * Snapping is visually free. opsz only nudges stroke weight to suit the
     * rendered size, the font clamps anything outside 20–48 anyway (so the 13s
     * and 80s in this tree were already being flattened, just at the cost of an
     * engine each), and FILL above is quantised to one decimal for this very
     * reason — this is the same trick applied to the axis that was missed.
     */
    readonly property real truncatedOpsz: root.iconSize >= 36 ? 48 : 20

    renderType: Text.NativeRendering
    font {
        hintingPreference: Font.PreferNoHinting
        family: Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded"
        pixelSize: iconSize
        weight: Font.Normal + (Font.DemiBold - Font.Normal) * truncatedFill
        variableAxes: {
            "FILL": truncatedFill,
            // "wght": font.weight,
            // "GRAD": 0,
            "opsz": root.truncatedOpsz,
        }
    }

    Behavior on fill { // Leaky leaky, no good
        NumberAnimation {
            duration: Appearance?.animation.elementMoveFast.duration ?? 200
            easing.type: Appearance?.animation.elementMoveFast.type ?? Easing.BezierSpline
            easing.bezierCurve: Appearance?.animation.elementMoveFast.bezierCurve ?? [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }
}
