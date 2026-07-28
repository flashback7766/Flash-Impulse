pragma Singleton
import Quickshell

Singleton {
    id: root

    /**
     * Formats a string according to the args that are passed inc
     * @param { string } str
     * @param  {...any} args
     * @returns { string }
     */
    function format(str, ...args) {
        return str.replace(/{(\d+)}/g, (match, index) => typeof args[index] !== 'undefined' ? args[index] : match);
    }

    /**
     * Returns the domain of the passed in url or null
     * @param { string } url
     * @returns { string| null }
     */
    function getDomain(url) {
        const match = url.match(/^(?:https?:\/\/)?(?:www\.)?([^\/]+)/);
        return match ? match[1] : null;
    }

    /**
     * Returns the base url of the passed in url or null
     * @param { string } url
     * @returns { string | null }
     */
    function getBaseUrl(url) {
        const match = url.match(/^(https?:\/\/[^\/]+)(\/.*)?$/);
        return match ? match[1] : null;
    }

    /**
     * Escapes single quotes in shell commands
     * @param { string } str
     * @returns { string }
     */
    function shellSingleQuoteEscape(str) {
        return String(str)
        // .replace(/\\/g, '\\\\')
        .replace(/'/g, "'\\''");
    }

    /**
     * Splits markdown into text and fenced-code blocks.
     * @param { string } markdown
     * @returns {Array<{type: "text" | "code", content: string, lang?: string, completed?: boolean}>}
     */
    /**
     * Pull <think> sections out of a model's text.
     *
     * Providers that expose reasoning properly get their own field and never come
     * through here; this is for models that inline the tags in the text, which is
     * what local models served through Ollama do. Returns
     * { content, reasoning } with the tags and their contents removed from content.
     *
     * Fenced code is masked out first, so a message *about* <think> tags — asking
     * how to parse them, say — doesn't get eaten by its own example.
     */
    // Every wrapper a local model has been seen to put its reasoning in. The
    // opener is what the cheap bail-out below looks for, so each entry needs one
    // that can't plausibly appear in ordinary prose.
    readonly property var reasoningTagPatterns: [
        // <think>…</think>, <thinking>, <thought>, <reason>, <reasoning>
        { probe: "<th", regex: /<think(?:ing)?>([\s\S]*?)(?:<\/think(?:ing)?>|$)/g },
        { probe: "<thought", regex: /<thought>([\s\S]*?)(?:<\/thought>|$)/g },
        { probe: "<reason", regex: /<reason(?:ing)?>([\s\S]*?)(?:<\/reason(?:ing)?>|$)/g },
        // Skywork/OpenThoughts-style special tokens that leak into the text
        { probe: "<|begin_of_thought|>", regex: /<\|begin_of_thought\|>([\s\S]*?)(?:<\|end_of_thought\|>|$)/g },
        // Kimi's unicode-bracketed form
        { probe: "◁think▷", regex: /◁think▷([\s\S]*?)(?:◁\/think▷|$)/g }
    ]

    function extractThinkTags(text) {
        if (!text) return { content: "", reasoning: "" };

        const patterns = root.reasoningTagPatterns.filter(p => text.indexOf(p.probe) !== -1);
        if (patterns.length === 0) return { content: text, reasoning: "" };

        const fences = [];
        // NUL delimits the placeholder: a model can write "FENCE0" but not a NUL byte,
        // so nothing in the text can be mistaken for one of ours.
        let stripped = text.replace(/```[\s\S]*?(?:```|$)/g, match => {
            fences.push(match);
            return `\x00FENCE${fences.length - 1}\x00`;
        });

        const reasoning = [];
        for (let i = 0; i < patterns.length; i++) {
            // Unterminated final tag is normal mid-stream, hence the `$` alternative
            // in every pattern.
            stripped = stripped.replace(patterns[i].regex, (match, inner) => {
                if (inner.trim().length > 0) reasoning.push(inner.trim());
                return "";
            });
        }

        const restore = s => s.replace(/\x00FENCE(\d+)\x00/g, (m, i) => fences[Number(i)]);
        return {
            content: restore(stripped),
            // Restored here too: a fence inside the thinking was masked along with
            // the rest, and reasoning that reached the UI unrestored showed the
            // placeholder instead of the code. Reasoning models write code in
            // their thoughts constantly, so this is the common case, not an edge.
            reasoning: restore(reasoning.join("\n\n"))
        };
    }

    /**
     * Split reasoning into display steps. Models paragraph their thoughts, and
     * providers that emit discrete blocks are joined with a blank line upstream,
     * so a blank-line split covers both without needing per-provider knowledge.
     */
    function splitReasoningSteps(reasoning) {
        if (!reasoning) return [];
        // Blank lines separate steps — except inside a fence, where they're part
        // of the code and splitting on them tears one snippet across two steps.
        const lines = reasoning.split("\n");
        const steps = [];
        let buffer = [];
        let inFence = false;
        const flush = () => {
            const step = buffer.join("\n").trim();
            if (step.length > 0) steps.push(step);
            buffer = [];
        };
        for (let i = 0; i < lines.length; i++) {
            if (/^\s*```/.test(lines[i])) inFence = !inFence;
            if (!inFence && lines[i].trim().length === 0) {
                flush();
                continue;
            }
            buffer.push(lines[i]);
        }
        flush();
        return steps;
    }

    /**
     * splitMarkdownBlocks, plus blockquotes pulled out into their own blocks.
     *
     * Qt's markdown renderer draws a blockquote as an anonymous indent, which is
     * indistinguishable from a nested list or a stray tab. Lifting quote runs out
     * lets the UI give them the accent bar that makes them read as a quote at all.
     * Quotes inside fenced code are untouched, since fences are split off first.
     */
    function splitMessageBlocks(markdown) {
        const blocks = splitMarkdownBlocks(markdown);
        const result = [];
        for (let i = 0; i < blocks.length; i++) {
            if (blocks[i].type !== "text") {
                result.push(blocks[i]);
                continue;
            }
            const parts = splitQuoteRuns(blocks[i].content);
            for (let j = 0; j < parts.length; j++) {
                if (parts[j].type !== "text") {
                    result.push(parts[j]);
                    continue;
                }
                const tables = splitTableRuns(parts[j].content);
                for (let k = 0; k < tables.length; k++) result.push(tables[k]);
            }
        }
        return result;
    }

    /**
     * Pull GFM tables out into their own blocks, parsed into header/rows.
     *
     * Qt renders a markdown table, but as an unstyled grid with no way to give
     * the header weight, alternate row shading, or scroll a wide one — in a
     * sidebar that's the difference between a comparison you can read and a
     * squashed column of fragments.
     */
    function splitTableRuns(text) {
        if (!text || text.indexOf("|") === -1) return [{ type: "text", content: text }];
        const lines = text.split("\n");
        const out = [];
        let buffer = [];

        const flushText = () => {
            if (buffer.length === 0) return;
            const content = buffer.join("\n");
            if (content.trim().length > 0) out.push({ type: "text", content: content });
            buffer = [];
        };

        for (let i = 0; i < lines.length; i++) {
            // A table is a header row immediately followed by a delimiter row.
            // Requiring both keeps ordinary prose containing a pipe out of here.
            if (isTableRow(lines[i]) && i + 1 < lines.length && isTableDelimiter(lines[i + 1])) {
                flushText();
                const header = splitTableRow(lines[i]);
                const aligns = splitTableRow(lines[i + 1]).map(cellAlignment);
                const rows = [];
                let j = i + 2;
                while (j < lines.length && isTableRow(lines[j])) {
                    rows.push(splitTableRow(lines[j]));
                    j++;
                }
                out.push({
                    type: "table",
                    content: lines.slice(i, j).join("\n"),
                    header: header,
                    aligns: aligns,
                    rows: rows
                });
                i = j - 1;
                continue;
            }
            buffer.push(lines[i]);
        }
        flushText();
        return out.length > 0 ? out : [{ type: "text", content: text }];
    }

    function isTableRow(line) {
        return line.indexOf("|") !== -1 && line.trim().length > 0;
    }

    function isTableDelimiter(line) {
        return /^\s*\|?(\s*:?-+:?\s*\|)*\s*:?-+:?\s*\|?\s*$/.test(line) && line.indexOf("-") !== -1;
    }

    function splitTableRow(line) {
        let t = line.trim();
        if (t.charAt(0) === "|") t = t.slice(1);
        if (t.charAt(t.length - 1) === "|") t = t.slice(0, -1);
        const cells = [];
        let cur = "";
        // Hand-scanned rather than split(): a cell may contain an escaped \| and
        // the engine can't be relied on for lookbehind.
        for (let i = 0; i < t.length; i++) {
            const ch = t.charAt(i);
            if (ch === "\\" && t.charAt(i + 1) === "|") {
                cur += "|";
                i++;
            } else if (ch === "|") {
                cells.push(cur.trim());
                cur = "";
            } else {
                cur += ch;
            }
        }
        cells.push(cur.trim());
        return cells;
    }

    function cellAlignment(spec) {
        const s = (spec ?? "").trim();
        const left = s.charAt(0) === ":";
        const right = s.charAt(s.length - 1) === ":";
        if (left && right) return "center";
        if (right) return "right";
        return "left";
    }

    function splitQuoteRuns(text) {
        if (!text || text.indexOf(">") === -1) return [{ type: "text", content: text }];
        const lines = text.split("\n");
        const out = [];
        let buffer = [];
        let inQuote = false;

        const flush = () => {
            if (buffer.length === 0) return;
            const content = buffer.join("\n");
            if (content.trim().length > 0) out.push({ type: inQuote ? "quote" : "text", content: content });
            buffer = [];
        };

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const quoted = /^\s{0,3}>/.test(line);
            if (quoted !== inQuote) {
                flush();
                inQuote = quoted;
            }
            // Strip the marker so the quote body renders as ordinary markdown.
            buffer.push(quoted ? line.replace(/^\s{0,3}>\s?/, "") : line);
        }
        flush();
        return out.length > 0 ? out : [{ type: "text", content: text }];
    }

    /**
     * Split a fence's info string into a language and, where the writer supplied
     * one, a file name. Models label snippets every which way — ```qml:path/File.qml,
     * ```js app.js, ```python title="setup.py" — and a named file is worth showing
     * in the header and reusing when saving, so all three forms are accepted.
     * @returns {{lang: string, filename: string}}
     */
    function parseCodeInfo(info) {
        const trimmed = (info ?? "").trim();
        if (trimmed.length === 0) return { lang: "", filename: "" };

        const titled = trimmed.match(/title\s*=\s*"([^"]+)"|title\s*=\s*'([^']+)'/);
        if (titled) {
            return { lang: trimmed.split(/[\s:]/)[0] ?? "", filename: titled[1] ?? titled[2] ?? "" };
        }

        const colon = trimmed.indexOf(":");
        if (colon > 0) {
            return { lang: trimmed.slice(0, colon), filename: trimmed.slice(colon + 1).trim() };
        }

        const parts = trimmed.split(/\s+/);
        // A bare second word is only a file name if it looks like one; "js copy"
        // and "bash {highlight}" are not paths.
        if (parts.length > 1 && /[./]/.test(parts[1])) {
            return { lang: parts[0], filename: parts[1] };
        }
        return { lang: parts[0], filename: "" };
    }

    function splitMarkdownBlocks(markdown) {
        // Two alternatives: with-info-string-then-newline, or one-liner with none.
        // The info string is anything up to the newline so that a labelled file
        // name survives to parseCodeInfo, not just a bare language word.
        const regex = /```([^\n`]*)\n([\s\S]*?)```|```([\s\S]*?)```/g;
        /**
         * @type {{type: "text" | "code"; content: string; lang: string | undefined; completed: boolean | undefined}[]}
         */
        let result = [];
        let lastIndex = 0;
        let match;
        while ((match = regex.exec(markdown)) !== null) {
            if (match.index > lastIndex) {
                const text = markdown.slice(lastIndex, match.index);
                if (text.trim()) {
                    result.push({
                        type: "text",
                        content: text
                    });
                }
            }
            const info = parseCodeInfo(match[1] || "");
            // The newline before the closing fence belongs to the fence, not to the
            // code. Kept, it showed as a phantom last line in the gutter and rode
            // along into every copy and save.
            const content = (match[2] !== undefined ? match[2] : (match[3] || "")).replace(/\n$/, "");
            if (content.trim()) {
                result.push({
                    type: "code",
                    lang: info.lang,
                    filename: info.filename,
                    content,
                    completed: true
                });
            }
            lastIndex = regex.lastIndex;
        }
        if (lastIndex < markdown.length) {
            const text = markdown.slice(lastIndex);
            const codeStart = text.indexOf('```');
            if (codeStart !== -1) {
                const beforeCode = text.slice(0, codeStart);
                if (beforeCode.trim()) {
                    result.push({
                        type: "text",
                        content: beforeCode
                    });
                }
                // Try to detect the info string after ```
                const codeLangMatch = text.slice(codeStart + 3).match(/^([^\n`]*)\n/);
                let info = { lang: "", filename: "" };
                let codeContentStart = codeStart + 3;
                if (codeLangMatch) {
                    info = parseCodeInfo(codeLangMatch[1] || "");
                    codeContentStart += codeLangMatch[0].length;
                } else if (text[codeStart + 3] === '\n') {
                    codeContentStart += 1;
                }
                const codeContent = text.slice(codeContentStart);
                if (codeContent.trim()) {
                    result.push({
                        type: "code",
                        lang: info.lang,
                        filename: info.filename,
                        content: codeContent,
                        completed: false
                    });
                }
            } else if (text.trim()) {
                result.push({
                    type: "text",
                    content: text
                });
            }
        }
        // console.log(JSON.stringify(result, null, 2));
        return result;
    }

    /**
     * Returns the original string with backslashes escaped
     * @param { string } str
     * @returns { string }
     */
    function escapeBackslashes(str) {
        return str.replace(/\\/g, '\\\\');
    }

    /**
     * Wraps words to supplied maximum length
     * @param { string | null } str
     * @param { number } maxLen
     * @returns { string }
     */
    function wordWrap(str, maxLen) {
        if (!str)
            return "";
        let words = str.split(" ");
        let lines = [];
        let current = "";
        for (let i = 0; i < words.length; ++i) {
            if ((current + (current.length > 0 ? " " : "") + words[i]).length > maxLen) {
                if (current.length > 0)
                    lines.push(current);
                current = words[i];
            } else {
                current += (current.length > 0 ? " " : "") + words[i];
            }
        }
        if (current.length > 0)
            lines.push(current);
        return lines.join("\n");
    }

    /**
     * Cleans up a music title by removing bracketed and special characters.
     * @param { string } title
     * @returns { string }
     */
    function cleanMusicTitle(title) {
        if (!title)
            return "";
        // Brackets
        title = title.replace(/^ *\([^)]*\) */g, " "); // Round brackets
        title = title.replace(/^ *\[[^\]]*\] */g, " "); // Square brackets
        title = title.replace(/^ *\{[^\}]*\} */g, " "); // Curly brackets
        // Japenis brackets
        title = title.replace(/^ *【[^】]*】/, ""); // Touhou
        title = title.replace(/^ *《[^》]*》/, ""); // ??
        title = title.replace(/^ *「[^」]*」/, ""); // OP/ED thingie
        title = title.replace(/^ *『[^』]*』/, ""); // OP/ED thingie

        return title.trim();
    }

    /**
     * Converts seconds to a friendly time string (e.g. 1:23 or 1:02:03).
     * @param { number } seconds
     * @returns { string }
     */
    function friendlyTimeForSeconds(seconds) {
        if (isNaN(seconds) || seconds < 0)
            return "0:00";
        seconds = Math.floor(seconds);
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = seconds % 60;
        if (h > 0) {
            return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
        } else {
            return `${m}:${s.toString().padStart(2, '0')}`;
        }
    }

    /**
     * Escapes HTML special characters in a string.
     * @param { string } str
     * @returns { string }
     */
    function escapeHtml(str) {
        if (typeof str !== 'string')
            return str;
        return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    /**
     * Cleans a cliphist entry by removing leading digits and tab.
     * @param { string } str
     * @returns { string }
     */
    function cleanCliphistEntry(str: string): string {
        return str.replace(/^\d+\t/, "");
    }

    /**
     * Checks if any substring in the list is contained in the string.
     * @param { string } str
     * @param { string[] } substrings
     * @returns { boolean }
     */
    function stringListContainsSubstring(str, substrings) {
        for (let i = 0; i < substrings.length; ++i) {
            if (str.includes(substrings[i])) {
                return true;
            }
        }
        return false;
    }

    /**
     * Removes the given prefix from the string if present.
     * @param { string } str
     * @param { string } prefix
     * @returns { string }
     */
    function cleanPrefix(str, prefix) {
        if (str.startsWith(prefix)) {
            return str.slice(prefix.length);
        }
        return str;
    }

    /**
     * Removes the first matching prefix from the string if present.
     * @param { string } str
     * @param { string[] } prefixes
     * @returns { string }
     */
    function cleanOnePrefix(str, prefixes) {
        for (let i = 0; i < prefixes.length; ++i) {
            if (str.startsWith(prefixes[i])) {
                return str.slice(prefixes[i].length);
            }
        }
        return str;
    }

    function toTitleCase(str) {
        // Replace "-" and "_" with space, then capitalize each word
        return str.replace(/[-_]/g, " ").replace(
            /\w\S*/g,
            function(txt) {
            return txt.charAt(0).toUpperCase() + txt.slice(1).toLowerCase();
            }
        );
    }
}
