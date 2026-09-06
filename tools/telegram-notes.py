#!/usr/bin/env python3
"""Append release footnotes to telegram-post.txt (HTML-escaped).
Usage: telegram-notes.py <extra-file> <post-file>
Skips # comment lines and blanks; inserts a Notes block before Download
(or appends at end if the template marker moved). No-op when empty.
"""
import html
import sys

extra, post = sys.argv[1], sys.argv[2]
lines = [
    l
    for l in open(extra).read().splitlines()
    if l.strip() and not l.strip().startswith("#")
]
text = open(post).read()
if lines:
    block = "<b>📌 Notes</b>\n" + "\n".join(html.escape(l) for l in lines) + "\n\n"
    marker = "<b>⬇️ Download</b>"
    text = text.replace(marker, block + marker) if marker in text else text + "\n" + block
    open(post, "w").write(text)
print("telegram notes:", len(lines))
