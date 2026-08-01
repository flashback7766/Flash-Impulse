import qs.modules.common
import QtQuick

// The sidebar used to be a tab bar over a SwipeView holding the AI chat, the
// translator and the anime browser. The other two are gone, so the chat is now
// the sidebar — no tabs, no SwipeView, and no full-panel layer to mask.
Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent

    function focusActiveItem() {
        aiChat.forceActiveFocus();
    }

    AiChat {
        id: aiChat
        anchors {
            fill: parent
            margins: root.sidebarPadding
        }
    }
}
