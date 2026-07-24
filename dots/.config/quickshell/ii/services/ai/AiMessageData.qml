import QtQuick;

/**
 * Represents a message in an AI conversation. (Kind of) follows the OpenAI API message structure.
 */
QtObject {
    property string role
    property string content
    property string rawContent
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
    property string contentBeforeCommand
    property var functionCallParts
    property bool visibleToUser: true
}
