import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

MaterialSymbol {
    id: root
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    text: Notifications.silent ? "notifications_paused" : "notifications"
    iconSize: Appearance.font.pixelSize.larger
    color: rightSidebarButton.colText

    Rectangle {
        id: notifPing
        readonly property bool shown: !Notifications.silent && Notifications.unread > 0
        // A notification arriving is exactly the moment you might be looking
        // elsewhere, so the dot pops rather than materialising fully formed.
        visible: opacity > 0
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.3
        transformOrigin: Item.Center
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
        }
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: root.showUnreadCount ? 0 : 1
            topMargin: root.showUnreadCount ? 0 : 3
        }
        radius: Appearance.rounding.full
        color: Appearance.colors.colOnLayer0
        z: 1

        implicitHeight: root.showUnreadCount ? Math.max(notificationCounterText.implicitWidth, notificationCounterText.implicitHeight) : 8
        implicitWidth: implicitHeight

        StyledText {
            id: notificationCounterText
            visible: root.showUnreadCount
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colLayer0
            text: Notifications.unread
        }
    }
}
