#!/usr/bin/env python3
"""Reads a uiautomator dump (stdin) and prints the centre "x y" of the first node whose text or description contains the
pattern (case-insensitive). With --edit, only text boxes. Exit 1 when nothing matches."""
import sys, re
pat = sys.argv[1].lower()
edit = '--edit' in sys.argv
skip = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--skip=')), '0'))
xml = sys.stdin.read()
for m in re.finditer(r'<node [^>]*>', xml):
    n = m.group(0)
    t = (re.search(r' text="([^"]*)"', n) or [None, ''])[1]
    d = (re.search(r' content-desc="([^"]*)"', n) or [None, ''])[1]
    cls = (re.search(r' class="([^"]*)"', n) or [None, ''])[1]
    if edit and 'EditText' not in cls: continue
    if pat in t.lower() or pat in d.lower():
        if skip: skip -= 1; continue
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        if b:
            x1, y1, x2, y2 = map(int, b.groups())
            print((x1 + x2) // 2, (y1 + y2) // 2); sys.exit(0)
sys.exit(1)
