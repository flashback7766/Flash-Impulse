#!/usr/bin/env python3
"""
Fetch a page and hand back its readable text.

Search alone gives the assistant three-line snippets, which is enough to pick a
link and not enough to answer from. This is the second half: the model searches,
decides which result actually matters, and then reads it — the same shape as the
search/fetch pair in claude.ai and ChatGPT.

Extraction is lxml only. bs4/readability/trafilatura would each read better on
messy pages, but lxml and requests are already in the shell's environment and
this does not need to be perfect — it needs to turn an article into prose
without script bodies and navigation menus in the middle of it.

Prints JSON on stdout: {"url", "title", "text", "truncated", "error"}. Always
exits 0 with a parseable object, for the same reason as web_search.py: the
output goes back to a model, which can act on "that page refused us" but not on
an empty string.
"""
import argparse
import json
import sys

# Chrome rather than python-requests: a number of sites answer the default
# urllib/requests agent with a 403 and nothing else.
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

# Everything here is either chrome or repeated on every page of a site, and all
# of it costs context that the article itself should be spending.
STRIP_TAGS = ("script", "style", "noscript", "svg", "nav", "footer", "header",
              "aside", "form", "iframe", "template", "button")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("--max-chars", type=int, default=6000)
    args = parser.parse_args()

    url = args.url.strip()
    # Anything without a scheme is very likely a model hallucinating a bare
    # domain; requests would raise MissingSchema on it anyway.
    if not url.startswith(("http://", "https://")):
        print(json.dumps({"url": url, "title": "", "text": "", "truncated": False,
                          "error": "URL must start with http:// or https://"}))
        return 0

    try:
        import requests
        from lxml import html as lxml_html
    except ImportError as exc:
        print(json.dumps({"url": url, "title": "", "text": "", "truncated": False,
                          "error": f"Missing Python dependency: {exc}"}))
        return 0

    try:
        resp = requests.get(url, headers={"User-Agent": UA, "Accept-Language": "en,*"},
                            timeout=20, allow_redirects=True)
        resp.raise_for_status()
    except Exception as exc:
        print(json.dumps({"url": url, "title": "", "text": "", "truncated": False,
                          "error": f"Could not fetch: {exc}"}))
        return 0

    ctype = (resp.headers.get("Content-Type") or "").lower()
    if "html" not in ctype and "xml" not in ctype:
        # Plain text, JSON and friends need no extraction and would come out of
        # the HTML parser mangled.
        body = resp.text[:args.max_chars]
        print(json.dumps({"url": resp.url, "title": "", "text": body,
                          "truncated": len(resp.text) > len(body), "error": None},
                         ensure_ascii=False))
        return 0

    try:
        doc = lxml_html.fromstring(resp.content)
    except Exception as exc:
        print(json.dumps({"url": resp.url, "title": "", "text": "", "truncated": False,
                          "error": f"Could not parse HTML: {exc}"}))
        return 0

    title = ""
    found = doc.xpath("//title/text()")
    if found:
        title = found[0].strip()

    for tag in STRIP_TAGS:
        for node in doc.xpath(f"//{tag}"):
            node.getparent().remove(node)

    # Prefer the semantic content root; fall back to the body only when the page
    # does not mark one, since on a page that does, <body> drags the chrome back
    # in that was just stripped.
    root = None
    for xp in ("//article", "//main", "//*[@role='main']"):
        nodes = doc.xpath(xp)
        if nodes:
            root = nodes[0]
            break
    if root is None:
        root = doc

    parts = []
    for node in root.iter():
        if node.tag in ("p", "h1", "h2", "h3", "h4", "li", "pre", "blockquote", "td"):
            text = " ".join(node.text_content().split())
            # One- and two-word fragments are almost always menu items or badges
            # that survived the tag strip.
            if len(text) > 2:
                parts.append(text)

    text = "\n".join(parts).strip()
    if not text:
        text = " ".join(doc.text_content().split())

    truncated = len(text) > args.max_chars
    print(json.dumps({"url": resp.url, "title": title, "text": text[:args.max_chars],
                      "truncated": truncated, "error": None}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
