# Flash-Impulse AI subsystem architecture

Audience: anyone touching `dots/.config/quickshell/ii/services/Ai.qml` or
`services/ai/*`. Read this before changing the AI stack; update it when you do.

## Big picture

```
AiChat.qml (UI, slash commands)
    │
    ▼
Ai.qml (orchestrator, ~2k lines)
    │  models map ──► AiModel {api_format, model, requires_key, ...}
    │  apiStrategies map: api_format ──► ApiStrategy instance
    ▼
ApiStrategy (contract, services/ai/ApiStrategy.qml)
    ├── GeminiApiStrategy      HTTP streamGenerateContent (curl)
    ├── OpenAiApiStrategy      HTTP chat/completions SSE (curl)
    ├── AnthropicApiStrategy   HTTP /v1/messages SSE (curl), prompt caching
    └── ClaudeCodeApiStrategy  local `claude` CLI, stream-json events
```

Request lifecycle (all providers):

1. `Ai.qml` builds the message array, calls `strategy.buildRequestData(...)`.
2. A **bash script** is assembled (normally a `curl --no-buffer` call) and executed as a
   Quickshell `Process` via a heredoc (nothing sensitive written to disk).
3. Each stdout line goes to `strategy.parseResponseLine(line, message)`, which mutates
   `message.rawContent` and returns `{finished?, functionCall?, tokenUsage?, errorCode?}`.
4. `functionCall` results dispatch to `Ai.handleFunctionCall(...)`; `finished` closes the
   turn; `tokenUsage` feeds the cost tracker (`modelPricing` table).

## Claude Code bridge (`ClaudeCodeApiStrategy.qml`)

The `claude-code` api_format replaces the HTTP call entirely: `finalizeScriptContent()`
discards the curl script and builds

```
claude -p --output-format stream-json --verbose \
  --model <alias> --permission-mode <mode> \
  --append-system-prompt <bridge prompt> [--resume <session_id>] <<'EOF'
<prompt>
EOF
```

Key mechanics, all verified against claude CLI 2.1.217:

- **Sessions**: the `init` event carries `session_id`; we store it on the strategy and
  pass `--resume` on the next turn, sending only the newest user message. Claude Code
  sessions are **per working directory**, so the script pins `cd "$HOME"`. The session is
  cleared in `Ai.resetSessionState()` (new/clear/load chat). If the shell restarts and the
  session is lost, `buildRequestData` falls back to replaying a compact transcript.
- **Events parsed**: `system/init` (session capture), `assistant` (content blocks:
  `thinking` → `<think>` markup, `text` → chat text, `tool_use` → rendered as a
  ```command``` annotation via `summarizeToolUse`), `result` (finish + token/cache usage).
  Everything else (`rate_limit_event`, `thinking_tokens`, `stream_event`) is ignored.
- **AskUserQuestion**: Claude Code's native question tool is detected among `tool_use`
  blocks and rendered as a numbered options list; the user answers with a plain message
  (full button UI is a roadmap item, ROADMAP §3.3).
- **stderr** is redirected to `~/.local/share/flash-impulse/logs/claude-code-bridge.log`
  so the JSON stdout stream stays clean.
- **Models**: `cc-haiku`/`cc-sonnet`/`cc-opus`/`cc-fable` use CLI aliases
  (`haiku`/`sonnet`/`opus`/`fable`), `requires_key: false`. The direct Anthropic API
  models remain available for API-key users.
- **Permission mode** comes from `Config.options.ai.claudeCodePermissionMode`
  (default `acceptEdits`). A GUI permission-prompt bridge (MCP permission-prompt tool
  feeding QML approve/deny cards) is the planned next step.

## Command safety pipeline (`CommandSafety.qml`)

Applies to the sidebar's own `run_shell_command` function tool (Gemini/OpenAI/local
providers — Claude Code runs its *own* tools under its *own* permission system).

Evaluation order for `evaluate(cmd, geminiKey, onAllow, onConfirm)`:

1. **YOLO** (`/yolo on`) — everything auto-approved. Explicit, session-only, loud UI
   warning.
2. **Blacklist** — destructive patterns (rm -rf variants, dd to devices, pipe-to-shell,
   fork bombs, destructive git, credential exfiltration). Always manual approval; the
   judge can never override this tier.
3. **Gemini judge** — `gemini-3.5-flash-lite` reviews every remaining command (yes, even
   whitelisted ones) with a strict allow/confirm JSON verdict, temperature 0, 8s timeout.
4. **Fallback** (no key / judge error): whitelisted read-only commands auto-run,
   everything else asks.

The whitelist only matches single plain invocations — any shell metacharacter
(`;&|<>$()` …) disqualifies the fast path.

**Audit**: every decision appends
`timestamp | tier | decision | command` to
`~/.local/share/flash-impulse/logs/command-audit.log`.

## Keys & config

- API keys live in the system keyring via the existing `KeyringStorage` service
  (`KeyringStorage.keyringData.apiKeys.<provider>`); `/key` writes there. The installer's
  `secrets` subcommand stores keys under the `flash-impulse` service via `secret-tool`.
- Fork-wide install state lives in `~/.config/flash-impulse/` (installer manifest);
  logs in `~/.local/share/flash-impulse/logs/`.

## Model roster policy

Model IDs and pricing are point-in-time facts (last verified 2026-07-24, official
provider docs). Never "update" them from memory — check the docs, and date the commit.
The default model is the cheapest Gemini Flash-Lite tier because of its free tier;
`summarizerModelId` (context condensation) and the safety judge follow the same model.
