#!/usr/bin/env python3
"""The two GST workbooks must hold the same parts with the same XML (compression may differ)."""
import sys, zipfile
a, b = zipfile.ZipFile(sys.argv[1]), zipfile.ZipFile(sys.argv[2])
na, nb = a.namelist(), b.namelist()
assert na == nb, f'parts differ: {na} vs {nb}'
bad = [n for n in na if a.read(n) != b.read(n)]
for n in bad: print('xlsx part differs:', n, '\n mac:', a.read(n)[:300], '\n ios:', b.read(n)[:300])
print(f'xlsx: {len(na)} parts compared, {len(bad)} differ')
sys.exit(1 if bad else 0)
