import QtQuick
import Quickshell
import Quickshell.Io

/**
 * One MCP server, spoken to over stdio.
 *
 * The protocol is JSON-RPC 2.0, one object per line: `initialize`, then
 * `notifications/initialized`, then `tools/list` to find out what it offers and
 * `tools/call` to use it. Everything here is that handshake and a table of
 * in-flight request ids, because a server may answer out of order and a reply
 * carries nothing but its id to say what it was for.
 *
 * Deliberately not a general MCP client: no resources, no prompts, no sampling.
 * Tools are the part a chat assistant can actually act on, and pretending to
 * support the rest would mean advertising capabilities nothing here honours.
 */
QtObject {
    id: root

    property string name: ""
    property string command: ""
    property var args: []
    property var env: ({})
    property bool enabled: true

    // "" | "starting" | "ready" | "failed" | "stopped"
    property string status: ""
    property string detail: ""
    property var tools: []
    readonly property bool ready: root.status === "ready"

    signal toolsChanged_()
    signal callFinished(int id, bool ok, string text)

    property int _nextId: 1
    // id -> "initialize" | "tools/list" | "call"
    property var _pending: ({})
    property string _buffer: ""

    function start() {
        if (!root.enabled || root.command.length === 0) return;
        root.stop();
        root.status = "starting";
        root.detail = "";
        root.tools = [];
        root._pending = {};
        root._buffer = "";
        proc.environment = root.env ?? {};
        proc.command = [root.command, ...(root.args ?? [])];
        proc.running = true;
    }

    function stop() {
        if (proc.running) proc.running = false;
        if (root.status !== "failed") root.status = "stopped";
    }

    function _send(method, params, kind) {
        if (!proc.running) return -1;
        const id = root._nextId++;
        root._pending[id] = kind;
        const message = { "jsonrpc": "2.0", "id": id, "method": method };
        if (params !== undefined) message.params = params;
        proc.write(JSON.stringify(message) + "\n");
        return id;
    }

    function _notify(method, params) {
        if (!proc.running) return;
        const message = { "jsonrpc": "2.0", "method": method };
        if (params !== undefined) message.params = params;
        proc.write(JSON.stringify(message) + "\n");
    }

    /**
     * @returns the request id, so the caller can match callFinished to it.
     */
    function callTool(toolName, toolArgs) {
        if (!root.ready) return -1;
        return root._send("tools/call", {
            "name": toolName,
            "arguments": toolArgs ?? {}
        }, "call");
    }

    function _handle(line) {
        const trimmed = line.trim();
        if (trimmed.length === 0) return;
        let message;
        try {
            message = JSON.parse(trimmed);
        } catch (e) {
            // Servers write diagnostics to stdout despite the spec. Anything that
            // isn't JSON is theirs to keep.
            return;
        }
        if (message.id === undefined) return; // A notification from the server.

        const kind = root._pending[message.id];
        delete root._pending[message.id];

        if (kind === "initialize") {
            if (message.error) {
                root.status = "failed";
                root.detail = message.error.message ?? "initialize failed";
                return;
            }
            root._notify("notifications/initialized");
            root._send("tools/list", {}, "tools/list");
            return;
        }

        if (kind === "tools/list") {
            if (message.error) {
                root.status = "failed";
                root.detail = message.error.message ?? "tools/list failed";
                return;
            }
            root.tools = message.result?.tools ?? [];
            root.status = "ready";
            root.detail = "";
            root.toolsChanged_();
            return;
        }

        if (kind === "call") {
            if (message.error) {
                root.callFinished(message.id, false, message.error.message ?? "call failed");
                return;
            }
            // Content is a list of typed parts; the text ones are what a chat
            // model can use, and a server that returns only an image has told us
            // something we can't pass on.
            const parts = message.result?.content ?? [];
            const text = parts
                .filter(part => part?.type === "text")
                .map(part => part.text ?? "")
                .join("\n")
                .trim();
            const failed = message.result?.isError === true;
            root.callFinished(message.id, !failed,
                text.length > 0 ? text : "(the tool returned nothing readable)");
        }
    }

    property Process proc: Process {
        stdinEnabled: true

        onRunningChanged: {
            if (!proc.running) return;
            // Protocol version is the one this handshake was written against;
            // servers negotiate down and tell us what they picked.
            root._send("initialize", {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": { "name": "flash-impulse", "version": "1" }
            }, "initialize");
        }

        onExited: (exitCode) => {
            if (root.status === "ready" || root.status === "starting") {
                root.status = "failed";
                root.detail = qsTr("Server exited with code %1").arg(exitCode);
            }
            root.tools = [];
            root.toolsChanged_();
        }

        stdout: SplitParser {
            onRead: line => root._handle(line)
        }

        stderr: SplitParser {
            onRead: line => {
                // Kept only as the reason shown when a server never comes up;
                // a chatty server would otherwise overwrite it with its last log
                // line forever.
                if (root.status === "starting" && line.trim().length > 0) {
                    root.detail = line.trim().slice(0, 200);
                }
            }
        }
    }
}
