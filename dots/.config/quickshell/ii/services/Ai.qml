pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services.ai

/**
 * AI chat service for Quickshell desktop. Multi-provider LLM client with:
 * - Providers: Gemini, OpenAI, Anthropic, Groq, xAI, DeepSeek, Ollama, any OpenAI-compatible
 * - Features: streaming, function calling (search, shell commands, config editing),
 *   file attachments, chat history,
 *   context compression, export, adaptive UI throttling
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}

    property Component anthropicApiStrategy: AnthropicApiStrategy {}
    property Component claudeCodeApiStrategy: ClaudeCodeApiStrategy {}
    GeminiApiStrategy { id: geminiStrategy }
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    property bool isGenerating: requester.running || commandExecutionProc.running
    property bool aborted: false
    property string previousChatSummary: ""
    property string sessionSummary: "" // Accumulated summary of compressed conversation
    property bool condensing: false // Indicates background summarization is active
    readonly property string summarizerModelId: "gemini-3.5-flash-lite"

    // A message typed while an answer is still streaming is queued rather than
    // interrupting it. Pressing Enter used to abort the running turn, throwing
    // away a half-finished answer nobody had read yet.
    property var queuedMessages: []

    /**
     * @returns true if the message was queued rather than sent immediately.
     */
    function queueUserMessage(text) {
        const message = (text ?? "").trim();
        if (message.length === 0) return false;
        if (root.conversationIdle && root.queuedMessages.length === 0) {
            root.sendUserMessage(message);
            return false;
        }
        root.queuedMessages = [...root.queuedMessages, message];
        return true;
    }

    /**
     * Nothing is in flight and nothing is waiting on the user.
     *
     * Both queueing and draining have to agree on this. They didn't: sending
     * only checked isGenerating, so a message typed while a command sat waiting
     * for approval went straight out and interleaved with the turn that command
     * belonged to.
     */
    readonly property bool conversationIdle: {
        if (root.isGenerating || requester.dispatchAfterExit || requester.retryPending) return false;
        for (let i = 0; i < root.messageIDs.length; i++) {
            if (root.messageByID[root.messageIDs[i]]?.functionPending) return false;
        }
        return true;
    }

    function clearQueue() {
        root.queuedMessages = [];
    }

    function sendNextQueued() {
        if (root.queuedMessages.length === 0) return;
        // Only once the whole exchange has settled. A tool call ends one turn and
        // immediately starts another, and a command can be sitting there waiting
        // for approval — jumping in at either point interleaves two conversations.
        if (!root.conversationIdle) return;
        const next = root.queuedMessages[0];
        root.queuedMessages = root.queuedMessages.slice(1);
        root.sendUserMessage(next);
    }

    onResponseFinished: queueDrainTimer.restart()

    Timer {
        id: queueDrainTimer
        // Long enough for a follow-up turn to have started, so the idle check
        // above sees it rather than racing it.
        interval: 300
        onTriggered: root.sendNextQueued()
    }

    function abortAll() {
        // Stop means stop: a queue drained after an abort would start the very
        // thing the user just interrupted.
        root.clearQueue();
        // Mark aborted so onExited handlers don't auto-restart the conversation
        root.aborted = true;
        // Cancel any pending retry so makeRequest doesn't fire after the user aborted
        if (retryTimer.running) retryTimer.stop();
        if (requester.retryPending) requester.retryPending = false;
        // Drop any deferred follow-up turn that handleFunctionCall queued mid-stream
        requester.dispatchAfterExit = false;
        // A regenerate that never reached the network shouldn't leave its stored
        // answers waiting to attach themselves to whatever asks next.
        requester.pendingVariants = [];
        // Kill any running AI processes
        if (commandExecutionProc.running) {
            commandExecutionProc.running = false;
        }
        if (webSearchProc.running) {
            webSearchProc.running = false;
        }
        if (requester.running) {
            requester.running = false;
        }
        // A command still awaiting approval belongs to the turn just stopped;
        // leaving its buttons live would run it long after the user said no.
        if (requester.message?.functionPending) {
            requester.message.functionPending = false;
            requester.message.commandState = "rejected";
        }
        // Mark current message as done
        if (requester.message && !requester.message.done) {
            if (requester.message.content.length === 0) {
                requester.message.content = Translation.tr("*[Interrupted]*");
                requester.message.rawContent = Translation.tr("*[Interrupted]*");
            }
            requester.message.done = true;
        }
        root.postResponseHook = null;
        root.responseFinished();
    }

    /**
     * Shipped prompt profiles. The inherited prompt is kept as "Custom" rather
     * than being the only option: it mixes tone, presentation and tooling advice
     * into one block, so the profiles below each say one thing well instead.
     *
     * Only the persona lives here. What the machine is (desktopRules) and what
     * the assistant may do (modeRules) are appended by the shell to every
     * profile, since neither is a matter of taste.
     */
    readonly property var promptProfiles: [
        {
            id: "code",
            name: Translation.tr("Code & Linux"),
            icon: "terminal",
            summary: Translation.tr("Pair programming and system work"),
            prompt: "You are a sharp, informal engineer sitting next to the user on their Linux desktop.\n"
                + "- Answer the question asked. No preamble, no restating it back, no \"as an AI\".\n"
                + "- Prefer doing over describing: check the actual state with a command before theorising about it.\n"
                + "- When something is broken, say why it broke, not just what to type. One quick fix and one proper fix, in that order.\n"
                + "- Code gets comments only where the logic isn't obvious. Match the style of the file you're editing.\n"
                + "- Say when you're unsure or when you're guessing, and say what would settle it.\n"
                + "- Format for a narrow sidebar: short paragraphs, bullets over prose, a table when comparing options.\n"
                + "- Use LaTeX in $$ delimiters for maths, never for ordinary documents."
        },
        {
            id: "plain",
            name: Translation.tr("Plain conversation"),
            icon: "chat_bubble",
            summary: Translation.tr("Talking, thinking out loud, no tooling"),
            prompt: "You are a thoughtful, direct conversational partner.\n"
                + "- Talk like a person: plain words, contractions, no bullet-point dumps unless the content is genuinely a list.\n"
                + "- Engage with what was actually said. Disagree when you disagree, and say why.\n"
                + "- Don't run commands or inspect the system unless explicitly asked; this is a conversation, not a work session.\n"
                + "- Length follows the question. A short question gets a short answer."
        },
        {
            id: "terse",
            name: Translation.tr("Terse"),
            icon: "compress",
            summary: Translation.tr("Answer only, minimum words"),
            prompt: "Answer in as few words as the question allows.\n"
                + "- No preamble, no summary, no offers of further help, no restating the question.\n"
                + "- A command, a number or a single sentence is a complete answer when it is one.\n"
                + "- Expand only when correctness genuinely requires it, and only by as much as it requires.\n"
                + "- Never pad with caveats the user didn't ask for."
        },
        {
            id: "ctf",
            name: Translation.tr("CTF & reversing"),
            icon: "lock_open",
            summary: Translation.tr("Security challenges and binary analysis"),
            prompt: "You are assisting with CTF challenges, reverse engineering and authorised security testing.\n"
                + "- Assume competence: skip the introductions to concepts the user clearly already uses.\n"
                + "- Work from evidence — file, strings, checksec, disassembly — before hypothesising.\n"
                + "- Name the class of the bug or the primitive when you spot one, and what it gets you.\n"
                + "- Give concrete payloads, offsets and commands, not descriptions of what a payload would look like.\n"
                + "- This is for challenges and systems the user is authorised to test. If a request looks like it targets "
                + "someone else's live system, say so and stop."
        },
        {
            id: "custom",
            name: Translation.tr("Custom"),
            icon: "edit_note",
            summary: Translation.tr("Whatever is in the config file"),
            prompt: ""
        }
    ]

    property string promptProfile: Persistent.states?.ai?.promptProfile ?? "code"
    readonly property var promptProfileInfo: root.promptProfiles.find(p => p.id === root.promptProfile)
        ?? root.promptProfiles[0]

    function setPromptProfile(id) {
        const profile = root.promptProfiles.find(p => p.id === id);
        if (!profile || id === root.promptProfile) return;
        root.savePersistentState("promptProfile", id);
        root.addDivider(Translation.tr("%1 — %2").arg(profile.name).arg(profile.summary),
            profile.icon, false, "prompt-profile");
    }

    property string systemPrompt: {
        // The custom profile is the config file's prompt; every other profile
        // replaces it outright rather than appending, or the two would argue.
        let prompt = root.promptProfile === "custom"
            ? (Config.options?.ai?.systemPrompt ?? "")
            : root.promptProfileInfo.prompt;
        for (let key in root.promptSubstitutions) {
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        // Appended by the shell rather than living in the editable prompt: these
        // are facts about *this* machine, and they have to survive the user
        // rewriting their prompt — getting them wrong costs a round of commands
        // that edit the wrong file or change something already set.
        return [prompt, root.contextBlock, root.desktopRules, root.modeRules]
            .filter(part => part.length > 0).join("\n\n");
    }

    // Where the assistant is running. Appended to every profile rather than left
    // in the prompt text: it's true regardless of which persona is selected, and
    // a profile that forgot to include it would be answering blind.
    readonly property string contextBlock: {
        const parts = [
            "## Where you are",
            `- ${SystemInfo.distroName}, ${SystemInfo.desktopEnvironment} on ${SystemInfo.windowingSystem}`,
            `- Now: ${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
            `- Focused app: ${ToplevelManager.activeToplevel?.appId ?? "unknown"}`
        ];
        if (root.previousChatSummary.length > 0) {
            parts.push("", "## What the recent conversations were about", root.previousChatSummary);
        }
        return parts.join("\n");
    }

    readonly property string modeRules: {
        if (root.permissionMode === "plan") {
            return "## Plan mode is on\n"
                + "You cannot run commands right now — the tool is refused before it executes, "
                + "so calling it only wastes a turn. Answer with the plan instead: the commands "
                + "you would run in order, each with one line saying what it does and what it "
                + "changes, and call out anything irreversible. The user will switch modes when "
                + "they want it carried out.";
        }
        if (root.permissionMode === "default") {
            return "## Default mode\nEvery command is shown to the user for approval before it runs. "
                + "Keep each one to a single purpose so it can be judged on its own.";
        }
        if (root.permissionMode === "yolo") {
            return "## Yolo mode\nCommands run without review. Nothing will stop a destructive one, "
                + "so be correspondingly careful: prefer the narrowest command that does the job, "
                + "and don't chain unrelated work.";
        }
        return "## Auto mode\nA safety judge clears low-risk commands automatically; anything else "
            + "goes to the user for approval. Keep each command to a single purpose.";
    }

    readonly property string desktopRules: `
## How this desktop is configured (authoritative — don't guess, don't probe for it)

Hyprland here is configured in **Lua**, not hyprlang. There is no \`hyprland.conf\`.
- \`~/.config/hypr/hyprland.lua\` only sources other files. Never edit it.
- \`~/.config/hypr/hyprland/*.lua\` are shipped defaults, replaced on every update. Never edit them.
- \`~/.config/hypr/custom/*.lua\` (\`env\`, \`execs\`, \`general\`, \`keybinds\`, \`rules\`, \`variables\`) and \`~/.config/hypr/monitors.lua\` are the user's. **Edit these.** They load after the defaults, so adding a line here overrides the shipped value — you never need to touch the shipped file to change something.
- Syntax is \`hl.keyword{...}\`, e.g. \`hl.monitor({ output = "DP-1", mode = "1920x1080@144", position = "1920x0", scale = 1 })\`. Match the style already in the file; do not write hyprlang lines into a Lua file.
- \`hyprctl keyword ...\` and \`hyprctl eval '<lua>'\` both change the **running session only** and are lost on reload. Use them to try something, then persist it by **editing the Lua file** — say which file you changed. Nothing in hyprctl writes config to disk.
- Apply config edits with \`hyprctl reload\`. Never log out or restart the compositor for something that reloads.

The shell (Quickshell config "ii"):
- Read its settings with \`get_shell_config\` and change them with \`set_shell_config\`. Do not hand-edit \`~/.config/illogical-impulse/config.json\` — the shell owns that file and will overwrite you.
- Its QML lives in \`~/.config/quickshell/ii\`, which is often a deployed copy of a dotfiles repo. Check for one before editing there, or the change is lost on the next deploy.
- Never kill or restart the shell to apply something that applies live.

## Don't waste turns
- Read the current state first (\`hyprctl monitors\`, \`hyprctl getoption\`, \`get_shell_config\`) and skip the change entirely if it already matches what was asked for.
- One command per step, and read its output before deciding the next one.
- Never re-run a command that already succeeded, and never repeat a read just to confirm it.
- Every command is shown to the user for approval before it runs, so combining unrelated work into one long chain gets the whole thing rejected. Keep each command to one purpose.
`.trim()
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property bool compactMessages: Persistent.states?.ai?.compactMessages ?? false

    function setCompactMessages(enabled) {
        root.savePersistentState("compactMessages", enabled);
    }

    // How much the assistant may do without asking. Shift+Tab cycles it, and the
    // chip beside the input always says which one is active — the difference
    // between "will ask" and "already ran it" is not something to have to guess.
    readonly property var permissionModes: [
        {
            id: "plan",
            name: Translation.tr("Plan"),
            icon: "checklist",
            hint: Translation.tr("Works out what to do and shows it. Runs nothing.")
        },
        {
            id: "default",
            name: Translation.tr("Default"),
            icon: "shield_person",
            hint: Translation.tr("Asks before every command.")
        },
        {
            id: "auto",
            name: Translation.tr("Auto"),
            icon: "bolt",
            hint: Translation.tr("Runs what the safety judge clears; asks about the rest.")
        },
        {
            id: "yolo",
            name: Translation.tr("Yolo"),
            icon: "local_fire_department",
            hint: Translation.tr("Runs everything without asking. You accept the consequences.")
        }
    ]

    property string permissionMode: Persistent.states?.ai?.permissionMode ?? "auto"
    readonly property var permissionModeInfo: root.permissionModes.find(m => m.id === root.permissionMode)
        ?? root.permissionModes[2]
    readonly property bool planMode: root.permissionMode === "plan"

    // The mode in force before the current run of divider-replacing changes, so
    // cycling all the way back around leaves no divider at all.
    property string _modeDividerBaseline: ""

    function setPermissionMode(mode) {
        if (!root.permissionModes.some(m => m.id === mode)) return;
        if (mode === root.permissionMode) return;
        const previous = root.permissionMode;
        root.savePersistentState("permissionMode", mode);

        // Shift+Tab cycles, so reaching the mode you want means passing through
        // the ones you don't. addDivider replaces the previous line for us; the
        // baseline is what makes a full lap around the cycle leave no line at all.
        const lastId = root.messageIDs[root.messageIDs.length - 1];
        if (root.messageByID[lastId]?.dividerKey !== "permission-mode") {
            root._modeDividerBaseline = previous;
        }
        if (mode === root._modeDividerBaseline) {
            if (root.messageByID[lastId]?.dividerKey === "permission-mode") {
                root.removeMessagesRange(root.messageIDs.length - 1, 1);
            }
            return;
        }
        const info = root.permissionModes.find(m => m.id === mode);
        root.addDivider(Translation.tr("%1 mode — %2").arg(info.name).arg(info.hint),
            info.icon, false, "permission-mode");
    }

    function cyclePermissionMode(backwards = false) {
        const modes = root.permissionModes;
        const at = modes.findIndex(m => m.id === root.permissionMode);
        const next = ((at < 0 ? 2 : at) + (backwards ? -1 : 1) + modes.length) % modes.length;
        root.setPermissionMode(modes[next].id);
    }

    // The pipeline reads the mode rather than the other way round, so /yolo and the
    // chip can't disagree about what's actually in force.
    Binding {
        target: root.commandSafety
        property: "yoloMode"
        value: root.permissionMode === "yolo"
    }
    Binding {
        target: root.commandSafety
        property: "alwaysConfirm"
        value: root.permissionMode === "default"
    }

    property bool promptCaching: Persistent.states?.ai?.promptCaching ?? true
    property bool functionsAutoConfirm: true

    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
        property int cacheRead: 0
        property int cacheWrite: 0
    }

    // Generation speed & cost tracking
    property real generationStartTime: 0
    property real generationSpeed: 0 // tokens per second
    property real sessionCost: 0 // accumulated $ cost this session

    // Pricing per million tokens: [input, output] — 0 means free
    readonly property var modelPricing: ({
        "gemini-3.5-flash-lite": [0.30, 2.50],
        "gemini-3.6-flash": [1.50, 7.50],
        "gemini-3.1-pro": [2.00, 12.00],
        "claude-haiku-4-5": [1.00, 5.00],
        "claude-sonnet-5": [3.00, 15.00],
        "claude-opus-4-8": [5.00, 25.00],
        "claude-fable-5": [10.00, 50.00],
        "gpt-5.6-luna": [1.00, 5.00],
        "gpt-5.6-terra": [2.50, 15.00],
        "gpt-5.6-sol": [5.00, 30.00],
    })

    function calculateCost(modelId, inputTokens, outputTokens, cacheReadTokens = 0, cacheWriteTokens = 0) {
        const pricing = root.modelPricing[modelId];
        if (!pricing) return 0;
        // Anthropic input_tokens already excludes cached tokens, so we don't subtract cacheRead.
        // Prompt cache reads ~10% of base price; cache writes ~1.25× base price.
        const effectiveInput = inputTokens + (cacheReadTokens * 0.1) + (cacheWriteTokens * 1.25);
        return (effectiveInput * pricing[0] + outputTokens * pricing[1]) / 1000000;
    }

    function idForMessage(message) {
        // Generate a unique ID using high-res timestamp and random entropy
        return Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 14);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    // Chat titles, for /save and /load completion. Backed by the store index,
    // so it stays in step with the chat list without an ls on every save.
    readonly property list<var> savedChats: chatStore.index.map(e => (e.title ?? "").length > 0 ? e.title : e.id)

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})`,
        "{PREVIOUS_CHAT_CONTEXT}": root.previousChatSummary.length > 0 ? `\n\n## Previous conversation context\n${root.previousChatSummary}` : "",
        "{PREVIOUS_CHAT_HISTORY}": root.previousChatSummary.length > 0 ? `\n\n## Previous conversation context\n${root.previousChatSummary}` : ""
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "search"
    property var tools: {
        "gemini": {
            "functions": [{"functionDeclarations": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
            ]}],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "switch_to_search_mode",
                        "description": "Switch to web search mode to look up current information, recent events, prices, documentation, etc. Use whenever the answer might require up-to-date data.",
                        "parameters": {
                            "type": "object",
                            "properties": {}
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {
                            "type": "object",
                            "properties": {}
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [
                {
                    "type": "function",
                    "function": {
                        "name": "web_search_preview",
                        "description": "Search the web for current information. Use for factual queries, recent events, prices, docs, etc.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": "The search query"
                                }
                            },
                            "required": ["query"]
                        }
                    }
                }
            ],
            "none": [],
        },
        "anthropic": {
            "functions": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Switch to web search mode to look up current information, recent events, prices, documentation, etc. Use whenever the answer might require up-to-date data.",
                    "input_schema": {
                        "type": "object",
                        "properties": {}
                    }
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                    "input_schema": {
                        "type": "object",
                        "properties": {}
                    }
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting."
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run"
                            }
                        },
                        "required": ["command"]
                    }
                }
            ],
            "search": [
                {
                    "name": "web_search_preview",
                    "description": "Search the web for current information. Use for factual queries, recent events, prices, docs, etc.",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "The search query"
                            }
                        },
                        "required": ["query"]
                    }
                }
            ],
            "none": [],
        }
    }
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format] ?? root.tools["openai"])
    property var toolDescriptions: {
        "functions": Translation.tr("Shell commands, config editing, web search.\nModel picks the right tool automatically."),
        "search": Translation.tr("Web search only (fastest for lookup tasks)"),
        "none": Translation.tr("Disable tools")
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
    // - key_get_link: Link to get an API key
    // - key_get_description: Description of pricing and how to get an API key
    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    property var models: Config.options.policies.ai === 2 ? {} : {
        "gemini-3.5-flash-lite": aiModelComponent.createObject(this, {
            "name": "Gemini Flash-Lite",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nFastest & cheapest. Generous free tier. Best for high-volume tasks and simple queries."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:streamGenerateContent",
            "model": "gemini-3.5-flash-lite",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free tier; paid ~$0.30/M input, ~$2.50/M output\n\n**Instructions**: Log into Google account → AI Studio → Get API key"),
            "api_format": "gemini",
        }),
        "gemini-3.6-flash": aiModelComponent.createObject(this, {
            "name": "Gemini Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nLatest stable Flash. Pro-level intelligence at Flash speed, great for agentic workflows and coding."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:streamGenerateContent",
            "model": "gemini-3.6-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free tier; paid ~$1.50/M input, ~$7.50/M output\n\n**Instructions**: Log into Google account → AI Studio → Get API key"),
            "api_format": "gemini",
        }),
        "gemini-3.1-pro": aiModelComponent.createObject(this, {
            "name": "Gemini Pro",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nMost advanced reasoning. Excels at complex problems, coding, and research. 1M context."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro-preview:streamGenerateContent",
            "model": "gemini-3.1-pro-preview",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: ~$2/M input, ~$12/M output\n\n**Instructions**: Log into Google account → AI Studio → Get API key"),
            "api_format": "gemini",
        }),
        "claude-haiku-4-5": aiModelComponent.createObject(this, {
            "name": "Claude Haiku",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Online | Anthropic's model\nFastest Claude model. Great for quick tasks and high-volume use."),
            "homepage": "https://anthropic.com",
            "endpoint": "https://api.anthropic.com/v1/messages",
            "model": "claude-haiku-4-5-20251001",
            "requires_key": true,
            "key_id": "anthropic",
            "key_get_link": "https://console.anthropic.com/settings/keys",
            "key_get_description": Translation.tr("**Pricing**: ~$0.80/M input, ~$4/M output\n\n**Instructions**: Anthropic Console → API Keys → Create Key"),
            "api_format": "anthropic",
        }),
        "claude-sonnet-5": aiModelComponent.createObject(this, {
            "name": "Claude Sonnet",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Online | Anthropic's model\nSmart, efficient. Great at coding, analysis and writing."),
            "homepage": "https://anthropic.com",
            "endpoint": "https://api.anthropic.com/v1/messages",
            "model": "claude-sonnet-5",
            "requires_key": true,
            "key_id": "anthropic",
            "key_get_link": "https://console.anthropic.com/settings/keys",
            "key_get_description": Translation.tr("**Pricing**: ~$3/M input, ~$15/M output\n\n**Instructions**: Anthropic Console → API Keys → Create Key"),
            "api_format": "anthropic",
        }),
        "claude-opus-4-8": aiModelComponent.createObject(this, {
            "name": "Claude Opus",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Online | Anthropic's model\nMost intelligent generally-available Opus. Best for complex reasoning and coding."),
            "homepage": "https://anthropic.com",
            "endpoint": "https://api.anthropic.com/v1/messages",
            "model": "claude-opus-4-8",
            "requires_key": true,
            "key_id": "anthropic",
            "key_get_link": "https://console.anthropic.com/settings/keys",
            "key_get_description": Translation.tr("**Pricing**: ~$5/M input, ~$25/M output\n\n**Instructions**: Anthropic Console → API Keys → Create Key"),
            "api_format": "anthropic",
        }),
        "claude-fable-5": aiModelComponent.createObject(this, {
            "name": "Claude Fable",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Online | Anthropic's model\nFrontier Mythos-class model above Opus. Best for the hardest reasoning tasks."),
            "homepage": "https://anthropic.com",
            "endpoint": "https://api.anthropic.com/v1/messages",
            "model": "claude-fable-5",
            "requires_key": true,
            "key_id": "anthropic",
            "key_get_link": "https://console.anthropic.com/settings/keys",
            "key_get_description": Translation.tr("**Pricing**: ~$10/M input, ~$50/M output\n\n**Instructions**: Anthropic Console → API Keys → Create Key"),
            "api_format": "anthropic",
        }),
        "gpt-5.6-luna": aiModelComponent.createObject(this, {
            "name": "GPT Luna",
            "icon": "openai-symbolic",
            "description": Translation.tr("Online | OpenAI's model\nFastest & cheapest GPT. Best for simple tasks, classification, and data extraction."),
            "homepage": "https://platform.openai.com",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "model": "gpt-5.6-luna",
            "requires_key": true,
            "key_id": "openai",
            "key_get_link": "https://platform.openai.com/api-keys",
            "key_get_description": Translation.tr("**Pricing**: ~$1/M input, ~$5/M output\n\n**Instructions**: platform.openai.com → API Keys → Create new secret key"),
            "api_format": "openai",
        }),
        "gpt-5.6-terra": aiModelComponent.createObject(this, {
            "name": "GPT Terra",
            "icon": "openai-symbolic",
            "description": Translation.tr("Online | OpenAI's model\nFast & capable. Great balance of speed, quality, and cost."),
            "homepage": "https://platform.openai.com",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "model": "gpt-5.6-terra",
            "requires_key": true,
            "key_id": "openai",
            "key_get_link": "https://platform.openai.com/api-keys",
            "key_get_description": Translation.tr("**Pricing**: ~$2.50/M input, ~$15/M output\n\n**Instructions**: platform.openai.com → API Keys → Create new secret key"),
            "api_format": "openai",
        }),
        "gpt-5.6-sol": aiModelComponent.createObject(this, {
            "name": "GPT Sol",
            "icon": "openai-symbolic",
            "description": Translation.tr("Online | OpenAI's model\nFlagship. Best for complex reasoning, coding, and professional work."),
            "homepage": "https://platform.openai.com",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "model": "gpt-5.6-sol",
            "requires_key": true,
            "key_id": "openai",
            "key_get_link": "https://platform.openai.com/api-keys",
            "key_get_description": Translation.tr("**Pricing**: paid\n\n**Instructions**: platform.openai.com → API Keys → Create new secret key"),
            "api_format": "openai",
        }),
        "cc-haiku": aiModelComponent.createObject(this, {
            "name": "Haiku · Claude Code",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Local claude CLI | Uses your Claude subscription, no API key\nFastest Claude. Runs with Claude Code's own tools and permission system."),
            "homepage": "https://claude.com/claude-code",
            "model": "haiku",
            "requires_key": false,
            "api_format": "claude-code",
        }),
        "cc-sonnet": aiModelComponent.createObject(this, {
            "name": "Sonnet · Claude Code",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Local claude CLI | Uses your Claude subscription, no API key\nBalanced Claude. Runs with Claude Code's own tools and permission system."),
            "homepage": "https://claude.com/claude-code",
            "model": "sonnet",
            "requires_key": false,
            "api_format": "claude-code",
        }),
        "cc-opus": aiModelComponent.createObject(this, {
            "name": "Opus · Claude Code",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Local claude CLI | Uses your Claude subscription, no API key\nMost capable Opus. Runs with Claude Code's own tools and permission system."),
            "homepage": "https://claude.com/claude-code",
            "model": "opus",
            "requires_key": false,
            "api_format": "claude-code",
        }),
        "cc-fable": aiModelComponent.createObject(this, {
            "name": "Fable · Claude Code",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Local claude CLI | Uses your Claude subscription, no API key\nAnthropic's frontier Mythos-class model. Availability depends on your plan."),
            "homepage": "https://claude.com/claude-code",
            "model": "fable",
            "requires_key": false,
            "api_format": "claude-code",
        }),
    }
    property var modelList: Object.keys(root.models)
    property var currentModelId: Persistent.states?.ai?.model || modelList[0]
    // Track built-in model IDs so we know which ones are removable
    readonly property var builtinModelIds: [
        "gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.1-pro",
        "claude-haiku-4-5", "claude-sonnet-5", "claude-opus-4-8", "claude-fable-5",
        "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol",
        "cc-haiku", "cc-sonnet", "cc-opus", "cc-fable"
    ]

    function isRemovableModel(modelId) {
        return root.builtinModelIds.indexOf(modelId) === -1;
    }

    function removeModel(modelId) {
        if (!root.isRemovableModel(modelId)) return;
        if (root.currentModelId === modelId) {
            root.setModel(root.modelList[0]); // Switch to first model
        }
        const newModels = Object.assign({}, root.models);
        delete newModels[modelId];
        root.models = newModels;
        root.modelList = Object.keys(root.models);
        root.addMessage(Translation.tr("Removed model: %1").arg(modelId), root.interfaceRole);
    }

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "anthropic": anthropicApiStrategy.createObject(this),
        "claude-code": claudeCodeApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    function addUserModels() {
        (Config?.options.ai?.extraModels ?? []).forEach(model => {
            const safeModelName = root.safeModelName(model["model"]);
            root.addModel(safeModelName, model)
        });
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
        }
    }

    property string pendingFilePath: ""

    Component.onCompleted: {
        // Ensure temporary directory exists
        CF.FileUtils.createDir(CF.FileUtils.trimFileProtocol(Directories.temp));
        
        // If stored model no longer exists (e.g. ollama model removed), fall back to first
        const storedId = (Persistent.states?.ai?.model ?? "").toLowerCase();
        const resolvedId = (storedId.length > 0 && modelList.indexOf(storedId) !== -1)
            ? storedId
            : modelList[0];
        setModel(resolvedId, false, resolvedId !== storedId);
        root.addUserModels();
        
        // Startup opens a fresh empty chat by design — history lives in the chat
        // list, one file per conversation, and is a click away instead of being
        // whatever happened to be on screen when the shell last exited.
        Qt.callLater(() => {
            chatStore.reloadIndex();
        });
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (model.includes("claude")) return "anthropic-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(this, data)
        });
    }

    /**
     * Add a local model with OpenAI-compatible API (Ollama, LM Studio, vLLM, etc.)
     * @param modelName display name / ID
     * @param endpoint API endpoint (default: http://localhost:11434/v1/chat/completions for Ollama)
     * @param modelString the model string to send in the API request
     */
    function addLocalModel(modelName, endpoint, modelString) {
        if (!modelName || modelName.length === 0) return;
        const safeId = root.safeModelName(modelString || modelName);
        const actualEndpoint = endpoint || "http://localhost:11434/v1/chat/completions";
        const actualModel = modelString || modelName;
        root.addModel(safeId, {
            "name": root.guessModelName(modelName),
            "icon": root.guessModelLogo(modelName),
            "description": Translation.tr("Local model | %1\nEndpoint: %2").arg(actualModel).arg(actualEndpoint),
            "homepage": actualEndpoint,
            "endpoint": actualEndpoint,
            "model": actualModel,
            "requires_key": false,
            "api_format": "openai",
        });
        root.modelList = Object.keys(root.models);

        // Write it to the config as well. addModel only touches the in-memory map,
        // which is read back from extraModels at every start — so /addlocal used
        // to report success and then lose the model on the next restart.
        const existing = (Config?.options.ai?.extraModels ?? []).filter(m =>
            root.safeModelName(m["model"]) !== safeId);
        Config.options.ai.extraModels = [...existing, {
            "api_format": "openai",
            "name": root.guessModelName(modelName),
            "icon": root.guessModelLogo(modelName),
            "description": Translation.tr("Local model | %1\nEndpoint: %2").arg(actualModel).arg(actualEndpoint),
            "homepage": actualEndpoint,
            "endpoint": actualEndpoint,
            "model": actualModel,
            "requires_key": false,
        }];

        root.addMessage(Translation.tr("Added local model: **%1**\nEndpoint: `%2`\nModel: `%3`").arg(root.guessModelName(modelName)).arg(actualEndpoint).arg(actualModel), root.interfaceRole);
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    root.modelList = [...root.modelList, ...dataJson];
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                            "api_format": "openai",
                        })
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        // Set the map entry BEFORE pushing the id — reassigning messageIDs fires the
        // ScriptModel signal synchronously, and delegates would bind messageData to
        // Ai.messageByID[id] before the entry exists, ending up stuck on null.
        root.messageByID[id] = aiMessage;
        root.messageIDs = [...root.messageIDs, id];
        root.persistCurrentChat();
    }

    /**
     * A labelled hairline in the conversation marking something that changed.
     * @param atStart put it above everything — for compaction, where the event
     *        applies to the messages that were just removed from the top.
     */
    /**
     * A labelled hairline marking an event rather than something anyone said.
     *
     * `key` groups dividers that supersede one another. Toggling a setting a few
     * times to see what it does should leave the one line saying where you ended
     * up, not one line per step, so a keyed divider replaces the previous one
     * when it is still the last thing in the conversation. Events that are
     * genuinely history — a context compaction — take no key and always stack.
     */
    function addDivider(text, icon, atStart = false, key = "") {
        if (!text || text.length === 0) return;
        if (key.length > 0 && !atStart) {
            const lastId = root.messageIDs[root.messageIDs.length - 1];
            if (lastId && root.messageByID[lastId]?.dividerKey === key) {
                root.removeMessagesRange(root.messageIDs.length - 1, 1);
            }
        }
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": root.interfaceRole,
            "content": "",
            "rawContent": "",
            "dividerText": text,
            "dividerIcon": icon ?? "",
            "dividerKey": key ?? "",
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageByID[id] = aiMessage;
        root.messageIDs = atStart ? [id, ...root.messageIDs] : [...root.messageIDs, id];
        root.persistCurrentChat();
    }

    function removeMessage(index) {
        root.removeMessagesRange(index, 1);
    }

    /**
     * Efficiently removes a range of messages and saves once.
     */
    function removeMessagesRange(startIndex, count) {
        if (startIndex < 0 || startIndex + count > root.messageIDs.length || count <= 0) return;
        
        for (let i = 0; i < count; i++) {
            const id = root.messageIDs[startIndex + i];
            const msg = root.messageByID[id];
            if (msg && msg.destroy) msg.destroy();
            delete root.messageByID[id];
        }
        
        // Reassign with a fresh array so QML's binding system observes the change.
        root.messageIDs = root.messageIDs.slice(0, startIndex).concat(root.messageIDs.slice(startIndex + count));
        root.persistCurrentChat();
    }

    function removeMessageById(id) {
        const index = root.messageIDs.indexOf(id);
        if (index !== -1) {
            root.removeMessage(index);
        }
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"), 
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId];
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        if (modelList.indexOf(modelId) !== -1) {
            root.currentModelId = modelId
            if (setPersistentState) root.savePersistentState("model", modelId)

            // A divider rather than a message: it's an event in the conversation,
            // not something anyone said, and it belongs exactly where it happened.
            if (feedback) root.addDivider(Translation.tr("Switched to %1").arg(models[modelId].name),
                "swap_horiz", false, "model");
            const model = models[modelId]
            // See if policy prevents online models
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported:\n```\n") + modelList.join("\n") + "\n```", Ai.interfaceRole)
        }
    }

    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (isNaN(value) || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        root.savePersistentState("temperature", value)
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    /**
     * Whether a key is set, and enough of it to tell two apart — never the key.
     * It used to print the whole thing into the chat, which then went to disk in
     * the autosave and into the context of the next summarisation call.
     */
    function maskKey(key) {
        if (!key || key.length === 0) return "";
        if (key.length <= 8) return "•".repeat(key.length);
        return `${key.slice(0, 4)}${"•".repeat(6)}${key.slice(-4)}`;
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        const key = root.apiKeys[model.key_id];
        if (key) {
            root.addMessage(Translation.tr("API key for %1 is set: `%2`\n\nIt lives in the system keyring; the shell never shows it in full.")
                .arg(model.name).arg(root.maskKey(key)), Ai.interfaceRole);
        } else {
            root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
        }
    }

    /**
     * Distinct providers that take a key, for the settings panel. Derived from the
     * model catalogue so a new model can't quietly introduce a provider the
     * settings don't know about.
     */
    // Title-casing the id gives "Openai" and "Openrouter"; providers get to be
    // spelled the way they spell themselves.
    readonly property var providerNames: ({
        "gemini": "Google Gemini",
        "anthropic": "Anthropic",
        "openai": "OpenAI",
        "openrouter": "OpenRouter",
        "mistral": "Mistral",
        "deepseek": "DeepSeek",
        "xai": "xAI"
    })

    readonly property var keyProviders: {
        const seen = {};
        const out = [];
        for (const id in root.models) {
            const model = root.models[id];
            if (!model.requires_key || !model.key_id) continue;
            if (seen[model.key_id]) continue;
            seen[model.key_id] = true;
            out.push({
                id: model.key_id,
                name: root.providerNames[model.key_id] ?? CF.StringUtils.toTitleCase(model.key_id),
                keyGetLink: model.key_get_link ?? "",
                exampleModel: id
            });
        }
        return out;
    }

    function setProviderKey(keyId, key) {
        if (!keyId) return;
        KeyringStorage.setNestedField(["apiKeys", keyId], (key ?? "").trim());
    }

    // Raised by `ipc call ai settings` and the input-row button.
    signal settingsRequested

    // ---- key verification --------------------------------------------------

    // "" | "checking" | "ok" | "badkey" | "error", per provider id.
    property var keyCheckState: ({})
    property var keyCheckDetail: ({})
    signal keyChecked(string provider, string state)

    function _setKeyCheck(provider, state, detail) {
        const next = Object.assign({}, root.keyCheckState);
        next[provider] = state;
        root.keyCheckState = next;
        const nextDetail = Object.assign({}, root.keyCheckDetail);
        nextDetail[provider] = detail ?? "";
        root.keyCheckDetail = nextDetail;
        root.keyChecked(provider, state);
    }

    /**
     * Send one throwaway request and report only the HTTP status. Checking the
     * status rather than parsing a reply keeps this the same code for every
     * provider — 200 means the key was accepted, 401/403 means it wasn't, and
     * anything else is worth showing verbatim rather than guessing about.
     */
    function verifyProviderKey(providerId) {
        const provider = root.keyProviders.find(p => p.id === providerId);
        if (!provider) return;
        const key = root.apiKeys[providerId] ?? "";
        if (key.length === 0) {
            root._setKeyCheck(providerId, "badkey", Translation.tr("No key set"));
            return;
        }
        const model = root.models[provider.exampleModel];
        const strategy = model ? root.apiStrategies[model.api_format] : null;
        if (!model || !strategy) {
            root._setKeyCheck(providerId, "error", Translation.tr("No model to test with"));
            return;
        }

        const probe = root.aiMessageComponent.createObject(root, {
            "role": "user", "rawContent": "ping", "content": "ping", "done": true
        });
        let data;
        try {
            data = strategy.buildRequestData(model, [probe], "", 0, [], "");
        } catch (e) {
            probe.destroy();
            root._setKeyCheck(providerId, "error", String(e));
            return;
        }
        probe.destroy();

        const authHeader = strategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
        // buildEndpoint, not model.endpoint: Gemini carries its key as a query
        // parameter and returns nothing from buildAuthorizationHeader, so the raw
        // endpoint sent an unauthenticated probe, got 403, and put a red badge on
        // a key that was working perfectly well two lines further down the file.
        // The URL it returns can contain $API_KEY, which the heredoc has exported.
        const endpoint = strategy.buildEndpoint(model);
        const script = `curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${endpoint}"`
            + ` -H 'Content-Type: application/json'`
            + (authHeader ? ` ${authHeader}` : "")
            + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`;

        keyCheckProc.provider = providerId;
        keyCheckProc.buffer = "";
        // Heredoc, so the key never becomes an argv entry visible in the process list.
        keyCheckProc.command = ["bash", "-c",
            `bash <<'EOP_KEYCHECK'\nexport ${root.apiKeyEnvVarName}='${CF.StringUtils.shellSingleQuoteEscape(key)}'\n${script}\nEOP_KEYCHECK\n`];
        root._setKeyCheck(providerId, "checking", "");
        keyCheckProc.running = true;
    }

    Process {
        id: keyCheckProc
        property string provider: ""
        property string buffer: ""
        stdout: StdioCollector {
            onStreamFinished: keyCheckProc.buffer = text.trim()
        }
        onExited: (exitCode) => {
            const code = parseInt(keyCheckProc.buffer, 10);
            if (exitCode !== 0 || isNaN(code) || code === 0) {
                root._setKeyCheck(keyCheckProc.provider, "error", Translation.tr("Could not reach the provider"));
            } else if (code === 200) {
                root._setKeyCheck(keyCheckProc.provider, "ok", "");
            } else if (code === 401 || code === 403) {
                root._setKeyCheck(keyCheckProc.provider, "badkey", Translation.tr("The provider rejected this key"));
            } else if (code === 429) {
                root._setKeyCheck(keyCheckProc.provider, "error", Translation.tr("Rate limited — the key looks valid but is throttled"));
            } else {
                root._setKeyCheck(keyCheckProc.provider, "error", Translation.tr("Provider answered HTTP %1").arg(code));
            }
        }
    }

    // ---- first run ---------------------------------------------------------

    // No key for anything, so nothing can answer yet. Drives the setup wizard.
    readonly property bool needsSetup: {
        if (!root.apiKeysLoaded) return false;
        for (let i = 0; i < root.keyProviders.length; i++) {
            if ((root.apiKeys[root.keyProviders[i].id] ?? "").length > 0) return false;
        }
        return true;
    }

    /**
     * Write the open conversation to a Markdown file in Downloads. Hidden
     * messages (function calls and their output) are left out — the point is a
     * readable transcript, not a replayable log.
     */
    /**
     * Hide a finished turn that has nothing in it.
     *
     * A tool-call turn's whole content is internal markers, so once they're
     * stripped there is no text, no reasoning and no command left to draw — just
     * an author line and a hover toolbar attached to nothing.
     *
     * Decided here, once, rather than in the delegate: a delegate that hides
     * itself is still an item in the list, and a zero-height item still takes
     * part in the scroll arithmetic, which parked the view above the first real
     * message. Filtering on message content in the list's model instead would
     * re-run over every message on every streamed token.
     */
    function hideIfEmpty(message: AiMessageData) {
        if (!message || !message.visibleToUser) return;
        if ((message.content ?? "").length > 0) return;
        if ((message.reasoning ?? "").length > 0) return;
        if ((message.dividerText ?? "").length > 0) return;
        if ((message.commandState ?? "").length > 0) return;
        if ((message.localFilePath ?? "").length > 0) return;
        message.visibleToUser = false;
    }

    function exportChat() {
        const lines = [];
        const title = root.currentChatDisplayTitle();
        lines.push(`# ${title}`, "");
        for (let i = 0; i < root.messageIDs.length; i++) {
            const message = root.messageByID[root.messageIDs[i]];
            if (!message || !message.visibleToUser) continue;
            if ((message.dividerText ?? "").length > 0) {
                lines.push(`---`, "", `*${message.dividerText}*`, "");
                continue;
            }
            const body = (message.content ?? "").trim();
            const command = (message.commandText ?? "").trim();
            if (body.length === 0 && command.length === 0) continue;

            const who = message.role === "user" ? (SystemInfo.username || "You")
                : message.role === "assistant" ? (root.models[message.model]?.name ?? message.model ?? "Assistant")
                : "Interface";
            lines.push(`## ${who}`, "");
            if ((message.reasoning ?? "").length > 0) {
                lines.push("<details><summary>Reasoning</summary>", "", message.reasoning, "", "</details>", "");
            }
            if (body.length > 0) lines.push(body, "");
            if (command.length > 0) {
                lines.push("```bash", `$ ${command}`, "```", "");
                if ((message.commandOutput ?? "").length > 0) {
                    lines.push("```", message.commandOutput, "```", "");
                }
            }
        }

        const safeTitle = title.replace(/[^\p{L}\p{N} _-]/gu, "").trim().replace(/\s+/g, "-").slice(0, 60) || "chat";
        const dir = CF.FileUtils.trimFileProtocol(Directories.downloads);
        const target = `${dir}/${safeTitle}.md`;
        chatExportProc.target = target;
        chatExportProc.command = ["bash", "-c",
            `printf '%s' '${CF.StringUtils.shellSingleQuoteEscape(lines.join("\n"))}' > '${CF.StringUtils.shellSingleQuoteEscape(target)}'`];
        chatExportProc.running = true;
    }

    Process {
        id: chatExportProc
        property string target: ""
        onExited: (exitCode) => {
            if (exitCode === 0) {
                Quickshell.execDetached(["notify-send", Translation.tr("Chat exported"),
                    Translation.tr("Saved to %1").arg(chatExportProc.target), "-a", "Shell"]);
            } else {
                root.addMessage(Translation.tr("Could not export the chat (exit %1)").arg(exitCode), root.interfaceRole);
            }
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }


    /**
     * Start a new chat. The current one is already on disk (autosave), so this is
     * just "put it away and open a blank one" — nothing is overwritten and nothing
     * rotates out, unlike the old five-slot ring buffer this replaces.
     */
    function newChat() {
        root.persistCurrentChat();
        // Capture the transcript before clearing; the idle summary timer may not
        // have fired yet and the memory of this chat would be lost.
        const summaryTarget = root.currentChatId;
        let transcript = "";
        for (let i = 0; i < root.messageIDs.length; i++) {
            const msg = root.messageByID[root.messageIDs[i]];
            if (!msg || msg.role === root.interfaceRole) continue;
            const role = msg.role === "user" ? "User" : "Assistant";
            transcript += `${role}: ${msg.rawContent}\n`;
        }
        memorySummaryTimer.stop();
        root.clearMessages();
        root.currentChatId = "";
        root.currentChatTitle = "";
        root.currentChatCreatedAt = 0;
        root.currentChatDraft = "";
        root.titleGenerated = false;
        if (summaryTarget.length > 0 && transcript.length > 50) {
            root.generateMemorySummary(`chat_${summaryTarget}`, transcript);
        } else {
            root.loadRecentChatSummaries();
        }
        root.chatOpened("");
    }

    function resetSessionState() {
        // Anything still queued belongs to the conversation being cleared
        root.clearQueue();
        // Destroy any live message objects to avoid leaking QML instances
        for (let i = 0; i < root.messageIDs.length; i++) {
            const msg = root.messageByID[root.messageIDs[i]];
            if (msg && msg.destroy) msg.destroy();
        }
        root.messageIDs = [];
        root.messageByID = ({});
        root.sessionSummary = "";
        root.sessionCost = 0;
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
        root.generationStartTime = 0;
        root.generationSpeed = 0;
        root.condensing = false;
        // The Claude Code CLI session belongs to the conversation being discarded
        root.apiStrategies["claude-code"]?.clearSession();
        root.responseFinished();
    }

    function clearMessages() {
        root.resetSessionState();
    }

    // Approximate token count for a string (~4 chars per token)
    function estimateTokens(text) {
        return Math.ceil((text?.length ?? 0) / 4);
    }

    // Get total estimated tokens in the current chat
    function estimateChatTokens() {
        let total = estimateTokens(root.systemPrompt);
        for (let i = 0; i < root.messageIDs.length; i++) {
            const msg = root.messageByID[root.messageIDs[i]];
            if (msg) total += estimateTokens(msg.rawContent);
        }
        return total;
    }

    function trimContextIfNeeded(maxTokens) {
        if (maxTokens <= 0) return;
        if (estimateChatTokens() <= maxTokens) return;
        if (root.messageIDs.length <= 6) return; // need enough messages to compress

        // Collect oldest messages to compress (keep last 4 messages intact)
        const keepCount = 4;
        const compressCount = root.messageIDs.length - keepCount;
        if (compressCount < 3) return;

        let transcript = "";
        if (root.sessionSummary.length > 0) {
            transcript += `Existing Context Summary: ${root.sessionSummary}\n\n`;
        }
        transcript += "Recent interaction to be compressed:\n";
        for (let i = 0; i < compressCount; i++) {
            const msg = root.messageByID[root.messageIDs[i]];
            if (!msg || msg.role === root.interfaceRole) continue;
            const role = msg.role === "user" ? "User" : "Assistant";
            transcript += `${role}: ${msg.rawContent}\n`;
        }

        root.performSemanticSummary(transcript, compressCount);
    }

    function performSemanticSummary(transcript, countToRemove) {
        // Don't stack summarizer requests — wait for the in-flight one to finish
        if (summarizerProc.running || root.condensing) return;
        const model = models[root.summarizerModelId];
        if (!model) {
            console.log("[AI] Summarizer model not found");
            return;
        }

        const prompt = "You are a conversation summarizer. Condense the provided conversation history into a very tight summary (approx 3-4 lines). " +
                       "Preserve essential context, technical facts, and the user's ultimate goal. If an existing summary is provided, " +
                       "merge the new information into it to maintain a single continuous summary of the session. " +
                       "Output ONLY the plain text summary, no preamble.";

        const summarizerData = geminiStrategy.buildRequestData(model, [{ role: "user", rawContent: transcript }], prompt, 0.3, [], "", false, 0);
        
        // Non-streaming request via summarizerProc (batch generateContent)
        const endpoint = geminiStrategy.buildEndpoint(model).replace(":streamGenerateContent", ":generateContent");
        const apiKey = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : "";
        
        // SECURITY HARDENING: Use in-memory bash heredoc for summarizer to protect API keys.
        const curlCmd = `curl -s "${endpoint}" -H "Content-Type: application/json" --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(summarizerData))}'`;
        const escapedApiKey = CF.StringUtils.shellSingleQuoteEscape(apiKey);
        const bashCommand = `bash <<'EOP_SUMMARIZER'\nexport ${root.apiKeyEnvVarName}='${escapedApiKey}'\n${curlCmd}\nEOP_SUMMARIZER\n`;
        
        root.condensing = true;
        summarizerProc.countToRemove = countToRemove;
        summarizerProc.command = ["bash", "-c", bashCommand];
        summarizerProc.running = true;
    }

    Process {
        id: summarizerProc
        property int countToRemove: 0
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => { summarizerProc.buffer += data; }
        }
        onExited: (exitCode, exitStatus) => {
            root.condensing = false;
            if (exitCode === 0) {
                try {
                    const response = JSON.parse(summarizerProc.buffer);
                    // A blocked or empty candidate has no parts at all.
                    const newSummary = response.candidates?.[0]?.content?.parts?.[0]?.text;
                    if (newSummary && newSummary.length > 0) {
                        root.sessionSummary = newSummary.trim();
                        console.log("[AI] Context compressed. New summary length:", root.sessionSummary.length);
                        const removed = summarizerProc.countToRemove;
                        // Safely remove messages in bulk (this also saves the chat)
                        root.removeMessagesRange(0, removed);
                        // Say so. Compaction used to delete the top of the
                        // conversation silently, which reads as messages going missing.
                        root.addDivider(
                            Translation.tr("Context compacted — %1 earlier messages summarised").arg(removed),
                            "compress", true);
                    }
                } catch (e) { console.log("[AI] Summarizer parse error:", e); }
            }
            summarizerProc.buffer = "";
        }
    }

    // Pull the memory summaries of the few most recently touched chats, so a new
    // conversation starts knowing roughly what the last ones were about.
    property int recentSummaryCount: 5

    function loadRecentChatSummaries() {
        try {
            let summaries = [];
            const recent = chatStore.index.slice(0, root.recentSummaryCount);
            for (let i = 0; i < recent.length; i++) {
                if (recent[i].id === root.currentChatId) continue;
                try {
                    chatSummaryLoader.path = `${Directories.aiChats}/chat_${recent[i].id}.summary.txt`;
                    chatSummaryLoader.reload();
                    const content = chatSummaryLoader.text();
                    if (content && content.length > 5) {
                        summaries.push(`- ${content.trim()}`);
                    } else if ((recent[i].preview ?? "").length > 0) {
                        // No generated summary yet — the opening question is still a
                        // better hint than nothing.
                        summaries.push(`- ${recent[i].title || recent[i].preview}`);
                    }
                } catch (e) {
                    continue;
                }
            }
            root.previousChatSummary = summaries.length > 0
                ? summaries.join("\n").substring(0, 1500)
                : "";
        } catch (e) {
            console.log("[AI] Could not load recent chat summaries:", e);
        }
    }

    Process {
        id: backgroundMemoryProc
        property string chatName: ""
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => { backgroundMemoryProc.buffer += data; }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                try {
                    const response = JSON.parse(backgroundMemoryProc.buffer);
                    // A blocked or empty candidate has no parts at all, and this
                    // runs in the background where a thrown error is just log noise.
                    const newSummary = response.candidates?.[0]?.content?.parts?.[0]?.text;
                    if (newSummary && newSummary.length > 0) {
                        const fileContent = CF.StringUtils.shellSingleQuoteEscape(newSummary.trim());
                        const safeChatName = CF.StringUtils.shellSingleQuoteEscape(backgroundMemoryProc.chatName);
                        const safeDir = CF.StringUtils.shellSingleQuoteEscape(String(Directories.aiChats).replace(/^file:\/\//, ""));
                        saveSummaryProc.command = ["bash", "-c", `printf '%s' '${fileContent}' > '${safeDir}'/'${safeChatName}'.summary.txt`];
                        saveSummaryProc.running = true;
                    }
                } catch (e) { console.log("[AI] Memory Summarizer parse error:", e); }
            }
            backgroundMemoryProc.buffer = "";
            backgroundMemoryProc.chatName = "";
        }
    }

    Process {
        id: saveSummaryProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.loadRecentChatSummaries();
        }
    }

    function generateMemorySummary(chatName, transcript) {
        if (backgroundMemoryProc.running) return;
        const model = models[root.summarizerModelId];
        if (!model) return;
        const prompt = "You are a memory module. Summarize the following chat into a very brief, concise bullet point detailing the context, key decisions, and user's intent. Output ONLY the short summary in the same language as the chat, so it can be injected into the next chat session's memory.";
        const requestData = geminiStrategy.buildRequestData(model, [{ role: "user", rawContent: transcript }], prompt, 0.3, [], "", false, 0);
        
        const endpoint = geminiStrategy.buildEndpoint(model).replace(":streamGenerateContent", ":generateContent");
        const apiKey = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : "";
        if (!apiKey) return;
        
        const curlCmd = `curl -s "${endpoint}" -H "Content-Type: application/json" --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(requestData))}'`;
        const escapedApiKey = CF.StringUtils.shellSingleQuoteEscape(apiKey);
        const bashCommand = `bash <<'EOP_MEMORY'\nexport ${root.apiKeyEnvVarName}='${escapedApiKey}'\n${curlCmd}\nEOP_MEMORY\n`;
        
        backgroundMemoryProc.chatName = chatName;
        backgroundMemoryProc.command = ["bash", "-c", bashCommand];
        backgroundMemoryProc.running = true;
    }

    // ---- automatic chat titles ---------------------------------------------

    property bool titleGenerated: false

    /**
     * Name the chat from its opening exchange, once, using the cheap model. Falls
     * back to a trimmed version of the first question when there's no API key for
     * the summarizer — an untitled chat in the list is worse than a crude title.
     */
    function maybeGenerateTitle() {
        if (root.titleGenerated || root.currentChatId.length === 0) return;
        if (root.messageIDs.length < 2) return;

        let firstUser = "";
        let firstAssistant = "";
        for (let i = 0; i < root.messageIDs.length; i++) {
            const msg = root.messageByID[root.messageIDs[i]];
            if (!msg || msg.role === root.interfaceRole) continue;
            if (!firstUser && msg.role === "user") firstUser = msg.rawContent;
            else if (firstUser && !firstAssistant && msg.role === "assistant") firstAssistant = msg.rawContent;
        }
        if (firstUser.length === 0 || firstAssistant.length === 0) return;

        root.titleGenerated = true; // One attempt per chat, success or not
        root.currentChatTitle = root.fallbackTitle(firstUser);

        const model = models[root.summarizerModelId];
        const apiKey = model ? (root.apiKeys?.[model.key_id] ?? "") : "";
        if (!model || !apiKey || titleProc.running) {
            root.persistCurrentChat();
            return;
        }

        const prompt = "Write a title for this conversation: at most 5 words, no quotes, no trailing period, "
            + "in the same language the user is writing in. Output only the title.";
        const transcript = `User: ${firstUser.substring(0, 800)}\nAssistant: ${firstAssistant.substring(0, 400)}`;
        const requestData = geminiStrategy.buildRequestData(model, [{ role: "user", rawContent: transcript }], prompt, 0.3, [], "", false, 0);
        const endpoint = geminiStrategy.buildEndpoint(model).replace(":streamGenerateContent", ":generateContent");
        const curlCmd = `curl -s "${endpoint}" -H "Content-Type: application/json" --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(requestData))}'`;
        const escapedApiKey = CF.StringUtils.shellSingleQuoteEscape(apiKey);

        titleProc.targetChatId = root.currentChatId;
        titleProc.buffer = "";
        titleProc.command = ["bash", "-c", `bash <<'EOP_TITLE'\nexport ${root.apiKeyEnvVarName}='${escapedApiKey}'\n${curlCmd}\nEOP_TITLE\n`];
        titleProc.running = true;
    }

    function fallbackTitle(text) {
        const clean = (text ?? "").replace(/\s+/g, " ").trim();
        if (clean.length === 0) return "";
        return clean.length > 40 ? clean.slice(0, 40).trim() + "…" : clean;
    }

    Process {
        id: titleProc
        property string targetChatId: ""
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => { titleProc.buffer += data; }
        }
        onExited: exitCode => {
            const raw = titleProc.buffer;
            titleProc.buffer = "";
            if (exitCode !== 0) return;
            let title = "";
            try {
                title = JSON.parse(raw).candidates?.[0]?.content?.parts?.[0]?.text ?? "";
            } catch (e) {
                return;
            }
            title = title.replace(/^["'`\s]+|["'`\s.]+$/g, "").split("\n")[0];
            if (title.length === 0 || title.length > 80) return;
            // The user may have moved on to another chat while this was in flight.
            root.renameChat(titleProc.targetChatId, title);
            if (titleProc.targetChatId === root.currentChatId) root.currentChatTitle = title;
        }
    }

    Timer {
        id: memorySummaryTimer
        interval: 10000 // 10s idle
        onTriggered: {
            if (root.messageIDs.length < 2) return;
            let transcript = "";
            for (let i = 0; i < root.messageIDs.length; i++) {
                const msg = root.messageByID[root.messageIDs[i]];
                if (!msg || msg.role === root.interfaceRole) continue;
                const role = msg.role === "user" ? "User" : "Assistant";
                transcript += `${role}: ${msg.rawContent}\n`;
            }
            if (transcript.length > 50 && root.currentChatId.length > 0) {
                root.generateMemorySummary(`chat_${root.currentChatId}`, transcript);
            }
        }
    }

    FileView {
        id: chatSummaryLoader
        watchChanges: false
        blockLoading: true
    }



    Process {
        id: requester
        property list<string> baseCommand: ["bash", "-c"]
        property AiMessageData message
        property int retryCount: 0
        readonly property int maxRetries: 3
        property bool retryPending: false
        // Set when handleFunctionCall wants to dispatch the follow-up turn but the
        // streaming process hasn't exited yet — drained in onExited.
        property bool dispatchAfterExit: false
        // Earlier answers handed over by regenerateById, attached to the message
        // this request is about to create.
        property var pendingVariants: []
        property ApiStrategy currentStrategy

        function markDone() {
            // Idempotent — strategies sometimes emit `finished:true` twice (e.g. Anthropic's
            // message_delta then message_stop), and we don't want to double-charge cost.
            if (requester.message?.done) return;
            requester.message.done = true;
            // Close the reasoning clock for responses that end without ever emitting
            // text after the thoughts (tool-only turns, aborted streams).
            if (requester.message.reasoningStartTime > 0 && requester.message.reasoningEndTime === 0) {
                requester.message.reasoningEndTime = Date.now();
            }
            // Reset adaptive flush interval for next message
            streamFlushTimer.interval = 50;
            // If content was truncated for large response, now show full content.
            // Route it back through the flusher rather than assigning rawContent
            // directly — that path also strips internal markers and <think> tags.
            if (requester.message.content !== requester.message.rawContent) {
                streamFlushTimer.flushNow();
            }
            root.hideIfEmpty(requester.message);
            // Calculate generation speed
            if (root.generationStartTime > 0 && root.tokenCount.output > 0) {
                const elapsed = (Date.now() - root.generationStartTime) / 1000;
                root.generationSpeed = elapsed > 0 ? Math.round(root.tokenCount.output / elapsed * 10) / 10 : 0;
            }
            // Calculate session cost
            if (root.tokenCount.input > 0) {
                root.sessionCost += root.calculateCost(root.currentModelId, root.tokenCount.input, root.tokenCount.output, root.tokenCount.cacheRead, root.tokenCount.cacheWrite);
            }
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null;
            }
            root.persistCurrentChat()
            memorySummaryTimer.restart()
            root.responseFinished()
        }

        function makeRequest(retry = false) {
            // Defer until the current streaming process exits — otherwise we'd reassign
            // requester.message mid-stream and the trailing `finished:true` chunk would
            // close the wrong (newly-created) message.
            if (requester.running && !retry) {
                requester.dispatchAfterExit = true;
                return;
            }
            if (!retry) requester.retryCount = 0;
            requester.retryPending = false;
            requester.dispatchAfterExit = false;
            // A fresh request clears any prior abort state
            root.aborted = false;
            // Start generation timer
            root.generationStartTime = Date.now();
            root.generationSpeed = 0;

            const model = models[currentModelId];
            if (!model) {
                root.addMessage(Translation.tr("No model selected or model not found. Use /model to pick one."), root.interfaceRole);
                return;
            }

            // Fetch API keys if needed
            if (model.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
            
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Auto-trim context if it's getting too large (~800k chars ≈ 200k tokens) */
            // Trim context to 32k tokens to keep responses fast and cheap
            root.trimContextIfNeeded(32000);

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            // Filter out null entries and interface messages
            let filteredMessageArray = messageArray.filter(message => message != null && message.role !== Ai.interfaceRole);

            // Inject session summary at the beginning if present
            if (root.sessionSummary.length > 0) {
                const summaryMsg = root.aiMessageComponent.createObject(root, {
                    "role": "user",
                    "rawContent": `[IMPORTANT CONTEXT SUMMARY OF PREVIOUS CONVERSATION PART: ${root.sessionSummary}]`,
                    "visibleToUser": false,
                    "done": true
                });
                filteredMessageArray.unshift(summaryMsg);
            }

            const toolsForFormat = root.tools[model.api_format] ?? root.tools["openai"];
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, toolsForFormat[root.currentTool] ?? [], root.pendingFilePath);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            if (!retry) {
                requester.message = root.aiMessageComponent.createObject(root, {
                    "role": "assistant",
                    "model": currentModelId,
                    "content": "",
                    "rawContent": "",
                    "done": false,
                    "variants": requester.pendingVariants ?? [],
                    "variantIndex": 0,
                });
                requester.pendingVariants = [];
                const id = idForMessage(requester.message);
                // map-first so the delegate's `Ai.messageByID[id]` binding is non-null
                // the instant the ScriptModel sees the new id (mutating a `var`'s
                // sub-property doesn't fire QML's property-change signal).
                root.messageByID[id] = requester.message;
                root.messageIDs = [...root.messageIDs, id];
            } else {
                requester.message.rawContent = "";
                requester.message.content = "";
                requester.message.done = false;
            }

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            
            // SECURITY HARDENING: Pass the entire request script through a bash heredoc 
            // to avoid writing sensitive API data to disk.
            const bashCommand = `bash <<'EOP_AI_REQUEST'\n${scriptContent}\nEOP_AI_REQUEST\n`;
            
            requester.command = ["bash", "-c", bashCommand];
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;

                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);

                    if (result.errorCode === 503 && requester.retryCount < requester.maxRetries) {
                        requester.retryCount++;
                        requester.retryPending = true;
                        requester.message.content = Translation.tr("*[High demand. Retrying... (%1/%2)]*").arg(requester.retryCount).arg(requester.maxRetries);
                        retryTimer.interval = 1000 * Math.pow(2, requester.retryCount - 1);
                        retryTimer.start();
                        return;
                    }

                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                        root.tokenCount.cacheRead = result.tokenUsage.cacheRead ?? 0;
                        root.tokenCount.cacheWrite = result.tokenUsage.cacheWrite ?? 0;
                    }
                    if (result.functionCall) {
                        // Flush content immediately before function call
                        streamFlushTimer.flushNow();
                        const callOwner = requester.message;
                        callOwner.functionCall = result.functionCall;
                        // The function call ends THIS turn — close it before dispatching, even if
                        // the strategy also reports finished:true (which would otherwise close
                        // the freshly-created next message instead).
                        if (result.finished) {
                            requester.markDone();
                        }
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, callOwner);
                    } else if (result.finished) {
                        streamFlushTimer.flushNow();
                        requester.markDone();
                    } else {
                        // Schedule debounced content flush
                        streamFlushTimer.restart();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    streamFlushTimer.restart();
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            streamFlushTimer.flushNow();
            const result = requester.currentStrategy.onRequestFinished(requester.message);

            if (requester.retryPending) return;

            // Late functionCall (e.g. OpenAI tool call that didn't get a finish_reason chunk)
            if (result && result.functionCall) {
                const callOwner = requester.message;
                callOwner.functionCall = result.functionCall;
                requester.markDone();
                root.handleFunctionCall(result.functionCall.name, result.functionCall.args, callOwner);
            } else if (result && result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }

            // Handle curl/network errors
            if (exitCode !== 0 && requester.message.content.length === 0) {
                requester.message.content = Translation.tr("**Connection error** (exit code %1). Check your network and API key.").arg(exitCode);
                requester.message.rawContent = requester.message.content;
            }

            // Clean up fileBase64 to free memory (keep path only)
            for (let i = 0; i < root.messageIDs.length; i++) {
                const msg = root.messageByID[root.messageIDs[i]];
                if (msg && msg.fileBase64 && msg.fileBase64.length > 0 && msg.done) {
                    msg.fileBase64 = ""; // Free memory, base64 data no longer needed
                }
            }

            // Drain any deferred follow-up request (function-call tools that sync-dispatched
            // mid-stream). Skip if the user aborted in the meantime.
            if (requester.dispatchAfterExit && !root.aborted) {
                requester.dispatchAfterExit = false;
                Qt.callLater(() => requester.makeRequest());
            } else {
                requester.dispatchAfterExit = false;
            }
        }
    }

    Timer {
        id: retryTimer
        interval: 1000
        onTriggered: requester.makeRequest(true)
    }

    // Debounced content flush: batches rapid token updates into intervals
    // This prevents re-parsing markdown on every single token
    Timer {
        id: streamFlushTimer
        interval: 50
        repeat: false

        // Thresholds for adaptive rendering
        readonly property int mediumContentThreshold: 12000  // Start mild throttling
        readonly property int largeContentThreshold: 40000   // Heavy throttling

        function flushNow() {
            streamFlushTimer.stop();
            if (!requester.message) return;
            const msg = requester.message;

            // Strip hidden internal markers from UI content
            let cleanContent = msg.rawContent.replace(/\[\[\s*(Function|Output of).*?\s*\]\]\n?/g, "").trim();

            // Fallback for models that inline <think> tags in the text rather than
            // exposing reasoning as its own stream field — local models via Ollama
            // mostly. Providers handled at the strategy layer never reach this branch
            // (no tags), and extractThinkTags bails on an indexOf miss, so it's free.
            const split = CF.StringUtils.extractThinkTags(cleanContent);
            if (split.reasoning.length > 0) {
                if (msg.reasoningStartTime === 0) msg.reasoningStartTime = Date.now();
                msg.reasoning = split.reasoning;
                cleanContent = split.content.trim();
                // The tag closed and real text follows: reasoning is over.
                if (msg.reasoningEndTime === 0 && cleanContent.length > 0) msg.reasoningEndTime = Date.now();
            }

            if (msg.content === cleanContent) return;

            const len = cleanContent.length;

            // For large responses during active streaming: throttle hard.
            if (!msg.done && len > largeContentThreshold) {
                const newInterval = Math.min(2000, 80 + Math.floor(len / 1000) * 15);
                if (streamFlushTimer.interval !== newInterval)
                    streamFlushTimer.interval = newInterval;

                const tail = cleanContent.slice(-30000);
                const notice = `> ⚠️ *Large response — showing last 30K of ${Math.round(len/1000)}K chars. Full content sent to model.*\n\n`;
                msg.content = notice + tail;
                return;
            }

            if (!msg.done && len > mediumContentThreshold) {
                const newInterval = Math.min(300, 50 + Math.floor(len / 2000) * 10);
                if (streamFlushTimer.interval !== newInterval)
                    streamFlushTimer.interval = newInterval;
            } else {
                streamFlushTimer.interval = 50;
            }

            msg.content = cleanContent;
        }

        onTriggered: flushNow()
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        root.addMessage(message, "user");
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function snapshotOf(message: AiMessageData) {
        return {
            "content": message.content,
            "rawContent": message.rawContent,
            "reasoning": message.reasoning,
            "reasoningSeconds": message.reasoningSeconds,
            "reasoningTokens": message.reasoningTokens,
            "model": message.model,
            "timestamp": message.timestamp,
            "annotationSources": message.annotationSources,
            "searchQueries": message.searchQueries
        };
    }

    function applySnapshot(message: AiMessageData, snap) {
        message.content = snap.content ?? "";
        message.rawContent = snap.rawContent ?? "";
        message.reasoning = snap.reasoning ?? "";
        // The clock is stored as a duration, so fake a pair that reproduces it.
        message.reasoningStartTime = (snap.reasoning ?? "").length > 0 ? 1 : 0;
        message.reasoningEndTime = (snap.reasoning ?? "").length > 0
            ? 1 + (snap.reasoningSeconds ?? 0) * 1000 : 0;
        message.reasoningTokens = snap.reasoningTokens ?? 0;
        message.model = snap.model ?? "";
        message.timestamp = snap.timestamp ?? 0;
        message.annotationSources = snap.annotationSources ?? [];
        message.searchQueries = snap.searchQueries ?? [];
    }

    /**
     * Regenerate an answer, keeping the one being replaced.
     *
     * Overwriting it meant the only way to compare two attempts was to remember
     * the first, and the only way back was to ask again and hope. The previous
     * answer becomes a variant and the message gains a 1/2 switcher.
     */
    function regenerateById(id) {
        const messageIndex = root.messageIDs.indexOf(id);
        if (messageIndex === -1) return;
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // If the message being regenerated is the one currently streaming, abort the
        // in-flight request first — otherwise removeMessagesRange destroys it under
        // the live requester and onExited writes into a freed object.
        if (requester.running && requester.message === message) {
            root.abortAll();
        }

        // Keep what's on screen, plus anything already stored, and drop the
        // follow-up turns that were answers to the version being replaced.
        const kept = [...(message.variants ?? [])];
        kept.splice(message.variantIndex, 0, root.snapshotOf(message));

        const countToRemove = root.messageIDs.length - messageIndex;
        root.removeMessagesRange(messageIndex, countToRemove);
        requester.pendingVariants = kept;
        requester.makeRequest();
    }

    /**
     * Show a stored answer. The live one is swapped into the store as it leaves,
     * so switching back and forth never loses either.
     */
    function selectVariant(id, index) {
        const message = root.messageByID[id];
        if (!message?.hasVariants) return;
        const clamped = Math.max(0, Math.min(index, message.variantCount - 1));
        if (clamped === message.variantIndex) return;

        const store = [...message.variants];
        // Put the live answer back where it came from, take the requested one out.
        store.splice(message.variantIndex, 0, root.snapshotOf(message));
        const incoming = store.splice(clamped, 1)[0];
        root.applySnapshot(message, incoming);
        message.variants = store;
        message.variantIndex = clamped;
        root.persistCurrentChat();
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        const content = `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n" + output) : ""}`;
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": content,
            "rawContent": content,
            "functionName": name,
            "functionResponse": output,
            "visibleToUser": false,
            "done": true,
        });
    }

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageByID[id] = aiMessage;
        root.messageIDs = [...root.messageIDs, id];
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false;
        message.commandState = "rejected";
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"));
        requester.makeRequest();
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false;
        message.commandState = "running";

        // Instead of creating a separate function output message,
        // we'll track output directly on the assistant message
        commandExecutionProc.assistantMessage = message;
        commandExecutionProc.outputMessage = createFunctionOutputMessage(message.functionName, "", false);
        const id = idForMessage(commandExecutionProc.outputMessage);
        root.messageByID[id] = commandExecutionProc.outputMessage; // Set object FIRST
        root.messageIDs = [...root.messageIDs, id]; // Then trigger the list update

        commandExecutionProc.shellCommand = message.functionCall.args.command;
        commandExecutionProc.running = true;
    }

    // Command safety pipeline (whitelist / blacklist / Gemini judge / YOLO + audit log)
    property CommandSafety commandSafety: CommandSafety {}

    function isDangerousCommand(cmd) {
        return commandSafety.isBlacklisted(cmd);
    }

    // Kept for /yolo, but it moves the permission mode rather than reaching past
    // it — two switches for one behaviour is how they end up disagreeing.
    function setYolo(enabled) {
        if (enabled) {
            root.setPermissionMode("yolo");
            root.addMessage(Translation.tr("⚠️ **Yolo mode** — every command the AI runs is auto-approved, including destructive ones. You accept full responsibility. Shift+Tab or `/mode auto` to step back."), root.interfaceRole);
        } else if (root.permissionMode === "yolo") {
            root.setPermissionMode("auto");
        }
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData assistantMessage
        property AiMessageData outputMessage
        property string collectedOutput: ""
        property int maxOutputChars: 8000 // Truncate command output to prevent huge context
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: (output) => {
                // Strip ANSI escape codes (colors, cursor moves, etc)
                const cleanOutput = output.replace(/\u001b\[[0-9;]*[a-zA-Z]/g, "");
                
                commandExecutionProc.collectedOutput += cleanOutput + "\n";
                // Truncate if too large — keep last N chars
                if (commandExecutionProc.collectedOutput.length > commandExecutionProc.maxOutputChars) {
                    commandExecutionProc.collectedOutput = "[...truncated...]\n" + commandExecutionProc.collectedOutput.slice(-commandExecutionProc.maxOutputChars);
                }
                // Update the hidden function output message for API context
                commandExecutionProc.outputMessage.functionResponse = commandExecutionProc.collectedOutput;
                const outputContent = `[[ Output of ${commandExecutionProc.outputMessage.functionName} ]]\n\n${commandExecutionProc.collectedOutput}`;
                commandExecutionProc.outputMessage.rawContent = outputContent;
                commandExecutionProc.outputMessage.content = outputContent;
                // Live tail in the block. The full output still goes to the model.
                if (commandExecutionProc.assistantMessage) {
                    commandExecutionProc.assistantMessage.commandOutput =
                        commandExecutionProc.collectedOutput.trim().split("\n").slice(-8).join("\n");
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // The output/assistant messages may have been destroyed by clearMessages /
            // abortAll while the process was running — guard every access.
            if (commandExecutionProc.outputMessage) {
                commandExecutionProc.outputMessage.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            }
            if (commandExecutionProc.assistantMessage) {
                const msg = commandExecutionProc.assistantMessage;
                msg.commandOutput = commandExecutionProc.collectedOutput.trim().split("\n").slice(-12).join("\n");
                msg.commandExitCode = exitCode;
                msg.commandState = exitCode === 0 ? "done" : "failed";
            }
            commandExecutionProc.collectedOutput = "";
            if (root.aborted) { root.aborted = false; return; }
            requester.makeRequest();
        }
    }

    // Web search process for OpenAI web_search_preview tool
    Process {
        id: webSearchProc
        property string query: ""
        property AiMessageData message
        property string functionName: "web_search_preview"
        property string collectedOutput: ""

        stdout: SplitParser {
            onRead: (output) => { webSearchProc.collectedOutput += output; }
        }
        onExited: (exitCode, exitStatus) => {
            const results = webSearchProc.collectedOutput.trim();
            const response = results.length > 0
                ? Translation.tr("Search results for \"%1\":\n\n%2").arg(webSearchProc.query).arg(results)
                : Translation.tr("No results found for \"%1\".").arg(webSearchProc.query);
            root.addFunctionOutputMessage(webSearchProc.functionName, response);
            webSearchProc.collectedOutput = "";
            if (root.aborted) { root.aborted = false; return; }
            requester.makeRequest();
        }
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (name === "switch_to_search_mode") {
            root.currentTool = "search";
            root.postResponseHook = () => {
                root.currentTool = Qt.binding(function() { return Config?.options.ai.tool ?? "search"; });
            };
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "web_search_preview") {
            // OpenAI search tool — run a quick web search and return results
            const query = args?.query;
            if (!query || query.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("No query provided."));
                requester.makeRequest();
                return;
            }
            // Show the query as a chip, the same way provider-side search is shown.
            message.searchQueries = [...message.searchQueries, query];
            // Use xdg-open or a simple curl-based DDG search summary
            webSearchProc.query = query;
            webSearchProc.message = message;
            webSearchProc.functionName = name;
            webSearchProc.command = ["bash", "-c", `curl -s -A 'Mozilla/5.0' 'https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}' | grep -oP '(?<=<a class="result__snippet">)[^<]+' | head -5 | tr '\n' ' '`];
            webSearchProc.running = true;
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                requester.makeRequest();
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
            addFunctionOutputMessage(name, Translation.tr("Config updated: %1 = %2").arg(key).arg(value));
            requester.makeRequest();
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            // Plan mode never runs anything. Refusing at the tool boundary rather
            // than trusting the prompt means it holds even when the model forgets.
            if (root.planMode) {
                message.commandText = args.command;
                message.commandState = "rejected";
                message.commandVerdict = Translation.tr("Plan mode — nothing runs");
                addFunctionOutputMessage(name, Translation.tr(
                    "Plan mode is on, so no command was run. Do not try again. "
                    + "Write out the plan instead: the commands you would run, in order, "
                    + "each with one line on what it does and what it changes."));
                requester.makeRequest();
                return;
            }

            message.commandText = args.command;
            message.commandOutput = "";
            message.commandExitCode = 0;
            message.commandVerdict = "";
            message.commandState = "pending";
            message.functionPending = true;
            message.functionName = name; // Ensure functionName is set for UI usage

            // Three-tier safety pipeline: YOLO / blacklist / Gemini judge (see CommandSafety.qml)
            const geminiKey = root.apiKeys ? (root.apiKeys["gemini"] ?? "") : "";
            commandSafety.evaluate(args.command, geminiKey,
                reason => { // allow
                    message.commandVerdict = reason;
                    message.commandAutoApproved = true;
                    root.approveCommand(message);
                },
                reason => { // confirm — leave the Approve/Reject buttons up for the user
                    message.commandVerdict = reason;
                    message.commandAutoApproved = false;
                });
        } else {
            root.addMessage(Translation.tr("Unknown function call: %1").arg(name), root.interfaceRole);
        }
    }

    function chatToJson() {
        return root.messageIDs
            .filter(id => root.messageByID[id] != null)
            .map(id => {
                const message = root.messageByID[id]
                return ({
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "fileTextContent": message.fileTextContent,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "done": true,
                    "timestamp": message.timestamp,
                    "reasoning": message.reasoning,
                    "reasoningSeconds": message.reasoningSeconds,
                    "reasoningTokens": message.reasoningTokens,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionCallParts": message.functionCallParts,
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                    "dividerText": message.dividerText,
                    "dividerIcon": message.dividerIcon,
                    "dividerKey": message.dividerKey,
                    // What ran, so a reopened chat still shows the commands rather
                    // than a run of empty assistant turns. Output is capped: the
                    // model already has the full text in its function response.
                    "commandState": message.commandState,
                    "commandText": message.commandText,
                    "commandExitCode": message.commandExitCode,
                    "commandVerdict": message.commandVerdict,
                    "commandOutput": (message.commandOutput ?? "").slice(-2000),
                    "variants": message.variants,
                    "variantIndex": message.variantIndex,
                })
            })
    }

    ChatStore {
        id: chatStore
        chatsDir: Directories.aiChats
    }

    // Identity of the conversation on screen. Empty id means "not written to disk
    // yet" — an untouched new chat leaves no file behind.
    property string currentChatId: ""
    property string currentChatTitle: ""
    property string currentChatDraft: ""
    property alias chatIndex: chatStore.index

    function currentChatDisplayTitle() {
        if (root.currentChatTitle.length > 0) return root.currentChatTitle;
        return Translation.tr("New chat");
    }

    /**
     * Autosave. Called after every answer, every message edit, and on send —
     * losing a conversation to a crash or a restart is not acceptable, and the
     * write is a single small file.
     */
    /**
     * True once anything has actually been said. Interface lines — mode changes,
     * command output, error notices — are commentary on a conversation, not one
     * themselves; a chat holding nothing else is what you get from cycling a
     * setting on a fresh tab, and it has no business in the history list.
     */
    readonly property bool currentChatHasConversation: {
        for (let i = 0; i < root.messageIDs.length; i++) {
            const role = root.messageByID[root.messageIDs[i]]?.role;
            if (role === "user" || role === "assistant") return true;
        }
        return false;
    }

    function persistCurrentChat() {
        if (!root.currentChatHasConversation) {
            // Nothing to keep. If the chat had already been written, drop the file
            // rather than leaving an empty husk in the list.
            if (root.currentChatId.length > 0) {
                chatStore.remove(root.currentChatId);
                root.currentChatId = "";
            }
            return;
        }
        if (root.currentChatId.length === 0) {
            root.currentChatId = chatStore.newId();
        }
        const claudeCode = root.apiStrategies["claude-code"];
        chatStore.save({
            "id": root.currentChatId,
            "title": root.currentChatTitle,
            "createdAt": root.currentChatCreatedAt > 0 ? root.currentChatCreatedAt : Date.now(),
            "model": root.currentModelId,
            "draft": root.currentChatDraft,
            "sessionSummary": root.sessionSummary,
            // Claude Code keeps the transcript on its side, keyed by session id and
            // working directory; without both, reopening a chat starts a new one.
            "claudeCodeSessionId": claudeCode?.sessionId ?? "",
            "claudeCodeCwd": claudeCode?.sessionCwd ?? "",
            "messages": root.chatToJson()
        });
        root.maybeGenerateTitle();
    }

    property double currentChatCreatedAt: 0

    /**
     * Loads a chat by store id, replacing whatever is on screen.
     */
    function loadChatById(id) {
        const chat = chatStore.load(id);
        if (!chat) {
            // Deliberately not addMessage(): that appends to whatever conversation
            // is open and persists it, so a failed open wrote its own error message
            // into the user's saved chat. And deliberately not remove(): a read can
            // fail for reasons that have nothing to do with the file still being
            // there, and deleting it would turn a bad read into lost history.
            console.log("[AI] No readable chat for id:", id);
            return false;
        }
        root.clearMessages();
        root.currentChatId = chat.id ?? id;
        root.currentChatTitle = chat.title ?? "";
        root.currentChatCreatedAt = chat.createdAt ?? Date.now();
        root.currentChatDraft = chat.draft ?? "";
        root.sessionSummary = chat.sessionSummary ?? "";
        const claudeCode = root.apiStrategies["claude-code"];
        if (claudeCode) {
            claudeCode.sessionId = chat.claudeCodeSessionId ?? "";
            claudeCode.sessionCwd = chat.claudeCodeCwd ?? "";
        }
        root.restoreMessages(chat.messages ?? []);
        root.chatOpened(root.currentChatId);
        return true;
    }

    signal chatOpened(string id)

    /**
     * Rebuilds live message objects from their saved form.
     */
    function restoreMessages(saveData) {
        if (!Array.isArray(saveData)) return;
        const saveIds = saveData.map((_, i) => `loaded_${Date.now()}_${i}`);
        // Populate the map first; assigning messageIDs triggers the UI rebuild,
        // and delegates need messageByID[id] to be live by then.
        for (let i = 0; i < saveData.length; i++) {
            const message = saveData[i];
            if (!message) continue;
            // rawContent is what goes back to the model; the displayed content is
            // it minus internal markers and any inlined <think> tags. Older saves
            // predate the reasoning field, so recover it from the tags on load.
            const rawContent = message.rawContent ?? "";
            const marked = rawContent.replace(/\[\[\s*(Function|Output of).*?\s*\]\]\n?/g, "").trim();
            const split = CF.StringUtils.extractThinkTags(marked);
            const reasoning = (message.reasoning?.length > 0) ? message.reasoning : split.reasoning;
            // Fake a start/end pair that reproduces the saved duration; a non-zero
            // end is also what keeps reasoningActive false on restored messages.
            const reasoningSeconds = message.reasoningSeconds ?? 0;
            root.messageByID[saveIds[i]] = root.aiMessageComponent.createObject(root, {
                "role": message.role,
                "rawContent": rawContent,
                "content": split.content.trim(),
                "reasoning": reasoning,
                "reasoningStartTime": reasoning.length > 0 ? 1 : 0,
                "reasoningEndTime": reasoning.length > 0 ? 1 + reasoningSeconds * 1000 : 0,
                "reasoningTokens": message.reasoningTokens ?? 0,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "fileTextContent": message.fileTextContent ?? "",
                "localFilePath": message.localFilePath,
                "model": message.model,
                "done": message.done ?? true,
                "timestamp": message.timestamp ?? 0,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
                "dividerText": message.dividerText ?? "",
                "dividerIcon": message.dividerIcon ?? "",
                "dividerKey": message.dividerKey ?? "",
                // A command that was still awaiting approval when the chat was
                // saved is not resurrected as pending — the turn it belonged to is
                // long over, so it reads as history.
                "commandState": (message.commandState === "pending" || message.commandState === "running")
                    ? "rejected" : (message.commandState ?? ""),
                "commandText": message.commandText ?? "",
                "commandExitCode": message.commandExitCode ?? 0,
                "commandVerdict": message.commandVerdict ?? "",
                "commandOutput": message.commandOutput ?? "",
                "variants": message.variants ?? [],
                "variantIndex": message.variantIndex ?? 0,
            });
            // Restore Gemini thought signature data (dynamic props, set after creation)
            if (message.functionCallParts) root.messageByID[saveIds[i]].functionCallParts = message.functionCallParts;
            // Chats saved before hideIfEmpty existed still carry tool-call turns
            // marked visible with nothing in them.
            root.hideIfEmpty(root.messageByID[saveIds[i]]);
        }
        root.messageIDs = saveIds;
    }

    /**
     * /save NAME — names the conversation on screen. There is no separate "saved"
     * state any more: everything is already on disk, so this is a rename.
     */
    function saveChat(chatName) {
        const name = (chatName ?? "").trim();
        if (name.length === 0) return;
        root.currentChatTitle = name;
        root.titleGenerated = true; // An explicit name is never overwritten by the auto-titler
        root.persistCurrentChat();
        root.addMessage(Translation.tr("Chat named **%1** ✓").arg(name), root.interfaceRole);
    }

    /**
     * /load NAME — opens a chat by title (or id).
     */
    function loadChat(chatName) {
        const name = (chatName ?? "").trim();
        if (name.length === 0) return;
        const id = chatStore.findByName(name);
        if (!id) {
            root.addMessage(Translation.tr("No chat matching '%1'.").arg(name), root.interfaceRole);
            return;
        }
        root.persistCurrentChat(); // Don't lose what's on screen
        root.loadChatById(id);
    }

    /**
     * /clear — throw this conversation away rather than filing it. Distinct from
     * /new, which keeps it in the list.
     */
    function discardCurrentChat() {
        if (root.currentChatId.length > 0) chatStore.remove(root.currentChatId);
        memorySummaryTimer.stop();
        root.clearMessages();
        root.currentChatId = "";
        root.currentChatTitle = "";
        root.currentChatCreatedAt = 0;
        root.currentChatDraft = "";
        root.titleGenerated = false;
        root.chatOpened("");
    }

    function deleteChat(id) {
        chatStore.remove(id);
        if (id === root.currentChatId) {
            root.currentChatId = "";
            root.currentChatTitle = "";
            root.clearMessages();
        }
    }

    function renameChat(id, title) {
        if (id === root.currentChatId) {
            root.currentChatTitle = title;
            root.titleGenerated = true;
            root.persistCurrentChat();
            return;
        }
        const chat = chatStore.load(id);
        if (!chat) return;
        chat.title = title;
        chatStore.save(chat);
    }

    /**
     * Headless control over the chat, for scripting and for driving the sidebar
     * from a keybind without going through the input field.
     */
    IpcHandler {
        target: "ai"

        function list(): string {
            return (chatStore.index ?? [])
                .map(e => `${e.id}\t${e.title || e.preview || "(untitled)"}\t${e.messageCount}`)
                .join("\n");
        }

        function open(id: string): string {
            if (!id || id.length === 0) return "usage: open <chat id>";
            root.persistCurrentChat();
            return root.loadChatById(id) ? `opened ${id}` : `no such chat: ${id}`;
        }

        function newChat(): string {
            root.newChat();
            return "ok";
        }

        function send(message: string): string {
            if (!message || message.trim().length === 0) return "nothing to send";
            // Route slash commands through the same handler the input box uses.
            // Without this, `ipc call ai send "/new"` posted the literal text to
            // the model — the one thing the caller definitely didn't mean.
            if (message.trim().startsWith("/")) {
                root.commandRequested(message.trim());
                return "ran";
            }
            root.queueUserMessage(message);
            return "sent";
        }

        function current(): string {
            return `${root.currentChatId}\t${root.currentChatDisplayTitle()}`;
        }

        function chats(): string {
            root.chatListRequested();
            return "ok";
        }

        function settings(): string {
            root.settingsRequested();
            return "ok";
        }

        function mode(name: string): string {
            if (!name || name.length === 0) return root.permissionMode;
            root.setPermissionMode(name.toLowerCase());
            return root.permissionMode;
        }

        function export_(): string {
            root.exportChat();
            return "exporting";
        }
    }

    // Raised by `ipc call ai chats`; the sidebar's history sheet listens for it.
    signal chatListRequested
    // Raised for slash commands arriving over IPC; the chat page owns the table
    // of commands, so it is the one that can run them.
    signal commandRequested(string text)

    // ---- favourites --------------------------------------------------------

    readonly property var favouriteModels: Persistent.states?.ai?.favouriteModels ?? []

    function isFavouriteModel(id) {
        return root.favouriteModels.indexOf(id) !== -1;
    }

    function toggleFavouriteModel(id) {
        if (!id || id.length === 0) return;
        const current = [...root.favouriteModels];
        const at = current.indexOf(id);
        if (at === -1) current.push(id);
        else current.splice(at, 1);
        root.savePersistentState("favouriteModels", current);
    }

    /**
     * Which company's model this is, for grouping in the picker. key_id is the
     * closest thing to a provider the model definitions carry — models sharing a
     * key are by definition the same provider — and a local model has no key at
     * all, which is exactly what distinguishes it.
     */
    function providerOfModel(id) {
        const model = root.models[id];
        if (!model) return Translation.tr("Other");
        if (!model.requires_key) return Translation.tr("Local");
        const names = {
            "gemini": "Google Gemini",
            "anthropic": "Anthropic",
            "openai": "OpenAI",
            "openrouter": "OpenRouter",
            "mistral": "Mistral",
            "claude-code": "Claude Code"
        };
        return names[model.key_id] ?? (model.key_id ?? Translation.tr("Other"));
    }

    function savePersistentState(key, value) {
        if (!Persistent.states || !Persistent.states.ai) return;
        Persistent.states.ai[key] = value;
    }
}
