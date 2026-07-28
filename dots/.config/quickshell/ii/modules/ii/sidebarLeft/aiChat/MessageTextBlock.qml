pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var messageData: {}
    property bool done: true
    property bool forceDisableChunkSplitting: false

    property list<string> renderedLatexHashes: []
    property string renderedSegmentContent: ""
    property string shownText: ""
    property bool fadeChunkSplitting: !forceDisableChunkSplitting && !editing && !/\n\|/.test(shownText) && Config.options.sidebar.ai.textFadeIn

    Layout.fillWidth: true

    Timer {
        id: renderTimer
        interval: 1000
        repeat: false
        onTriggered: {
            renderLatex()
            for (const hash of renderedLatexHashes) {
                handleRenderedLatex(hash, true);
            }
        }
    }

    /**
     * True if a `$…$` span is plausibly maths rather than shell.
     *
     * A dollar in a terminal line is a prompt, not a delimiter, and taking
     * `$ which pacman … $ checkupdates` for an equation replaced both commands
     * with a broken image. TeX inline maths never opens or closes against
     * whitespace and never spans a blank line, which is enough to tell them
     * apart without trying to parse either.
     */
    function looksLikeMath(inner, after) {
        if (!inner || inner.length === 0) return false;
        if (/^\s|\s$/.test(inner)) return false;
        if (inner.indexOf("\n") !== -1) return false;
        // "$5 and $10" is money on both ends, not a span.
        if (/^\d/.test(after ?? "")) return false;
        return true;
    }

    function renderLatex() {
        // Fenced and inline code first: a shell snippet is exactly where stray
        // dollars live, and it is never maths.
        const masked = segmentContent
            .replace(/```[\s\S]*?(?:```|$)/g, m => " ".repeat(m.length))
            .replace(/`[^`\n]*`/g, m => " ".repeat(m.length));

        // Regex for $$...$$, $...$, \[...\], \(...\). We pass the full delimited
        // match to the renderer so the later content.replace(expression, image)
        // can find and substitute the original delimited substring back.
        let regex = /(\$\$([\s\S]+?)\$\$)|(\$([^\$]+?)\$)|(\\\[((?:.|\n)+?)\\\])|(\\\(([\s\S]+?)\\\))/g;
        let match;
        while ((match = regex.exec(masked)) !== null) {
            let expression = match[1] || match[3] || match[5] || match[7];
            // Only the single-dollar form is ambiguous; the rest are unmistakable.
            if (match[3] !== undefined
                && !root.looksLikeMath(match[4], masked.slice(regex.lastIndex, regex.lastIndex + 1))) {
                continue;
            }
            if (expression) {
                Qt.callLater(() => {
                    const [renderHash, isNew] = LatexRenderer.requestRender(expression.trim());
                    if (!renderedLatexHashes.includes(renderHash)) {
                        renderedLatexHashes.push(renderHash);
                    }
                });
            }
        }
    }

    function handleRenderedLatex(hash, force = false) {
        if (renderedLatexHashes.includes(hash) || force) {
            const imagePath = LatexRenderer.renderedImagePaths[hash];
            const markdownImage = `![latex](${imagePath})`;

            const expression = LatexRenderer.processedExpressions[hash];
            renderedSegmentContent = renderedSegmentContent.replace(expression, markdownImage);
        }
    }

    onDoneChanged: {
        renderTimer.restart();
    }
    onEditingChanged: {
        if (!editing) {
            renderLatex()
        } else {
            // console.log("Editing mode enabled", segmentContent)
            root.shownText = segmentContent
        }
    }

    onSegmentContentChanged: {
        // console.log("Segment content changed: " + segmentContent);
        renderedSegmentContent = segmentContent;
        if (!root.editing && segmentContent) {
            root.renderLatex();
        }
    }

    onRenderedSegmentContentChanged: {
        // console.log("Rendered segment content changed: " + renderedSegmentContent);
        if (renderedSegmentContent) {
            root.shownText = renderedSegmentContent;
        }
    }

    // When something finishes rendering
    // 1. Check if the hash is in the list
    // 2. If it is, replace the expression with the image path
    Connections {
        target: LatexRenderer
        function onRenderFinished(hash, imagePath) {
            const expression = LatexRenderer.processedExpressions[hash];
            // console.log("Render finished: " + hash + " " + expression);
            handleRenderedLatex(hash);
        }
    }

    spacing: 0
    Repeater {
        id: textLinesRepeater
        property list<real> textLineOpacities: []
        model: ScriptModel {
            // Split by either double newlines or single newlines in a list
            values: root.fadeChunkSplitting ? root.shownText.split(/\n\n(?= {0,2})|\n(?= {0,2}[-\*])/g).filter(line => line.trim() !== "") : [root.shownText]
            onValuesChanged: {
                while (textLinesRepeater.textLineOpacities.length < values.length) {
                    textLinesRepeater.textLineOpacities.push(root.messageData.done ? 1 : 0);
                }
            }
        }
        delegate: TextArea {
            id: textArea
            required property int index
            required property string modelData

            // Fade in animation
            visible: opacity > 0
            opacity: fadeChunkSplitting ? (textLinesRepeater.textLineOpacities[index] ?? (root.messageData.done ? 1 : 0)) : 1
            Connections {
                target: root.messageData
                function onDoneChanged() {
                    if (root.messageData.done) {
                        textLinesRepeater.textLineOpacities[textArea.index] = 1
                    }
                }
            }
            Connections {
                target: textLinesRepeater.model
                function onValuesChanged() {
                    if (textLinesRepeater.model.values.length > textArea.index + 1) {
                        textLinesRepeater.textLineOpacities[textArea.index] = 1
                    }
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Layout.fillWidth: true
            // TextArea brings ~6px of padding of its own from the control style.
            // The user bubble is sized from a separate unwrapped measurement of
            // the same string, which can't see that padding — so a short question
            // got a bubble ~12px too narrow and "Спасибо!" wrapped mid-word.
            padding: 0
            readOnly: !editing
            selectByMouse: enableMouseSelection || editing
            renderType: Text.NativeRendering
            font.family: Appearance.font.family.reading
            font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
            selectionColor: Appearance.colors.colSecondaryContainer
            wrapMode: TextEdit.Wrap
            color: Appearance.colors.colOnLayer1
            textFormat: renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText
            text: modelData

            onTextChanged: {
                if (!root.editing) return
                segmentContent = text
            }

            onLinkActivated: (link) => {
                Qt.openUrlExternally(link)
                GlobalStates.sidebarLeftOpen = false
            }

            MouseArea { // Pointing hand for links
                anchors.fill: parent
                acceptedButtons: Qt.NoButton // Only for hover
                hoverEnabled: true
                cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : 
                    (enableMouseSelection || editing) ? Qt.IBeamCursor : Qt.ArrowCursor
            }

            // Rectangle {
            //     anchors.fill: parent
            //     color: "#22786378"
            //     border.width: 1
            //     border.color: "#7E7E7E"
            // }
        }
    }
}
