import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.services

RowLayout {
    id: root

    // StyledToolTip looks for `hovered` on its parent; a bare RowLayout has no
    // such property, so the tooltip's visible-condition sees `undefined`,
    // treats that as "no hover tracking needed" and shows permanently.
    property alias hovered: rootHoverHandler.hovered
    HoverHandler {
        id: rootHoverHandler
    }
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    property string text: ""
    property string buttonIcon: ""
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property alias stepSize: slider.stepSize
    property bool usePercentTooltip: true
    // The tooltip only shows while dragging, which is no help when the question
    // is what the value currently is.
    property bool showValue: false
    property int valueDecimals: 2
    property string valueSuffix: ""
    property real from: slider.from
    property real to: slider.to
    property real textWidth: 120

    RowLayout {
        id: row
        spacing: 10

        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            id: labelWidget
            Layout.preferredWidth: root.textWidth
            text: root.text
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }
    }

    StyledSlider {
        id: slider
        // A disabled row has to look disabled all the way across, or the only
        // dimmed thing is the label and the track still invites a drag.
        enabled: root.enabled
        opacity: root.enabled ? 1 : 0.4
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        value: root.value
        from: root.from
        to: root.to
    }

    StyledText {
        visible: root.showValue
        Layout.preferredWidth: 56
        horizontalAlignment: Text.AlignRight
        text: `${slider.value.toFixed(root.valueDecimals)}${root.valueSuffix}`
        font.family: Appearance.font.family.numbers
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
