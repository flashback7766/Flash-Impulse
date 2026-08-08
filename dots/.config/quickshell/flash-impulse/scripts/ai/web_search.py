#!/usr/bin/env python3
"""
Web search for the sidebar assistant.

Replaces a curl|grep scrape of html.duckduckgo.com that had stopped returning
anything at all: that endpoint now answers a bare landing page for GET and a
202 challenge for POST, so the old pipeline produced empty output on every
search and the assistant was told "No results found" every time. lite.duckduckgo
and the public SearXNG instances are blocked or rate-limited the same way.

ddgs is the maintained client for the same engine and keeps up with the
token/endpoint changes that broke the scrape, which is the whole reason to take
a dependency here rather than pin a fragile regex to somebody's markup.

Prints JSON on stdout: {"results": [{title, url, snippet}], "error": str|None}.
Always exits 0 with a parseable object — the caller feeds this straight back to
a model, and a non-zero exit with a traceback on stderr would reach it as an
empty result rather than as something it can tell the user about.
"""
import argparse
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("query")
    parser.add_argument("--max-results", type=int, default=6)
    args = parser.parse_args()

    query = args.query.strip()
    if not query:
        print(json.dumps({"results": [], "error": "Empty query."}))
        return 0

    try:
        from ddgs import DDGS
    except ImportError:
        print(json.dumps({
            "results": [],
            "error": "The 'ddgs' package is missing from the shell's Python environment. "
                     "Reinstall dependencies, or run: uv pip install ddgs",
        }))
        return 0

    try:
        # Capped rather than unbounded: this text goes back into the model's
        # context, and ten verbose snippets cost more than they add.
        raw = list(DDGS().text(query, max_results=max(1, min(args.max_results, 10))))
    except Exception as exc:
        print(json.dumps({"results": [], "error": f"Search failed: {exc}"}))
        return 0

    results = []
    for item in raw:
        url = item.get("href") or item.get("url") or ""
        if not url:
            continue
        results.append({
            "title": (item.get("title") or "").strip(),
            "url": url,
            # Trimmed: snippets are occasionally a whole paragraph, and the
            # model only needs enough to decide which link is worth fetching.
            "snippet": (item.get("body") or "").strip()[:400],
        })

    print(json.dumps({"results": results, "error": None}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
