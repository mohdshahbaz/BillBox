#!/usr/bin/env python3
"""Records the Mac engine's answers (Node, backend/src) as golden files for the Xcode unit tests (ios/BillBoxCore/Tests/BillBoxCoreTests, run by `swift test` and by the BillBoxTests target in Xcode).

The unit tests replay the same steps on the iOS engine inside the simulator and compare every reply, field by field,
with what the Mac answered. Run this again whenever the Mac backend changes:  python3 make_golden.py
Paths inside the steps use {work} (a temporary folder), {engine} and {macbackup} (the bundled Mac backup folder)."""
import json, os, subprocess, sys, shutil, tempfile, datetime
# the answers are labelled as recorded in India (meta.json); the Mac engine must work out "today" in that time zone too,
# whatever this computer's own zone is (otherwise answers recorded between midnight UTC and 05:30 IST carry yesterday)
os.environ['TZ'] = 'Asia/Kolkata'

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '../../BillBoxCore/Tests/BillBoxCoreTests/Golden')
FIX = os.path.join(HERE, '../../../backend/test/fixtures/private')   # real bills, kept off GitHub
PRIV_OUT = os.path.join(OUT, 'private')
TMP = tempfile.mkdtemp()

def node(steps, name):
    data = os.path.join(TMP, name + '-data'); bdir = os.path.join(TMP, name + '-home', 'DistributorProBackups')
    f = os.path.join(TMP, name + '.json')
    json.dump(steps, open(f, 'w'))
    out = subprocess.run(['node', '--disable-warning=ExperimentalWarning', os.path.join(HERE, 'run-node.js'), data, f, bdir],
                         capture_output=True, text=True, check=True).stdout
    return [json.loads(l) for l in out.splitlines() if l.strip()]

def concrete(steps, **subs):
    s = json.dumps(steps)
    for k, v in subs.items(): s = s.replace('{' + k + '}', v)
    return json.loads(s)

def save(name, steps, outputs):
    json.dump(steps, open(os.path.join(OUT, name + '.json'), 'w'))
    with open(os.path.join(OUT, name + '.mac.jsonl'), 'w') as f:
        for o in outputs: f.write(json.dumps(o, separators=(',', ':')) + '\n')
    print(f'{name}: {len(steps)} steps')

shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
started = datetime.datetime.now(datetime.timezone.utc)

# 1. the main working session (dates relative to today: the tests freeze the iOS clock at the recorded time)
subprocess.run([sys.executable, os.path.join(HERE, 'gen_scenario.py'), TMP], check=True, capture_output=True)
scen = json.loads(open(os.path.join(TMP, 'scenario.json')).read().replace(TMP, '{work}'))
save('scenario', scen, node(concrete(scen, work=TMP, engine='mac'), 'scenario'))

# 2. supplier-bill parser, random bills, page text from the real PDFs' text runs (watermarks included)
# (the parser and page-text goldens come from real supplier bills: they go to Golden/private, which is kept off GitHub)
os.makedirs(PRIV_OUT, exist_ok=True)
for name in ('parser', 'fuzz'):
    subprocess.run([sys.executable, os.path.join(HERE, f'gen_{name}.py'), TMP], check=True, capture_output=True)
    steps = json.load(open(os.path.join(TMP, name + '.json')))
    save(('private/' if name == 'parser' else '') + name, steps, node(steps, name))
if os.path.exists(os.path.join(FIX, 'pdf_text_runs.json')):
    steps = json.load(open(os.path.join(FIX, 'pdf_text_runs.json')))
    save('private/pagetext', steps, node(steps, 'pagetext'))

