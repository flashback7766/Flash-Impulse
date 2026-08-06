//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

/**
 * Settings.
 *
 * Material 3 navigation-drawer layout: one destination per topic, grouped into
 * categories, with a search field that flattens the whole tree into a single
 * result list. The old build had eight pages, three of which were grab-bags —
 * "Interface" alone held the lock screen, notifications, overlays, sidebars and
 * the overview — so finding anything meant scrolling a page you had to already
 * know the contents of. Splitting by topic makes the drawer the index.
 */
ApplicationWindow {
    id: root
    property real contentPadding: 8
    property string search: ""
    readonly property bool searching: root.search.trim().length > 0

    // Every destination. `keywords` exists so a search for a word that appears
    // only inside the page (not in its title) still finds it.
    readonly property var pages: [
        {
            id: "home",
            name: Translation.tr("Home"),
            icon: "home",
            category: "",
            description: Translation.tr("The handful of settings worth changing on day one"),
            keywords: "quick start overview dashboard",
            component: "modules/settings/pages/Home.qml"
        },

        {
            id: "style",
            name: Translation.tr("Theme & color"),
            icon: "palette",
            category: Translation.tr("Appearance"),
            description: Translation.tr("Light and dark, when to switch, and how colors are derived"),
            keywords: "dark light auto sunset schedule palette scheme accent transparency material you",
            component: "modules/settings/pages/Theme.qml"
        },
        {
            id: "wallpaper",
            name: Translation.tr("Wallpaper"),
            icon: "wallpaper",
            category: Translation.tr("Appearance"),
            description: Translation.tr("The image behind everything, and how it reacts to the workspace"),
            keywords: "background image parallax selector picker",
            component: "modules/settings/pages/Wallpaper.qml"
        },
        {
            id: "fonts",
            name: Translation.tr("Fonts"),
            icon: "text_fields",
            category: Translation.tr("Appearance"),
            description: Translation.tr("Typefaces for the shell, numbers, code and reading"),
            keywords: "font typeface family monospace reading expressive title",
            component: "modules/settings/pages/Fonts.qml"
        },
        {
            id: "colorgen",
            name: Translation.tr("Color generation"),
            icon: "colors",
            category: Translation.tr("Appearance"),
            description: Translation.tr("How the palette is extracted from the wallpaper"),
            keywords: "material colors generate contrast harmony terminal",
            component: "modules/settings/pages/ColorGeneration.qml"
        },
        {
            id: "desktopclock",
            name: Translation.tr("Desktop clock"),
            icon: "clock_loader_40",
            category: Translation.tr("Appearance"),
            description: Translation.tr("The clock widget drawn on the wallpaper"),
            keywords: "clock analog digital cookie dial hands date quote widget",
            component: "modules/settings/pages/DesktopClock.qml"
        },
        {
            id: "desktopweather",
            name: Translation.tr("Desktop weather"),
            icon: "weather_mix",
            category: Translation.tr("Appearance"),
            description: Translation.tr("The weather widget drawn on the wallpaper"),
            keywords: "weather widget forecast desktop",
            component: "modules/settings/pages/DesktopWeather.qml"
        },

        {
            id: "bar",
            name: Translation.tr("Bar"),
            icon: "toast",
            iconRotation: 180,
            category: Translation.tr("Shell"),
            description: Translation.tr("Where the bar sits and what shape it takes"),
            keywords: "bar panel position top bottom left right corner style float hide background",
            component: "modules/settings/pages/Bar.qml"
        },
        {
            id: "barmodules",
            name: Translation.tr("Bar contents"),
            icon: "widgets",
            category: Translation.tr("Shell"),
            description: Translation.tr("Which modules are on it, and how wide the capsules get"),
            keywords: "tray systray utility buttons screenshot color picker keyboard weather tooltip notification count modules resources media clock battery status icons width verbose",
            component: "modules/settings/pages/BarModules.qml"
        },
        {
            id: "workspaces",
            name: Translation.tr("Workspaces"),
            icon: "workspaces",
            category: Translation.tr("Shell"),
            description: Translation.tr("How many are shown, and how they are numbered"),
            keywords: "workspace numbers app icons scroll",
            component: "modules/settings/pages/Workspaces.qml"
        },
        {
            id: "sidebars",
            name: Translation.tr("Sidebars"),
            icon: "side_navigation",
            category: Translation.tr("Shell"),
            description: Translation.tr("The left AI panel and the right quick-settings panel"),
            keywords: "sidebar left right quick toggles sliders corner open translator",
            component: "modules/settings/pages/Sidebars.qml"
        },
        {
            id: "overview",
            name: Translation.tr("Overview & launcher"),
            icon: "overview_key",
            category: Translation.tr("Shell"),
            description: Translation.tr("The workspace grid and the search field over it"),
            keywords: "overview launcher search grid rows columns scale",
            component: "modules/settings/pages/Overview.qml"
        },
        {
            id: "notifications",
            name: Translation.tr("Notifications"),
            icon: "notifications",
            category: Translation.tr("Shell"),
            description: Translation.tr("Popup behaviour and timeouts"),
            keywords: "notification popup timeout do not disturb",
            component: "modules/settings/pages/Notifications.qml"
        },
        {
            id: "osd",
            name: Translation.tr("On-screen display"),
            icon: "voting_chip",
            category: Translation.tr("Shell"),
            description: Translation.tr("The volume and brightness overlay"),
            keywords: "osd volume brightness overlay timeout",
            component: "modules/settings/pages/Osd.qml"
        },
        {
            id: "lockscreen",
            name: Translation.tr("Lock screen"),
            icon: "lock",
            category: Translation.tr("Shell"),
            description: Translation.tr("What the lock screen shows, and how it behaves"),
            keywords: "lock screen idle blur security password fingerprint",
            component: "modules/settings/pages/LockScreen.qml"
        },
        {
            id: "overlays",
            name: Translation.tr("Overlays"),
            icon: "point_scan",
            category: Translation.tr("Shell"),
            description: Translation.tr("Crosshair and floating image, drawn over everything"),
            keywords: "overlay crosshair floating image gaming",
            component: "modules/settings/pages/Overlays.qml"
        },
        {
            id: "screencapture",
            name: Translation.tr("Screen capture"),
            icon: "screenshot_frame_2",
            category: Translation.tr("Shell"),
            description: Translation.tr("Region selection for screenshots and Google Lens"),
            keywords: "screenshot snip region selector google lens circle to search ocr",
            component: "modules/settings/pages/ScreenCapture.qml"
        },
        {
            id: "cheatsheet",
            name: Translation.tr("Cheat sheet"),
            icon: "keyboard",
            category: Translation.tr("Shell"),
            description: Translation.tr("The keybind reference and its keyboard glyphs"),
            keywords: "cheatsheet keybinds shortcuts super key periodic table",
            component: "modules/settings/pages/CheatSheet.qml"
        },

        {
            id: "audio",
            name: Translation.tr("Audio"),
            icon: "volume_up",
            category: Translation.tr("System"),
            description: Translation.tr("Volume limits and step size"),
            keywords: "audio volume sound protection overdrive increment",
            component: "modules/settings/pages/Audio.qml"
        },
        {
            id: "battery",
            name: Translation.tr("Battery"),
            icon: "battery_android_full",
            category: Translation.tr("System"),
            description: Translation.tr("Low-battery warnings and charge limiting"),
            keywords: "battery power charge low critical suspend automatic suspend",
            component: "modules/settings/pages/Battery.qml"
        },
        {
            id: "time",
            name: Translation.tr("Time & date"),
            icon: "nest_clock_farsight_analog",
            category: Translation.tr("System"),
            description: Translation.tr("Clock format across the shell"),
            keywords: "time date format 24 hour clock",
            component: "modules/settings/pages/TimeDate.qml"
        },
        {
            id: "language",
            name: Translation.tr("Language"),
            icon: "language",
            category: Translation.tr("System"),
            description: Translation.tr("Interface language, and generating a missing translation"),
            keywords: "language locale translation translate gemini",
            component: "modules/settings/pages/Language.qml"
        },
        {
            id: "sounds",
            name: Translation.tr("Sounds"),
            icon: "notification_sound",
            category: Translation.tr("System"),
            description: Translation.tr("Feedback sounds for shell events"),
            keywords: "sound effects feedback click notification",
            component: "modules/settings/pages/Sounds.qml"
        },
        {
            id: "privacy",
            name: Translation.tr("Privacy & policies"),
            icon: "shield_person",
            category: Translation.tr("System"),
            description: Translation.tr("What the shell is allowed to do, and what it hides at work"),
            keywords: "policy ai weather privacy work safety nsfw blur keywords network",
            component: "modules/settings/pages/Privacy.qml"
        },
        {
            id: "nightlight",
            name: Translation.tr("Night light"),
            icon: "nightlight",
            category: Translation.tr("System"),
            description: Translation.tr("Warming the display after dark"),
            keywords: "night light color temperature blue anti flashbang gamma",
            component: "modules/settings/pages/NightLight.qml"
        },
        {
            id: "input",
            name: Translation.tr("Input & scrolling"),
            icon: "swipe",
            category: Translation.tr("System"),
            description: Translation.tr("How the shell reads your wheel and your touchpad"),
            keywords: "scroll scrolling mouse touchpad wheel dead pixel workaround",
            component: "modules/settings/pages/Input.qml"
        },
        {
            id: "apps",
            name: Translation.tr("Default apps"),
            icon: "apps",
            category: Translation.tr("System"),
            description: Translation.tr("Which program opens when a panel offers to open one"),
            keywords: "apps default terminal task manager network bluetooth password users volume mixer",
            component: "modules/settings/pages/Apps.qml"
        },

        {
            id: "ai",
            name: Translation.tr("AI"),
            icon: "neurology",
            category: Translation.tr("Services"),
            description: Translation.tr("Defaults for the assistant in the left sidebar"),
            keywords: "ai assistant gemini openai claude model system prompt",
            component: "modules/settings/pages/Ai.qml"
        },
        {
            id: "search",
            name: Translation.tr("Search"),
            icon: "search",
            category: Translation.tr("Services"),
            description: Translation.tr("Launcher prefixes, web search and what gets searched"),
            keywords: "search launcher prefix web engine math clipboard emoji",
            component: "modules/settings/pages/Search.qml"
        },
        {
            id: "weatherservice",
            name: Translation.tr("Weather service"),
            icon: "cloud",
            category: Translation.tr("Services"),
            description: Translation.tr("Where weather comes from and how often it refreshes"),
            keywords: "weather location city units metric imperial interval",
            component: "modules/settings/pages/WeatherService.qml"
        },
        {
            id: "network",
            name: Translation.tr("Network"),
            icon: "cell_tower",
            category: Translation.tr("Services"),
            description: Translation.tr("Wi-Fi and Bluetooth polling"),
            keywords: "network wifi bluetooth interval scan",
            component: "modules/settings/pages/Network.qml"
        },
        {
            id: "resources",
            name: Translation.tr("Resources"),
            icon: "memory",
            category: Translation.tr("Services"),
            description: Translation.tr("How often CPU, memory and GPU are polled"),
            keywords: "resources cpu memory gpu vram polling interval",
            component: "modules/settings/pages/Resources.qml"
        },
        {
            id: "files",
            name: Translation.tr("Save paths"),
            icon: "folder",
            category: Translation.tr("Services"),
            description: Translation.tr("Where screenshots and recordings are written"),
            keywords: "path folder screenshot recording save directory",
            component: "modules/settings/pages/Files.qml"
        },
        {
            id: "musicrecognition",
            name: Translation.tr("Music recognition"),
            icon: "music_cast",
            category: Translation.tr("Services"),
            description: Translation.tr("Identifying whatever is currently playing"),
            keywords: "music recognition shazam identify song listen",
            component: "modules/settings/pages/MusicRecognition.qml"
        },

        {
            id: "updates",
            name: Translation.tr("Updates"),
            icon: "deployed_code_update",
            category: Translation.tr("Services"),
            description: Translation.tr("Checking for pending packages"),
            keywords: "updates packages pacman check interval threshold",
            component: "modules/settings/pages/Updates.qml"
        },

        {
            id: "advanced",
            name: Translation.tr("Advanced"),
            icon: "construction",
            category: Translation.tr("About"),
            description: Translation.tr("Titlebars, conflicting programs, and timing workarounds"),
            keywords: "advanced titlebar window conflict kill daemon tray media duplicate race condition hack",
            component: "modules/settings/pages/Advanced.qml"
        },
        {
            id: "about",
            name: Translation.tr("About"),
            icon: "info",
            category: Translation.tr("About"),
            description: Translation.tr("This system, and the dotfiles behind it"),
            keywords: "about version distro kernel dotfiles update git",
            component: "modules/settings/pages/About.qml"
        }
    ]

    // Search matches title, description, category and keywords, so "shazam"
    // reaches Music recognition and "nsfw" reaches Privacy.
    readonly property var visiblePages: {
        if (!root.searching)
            return root.pages;
        const q = root.search.trim().toLowerCase();
        return root.pages.filter(p => `${p.name} ${p.description} ${p.category} ${p.keywords}`.toLowerCase().includes(q));
    }

    property string currentPageId: "home"
    readonly property var currentPage: root.pages.find(p => p.id === root.currentPageId) ?? root.pages[0]

    function goToPage(id: string): void {
        if (id === root.currentPageId)
            return;
        root.currentPageId = id;
    }

    function stepPage(delta: int): void {
        const i = root.pages.findIndex(p => p.id === root.currentPageId);
        const next = (i + delta + root.pages.length) % root.pages.length;
        root.goToPage(root.pages[next].id);
    }

    visible: true
    onClosing: Qt.quit()
    title: "Flash-Impulse Settings"

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 0; // Settings app always only sets one var at a time so delay isn't needed
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1180
    height: 780
    color: Appearance.m3colors.m3background

    // Below this the labels have to go or the content pane gets squeezed into
    // a column too narrow for a two-up ConfigRow.
    readonly property bool navCollapsed: root.width < 1000

    Shortcut {
        sequences: ["Ctrl+F"]
        onActivated: searchField.forceActiveFocus()
    }
    Shortcut {
        sequences: ["Ctrl+Tab", "Ctrl+PgDown"]
        onActivated: root.stepPage(1)
    }
    Shortcut {
        sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]
        onActivated: root.stepPage(-1)
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }
        spacing: root.contentPadding

        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)

            StyledText {
                id: titleText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right

                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding

            Item { // Navigation drawer
                Layout.fillHeight: true
                implicitWidth: root.navCollapsed ? 68 : 272

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    // Search. Hidden in the rail: a text field 68px wide is a
                    // worse affordance than no text field at all.
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: root.navCollapsed ? 48 : searchField.implicitHeight
                        clip: true

                        MaterialTextField {
                            id: searchField
                            anchors.fill: parent
                            visible: !root.navCollapsed
                            // A full pill with room for a leading glyph — this
                            // is a search bar, and it should not look like the
                            // value fields on the pages beside it.
                            fieldRadius: Appearance.rounding.full
                            leftPadding: 44
                            rightPadding: root.searching ? 40 : 14
                            placeholderText: Translation.tr("Search settings")
                            text: root.search
                            onTextChanged: root.search = text
                            Keys.onEscapePressed: {
                                searchField.text = "";
                                searchField.focus = false;
                            }
                            // Enter on a filtered list is unambiguous when only
                            // one thing survived the filter.
                            Keys.onReturnPressed: {
                                if (root.visiblePages.length > 0)
                                    root.goToPage(root.visiblePages[0].id);
                            }
                        }

                        MaterialSymbol {
                            anchors {
                                left: parent.left
                                leftMargin: 15
                                verticalCenter: parent.verticalCenter
                            }
                            visible: !root.navCollapsed
                            text: "search"
                            iconSize: 20
                            color: Appearance.colors.colSubtext
                        }

                        RippleButton {
                            anchors {
                                right: parent.right
                                rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            visible: !root.navCollapsed && root.searching
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            onClicked: {
                                searchField.text = "";
                                searchField.forceActiveFocus();
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 16
                                color: Appearance.colors.colSubtext
                            }
                        }

                        RippleButton {
                            anchors.centerIn: parent
                            visible: root.navCollapsed
                            implicitWidth: 48
                            implicitHeight: 48
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSurfaceContainerHigh
                            // Widening the window is the only way to reach the
                            // field, so say so rather than doing nothing.
                            onClicked: root.width = 1180
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "search"
                                iconSize: 22
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledToolTip {
                                text: Translation.tr("Widen the window to search")
                            }
                        }
                    }

                    StyledFlickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        // Slack at the end so the last destination can scroll
                        // clear of the pinned button below it.
                        contentHeight: navColumn.implicitHeight + 12

                        ColumnLayout {
                            id: navColumn
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: root.visiblePages

                                delegate: ColumnLayout {
                                    id: navEntry
                                    required property int index
                                    required property var modelData

                                    // A category header, drawn once above the
                                    // first destination that belongs to it.
                                    // Suppressed while searching: results are a
                                    // flat relevance list, not a tree.
                                    readonly property bool startsCategory: !root.searching && modelData.category.length > 0 && (index === 0 || root.visiblePages[index - 1].category !== modelData.category)

                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 14
                                        Layout.bottomMargin: 2
                                        Layout.leftMargin: 20
                                        visible: navEntry.startsCategory && !root.navCollapsed
                                        text: navEntry.modelData.category
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colSubtext
                                    }

                                    // In the rail the header has no room, so a
                                    // divider carries the same grouping.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 8
                                        Layout.bottomMargin: 8
                                        Layout.leftMargin: 16
                                        Layout.rightMargin: 16
                                        visible: navEntry.startsCategory && root.navCollapsed
                                        implicitHeight: 1
                                        color: Appearance.colors.colOutlineVariant
                                    }

                                    SettingsNavItem {
                                        itemIcon: navEntry.modelData.icon
                                        itemLabel: navEntry.modelData.name
                                        collapsed: root.navCollapsed
                                        toggled: root.currentPageId === navEntry.modelData.id
                                        onClicked: root.goToPage(navEntry.modelData.id)
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.topMargin: 20
                                visible: root.visiblePages.length === 0
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                text: Translation.tr("Nothing matches “%1”").arg(root.search.trim())
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }

                    // Escape hatch for everything this app does not expose.
                    RippleButtonWithIcon {
                        id: configFileButton
                        property bool justCopied: false

                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        Layout.bottomMargin: 4
                        implicitHeight: 48
                        buttonRadius: Appearance.rounding.full
                        materialIcon: justCopied ? "check" : "edit_document"
                        mainText: root.navCollapsed ? "" : (justCopied ? Translation.tr("Path copied") : Translation.tr("Config file"))
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive

                        onClicked: Qt.openUrlExternally(`${Directories.config}/flash-impulse/config.json`)
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/flash-impulse/config.json`);
                            configFileButton.justCopied = true;
                            revertTextTimer.restart();
                        }

                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: configFileButton.justCopied = false
                        }

                        StyledToolTip {
                            text: Translation.tr("Open the shell config file\nRight-click to copy its path")
                        }
                    }
                }
            }

            Rectangle { // Content pane
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Page header. Stays put while the page scrolls, so you can
                    // always see which of thirty destinations you are on.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 28
                        Layout.rightMargin: 28
                        Layout.topMargin: 22
                        Layout.bottomMargin: 14
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            MaterialSymbol {
                                text: root.currentPage.icon
                                rotation: root.currentPage.iconRotation ?? 0
                                iconSize: 30
                                fill: 1
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.currentPage.name
                                color: Appearance.colors.colOnLayer1
                                font {
                                    family: Appearance.font.family.title
                                    pixelSize: Appearance.font.pixelSize.title
                                    variableAxes: Appearance.font.variableAxes.title
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 42
                            text: root.currentPage.description
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20
                        implicitHeight: 1
                        color: Appearance.colors.colOutlineVariant
                    }

                    Loader {
                        id: pageLoader
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        opacity: 1.0
                        active: Config.ready

                        Component.onCompleted: source = root.currentPage.component

                        Connections {
                            target: root
                            function onCurrentPageIdChanged(): void {
                                switchAnim.complete();
                                switchAnim.start();
                            }
                        }

                        SequentialAnimation {
                            id: switchAnim

                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 1
                                to: 0
                                duration: 100
                                easing.type: Appearance.animation.elementMoveExit.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                            }
                            ParallelAnimation {
                                PropertyAction {
                                    target: pageLoader
                                    property: "source"
                                    value: root.currentPage.component
                                }
                                PropertyAction {
                                    target: pageLoader
                                    property: "Layout.topMargin"
                                    value: 16
                                }
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: pageLoader
                                    properties: "opacity"
                                    from: 0
                                    to: 1
                                    duration: 200
                                    easing.type: Appearance.animation.elementMoveEnter.type
                                    easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                                }
                                NumberAnimation {
                                    target: pageLoader
                                    properties: "Layout.topMargin"
                                    to: 0
                                    duration: 200
                                    easing.type: Appearance.animation.elementMoveEnter.type
                                    easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
