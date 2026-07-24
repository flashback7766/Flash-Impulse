import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions as CF

/**
 * Claude Code CLI bridge.
 *
 * Instead of calling the Anthropic HTTP API, this strategy shells out to the
 * local `claude` binary in print mode with `--output-format stream-json` and
 * parses its event stream. This lets a Claude subscription power the sidebar
 * (no API key needed) and reuses Claude Code's own tool suite (Read, Bash,
 * Edit, WebSearch, ...) with its permission system instead of the sidebar's
 * run_shell_command layer.
 *
 * Conversation continuity: Claude Code keeps the transcript server-side per
 * session; we capture session_id from the init event and pass --resume on
 * subsequent turns, sending only the newest user message. If the chat has
 * history but no live session (e.g. Quickshell restarted), a compact
 * transcript replay is sent instead so context is not lost.
 */
ApiStrategy {
    id: root

    // Session state — survives reset(), which runs before every request.
    property string sessionId: ""
    property string pendingPrompt: ""
    property string pendingModel: ""
    property bool sawResult: false

    // Stderr goes here instead of polluting the JSON stdout stream.
    readonly property string logDir: Quickshell.env("HOME") + "/.local/share/flash-impulse/logs"

    readonly property string bridgeSystemPrompt: [
        "You are the AI assistant inside the Flash-Impulse desktop shell sidebar (Hyprland + Quickshell).",
        "Answers are rendered as markdown in a chat panel; keep them concise and avoid huge headings.",
        "You may use your tools to inspect or modify the user's system when they ask for it.",
        "When you need the user to pick between options, use the AskUserQuestion tool — the sidebar renders it."
    ].join(" ")

    function clearSession() {
        sessionId = "";
    }

    function reset() {
        sawResult = false;
    }

    function buildEndpoint(model: AiModel): string {
        return ""; // No HTTP endpoint — finalizeScriptContent() replaces the whole script.
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return "";
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools, filePath: string) {
        pendingModel = model.model;

        // Latest user message is the new turn.
        let lastUser = null;
        for (let i = messages.length - 1; i >= 0; i--) {
            if (messages[i].role === "user") { lastUser = messages[i]; break; }
        }
        let prompt = lastUser ? (lastUser.fileTextContent?.length > 0
            ? `${lastUser.rawContent}\n\n[Attached file content]\n${lastUser.fileTextContent}`
            : lastUser.rawContent) : "";

        if (filePath && filePath.length > 0) {
            prompt += `\n\n[The user attached a file at: ${filePath} — read it if relevant.]`;
        }

        // No live session but prior context exists -> replay a compact transcript.
        if (sessionId.length === 0 && messages.length > 1) {
            let transcript = "";
            for (let i = 0; i < messages.length - 1; i++) {
                const m = messages[i];
                if (!m || m.rawContent.length === 0) continue;
                const role = m.role === "user" ? "User" : "Assistant";
                transcript += `${role}: ${m.rawContent}\n`;
            }
            if (transcript.length > 0) {
                prompt = `[Earlier conversation, for context]\n${transcript}\n[New message]\n${prompt}`;
            }
        }

        pendingPrompt = prompt;
        return {}; // Unused — the CLI carries the payload.
    }

    function finalizeScriptContent(scriptContent: string): string {
        const permissionMode = Config?.options.ai?.claudeCodePermissionMode ?? "acceptEdits";
        const heredoc = "FI_CLAUDE_PROMPT_EOF";
        const args = [
            "-p",
            "--output-format stream-json",
            "--verbose",
            `--model '${root.pendingModel}'`,
            `--permission-mode '${permissionMode}'`,
            `--append-system-prompt '${CF.StringUtils.shellSingleQuoteEscape(root.bridgeSystemPrompt)}'`,
        ];
        if (root.sessionId.length > 0) args.push(`--resume '${root.sessionId}'`);

        // Guard against heredoc delimiter collision in user text.
        const promptBody = root.pendingPrompt.split(heredoc).join("FI_CLAUDE_PROMPT_");

        return "#!/usr/bin/env bash\n"
            + `export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"\n`
            // Claude Code sessions are stored per working directory — pin it so
            // --resume always finds the conversation regardless of who spawns us.
            + `cd "$HOME"\n`
            + `mkdir -p '${root.logDir}'\n`
            + `exec 2>>'${root.logDir}/claude-code-bridge.log'\n`
            + `echo "[$(date -Iseconds)] model=${root.pendingModel} resume=${root.sessionId}" >&2\n`
            + `claude ${args.join(" ")} <<'${heredoc}'\n`
            + promptBody + "\n"
            + heredoc + "\n";
    }

    function formatAskUserQuestion(input): string {
        let out = "";
        const questions = input?.questions ?? [];
        for (const q of questions) {
            out += `\n\n❓ **${q.question}**\n`;
            const opts = q.options ?? [];
            for (let i = 0; i < opts.length; i++) {
                out += `\n${i + 1}. **${opts[i].label}**${opts[i].description ? " — " + opts[i].description : ""}`;
            }
            out += `\n\n*${q.multiSelect ? "Reply with the numbers of your choices." : "Reply with a number or your own answer."}*`;
        }
        return out;
    }

    function summarizeToolUse(name, input): string {
        if (name === "Bash") return `$ ${input?.command ?? ""}`;
        if (name === "Read") return `read ${input?.file_path ?? ""}`;
        if (name === "Edit" || name === "Write") return `${name.toLowerCase()} ${input?.file_path ?? ""}`;
        if (name === "WebSearch") return `search: ${input?.query ?? ""}`;
        if (name === "WebFetch") return `fetch: ${input?.url ?? ""}`;
        const argStr = JSON.stringify(input ?? {});
        return `${name} ${argStr.length > 120 ? argStr.slice(0, 120) + "…" : argStr}`;
    }

    function parseResponseLine(line: string, message: AiMessageData) {
        let obj;
        try {
            obj = JSON.parse(line);
        } catch (e) {
            return {}; // Non-JSON noise; stderr is already redirected away.
        }

        if (obj.type === "system" && obj.subtype === "init") {
            root.sessionId = obj.session_id ?? root.sessionId;
            return {};
        }

        if (obj.type === "assistant") {
            const blocks = obj.message?.content ?? [];
            for (const block of blocks) {
                if (block.type === "thinking" && block.thinking?.length > 0) {
                    message.rawContent += `\n<think>\n${block.thinking}\n</think>\n`;
                } else if (block.type === "text" && block.text?.length > 0) {
                    message.rawContent += block.text;
                } else if (block.type === "tool_use") {
                    if (block.name === "AskUserQuestion") {
                        message.rawContent += root.formatAskUserQuestion(block.input);
                    } else {
                        message.rawContent += `\n\`\`\`command\n🔧 ${root.summarizeToolUse(block.name, block.input)}\n\`\`\`\n`;
                    }
                }
            }
            return {};
        }

        if (obj.type === "result") {
            root.sawResult = true;
            root.sessionId = obj.session_id ?? root.sessionId;
            const usage = obj.usage ?? {};
            if (obj.is_error === true) {
                const errText = typeof obj.result === "string" ? obj.result : (obj.error ?? "unknown error");
                message.rawContent += `\n\n⚠️ *Claude Code error: ${errText}*`;
            }
            return {
                finished: true,
                tokenUsage: {
                    input: usage.input_tokens ?? 0,
                    output: usage.output_tokens ?? 0,
                    total: (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0)
                        + (usage.cache_read_input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0),
                    cacheRead: usage.cache_read_input_tokens ?? 0,
                    cacheWrite: usage.cache_creation_input_tokens ?? 0,
                },
            };
        }

        // stream_event / rate_limit_event / other system events: ignore.
        return {};
    }

    function onRequestFinished(message: AiMessageData): var {
        if (!root.sawResult && message.rawContent.length === 0) {
            message.rawContent = "⚠️ *The `claude` CLI produced no output. Is it installed and logged in? "
                + `Check ~/.local/share/flash-impulse/logs/claude-code-bridge.log*`;
        }
        return { finished: true };
    }
}
