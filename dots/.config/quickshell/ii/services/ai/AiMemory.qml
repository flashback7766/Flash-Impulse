pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Durable facts about the user and this machine, kept across chats.
 *
 * Deliberately not a transcript archive. Recaps of past conversations are long,
 * mostly irrelevant to the next question, and change every time a chat ends —
 * which is the worst possible shape for something that lives in a cached prompt
 * prefix. A short list of settled facts is small, changes rarely, and stays
 * worth its tokens.
 *
 * Past conversations are still searchable; they're just fetched when they match
 * rather than carried everywhere. See Ai.recallForQuestion.
 */
Item {
    id: root

    readonly property string path: `${Directories.state}/user/ai/memory.json`
    // [{ id, text, createdAt }], newest last so the file reads chronologically.
    property var entries: []
    readonly property int count: root.entries.length

    // How much of the prompt this is allowed to occupy. A memory that grows
    // without limit turns into the thing it was meant to replace.
    readonly property int maxEntries: 40
    readonly property int maxTextLength: 240

    signal changed

    /**
     * What goes in the system prompt. Empty when there's nothing to say, so a
     * fresh install carries no heading for an empty list.
     */
    readonly property string promptBlock: {
        if (root.entries.length === 0) return "";
        const lines = root.entries.map(e => `- ${e.text}`);
        return "## What you already know about this user and machine\n"
            + "Facts they've told you before, or that you worked out and were asked to keep.\n"
            + lines.join("\n");
    }

    function remember(text) {
        const clean = (text ?? "").replace(/\s+/g, " ").trim();
        if (clean.length === 0) return false;
        const capped = clean.length > root.maxTextLength
            ? clean.slice(0, root.maxTextLength) + "…" : clean;

        // Near-duplicates are the failure mode of a self-writing memory: the same
        // fact re-learned every few chats, each time slightly reworded.
        const lowered = capped.toLowerCase();
        for (let i = 0; i < root.entries.length; i++) {
            if (root.entries[i].text.toLowerCase() === lowered) return false;
        }

        const next = [...root.entries, {
            "id": `${Date.now()}${Math.floor(Math.random() * 1000)}`,
            "text": capped,
            "createdAt": Date.now()
        }];
        // Oldest out first when full — a fact that hasn't come up in forty
        // entries is one the model can learn again if it still matters.
        root.entries = next.length > root.maxEntries ? next.slice(next.length - root.maxEntries) : next;
        root._write();
        return true;
    }

    function forget(id) {
        const next = root.entries.filter(e => e.id !== id);
        if (next.length === root.entries.length) return false;
        root.entries = next;
        root._write();
        return true;
    }

    function forgetAll() {
        root.entries = [];
        root._write();
    }

    function _write() {
        try {
            memoryFile.path = root.path;
            memoryFile.setText(JSON.stringify(root.entries, null, 2));
        } catch (e) {
            console.log("[AiMemory] Could not write:", e);
        }
        root.changed();
    }

    function reload() {
        try {
            memoryFile.path = "";
            memoryFile.path = root.path;
            const text = memoryFile.text();
            if (!text || text.length < 2) return;
            const parsed = JSON.parse(text);
            if (Array.isArray(parsed)) root.entries = parsed.filter(e => (e?.text ?? "").length > 0);
        } catch (e) {
            // No file yet is the normal first-run case, not a problem.
        }
    }

    FileView {
        id: memoryFile
        blockLoading: true
    }

    Component.onCompleted: Qt.callLater(() => root.reload())
}
