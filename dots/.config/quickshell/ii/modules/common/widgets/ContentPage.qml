import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Scrolling body of a settings page.
 *
 * The column is left-aligned and capped rather than centred: the page header
 * above it is left-aligned, and a centred body under a left-aligned title reads
 * as two unrelated things floating in the same pane. The cap exists because
 * settings rows are label-then-control — stretched across a wide window the two
 * ends stop belonging to each other.
 */
StyledFlickable {
    id: root
    property real baseWidth: 600
    property real maxWidth: 880
    property real horizontalPadding: 28
    property bool forceWidth: false
    property real bottomContentPadding: 100

    default property alias contentData: contentColumn.data

    clip: true
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding // Add some padding at the bottom
    implicitWidth: contentColumn.implicitWidth

    ColumnLayout {
        id: contentColumn
        width: Math.min(root.maxWidth, Math.max(root.baseWidth, root.width - root.horizontalPadding * 2))
        anchors {
            top: parent.top
            left: parent.left
            leftMargin: root.horizontalPadding
            topMargin: 20
        }
        spacing: 26
    }
}