# 3. a backup made by the Mac, with the Mac's books at that moment
steps = [s for s in concrete(scen, work=TMP, engine='mac') if s.get('op') != 'dump'] + [{'op': 'backup'}, {'op': 'dump'}]
res = node(steps, 'macbackup')
folder = res[-2]['folder']
shutil.copytree(folder, os.path.join(OUT, 'MacBackup'))
json.dump(res[-1]['dump'], open(os.path.join(OUT, 'macbackup.dump.json'), 'w'))
print('MacBackup:', sorted(os.listdir(os.path.join(OUT, 'MacBackup'))))
# the same backup as it often reaches a phone: zipped by Finder (deflated, folder inside, __MACOSX junk)
import zipfile, random
with zipfile.ZipFile(os.path.join(OUT, 'MacBackup.zip'), 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for f in sorted(os.listdir(os.path.join(OUT, 'MacBackup'))):
        z.write(os.path.join(OUT, 'MacBackup', f), os.path.basename(folder) + '/' + f)
    z.writestr('__MACOSX/' + os.path.basename(folder) + '/._manifest.json', b'junk')
rnd = random.Random(5)
blob = bytes(rnd.choice(b'ABCDEFGH  \n0123') for _ in range(300000)) + bytes(rnd.randrange(256) for _ in range(5000)) + b'x' * 70000
with zipfile.ZipFile(os.path.join(OUT, 'mixed.zip'), 'w') as z:
    for lvl, name in [(0, 'stored.bin'), (1, 'fast.bin'), (9, 'best.bin')]:
        z.writestr(zipfile.ZipInfo(name), blob, compress_type=zipfile.ZIP_STORED if lvl == 0 else zipfile.ZIP_DEFLATED, compresslevel=lvl or None)
    z.writestr('empty.txt', b'', compress_type=zipfile.ZIP_DEFLATED)
    z.writestr('sub/dir/tiny.txt', b'a', compress_type=zipfile.ZIP_DEFLATED)
open(os.path.join(OUT, 'mixed.blob'), 'wb').write(blob)

# 4. restoring that backup: Replace into a fresh install, Merge into partly overlapping books, one company file
replace = [{'method': 'POST', 'path': '/backup/restore', 'body': {'folder': '{macbackup}'}}, {'op': 'dump'}]
merge = [
    {'method': 'PUT', 'path': '/companies/1', 'body': {'name': 'ak  enterprises'}},
    {'method': 'POST', 'path': '/parties', 'body': {'name': 'Gupta General Store', 'phone': '1111111111', 'opening_balance': 99}},
    {'method': 'POST', 'path': '/items', 'body': {'name': 'BIKANO BHUJIA(1X300PKT) MRP-10/-', 'gst_rate': 5, 'retail_price': 1}},
    {'method': 'POST', 'path': '/items', 'body': {'name': 'Local Only Item', 'gst_rate': 18}},
    {'method': 'POST', 'path': '/batches', 'body': {'item_id': 2, 'qty': 50}},
    {'method': 'POST', 'path': '/invoices', 'body': {'pay_mode': 'CASH', 'lines': [{'item_id': 2, 'pcs': 3}]}},
    {'method': 'POST', 'path': '/backup/restore', 'body': {'folder': '{macbackup}', 'mode': 'merge'}}, {'op': 'dump'}]
one = [f for f in os.listdir(folder) if f.startswith('AK_Enterprises')][0]
single = [{'method': 'POST', 'path': '/backup/restore', 'body': {'file': '{macbackup}/' + one, 'company_id': 1}}, {'op': 'dump'}]
mb = os.path.join(TMP, 'mb-copy')
for name, steps in (('restore_replace', replace), ('restore_merge', merge), ('restore_single', single)):
    shutil.rmtree(mb, ignore_errors=True); shutil.copytree(folder, mb)
    save(name, steps, node(concrete(steps, macbackup=mb), name))

# 5. the billing screen's live arithmetic: the Mac's BillMath (via its line-for-line JS copy) on 3,000 random bills
import random
rnd = random.Random(20261028)
bills = []
for n in range(3000):
    lines = []
    for _ in range(rnd.randint(1, 12)):
        ppb = rnd.choice([1, 1, 6, 10, 12, 24, 30, 48, 72, 96, 120, 144, 300, 432])
        rate = round(rnd.uniform(0.5, 900) if rnd.random() < 0.9 else rnd.uniform(900, 25000), rnd.choice([2, 2, 4, 8]))
        lines.append({'boxes': rnd.randint(0, 40) if ppb > 1 else 0, 'pcs': rnd.randint(0, ppb * 2 if ppb > 1 else 500), 'ppb': ppb,
                      'listRate': rate, 'typedRate': (round(rate * rnd.uniform(0.8, 1.2), rnd.choice([0, 2, 3])) if rnd.random() < 0.25 else None),
                      'discPct': rnd.choice([0, 0, 0, 1, 2.5, 3, 5, 7.25, 10, 12.5, 33.333, 100, 120, -5]), 'gstRate': rnd.choice([0, 3, 5, 12, 18, 28])})
    bills.append({'intra': rnd.random() < 0.7, 'lines': lines})
js = "const m=require(%r);const b=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(JSON.stringify(b.map(x=>m.compute(x.lines.map(l=>({...l,typedRate:l.typedRate===null?undefined:l.typedRate})),x.intra))))" % os.path.join(HERE, '../../../backend/test/billmath_port.js')
res = subprocess.run(['node', '-e', js], input=json.dumps(bills), capture_output=True, text=True, check=True).stdout
json.dump({'bills': bills, 'mac': json.loads(res)}, open(os.path.join(OUT, 'billmath.json'), 'w'))
print('billmath: 3000 bills')

json.dump({'recorded': started.strftime('%Y-%m-%dT%H:%M:%S.000Z'), 'timezone': 'Asia/Kolkata',
           'note': 'Recorded from the Mac engine (Node, backend/src) by ios/tests/parity/make_golden.py'},
          open(os.path.join(OUT, 'meta.json'), 'w'), indent=1)
shutil.rmtree(TMP, ignore_errors=True)
