import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

RippleButton {
    id: root
    property string query

    // Still running. The chip used to appear the moment the tool was called and
    // look exactly the same whether the lookup was in flight, done, or had
    // failed — which is why a multi-second search registered as a flicker and
    // then an unexplained pause.
    property bool busy: false

    // The same chip carries both tools. A fetch is given a URL, and for one of
    // those "run this through the search engine" is the wrong thing to do on
    // click — the page itself is what you want.
    readonly property bool isUrl: /^https?:\/\//.test(root.query)

    implicitHeight: 30
    leftPadding: 6
    rightPadding: 10
    buttonRadius: Appearance.rounding.verysmall
    colBackground: Appearance.colors.colSurfaceContainerHighest
    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
    colRipple: Appearance.colors.colSurfaceContainerHighestActive

    PointingHandInteraction {}
    onClicked: {
        if (root.isUrl) {
            Qt.openUrlExternally(root.query);
            GlobalStates.sidebarLeftOpen = false;
            return;
        }
        let url = Config.options.search.engineBaseUrl + root.query;
        for (let site of (Config?.options?.search.excludedSites ?? [])) {
            url += ` -site:${site}`;
        }
        Qt.openUrlExternally(url);
        GlobalStates.sidebarLeftOpen = false;
    }

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: rowLayout.implicitWidth
        implicitHeight: rowLayout.implicitHeight
        RowLayout {
            id: rowLayout
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                id: chipIcon
                // progress_activity is Material's spinner glyph; spinning the
                // icon in place keeps the chip the same width, so a row of them
                // doesn't reflow every time one finishes.
                text: root.busy ? "progress_activity"
                    : (root.isUrl ? "link" : "search")
                iconSize: 20
                color: Appearance.m3colors.m3onSurface

                RotationAnimator {
                    target: chipIcon
                    running: root.busy
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    // Left where it stopped rather than snapped back to 0, so a
                    // finished chip doesn't twitch as the glyph swaps.
                    onRunningChanged: if (!running) chipIcon.rotation = 0
                }
            }
            StyledText {
                id: text
                horizontalAlignment: Text.AlignHCenter
                // A full URL is far too long for a chip in a narrow sidebar.
                text: root.isUrl ? StringUtils.shortenUrl(root.query) : root.query
                color: Appearance.m3colors.m3onSurface
            }
        }
    }
}
