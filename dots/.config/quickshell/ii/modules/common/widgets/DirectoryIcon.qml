import QtQuick
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

StyledImage {
    id: root
    required property var fileModelData
    asynchronous: true
    fillMode: Image.PreserveAspectFit

    /**
     * Paint the icon in the shell's own ink.
     *
     * These come from the system icon theme, which picks its colours for
     * whatever that theme assumes — nothing here substitutes them the way a KDE
     * app would, so the folders arrived in a mustard that belongs to neither
     * the light nor the dark palette. The glyphs still differ per folder type;
     * only the ink is ours.
     *
     * Through layer.effect rather than a ColorOverlay child: an effect parented
     * to the item it also reads renders its own output back into itself.
     */
    property color colIcon: Appearance.colors.colOnLayer1
    readonly property bool showsThumbnail: !fileModelData.fileIsDir
        && Images.isValidImageByName(fileModelData.fileName)

    layer.enabled: !root.showsThumbnail
    layer.effect: ColorOverlay {
        color: root.colIcon
    }

    source: {
        if (!fileModelData.fileIsDir)
            return Quickshell.iconPath("application-x-zerosize");

        if ([Directories.documents, Directories.downloads, Directories.music, Directories.pictures, Directories.videos].some(dir => FileUtils.trimFileProtocol(dir) === fileModelData.filePath))
            return Quickshell.iconPath(`folder-${fileModelData.fileName.toLowerCase()}`);

        return Quickshell.iconPath("inode-directory");
    }

    onStatusChanged: {
        if (status === Image.Error)
            source = Quickshell.iconPath("error");
    }

    Process {
        running: !fileModelData.fileIsDir
        command: ["file", "--mime", "-b", fileModelData.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const mime = text.split(";")[0].replace("/", "-");
                root.source = Images.validImageTypes.some(t => mime === `image-${t}`) ? fileModelData.fileUrl : Quickshell.iconPath(mime, "image-missing");
            }
        }
    }
}
