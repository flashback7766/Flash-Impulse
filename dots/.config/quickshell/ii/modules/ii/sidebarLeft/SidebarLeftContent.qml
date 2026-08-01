import qs.modules.common
import QtQuick
import Quickshell.Widgets

// The sidebar used to be a tab bar over a SwipeView holding the AI chat, the
// translator and the anime browser. The other two are gone, so the chat is now
// the sidebar — no tabs and no SwipeView.
//
// The layer-1 panel underneath it stays, though. Everything the chat draws —
// the composer, the cards, the message rows — is colLayer2, and colLayer2 is
// defined as an overlay computed over colLayer1Base. Drop the panel and every
// one of those surfaces is sitting on colLayer0 instead, a step further from
// the colour it was picked to contrast with.
Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent

    // Forwarded for SidebarLeft's unload check — see its contentBusy.
    readonly property bool composerBusy: aiChat.composerBusy

    // Quickshell's own rounded-clipping rectangle rather than the layer.effect
    // OpacityMask this replaces: same rounded corners, without rendering the
    // whole panel through an offscreen buffer to get them.
    ClippingRectangle {
        anchors {
            fill: parent
            margins: root.sidebarPadding
        }
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        AiChat {
            id: aiChat
            anchors.fill: parent
        }
    }
}
