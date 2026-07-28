import QtQuick;

/**
 * Represents a message in an AI conversation. (Kind of) follows the OpenAI API message structure.
 */
QtObject {
    property string role
    property string content
    property string rawContent

    // Reasoning ("thinking") kept out of the content entirely. It used to be spliced
    // into the text as <think> tags, which MarkdownText silently swallows as an
    // unknown tag — so reasoning rendered as part of the answer with no way to tell
    // them apart. Strategies now append here instead, separating discrete blocks
    // with a blank line so the UI can show them as steps.
    property string reasoning
    property double reasoningStartTime: 0 // ms, first reasoning chunk
    property double reasoningEndTime: 0   // ms, first content chunk after reasoning
    property int reasoningTokens: 0       // reported by the API where available
    readonly property bool hasReasoning: reasoning.length > 0
    readonly property real reasoningSeconds: (reasoningStartTime > 0 && reasoningEndTime > reasoningStartTime)
        ? (reasoningEndTime - reasoningStartTime) / 1000 : 0
    // True while reasoning is still arriving — drives the header ticker.
    readonly property bool reasoningActive: reasoningStartTime > 0 && reasoningEndTime === 0 && !done
    // Wall-clock creation time, shown on hover. Zero on messages saved before this
    // existed, which the UI treats as "no timestamp" rather than 1970.
    property double timestamp: Date.now()
    property string fileMimeType
    property string fileUri
    property string fileBase64
    property string fileTextContent  // Extracted text content from non-image files
    property string localFilePath
    property string model
    property bool done: false
    property var annotations: []
    property var annotationSources: []
    property list<string> searchQueries: []
    property string functionName
    property var functionCall
    property string functionResponse
    property bool functionPending: false
    property var functionCallParts
    property bool visibleToUser: true

    // Set on a message that marks an event rather than something anyone said —
    // the model was switched, the context was compacted. The UI draws it as a
    // labelled hairline in place of the usual author/body/controls.
    property string dividerText
    property string dividerIcon

    // Shell-command lifecycle, for the command block.
    //
    // This used to be spliced into `content` as a ```command fence and read back
    // out by sniffing the rendered text: "did the body contain a ✓". So a command
    // whose own output contained a check mark reported success, one awaiting
    // approval looked identical to one already running, and every line of stdout
    // re-parsed the entire message's markdown. State belongs here.
    property string commandState: "" // "" | "pending" | "running" | "done" | "failed" | "rejected"
    property string commandText      // exactly what will run, so the user approves what they read
    property string commandOutput    // tail of the output, shown in the block
    property int commandExitCode: 0
    property string commandVerdict   // why the safety pipeline allowed it or asked for review
    property bool commandAutoApproved: false
}
