pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * The set of configured MCP servers, and the tools they add to the assistant.
 *
 * Names are prefixed with the server they came from — two servers may both
 * offer `search`, and the model has to be able to say which one it means.
 */
Item {
    id: root

    // [{ name, command, args, env, enabled }] from the config file.
    readonly property var configured: Config.options?.ai?.mcpServers ?? []
    property var servers: []

    signal toolsChanged
    signal callFinished(string requestKey, bool ok, string text)

    readonly property int readyCount: root.servers.filter(s => s.ready).length
    readonly property int toolCount: root.servers.reduce((n, s) => n + (s.tools?.length ?? 0), 0)

    // Tool name as the model sees it: server__tool. Two underscores because a
    // server name may contain one and the split has to be unambiguous.
    readonly property string separator: "__"

    function toolNameFor(serverName, toolName) {
        return `${serverName}${root.separator}${toolName}`;
    }

    function isMcpTool(name) {
        return (name ?? "").indexOf(root.separator) !== -1 && root.serverForTool(name) !== null;
    }

    function serverForTool(name) {
        const at = (name ?? "").indexOf(root.separator);
        if (at === -1) return null;
        const serverName = name.slice(0, at);
        for (let i = 0; i < root.servers.length; i++) {
            if (root.servers[i].name === serverName) return root.servers[i];
        }
        return null;
    }

    /**
     * Every ready server's tools, in the neutral shape the strategies convert
     * from: { name, description, parameters }.
     */
    readonly property var toolDeclarations: {
        const out = [];
        for (let i = 0; i < root.servers.length; i++) {
            const server = root.servers[i];
            if (!server.ready) continue;
            const tools = server.tools ?? [];
            for (let j = 0; j < tools.length; j++) {
                const tool = tools[j];
                if (!tool?.name) continue;
                out.push({
                    "name": root.toolNameFor(server.name, tool.name),
                    "description": `[${server.name}] ${tool.description ?? ""}`.trim(),
                    "parameters": tool.inputSchema ?? { "type": "object", "properties": {} }
                });
            }
        }
        return out;
    }

    function callTool(name, args) {
        const server = root.serverForTool(name);
        if (!server) {
            root.callFinished(name, false, qsTr("No MCP server offers that tool"));
            return;
        }
        const bare = name.slice(name.indexOf(root.separator) + root.separator.length);
        const id = server.callTool(bare, args);
        if (id === -1) {
            root.callFinished(name, false, qsTr("That server isn't connected"));
            return;
        }
        root._inFlight[`${server.name}#${id}`] = name;
    }

    property var _inFlight: ({})

    // ---- lifecycle ---------------------------------------------------------

    Component {
        id: serverComponent
        McpServer {}
    }

    function reload() {
        for (let i = 0; i < root.servers.length; i++) {
            root.servers[i].stop();
            root.servers[i].destroy();
        }
        const next = [];
        const configs = root.configured ?? [];
        for (let i = 0; i < configs.length; i++) {
            const config = configs[i];
            if (!config?.name || !config?.command) continue;
            const server = serverComponent.createObject(root, {
                "name": config.name,
                "command": config.command,
                "args": config.args ?? [],
                "env": config.env ?? ({}),
                "enabled": config.enabled !== false
            });
            server.toolsChanged_.connect(() => root.toolsChanged());
            server.callFinished.connect((id, ok, text) => {
                const key = `${server.name}#${id}`;
                const toolName = root._inFlight[key];
                delete root._inFlight[key];
                root.callFinished(toolName ?? server.name, ok, text);
            });
            next.push(server);
            if (server.enabled) server.start();
        }
        root.servers = next;
        root.toolsChanged();
    }

    onConfiguredChanged: reloadDebounce.restart()

    Timer {
        id: reloadDebounce
        // Editing the server list writes the config on every keystroke; restarting
        // a subprocess per keystroke is not what anyone meant by that.
        interval: 600
        onTriggered: root.reload()
    }

    Component.onCompleted: Qt.callLater(() => root.reload())
}
