import QtQuick
import Quickshell
import Quickshell.Io

/**
 * On-disk chat store.
 *
 * One JSON file per chat, no cap, plus an index.json that carries just enough
 * per-chat metadata to render the chat list without opening every file. The
 * index is written by us on every save; if it goes missing or gets corrupted it
 * is rebuilt from the chat files themselves, so the files stay authoritative
 * and the index is only ever a cache.
 *
 * This replaces the old scheme of five rotating history_N slots plus manually
 * named saves, which lost chats silently once the ring wrapped around.
 */
Item {
    id: root

    property string chatsDir
    // [{ id, title, createdAt, updatedAt, messageCount, preview, model }] — newest first.
    property var index: []

    signal indexReloaded

    readonly property string indexPath: `${root.chatsDir}/index.json`

    function newId() {
        // Sortable and collision-proof enough for a single desktop session.
        return `${Date.now()}${Math.floor(Math.random() * 1000)}`;
    }

    function chatPath(id) {
        return `${root.chatsDir}/chat_${id}.json`;
    }

    // ---- writing -----------------------------------------------------------

    /**
     * @param chat full chat object; must have an id.
     */
    function save(chat) {
        if (!chat?.id) return false;
        chat.version = 2;
        chat.updatedAt = Date.now();
        try {
            chatFile.path = root.chatPath(chat.id);
            chatFile.setText(JSON.stringify(chat));
        } catch (e) {
            console.log("[ChatStore] Could not write chat:", e);
            return false;
        }
        root._upsertIndex(chat);
        return true;
    }

    function _upsertIndex(chat) {
        const entry = {
            "id": chat.id,
            "title": chat.title ?? "",
            "createdAt": chat.createdAt ?? chat.updatedAt,
            "updatedAt": chat.updatedAt,
            "messageCount": chat.messages?.length ?? 0,
            "preview": root._previewOf(chat),
            "model": chat.model ?? ""
        };
        const next = root.index.filter(e => e.id !== chat.id);
        next.unshift(entry);
        next.sort((a, b) => b.updatedAt - a.updatedAt);
        root.index = next;
        root._writeIndex();
    }

    function _previewOf(chat) {
        const messages = chat.messages ?? [];
        for (let i = 0; i < messages.length; i++) {
            const m = messages[i];
            if (m?.role !== "user") continue;
            const text = (m.rawContent ?? "").replace(/\s+/g, " ").trim();
            if (text.length > 0) return text.length > 120 ? text.slice(0, 120) + "…" : text;
        }
        return "";
    }

    function _writeIndex() {
        try {
            indexFile.path = root.indexPath;
            indexFile.setText(JSON.stringify(root.index));
        } catch (e) {
            console.log("[ChatStore] Could not write index:", e);
        }
    }

    // ---- reading -----------------------------------------------------------

    /**
     * @returns the chat object, or null if it can't be read.
     */
    function load(id) {
        // Two attempts: reading two different chats in a row can hand back the
        // previous one's text, which the id check below catches. Clearing the path
        // between attempts forces the view to drop what it was holding.
        for (let attempt = 0; attempt < 2; attempt++) {
            const chat = root._readChat(id);
            if (chat) return chat;
        }
        return null;
    }

    function _readChat(id) {
        try {
            // Reset first: assigning a path the view isn't already on is what
            // triggers a fresh blocking read. reload() on top of a stale path can
            // return the text that was already there.
            chatReadFile.path = "";
            chatReadFile.path = root.chatPath(id);
            const text = chatReadFile.text();
            if (!text || text.length < 2) return null;
            const chat = JSON.parse(text);
            if (!Array.isArray(chat?.messages)) return null;
            // Reading back a different chat than the one asked for means the view
            // handed us stale text; opening it would silently switch the user to
            // the wrong conversation, so fail instead.
            if (chat.id && chat.id !== id) {
                console.log("[ChatStore] Stale read for", id, "got", chat.id);
                return null;
            }
            return chat;
        } catch (e) {
            console.log("[ChatStore] Could not read chat:", id, e);
            return null;
        }
    }

    function remove(id) {
        Quickshell.execDetached(["rm", "-f", root.chatPath(id)]);
        root.index = root.index.filter(e => e.id !== id);
        root._writeIndex();
    }

    function entryById(id) {
        for (let i = 0; i < root.index.length; i++) {
            if (root.index[i].id === id) return root.index[i];
        }
        return null;
    }

    /**
     * Resolve a user-typed name to a chat id: exact title first, then a
     * case-insensitive prefix, then any substring. Ids are accepted too so
     * /load works with whatever the list shows.
     */
    function findByName(name) {
        const query = (name ?? "").trim();
        if (query.length === 0) return null;
        const lower = query.toLowerCase();
        let prefix = null;
        let substring = null;
        for (let i = 0; i < root.index.length; i++) {
            const e = root.index[i];
            if (e.id === query || e.title === query) return e.id;
            const title = (e.title ?? "").toLowerCase();
            if (!prefix && title.startsWith(lower)) prefix = e.id;
            if (!substring && title.indexOf(lower) !== -1) substring = e.id;
        }
        return prefix ?? substring;
    }

    function reloadIndex() {
        try {
            indexReadFile.path = root.indexPath;
            indexReadFile.reload();
            const text = indexReadFile.text();
            if (text && text.length > 1) {
                const parsed = JSON.parse(text);
                if (Array.isArray(parsed)) {
                    root.index = parsed.sort((a, b) => b.updatedAt - a.updatedAt);
                    root.indexReloaded();
                    return;
                }
            }
        } catch (e) {
            console.log("[ChatStore] Index unreadable, rebuilding:", e);
        }
        root.rebuildIndex();
    }

    /**
     * Regenerate index.json from the chat files. Done in python rather than QML
     * because it means opening every chat, and blocking the UI thread on that is
     * exactly what the index exists to avoid.
     */
    function rebuildIndex() {
        indexRebuilder.running = true;
    }

    // Reads and writes get their own views on purpose. Sharing one meant that
    // opening a chat right after autosaving another — which is exactly what the
    // chat list does — could read back the text just written and load the wrong
    // conversation.
    FileView {
        id: chatFile
        blockLoading: true
    }

    FileView {
        id: chatReadFile
        blockLoading: true
    }

    FileView {
        id: indexFile
        blockLoading: true
    }

    FileView {
        id: indexReadFile
        blockLoading: true
    }

    Process {
        id: indexRebuilder
        command: ["python3", "-c", `
import glob, json, os, re, sys
out = []
for path in glob.glob(os.path.join(sys.argv[1], "chat_*.json")):
    try:
        with open(path) as f:
            chat = json.load(f)
    except Exception:
        continue
    if not isinstance(chat, dict):
        continue
    messages = chat.get("messages") or []
    preview = ""
    for m in messages:
        if m.get("role") == "user":
            text = re.sub(r"\\s+", " ", m.get("rawContent") or "").strip()
            if text:
                preview = text[:120] + ("\\u2026" if len(text) > 120 else "")
                break
    stamp = chat.get("updatedAt") or int(os.path.getmtime(path) * 1000)
    out.append({
        "id": chat.get("id") or os.path.basename(path)[5:-5],
        "title": chat.get("title") or "",
        "createdAt": chat.get("createdAt") or stamp,
        "updatedAt": stamp,
        "messageCount": len(messages),
        "preview": preview,
        "model": chat.get("model") or "",
    })
out.sort(key=lambda e: e["updatedAt"], reverse=True)
print(json.dumps(out))
`, root.chatsDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed)) {
                        root.index = parsed;
                        root._writeIndex();
                    }
                } catch (e) {
                    console.log("[ChatStore] Could not rebuild index:", e);
                }
                root.indexReloaded();
            }
        }
    }
}
