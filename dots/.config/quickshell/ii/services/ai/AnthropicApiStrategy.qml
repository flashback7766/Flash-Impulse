import QtQuick

ApiStrategy {
    id: root

    property int inputTokens: 0
    property int cacheReadTokens: 0
    property int cacheWriteTokens: 0
    property string _toolCallName: ""
    property string _toolCallArgs: ""
    property string _toolCallId: ""
    property bool _isToolCall: false

    function reset() {
        inputTokens = 0;
        cacheReadTokens = 0;
        cacheWriteTokens = 0;
        _toolCallName = "";
        _toolCallArgs = "";
        _toolCallId = "";
        _isToolCall = false;
    }

    function buildEndpoint(model) {
        return model.endpoint;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName) {
        return `-H "x-api-key: $${apiKeyEnvVarName}" -H 'anthropic-version: 2023-06-01' -H 'anthropic-beta: prompt-caching-2024-07-31'`
    }

    function buildRequestData(model, messages, systemPrompt, temperature, tools, pendingFilePath) {
        const anthropicMessages = [];

        for (let i = 0; i < messages.length; i++) {
            const msg = messages[i];
            if (msg.role !== "user" && msg.role !== "assistant") continue;

            let contentArray = [];

            // 1. Assistant invokes a tool
            if (msg.role === "assistant" && msg.functionCall && msg.functionName && msg.functionName.length > 0) {
                const textOnly = msg.rawContent ? msg.rawContent.split("\n\n[[ Function:")[0] : "";
                if (textOnly.trim().length > 0) {
                    contentArray.push({ "type": "text", "text": textOnly });
                }
                // If the live message was loaded from disk (or built before the API gave us
                // an id), persist a synthetic id back so the next user tool_result can find it.
                if (!msg.functionCall.id) {
                    const synthId = "toolu_" + i + "_" + Math.random().toString(36).slice(2, 12);
                    msg.functionCall = Object.assign({}, msg.functionCall, { id: synthId });
                }
                contentArray.push({
                    "type": "tool_use",
                    "id": msg.functionCall.id,
                    "name": msg.functionName,
                    "input": msg.functionCall.args || {}
                });
                anthropicMessages.push({ "role": "assistant", "content": contentArray });
                continue;
            }

            // 2. Tool result message (only when a function name is actually present)
            if (msg.role === "user" && msg.functionName && msg.functionName.length > 0) {
                let validToolUseId = null;
                if (i > 0 && messages[i-1]?.functionCall?.id) {
                    validToolUseId = messages[i-1].functionCall.id;
                }

                if (validToolUseId) {
                    contentArray.push({
                        "type": "tool_result",
                        "tool_use_id": validToolUseId,
                        "content": msg.functionResponse || "" 
                    });
                } else {
                    contentArray.push({
                        "type": "text",
                        "text": `[[ Output of ${msg.functionName} ]]:\n${msg.functionResponse || ""}`
                    });
                }
                anthropicMessages.push({ "role": "user", "content": contentArray });
                continue;
            }

            // 3. Regular messages
            const textContent = msg.rawContent || msg.content || "";
            
            if (msg.role === "user" && msg.fileBase64 && msg.fileBase64.length > 0) {
                const mediaType = msg.fileMimeType || "image/png";
                // Images go as image blocks; other types (text, pdf, code) go as text blocks
                if (mediaType.startsWith("image/")) {
                    contentArray.push({
                        "type": "image",
                        "source": { "type": "base64", "media_type": mediaType, "data": msg.fileBase64 }
                    });
                    contentArray.push({ "type": "text", "text": textContent || "Describe this image." });
                } else {
                    // Decode base64 to text and send as a text block
                    const fileName = msg.localFilePath ? msg.localFilePath.split("/").pop() : "attached file";
                    contentArray.push({ "type": "text", "text": "[Attached file: " + fileName + " (" + mediaType + ")]" });
                    contentArray.push({ "type": "text", "text": textContent || "Please analyze this file." });
                }
            } else if (msg.fileTextContent && msg.fileTextContent.length > 0) {
                const fileName = msg.localFilePath ? msg.localFilePath.split("/").pop() : "attached file";
                contentArray.push({ "type": "text", "text": "[Attached file: " + fileName + "]\n```\n" + msg.fileTextContent + "\n```" });
                contentArray.push({ "type": "text", "text": textContent || "Please analyze this file." });
            } else if (textContent.length > 0) {
                contentArray.push({ "type": "text", "text": textContent });
            }

            // Only add to the array if there is actual text or an image
            if (contentArray.length > 0) {
                anthropicMessages.push({ "role": msg.role, "content": contentArray });
            }
        }

        if (Ai.promptCaching && anthropicMessages.length >= 4) {
             // Cache the 4th message from the end (approx) to keep a large chunk cached.
             // Anthropic's cache_control must sit on a text/image/tool_result/tool_use block;
             // pin to the last text block when possible, otherwise the last block.
             const cacheIndex = anthropicMessages.length - 4;
             const msg = anthropicMessages[cacheIndex];
             if (Array.isArray(msg.content) && msg.content.length > 0) {
                 let target = -1;
                 for (let bi = msg.content.length - 1; bi >= 0; bi--) {
                     if (msg.content[bi]?.type === "text") { target = bi; break; }
                 }
                 if (target < 0) target = msg.content.length - 1;
                 msg.content[target].cache_control = {"type": "ephemeral"};
             }
        }

        const requestData = {
            "model": model.model,
            "max_tokens": 8192,
            "messages": anthropicMessages,
            "temperature": temperature,
            "stream": true
        };

        if (tools && tools.length > 0) {
            const cachedTools = JSON.parse(JSON.stringify(tools));
            if (Ai.promptCaching) {
                 // Add cache_control to the last tool to cache the whole toolset
                 cachedTools[cachedTools.length - 1].cache_control = {"type": "ephemeral"};
            }
            requestData["tools"] = cachedTools;
        }

        if (systemPrompt && systemPrompt.length > 0) {
            if (Ai.promptCaching) {
                requestData["system"] = [{
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": {"type": "ephemeral"}
                }];
            } else {
                requestData["system"] = systemPrompt;
            }
        }

        return requestData;
    }

    function buildScriptFileSetup(filePath) {
        const trimmedFilePath = filePath.replace(/^file:\/\//, "");
        const escapedPath = trimmedFilePath.replace(/'/g, "'\\''" );
        let content = "";
        content += "ATTACH_PATH='" + escapedPath + "'\n";
        content += "ATTACH_MIME=$(file -b --mime-type \"$ATTACH_PATH\")\n";
        // Images: base64 → inlineFile JSON (handled as image blocks)
        // Other: read text → textFile JSON (handled as text blocks)
        content += "if echo \"$ATTACH_MIME\" | grep -qE '^image/'; then\n";
        content += "  ATTACH_B64=$(base64 -w0 \"$ATTACH_PATH\")\n";
        content += "  printf '{\"inlineFile\": {\"data\": \"%s\", \"mimeType\": \"%s\"}}\\n,\\n' \"$ATTACH_B64\" \"$ATTACH_MIME\"\n";
        content += "else\n";
        content += "  ATTACH_TEXT=$(head -c 100000 \"$ATTACH_PATH\" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || head -c 50000 \"$ATTACH_PATH\")\n";
        content += "  ATTACH_NAME=$(basename \"$ATTACH_PATH\")\n";
        content += "  printf '{\"textFile\": {\"content\": %s, \"mimeType\": \"%s\", \"name\": \"%s\"}}\\n,\\n' \"$ATTACH_TEXT\" \"$ATTACH_MIME\" \"$ATTACH_NAME\"\n";
        content += "fi\n";
        return content;
    }

    function finalizeScriptContent(content) {
        return content;
    }

    function parseResponseLine(data, message) {
        const cleanData = data.trim();

        if (cleanData.startsWith("event:") || cleanData.length === 0) return {};

        if (!cleanData.startsWith("data:")) {
            try {
                const errJson = JSON.parse(cleanData);
                if (errJson.inlineFile) {
                    message.fileBase64 = errJson.inlineFile.data;
                    message.fileMimeType = errJson.inlineFile.mimeType;
                    return {};
                }
                if (errJson.textFile) {
                    message.fileTextContent = errJson.textFile.content;
                    message.fileMimeType = errJson.textFile.mimeType;
                    if (errJson.textFile.name) message.localFilePath = errJson.textFile.name;
                    return {};
                }
                if (errJson.type === "error" || errJson.error) {
                    const errType = errJson.error?.type ?? "unknown_error";
                    const errMsg = errJson.error?.message ?? JSON.stringify(errJson);
                    message.rawContent += `**API Error** (${errType}): ${errMsg}`;
                    message.content += `**API Error** (${errType}): ${errMsg}`;
                    return { finished: true };
                }
            } catch(e) {
                // Unrecognised non-data line (e.g. HTTP header, keepalive). Skip silently.
                console.log("[Anthropic] Skipping unrecognised line:", cleanData.substring(0, 80));
            }
            return {};
        }

        const jsonStr = cleanData.replace(/^data:\s*/, "").trim();
        if (jsonStr === "[DONE]" || jsonStr.length === 0) return {};

        let json;
        try {
            json = JSON.parse(jsonStr);
        } catch(e) { return {}; }

        if (json.type === "message_start" && json.message?.usage) {
            root.inputTokens = json.message.usage.input_tokens ?? 0;
            root.cacheReadTokens = json.message.usage.cache_read_input_tokens ?? 0;
            root.cacheWriteTokens = json.message.usage.cache_creation_input_tokens ?? 0;
        }

        if (json.type === "content_block_start" && json.content_block?.type === "tool_use") {
            root._isToolCall = true;
            root._toolCallName = json.content_block.name;
            root._toolCallId = json.content_block.id;
            root._toolCallArgs = "";
            return {};
        }

        if (json.type === "content_block_delta" && json.delta?.type === "input_json_delta") {
            root._toolCallArgs += json.delta.partial_json;
            return {};
        }

        if (json.type === "content_block_stop" && root._isToolCall) {
            root._isToolCall = false;
            let args = {};
            try { args = JSON.parse(root._toolCallArgs); } catch(e) {}
            
            const fc = { name: root._toolCallName, args: args, id: root._toolCallId };
            
            message.functionName = root._toolCallName;
            message.functionCall = fc;
            const rawEntry = `\n\n[[ Function: ${root._toolCallName}(${root._toolCallArgs}) ]]\n`;
            message.rawContent += rawEntry;
            
            root._toolCallName = "";
            root._toolCallArgs = "";
            root._toolCallId = "";
            
            return { functionCall: fc, finished: false };
        }

        if (json.type === "content_block_delta" && json.delta?.type === "text_delta") {
            message.rawContent += json.delta.text ?? "";
            return {};
        }

        if (json.type === "message_delta") {
            const outputTokens = json.usage?.output_tokens ?? 0;
            return {
                finished: true,
                tokenUsage: {
                    input: root.inputTokens,
                    output: outputTokens,
                    total: root.inputTokens + outputTokens,
                    cacheRead: root.cacheReadTokens,
                    cacheWrite: root.cacheWriteTokens
                }
            };
        }

        if (json.type === "message_stop") {
            return { finished: true };
        }

        return {};
    }

    function onRequestFinished(message) {
        return { finished: false };
    }
}
