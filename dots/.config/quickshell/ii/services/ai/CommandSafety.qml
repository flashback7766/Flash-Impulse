import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions as CF

/**
 * Shell-command safety pipeline for AI function calling (ROADMAP §3.4).
 *
 * Three tiers, evaluated in order:
 *   1. YOLO mode        — explicit opt-in, everything auto-approved (still audited).
 *   2. Blacklist        — destructive patterns always need manual approval;
 *                         nothing can override this except YOLO.
 *   3. AI judge         — a Gemini Flash-Lite call reviews EVERY remaining command
 *                         (including whitelisted ones) as a second layer of defense.
 *                         Verdict "allow" auto-runs; anything else asks the user.
 *      Fallback         — without a Gemini key (or on judge error/timeout) the static
 *                         tiers decide: whitelisted read-only commands auto-run,
 *                         everything else asks the user.
 *
 * Every evaluated command and decision is appended to
 * ~/.local/share/flash-impulse/logs/command-audit.log for auditing.
 */
QtObject {
    id: root

    property bool yoloMode: false

    readonly property string logDir: Quickshell.env("HOME") + "/.local/share/flash-impulse/logs"
    readonly property string judgeModel: "gemini-3.1-flash-lite"
    readonly property string judgeEndpoint:
        `https://generativelanguage.googleapis.com/v1beta/models/${judgeModel}:generateContent`

    // Read-only informational commands. A command is only whitelisted when it is a
    // single plain invocation — any shell metacharacter disqualifies it.
    readonly property var whitelistPrefixes: [
        "ls", "cat", "head", "tail", "grep", "rg", "find", "file", "stat", "wc",
        "du", "df", "free", "ps", "uname", "date", "whoami", "id", "pwd", "which",
        "echo", "printf", "uptime", "nproc", "lscpu", "lsblk", "lsusb", "lspci",
        "ip", "hostnamectl", "pacman -Q", "dnf list installed", "systemctl status",
        "systemctl list-units", "journalctl", "hyprctl monitors", "hyprctl clients",
        "hyprctl activewindow", "hyprctl workspaces", "hyprctl version"
    ]

    readonly property var blacklistPatterns: [
        // Deletion or modification of root/system dirs
        /\brm\s+.*-[rfRF]+.*\s+\/(?:bin|boot|dev|etc|home|lib|lib64|lost\+found|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|var|[^\w\-]|$)/,
        /\bmv\s+.*\s+\/(?:bin|boot|dev|etc|home|lib|lib64|lost\+found|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|var|[^\w\-]|$)/,
        /\bchmod\s+.*-R.*\s+\/(?:bin|boot|dev|etc|home|lib|lib64|lost\+found|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|var|[^\w\-]|$)/,
        /\bchown\s+.*-R.*\s+\/(?:bin|boot|dev|etc|home|lib|lib64|lost\+found|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|var|[^\w\-]|$)/,
        // Recursive delete of HOME / cwd / glob
        /\brm\s+(?:-[a-zA-Z]*\s+)*-[rfRF]+[a-zA-Z]*(?:\s+-[a-zA-Z]+)*\s+(?:~|\$HOME|\$\{HOME\}|\.|\.\/|\*|\.\*)(?:\s|$)/,
        /\brm\s+.*\s+(?:~|\$HOME|\$\{HOME\}|\*|\.\*)(?:\s|$)/,
        // Low level disk access
        /\bdd\s+.*of=\/dev\//,
        /\bmkfs\b/,
        />\s*\/dev\/(?:sd[a-z]|nvme|hd[a-z]|mmcblk)/,
        // Pipe-to-shell from network
        /\bcurl\b.*\|\s*(?:bash|sh|zsh|fish)\b/,
        /\bwget\b.*\|\s*(?:bash|sh|zsh|fish)\b/,
        // Fork bomb
        /:\s*\(\s*\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:/,
        // System control
        /\breboot\b/, /\bshutdown\b/, /\bpoweroff\b/, /\bhalt\b/,
        // Destructive git
        /\bgit\s+clean\s+.*-[a-zA-Z]*[fdx]/,
        /\bgit\s+reset\s+.*--hard/,
        /\bgit\s+push\s+.*--force\b/,
        /\bgit\s+push\s+.*-f\b/,
        // Credential exfiltration surface
        /\b(?:cat|cp|scp|curl|wget)\b.*(?:\.ssh\/id_|\.gnupg|\/etc\/shadow)/
    ]

    function isBlacklisted(cmd): bool {
        if (!cmd) return false;
        return blacklistPatterns.some(pattern => pattern.test(cmd));
    }

    function isWhitelisted(cmd): bool {
        if (!cmd) return false;
        const trimmed = cmd.trim();
        // Any shell metacharacter disqualifies from the fast path.
        if (/[;&|<>`$(){}]/.test(trimmed)) return false;
        return whitelistPrefixes.some(p =>
            trimmed === p || trimmed.startsWith(p + " ") || trimmed.startsWith(p + "\t"));
    }

    function audit(cmd, tier, decision) {
        const line = `${new Date().toISOString()} | ${tier} | ${decision} | ${cmd.replace(/\n/g, "\\n")}`;
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p '${root.logDir}' && printf '%s\\n' '${CF.StringUtils.shellSingleQuoteEscape(line)}' >> '${root.logDir}/command-audit.log'`]);
    }

    // In-flight evaluation state (chat flow serializes commands, so one at a time).
    property var _onAllow: null
    property var _onConfirm: null
    property string _cmd: ""
    property bool _staticSafe: false

    /**
     * Evaluate a command. Exactly one of the callbacks fires (asynchronously
     * when the judge is involved):
     *   onAllow(reason)   — run it without asking
     *   onConfirm(reason) — surface Approve/Reject to the user
     */
    function evaluate(cmd, geminiKey, onAllow, onConfirm) {
        if (root.yoloMode) {
            audit(cmd, "yolo", "auto-approve");
            onAllow("YOLO mode: auto-approved");
            return;
        }
        if (isBlacklisted(cmd)) {
            audit(cmd, "blacklist", "confirm");
            onConfirm("Potentially destructive command — review carefully before approving");
            return;
        }

        const staticSafe = isWhitelisted(cmd);
        if (!geminiKey || geminiKey.length === 0) {
            if (staticSafe) {
                audit(cmd, "whitelist", "auto-approve");
                onAllow("Read-only command");
            } else {
                audit(cmd, "no-judge", "confirm");
                onConfirm("No Gemini key for the safety judge — manual approval required");
            }
            return;
        }

        // Judge reviews everything that isn't blacklisted, whitelisted or not.
        root._cmd = cmd;
        root._onAllow = onAllow;
        root._onConfirm = onConfirm;
        root._staticSafe = staticSafe;
        judgeProc.environment = { "GEMINI_API_KEY": geminiKey };
        const request = {
            "system_instruction": { "parts": [{ "text":
                "You are a shell-command safety judge for a desktop AI assistant on Linux. "
                + "Given one command, decide if it is safe to run automatically on the user's machine. "
                + "allow: read-only or trivially reversible, no data loss, no privacy risk, no network exfiltration, no system config change. "
                + "confirm: anything else, including installs, writes outside temp dirs, sudo, service changes, or anything ambiguous. "
                + "Reply with ONLY minified JSON: {\"verdict\":\"allow\"|\"confirm\",\"reason\":\"<max 10 words>\"}" }] },
            "contents": [{ "parts": [{ "text": cmd }] }],
            "generationConfig": { "temperature": 0, "maxOutputTokens": 60 }
        };
        judgeProc.command = ["bash", "-c",
            `curl -sS --max-time 8 -X POST '${root.judgeEndpoint}' `
            + `-H 'Content-Type: application/json' -H "x-goog-api-key: $GEMINI_API_KEY" `
            + `--data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(request))}'`];
        judgeProc.buffer = "";
        judgeProc.running = true;
    }

    function _judgeFallback(reasonPrefix) {
        if (root._staticSafe) {
            audit(root._cmd, "judge-fallback-whitelist", "auto-approve");
            root._onAllow?.(reasonPrefix + " — allowed by whitelist");
        } else {
            audit(root._cmd, "judge-fallback", "confirm");
            root._onConfirm?.(reasonPrefix + " — manual approval required");
        }
        root._onAllow = null;
        root._onConfirm = null;
    }

    property Process judgeProc: Process {
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => judgeProc.buffer += data
        }
        onExited: (exitCode, exitStatus) => {
            if (root._onAllow === null && root._onConfirm === null) return;
            if (exitCode !== 0) {
                root._judgeFallback("Safety judge unreachable");
                return;
            }
            try {
                const response = JSON.parse(judgeProc.buffer);
                let text = response.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
                text = text.replace(/```json|```/g, "").trim();
                const verdict = JSON.parse(text);
                if (verdict.verdict === "allow") {
                    root.audit(root._cmd, "judge", `auto-approve (${verdict.reason ?? ""})`);
                    root._onAllow?.(`Judge: ${verdict.reason ?? "safe"}`);
                    root._onAllow = null;
                    root._onConfirm = null;
                } else {
                    root.audit(root._cmd, "judge", `confirm (${verdict.reason ?? ""})`);
                    root._onConfirm?.(`Judge: ${verdict.reason ?? "needs review"}`);
                    root._onAllow = null;
                    root._onConfirm = null;
                }
            } catch (e) {
                root._judgeFallback("Safety judge returned an unparsable verdict");
            }
        }
    }
}
