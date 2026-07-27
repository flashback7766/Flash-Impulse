import QtQuick

QtObject {
    function buildEndpoint(model: AiModel): string { throw new Error("Not implemented") }
    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) { throw new Error("Not implemented") }
    function buildAuthorizationHeader(apiKeyEnvVarName: string): string { throw new Error("Not implemented") }
    function parseResponseLine(line: string, message: AiMessageData) { throw new Error("Not implemented") }
    function onRequestFinished(message: AiMessageData): var { return {} } // Default: no special handling

    /**
     * Append a chunk of reasoning to a message and keep its timing straight.
     * `discrete` marks a self-contained block (one Anthropic thinking block, one
     * Gemini thought part) so the UI can render it as its own step; streamed
     * reasoning deltas pass false and simply concatenate.
     */
    function appendReasoning(message: AiMessageData, text: string, discrete: bool) {
        if (!text || text.length === 0) return;
        if (message.reasoningStartTime === 0) message.reasoningStartTime = Date.now();
        if (discrete && message.reasoning.length > 0) message.reasoning += "\n\n";
        message.reasoning += text;
    }

    /** Reasoning has ended: the model started producing the answer proper. */
    function endReasoning(message: AiMessageData) {
        if (message.reasoningStartTime > 0 && message.reasoningEndTime === 0)
            message.reasoningEndTime = Date.now();
    }
    function reset() { } // Reset any internal state if needed
    function buildScriptFileSetup(filePath) { return "" } // Default: no setup
    function finalizeScriptContent(scriptContent: string): string { return scriptContent } // Optionally modify/finalize script
}
