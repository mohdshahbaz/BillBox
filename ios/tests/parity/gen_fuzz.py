#!/usr/bin/env python3
"""Random bills: thousands of previews (and some saves) over random tiers, states, boxes, pieces, typed rates, discounts and schemes."""
import json, os, sys, random, datetime
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 7)
out = sys.argv[1]
today = datetime.date.today().isoformat()
S = []
add = lambda m, p, b=None, **k: S.append(dict({'method': m, 'path': p, 'body': b or {}}, **k))
gst = [0, 5, 12, 18, 28, 3]
for i in range(40):
    ppb = random.choice([1, 1, 6, 12, 24, 48, 144, 240, 300, 432])
    mrp = random.choice([1, 2, 5, 10, 20, 35.5, 99, 120, 499, 650, 2999])
    add('POST', '/items', {'name': f'Item {i} (1X{ppb})' if ppb > 1 else f'Loose item {i}', 'gst_rate': random.choice(gst), 'mrp': mrp,
                           'retail_price': round(mrp * random.uniform(0.6, 0.95), random.choice([2, 4, 6])), 'wholesale_price': round(mrp * random.uniform(0.5, 0.9), random.choice([2, 6])),
                           'purchase_price': round(mrp * 0.5, 2), 'pcs_per_box': ppb})
    for b in range(random.randint(1, 3)):
        add('POST', '/batches', {'item_id': i + 1, 'qty': random.randint(50, 5000), 'batch_no': f'B{b}', 'exp_date': random.choice(['2099-12-31', '2027-03-31', '2026-11-30'])})
    if random.random() < 0.3: add('POST', '/schemes', {'item_id': i + 1, 'type': 'FREE_QTY', 'buy_qty': random.choice([5, 10, 24]), 'free_qty': random.choice([1, 2])})
    if random.random() < 0.3: add('POST', '/schemes', {'item_id': i + 1, 'type': 'PERCENT', 'buy_qty': random.choice([1, 12, 50]), 'percent': random.choice([1.5, 2, 5, 7.25])})
for i, (tier, st) in enumerate([('RETAIL', '09'), ('WHOLESALE', '09'), ('MRP', '09'), ('RETAIL', '07'), ('WHOLESALE', ''), ('MRP', '27')]):
    add('POST', '/parties', {'name': f'Party {i}', 'price_tier': tier, 'state_code': st})
for n in range(1500):
    lines = []
    for _ in range(random.randint(1, 6)):
        ln = {'item_id': random.randint(1, 40)}
        r = random.random()
        if r < 0.45: ln['boxes'] = random.randint(0, 3); ln['pcs'] = random.randint(0, 30)
        elif r < 0.75: ln['pcs'] = random.randint(1, 400)
        elif r < 0.9: ln['qty'] = random.randint(1, 200)
        else: ln['boxes'] = str(random.randint(1, 2)); ln['pcs'] = ''
        if random.random() < 0.3: ln['rate'] = random.choice([str(round(random.uniform(0.5, 500), random.choice([0, 2, 4, 8]))), round(random.uniform(1, 2000), 6), ''])
        if random.random() < 0.3: ln['disc_pct'] = random.choice([2.5, '5', 10, 0.75, 33.333])
        lines.append(ln)
    party = random.choice([None, 1, 2, 3, 4, 5, 6])
    body = {'lines': lines, 'date': today}
    if party: body['party_id'] = party
    save = n % 10 == 0
    if save:
        body['pay_mode'] = random.choice(['CASH', 'UPI', 'CREDIT'])
        if party is None: body['pay_mode'] = 'CASH'
        if random.random() < 0.3: body['paid_amount'] = random.choice([0, 100, '250.5'])
    add('POST', '/invoices' if save else '/invoices/preview', body)
S.append({'method': 'GET', 'path': '/reports/dashboard'}); S.append({'method': 'GET', 'path': '/reports/gst-outward'}); S.append({'op': 'dump'})
json.dump(S, open(os.path.join(out, 'fuzz.json'), 'w'))
print(len(S), 'steps')
