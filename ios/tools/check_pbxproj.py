#!/usr/bin/env python3
"""Parses BillBox.xcodeproj/project.pbxproj (OpenStep plist) and checks every object reference resolves and every file exists."""
import re, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, 'BillBox.xcodeproj/project.pbxproj')).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S); src = re.sub(r'^//.*$', '', src, flags=re.M)
tok = re.compile(r'\s*("(?:[^"\\]|\\.)*"|[{}()=;,]|[^\s{}()=;,"]+)')
toks = []; pos = 0
while True:
    m = tok.match(src, pos)
    if not m or m.end() == pos: break
    toks.append(m.group(1)); pos = m.end()
assert src[pos:].strip() == '', 'unparsed tail: ' + src[pos:pos+80]
i = 0
def val():
    global i
    t = toks[i]; i += 1
    if t == '{':
        d = {}
        while toks[i] != '}':
            k = val(); assert toks[i] == '=', (k, toks[i:i+5]); i += 1
            d[k] = val(); assert toks[i] == ';', (k, toks[i:i+5]); i += 1
        i += 1; return d
    if t == '(':
        a = []
        while toks[i] != ')':
            a.append(val())
            if toks[i] == ',': i += 1
        i += 1; return a
    return t[1:-1] if t.startswith('"') else t
root = val()
objs = root['objects']
bad = []
def walk(v, where):
    if isinstance(v, dict): [walk(x, where) for x in v.values()]
    elif isinstance(v, list): [walk(x, where) for x in v]
    elif isinstance(v, str) and re.fullmatch(r'[0-9A-F]{24}', v) and v not in objs: bad.append((where, v))
for k, o in objs.items(): walk(o, k)
assert root['rootObject'] in objs
# resolve file paths through groups
parent = {}
for k, o in objs.items():
    if o['isa'] == 'PBXGroup':
        for c in o['children']: parent[c] = k
def full(k):
    parts = []
    while k in parent or objs[k].get('path'):
        if objs[k].get('path'): parts.append(objs[k]['path'])
        if k not in parent: break
        k = parent[k]
    return os.path.join(ROOT, *reversed(parts))
missing = [full(k) for k, o in objs.items() if o['isa'] == 'PBXFileReference' and o.get('sourceTree') == '<group>' and not os.path.exists(full(k))]
for t in (o for o in objs.values() if o['isa'] == 'PBXNativeTarget'):
    print(t['name'], {objs[p]['isa']: len(objs[p]['files']) for p in t['buildPhases']})
print('objects', len(objs), 'dangling', bad, 'missing files', missing)
sys.exit(1 if bad or missing else 0)
