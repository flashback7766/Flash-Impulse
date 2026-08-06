pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        // Both directions written out, rather than a binding on currentIndex
        // plus a handler assigning to what that binding reads — which is a
        // cycle, and QML reported it every time the region selector opened.
        // Synchronizer, which the rest of this file uses, can't help here: the
        // two ends are an enum and a tab number, not the same value twice.
        function indexForMode() {
            return root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1;
        }
        onCurrentIndexChanged: {
            root.selectionMode = currentIndex === 0 ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle;
        }
        Component.onCompleted: tabBar.setCurrentIndex(tabBar.indexForMode())
        Connections {
            target: root
            function onSelectionModeChanged() {
                tabBar.setCurrentIndex(tabBar.indexForMode());
            }
        }
    }
}
