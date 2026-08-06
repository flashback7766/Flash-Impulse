pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

Item {
    id: root

    signal clicked(event: var)
    property alias iconText: fabWidget.iconText
    default property alias fabData: fabWidget.data
    property bool enableShadow: true

    anchors {
        verticalCenter: parent.verticalCenter
    }
    implicitWidth: fabWidget.implicitWidth
    implicitHeight: fabWidget.implicitHeight
    Loader {
        active: root.enableShadow
        anchors.fill: parent
        sourceComponent: StyledRectangularShadow {
            // Parented past the Loader on purpose. StyledRectangularShadow fills
            // its target, and anchoring only reaches a parent or a sibling — as
            // the Loader's child it could see neither, so it anchored to nothing
            // and logged for every FAB on screen.
            parent: root
            target: fabWidget
            radius: fabWidget.buttonRadius
        }
    }
    FloatingActionButton {
        id: fabWidget
        onClicked: e => root.clicked(e)
        baseSize: 48
        colBackground: Appearance.colors.colTertiaryContainer
        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
        colRipple: Appearance.colors.colTertiaryContainerActive
        colOnBackground: Appearance.colors.colOnTertiaryContainer
    }
}