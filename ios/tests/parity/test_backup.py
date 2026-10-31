#!/usr/bin/env python3
"""Backups made by one app restore in the other, both ways, in Replace and Merge mode, and from a single company file.

  1. The main scenario runs on the Mac engine and on the iOS engine; each makes a backup.
  2. Mac backup -> restored by iOS into a fresh install; iOS backup -> restored by the Mac into a fresh install.
     Every table of every restored company must equal the books that were backed up (matched by company name).
  3. Merge: both engines set up the same partly overlapping books and merge the Mac backup; replies and books must agree.
  4. A single company .db file restores into the company it belongs to, on both.
"""
import json, os, subprocess, sys, shutil, sqlite3, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = sys.argv[1]
BIN = sys.argv[2]
SCEN = json.load(open(os.path.join(WORK, 'scenario.json')))

def run(engine, data, steps, name):
    f = os.path.join(WORK, f'bk-{name}-{engine}.json')
    json.dump(steps, open(f, 'w'))
    home = os.path.join(WORK, f'bk-{name}-{engine}-home')
    os.makedirs(home, exist_ok=True)
    bdir = os.path.join(home, 'DistributorProBackups')
    if engine == 'mac':
        cmd = ['node', '--disable-warning=ExperimentalWarning', os.path.join(HERE, 'run-node.js'), data, f, bdir]
    else:
        cmd = [BIN, data, f, bdir]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return [json.loads(l) for l in out.splitlines() if l.strip()]

def by_name(dump):
    names = {str(r['id']): r['name'] + ((' ' + r['fy']) if r.get('fy') else '') for r in dump['registry']}
    out = {}
    for cid, tables in dump['companies'].items():
        t = {k: v for k, v in tables.items()}
        out[' '.join(names[cid].split()).lower()] = t
    return out

failures = 0
def check(cond, msg):
    global failures
    print(('  ok   ' if cond else '  FAIL ') + msg)
    if not cond: failures += 1

def tables_equal(a, b, label):
    sys.path.insert(0, HERE)
    diffs = []
    for k in sorted(set(a) | set(b)):
        if k not in a or k not in b: diffs.append(f'{k}: table missing'); continue
        if json.dumps(a[k], sort_keys=True) != json.dumps(b[k], sort_keys=True):
            # numbers may print 5 vs 5.0 between engines; compare numerically
            ra, rb = a[k], b[k]
            if len(ra) != len(rb): diffs.append(f'{k}: {len(ra)} rows vs {len(rb)}'); continue
            for x, y in zip(ra, rb):
                for c in set(x) | set(y):
                    vx, vy = x.get(c), y.get(c)
                    if isinstance(vx, (int, float)) and isinstance(vy, (int, float)) and abs(vx - vy) < 1e-9: continue
                    if vx != vy: diffs.append(f'{k}.{c}: {vx!r} vs {vy!r}'); break
    check(not diffs, f'{label}' + (': ' + '; '.join(diffs[:5]) if diffs else ''))

def fresh(name):
    d = os.path.join(WORK, name)
    shutil.rmtree(d, ignore_errors=True)
    shutil.rmtree(d + '-home', ignore_errors=True)
    return d

# 1. both engines build the books and back up
steps = [s for s in SCEN if s.get('op') != 'dump'] + [{'op': 'backup'}, {'op': 'dump'}]
mac_out = run('mac', fresh('bk-a-mac-data'), steps, 'a')
ios_out = run('ios', fresh('bk-a-ios-data'), steps, 'a')
mac_folder, ios_folder = mac_out[-2]['folder'], ios_out[-2]['folder']
mac_books, ios_books = by_name(mac_out[-1]['dump']), by_name(ios_out[-1]['dump'])
print('Backups:', os.path.basename(mac_folder), '(Mac)', os.path.basename(ios_folder), '(iOS)')

def manifest_ok(folder, label):
    m = json.load(open(os.path.join(folder, 'manifest.json')))
    good = all(hashlib.sha256(open(os.path.join(folder, f['file']), 'rb').read()).hexdigest() == f['sha256'] for f in m['files'])
    keys = list(m.keys()) == ['created', 'reason', 'files'] and all(list(f.keys())[-3:] == ['file', 'bytes', 'sha256'] for f in m['files'])
    ok = all(sqlite3.connect(os.path.join(folder, f['file'])).execute('PRAGMA integrity_check').fetchone()[0] == 'ok' for f in m['files'])
    check(good and keys and ok and len(m['files']) == 5, f'{label} backup: manifest layout, SHA-256 of every file and integrity check')
manifest_ok(mac_folder, 'Mac'); manifest_ok(ios_folder, 'iOS')

