#!/usr/bin/env python3
"""Compares the Node (Mac) and Swift (iOS) outputs of a parity scenario, step by step and field by field."""
import json, sys, math

LOOSE_KEYS = {'created', 'last_run', 'last_status', 'folder', 'sha256', 'bytes', 'name_ts'}

def same(a, b, path, diffs, loose):
    if isinstance(a, bool) or isinstance(b, bool):
        if a != b: diffs.append(f'{path}: {a!r} != {b!r}')
        return
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        if (isinstance(a, float) and math.isnan(a)) and (isinstance(b, float) and math.isnan(b)): return
        if abs(a - b) > 1e-9 * max(1.0, abs(a), abs(b)): diffs.append(f'{path}: {a!r} != {b!r}')
        return
    if isinstance(a, dict) and isinstance(b, dict):
        ka, kb = set(a), set(b)
        for k in sorted(ka | kb):
            if (loose and k in LOOSE_KEYS) or k == 'created_at': continue   # created_at is the wall clock of each run
            if k not in a: diffs.append(f'{path}.{k}: missing on Mac (iOS has {b[k]!r:.80})'); continue
            if k not in b: diffs.append(f'{path}.{k}: missing on iOS (Mac has {a[k]!r:.80})'); continue
            same(a[k], b[k], f'{path}.{k}', diffs, loose)
        return
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b): diffs.append(f'{path}: {len(a)} items on Mac, {len(b)} on iOS')
        for i, (x, y) in enumerate(zip(a, b)): same(x, y, f'{path}[{i}]', diffs, loose)
        return
    if a != b: diffs.append(f'{path}: {a!r:.120} != {b!r:.120}')

def strip_local(o):
    """The licence's device id and trial start are written by the app itself when it opens (on the Android emulator
    that can happen while the session replays), so they are per-device, not part of the books: left out of dumps."""
    if isinstance(o, dict):
        for k, v in o.items():
            if k == 'app_settings' and isinstance(v, list):
                o[k] = [r for r in v if not (isinstance(r, dict) and str(r.get('key', '')).startswith('license_'))]
            else:
                strip_local(v)
    elif isinstance(o, list):
        for v in o: strip_local(v)
    return o

def main():
    scen = json.load(open(sys.argv[1]))
    mac = [strip_local(json.loads(l)) for l in open(sys.argv[2]) if l.strip()]
    ios = [strip_local(json.loads(l)) for l in open(sys.argv[3]) if l.strip()]
    bad = 0
    if len(mac) != len(ios): print(f'step count differs: Mac {len(mac)}, iOS {len(ios)}'); bad += 1
    for m, i in zip(mac, ios):
        st = scen[m['step']]
        diffs = []
        same(m, i, f"step {m['step']} {st.get('op') or st.get('method','GET')} {st.get('path','')}", diffs, st.get('loose', False))
        if diffs:
            bad += 1
            print('\n'.join(diffs[:12]) + ('\n  ...' if len(diffs) > 12 else ''))
    print(f'{len(mac)} steps compared, {bad} with differences')
    sys.exit(1 if bad else 0)

main()
