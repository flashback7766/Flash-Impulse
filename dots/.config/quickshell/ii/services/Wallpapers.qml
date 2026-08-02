import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Provides a list of wallpapers and an "apply" action that calls the existing
 * switchwall.sh script. Pretty much a limited file browsing service.
 */
Singleton {
    id: root

    property string thumbgenScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/thumbgen-venv.sh`
    property string generateThumbnailsMagickScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/generate-thumbnails-magick.sh`
    property alias directory: folderModel.folder
    readonly property string effectiveDirectory: FileUtils.trimFileProtocol(folderModel.folder.toString())
    property url defaultFolder: Qt.resolvedUrl(`${Directories.pictures}/Wallpapers`)
    property alias folderModel: folderModel // Expose for direct binding when needed
    property string searchQuery: ""
    readonly property list<string> extensions: [ // TODO: add videos
        "jpg", "jpeg", "png", "webp", "avif", "bmp", "svg"
    ]
    property list<string> wallpapers: [] // List of absolute file paths (without file://)
    readonly property bool thumbnailGenerationRunning: thumbgenProc.running
    property real thumbnailGenerationProgress: 0

    signal changed()
    signal thumbnailGenerated(directory: string)
    signal thumbnailGeneratedFile(filePath: string)

    function load () {} // For forcing initialization
    
    function openFallbackPicker(darkMode = Appearance.m3colors.darkmode) {
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", darkMode ? "dark" : "light"]);
    }

    function apply(path, darkMode = Appearance.m3colors.darkmode) {
        if (!path || path.length === 0) return;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", darkMode ? "dark" : "light", "--image", path]);
        root.changed()
    }

    Process {
        id: selectProc
        property string filePath: ""
        property bool darkMode: Appearance.m3colors.darkmode
        function select(filePath, darkMode = Appearance.m3colors.darkmode) {
            selectProc.filePath = filePath
            selectProc.darkMode = darkMode
            selectProc.exec(["test", "-d", FileUtils.trimFileProtocol(filePath)])
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                setDirectory(selectProc.filePath);
                return;
            }
            root.apply(selectProc.filePath, selectProc.darkMode);
        }
    }

    function select(filePath, darkMode = Appearance.m3colors.darkmode) {
        selectProc.select(filePath, darkMode);
    }

    function randomFromCurrentFolder(darkMode = Appearance.m3colors.darkmode) {
        if (folderModel.count === 0) return;
        const randomIndex = Math.floor(Math.random() * folderModel.count);
        const filePath = folderModel.get(randomIndex, "filePath");
        print("Randomly selected wallpaper:", filePath);
        root.select(filePath, darkMode);
    }

    Process {
        id: validateDirProc
        property string nicePath: ""
        function setDirectoryIfValid(path) {
            validateDirProc.nicePath = FileUtils.trimFileProtocol(path).replace(/\/+$/, "")
            if (/^\/*$/.test(validateDirProc.nicePath)) validateDirProc.nicePath = "/";
            validateDirProc.exec([
                "bash", "-c",
                `if [ -d "${validateDirProc.nicePath}" ]; then echo dir; elif [ -f "${validateDirProc.nicePath}" ]; then echo file; else echo invalid; fi`
            ])
        }
        stdout: StdioCollector {
            onStreamFinished: {
                    root.directory = Qt.resolvedUrl(validateDirProc.nicePath)
                const result = text.trim()
                if (result === "dir") {
                } else if (result === "file") {
                    root.directory = Qt.resolvedUrl(FileUtils.parentDirectory(validateDirProc.nicePath))
                } else {
                    // Ignore
                }
            }
        }
    }
    function setDirectory(path) {
        validateDirProc.setDirectoryIfValid(path)
    }
    function navigateUp() {
        folderModel.navigateUp()
    }
    function navigateBack() {
        folderModel.navigateBack()
    }
    function navigateForward() {
        folderModel.navigateForward()
    }

    // Folder model
    FolderListModelWithHistory {
        id: folderModel
        folder: Qt.resolvedUrl(root.defaultFolder)
        caseSensitive: false
        nameFilters: root.extensions.map(ext => `*${searchQuery.split(" ").filter(s => s.length > 0).map(s => `*${s}*`)}*.${ext}`)
        showDirs: true
        showDotAndDotDot: false
        showOnlyReadable: true
        sortField: FolderListModel.Time
        sortReversed: false
        onCountChanged: {
            root.wallpapers = []
            for (let i = 0; i < folderModel.count; i++) {
                const path = folderModel.get(i, "filePath") || FileUtils.trimFileProtocol(folderModel.get(i, "fileURL"))
                if (path && path.length) root.wallpapers.push(path)
            }
        }
    }

    // Thumbnail generation
    function generateThumbnail(size: string) {
        if (!["normal", "large", "x-large", "xx-large"].includes(size)) throw new Error("Invalid thumbnail size");
        thumbgenProc.directory = root.directory
        thumbgenProc.running = false
        thumbgenProc.command = [
            "bash", "-c",
            `${thumbgenScriptPath} --size ${size} --machine_progress -d ${FileUtils.trimFileProtocol(root.directory)} || ${generateThumbnailsMagickScriptPath} --size ${size} -d ${FileUtils.trimFileProtocol(root.directory)}`,
        ]
        // console.log("[Wallpapers] Updating thumbnails with command ", thumbgenProc.command.join(" "))
        root.thumbnailGenerationProgress = 0
        thumbgenProc.running = true
    }
    Process {
        id: thumbgenProc
        property string directory
        stdout: SplitParser {
            onRead: data => {
                // print("thumb gen proc:", data)
                let match = data.match(/PROGRESS (\d+)\/(\d+)/)
                if (match) {
                    const completed = parseInt(match[1])
                    const total = parseInt(match[2])
                    root.thumbnailGenerationProgress = completed / total
                }
                match = data.match(/FILE (.+)/)
                if (match) {
                    const filePath = match[1]
                    root.thumbnailGeneratedFile(filePath)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // print("[Wallpapers] Thumbnail generation completed with exit code", exitCode)
            root.thumbnailGenerated(thumbgenProc.directory)
        }
    }

    IpcHandler {
        target: "wallpapers"

        function apply(path: string): void {
            root.apply(path);
        }
    }

    // ---- light/dark wallpaper pair -----------------------------------------

    // Empty means "the pair we ship". Resolved here rather than as a config
    // default so an existing config.json doesn't have to be edited to get them,
    // and so the paths follow the shell wherever it's installed.
    readonly property string themeWallpaperLight: {
        const set = Config.options?.background.themeWallpaper.light ?? "";
        return set.length > 0 ? FileUtils.trimFileProtocol(set)
            : FileUtils.trimFileProtocol(`${Directories.assetsPath}/images/default_wallpaper.png`);
    }
    readonly property string themeWallpaperDark: {
        const set = Config.options?.background.themeWallpaper.dark ?? "";
        return set.length > 0 ? FileUtils.trimFileProtocol(set)
            : FileUtils.trimFileProtocol(`${Directories.assetsPath}/images/default_wallpaper_dark.png`);
    }
    readonly property bool themeWallpaperEnabled: Config.options?.background.themeWallpaper.enable ?? false

    function themeWallpaperFor(darkMode) {
        return darkMode ? root.themeWallpaperDark : root.themeWallpaperLight;
    }

    function isThemeWallpaper(path) {
        const p = FileUtils.trimFileProtocol(path ?? "");
        if (p.length === 0) return false;
        return p === FileUtils.trimFileProtocol(root.themeWallpaperLight)
            || p === FileUtils.trimFileProtocol(root.themeWallpaperDark);
    }

    /**
     * Swap to the cut that matches the theme.
     *
     * Applied through the same switchwall.sh every other path uses, so the
     * colour scheme is regenerated from whichever image actually ends up on
     * screen. Passing the mode explicitly matters: the script would otherwise
     * re-derive it from gsettings, which at this moment may still be reporting
     * the mode we're in the middle of leaving.
     */
    function applyThemeWallpaper(darkMode) {
        if (!root.themeWallpaperEnabled) return;
        const current = FileUtils.trimFileProtocol(Config.options?.background.wallpaperPath ?? "");
        // The opt-out, and it's derived rather than remembered: swapping only
        // happens while one of the pair is actually on screen. Set a wallpaper
        // of your own and there is nothing here to swap, so the theme stops
        // touching it; go back to one of the pair and it picks up again.
        //
        // A stored "the user went custom" flag would have to be written at the
        // exact moment an external change lands, which is mid-reload of the
        // config file — the write is lost there, and a flag that silently fails
        // to save is a flag that lets the shell overwrite a chosen wallpaper on
        // the next restart. wallpaperPath is already persisted; ask it instead.
        if (!root.isThemeWallpaper(current)) return;
        const wanted = root.themeWallpaperFor(darkMode);
        if (!wanted || wanted.length === 0) return;
        if (current === FileUtils.trimFileProtocol(wanted)) return;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath,
            "--mode", darkMode ? "dark" : "light", "--image", FileUtils.trimFileProtocol(wanted)]);
    }

    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            root.applyThemeWallpaper(Appearance.m3colors.darkmode);
        }
    }

    /** Whether the theme is currently allowed to swap the wallpaper. */
    readonly property bool themeWallpaperActive: root.themeWallpaperEnabled
        && root.isThemeWallpaper(Config.options?.background.wallpaperPath ?? "")
}