# 2. cross restore, Replace
r_ios = run('ios', fresh('bk-r1-ios-data'), [{'method': 'POST', 'path': '/backup/restore', 'body': {'folder': mac_folder}}, {'op': 'dump'}], 'r1')
check(r_ios[0].get('status') == 200 and [' '.join(n.split()) for n in r_ios[0]['body']['restored']] == ['AK Enterprises', 'Second Traders', 'AK Enterprises', 'AK Enterprises'], f"iOS restores the Mac backup: {r_ios[0].get('body')}")
got = by_name(r_ios[-1]['dump'])
for co in ('ak enterprises', 'second traders', 'ak enterprises 2027-28', 'ak enterprises 2025-26'): tables_equal(mac_books[co], got[co], f'Mac backup restored on iOS: every table of "{co}" equals the Mac books')

r_mac = run('mac', fresh('bk-r2-mac-data'), [{'method': 'POST', 'path': '/backup/restore', 'body': {'folder': ios_folder}}, {'op': 'dump'}], 'r2')
check(r_mac[0].get('status') == 200 and [' '.join(n.split()) for n in r_mac[0]['body']['restored']] == ['AK Enterprises', 'Second Traders', 'AK Enterprises', 'AK Enterprises'], f"Mac restores the iOS backup: {r_mac[0].get('body')}")
got = by_name(r_mac[-1]['dump'])
for co in ('ak enterprises', 'second traders', 'ak enterprises 2027-28', 'ak enterprises 2025-26'): tables_equal(ios_books[co], got[co], f'iOS backup restored on the Mac: every table of "{co}" equals the iOS books')

# 3. Merge: partly overlapping books, then merge the Mac backup; both engines must agree
setup = [
    {'method': 'PUT', 'path': '/companies/1', 'body': {'name': 'ak  enterprises'}},
    {'method': 'POST', 'path': '/parties', 'body': {'name': 'Gupta General Store', 'phone': '1111111111', 'opening_balance': 99}},
    {'method': 'POST', 'path': '/items', 'body': {'name': 'BIKANO BHUJIA(1X300PKT) MRP-10/-', 'gst_rate': 5, 'retail_price': 1}},
    {'method': 'POST', 'path': '/items', 'body': {'name': 'Local Only Item', 'gst_rate': 18}},
    {'method': 'POST', 'path': '/batches', 'body': {'item_id': 2, 'qty': 50}},
    {'method': 'POST', 'path': '/invoices', 'body': {'pay_mode': 'CASH', 'lines': [{'item_id': 2, 'pcs': 3}]}},
]
merge = setup + [{'method': 'POST', 'path': '/backup/restore', 'body': {'folder': mac_folder, 'mode': 'merge'}}, {'op': 'dump'}]
m_mac = run('mac', fresh('bk-m-mac-data'), merge, 'm')
m_ios = run('ios', fresh('bk-m-ios-data'), merge, 'm')
rep_mac, rep_ios = m_mac[-2], m_ios[-2]
check(rep_mac.get('status') == 200 and json.dumps(rep_mac['body'], sort_keys=True) == json.dumps(rep_ios['body'], sort_keys=True),
      'Merge reply (added / skipped / conflicts per company) is the same on both: ' + json.dumps(rep_ios.get('body'))[:300])
a, b = by_name(m_mac[-1]['dump']), by_name(m_ios[-1]['dump'])
for co in sorted(set(a) | set(b)): tables_equal(a.get(co, {}), b.get(co, {}), f'After merge, "{co}" books are identical on Mac and iOS')

# 4. single company file
one = os.path.join(mac_folder, [f for f in os.listdir(mac_folder) if f.startswith('AK_Enterprises')][0])
single = [{'method': 'POST', 'path': '/backup/restore', 'body': {'file': one, 'company_id': 1}}, {'op': 'dump'}]
s_mac = run('mac', fresh('bk-s-mac-data'), single, 's')
s_ios = run('ios', fresh('bk-s-ios-data'), single, 's')
check(s_mac[0]['body'] == s_ios[0]['body'], f"Single company file restores the same way on both: {s_ios[0].get('body')}")
a, b = by_name(s_mac[-1]['dump']), by_name(s_ios[-1]['dump'])
for co in sorted(set(a) | set(b)): tables_equal(a.get(co, {}), b.get(co, {}), f'Single file: "{co}" identical on Mac and iOS')

# refusals are the same
bad = [{'method': 'POST', 'path': '/backup/restore', 'body': {'folder': '/nonexistent'}}, {'method': 'POST', 'path': '/backup/restore', 'body': {'file': 'relative.db'}},
       {'method': 'POST', 'path': '/backup/restore', 'body': {'folder': WORK}}, {'method': 'DELETE', 'path': '/backup/notabackup'},
       {'method': 'PUT', 'path': '/backup/config', 'body': {'dir': 'relative/path'}}, {'method': 'PUT', 'path': '/backup/config', 'body': {'time': '25:00'}}]
x, y = run('mac', fresh('bk-x-mac-data'), bad, 'x'), run('ios', fresh('bk-x-ios-data'), bad, 'x')
check([(r['status'], r['body']) for r in x] == [(r['status'], r['body']) for r in y], 'Refused restores and settings give the same errors on both')

print(f'{failures} failure(s)')
sys.exit(1 if failures else 0)
