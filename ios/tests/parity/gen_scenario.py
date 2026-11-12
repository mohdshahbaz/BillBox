#!/usr/bin/env python3
"""Writes scenario.json: one long working session (companies, stock, parties, purchases, bills, payments, reports, mistakes
and corrections) that both engines replay. Dates sit in the current financial year plus one earlier year."""
import json, sys, datetime, os

today = datetime.date.today()
fy_start = today.year if today.month >= 4 else today.year - 1
cur = lambda m, d: f"{fy_start + (1 if m < 4 else 0)}-{m:02d}-{d:02d}"     # a date in the current FY
prev = lambda m, d: f"{fy_start - 1 + (1 if m < 4 else 0)}-{m:02d}-{d:02d}" # a date in the previous FY
month = today.strftime('%Y-%m')
D1, D2, D3 = today.replace(day=1).isoformat(), today.isoformat(), (today - datetime.timedelta(days=3)).isoformat()
if D3 < cur(4, 1): D3 = D2
S = []
def req(method, path, body=None, query=None, company=None, **kw):
    s = {'method': method, 'path': path}
    if body is not None: s['body'] = body
    if query is not None: s['query'] = query
    if company is not None: s['company'] = company
    s.update(kw)
    S.append(s)
get = lambda p, q=None, **k: req('GET', p, query=q, **k)
post = lambda p, b=None, **k: req('POST', p, b if b is not None else {}, **k)
put = lambda p, b=None, **k: req('PUT', p, b if b is not None else {}, **k)
delete = lambda p, q=None, **k: req('DELETE', p, query=q, **k)
dump = lambda: S.append({'op': 'dump'})
out_dir = sys.argv[1] if len(sys.argv) > 1 else '.'

# ---------------- companies and settings
get('/companies'); get('/fy'); get('/settings')
put('/companies/1', {'name': 'AK Enterprises', 'company_gstin': '09aaaca0000a1z5', 'state_code': '09', 'company_address': 'Main Bazar, Bijnor', 'company_phone': '9000000001'})
post('/companies', {'name': 'Bad Co', 'company_gstin': 'XYZ'})
post('/companies', {'name': ''})
post('/companies', {'name': 'Bad State', 'state_code': '9'})
post('/companies', {'name': '  Second Traders ', 'company_gstin': '07aaacn6666e1z6', 'state_code': '07', 'invoice_terms': 'No returns'})
post('/companies/2/activate'); post('/companies/99/activate'); put('/companies/99', {'name': 'x'})
get('/companies')
put('/settings', {'low_stock_qty': -1}); put('/settings', {'low_stock_qty': '25', 'print_layout': 'a4Full', 'wa_cc': 91})
get('/settings')
get('/items', company=99)

# ---------------- categories and items
post('/categories', {'name': 'Namkeen & Snacks'}); post('/categories', {'name': ' '}); post('/categories', {'name': 'Namkeen & Snacks'})
post('/categories', {'name': 'Beverages'})
items = [
    {'name': 'BIKANO BHUJIA(1X300PKT) MRP-10/-', 'hsn': '2106909', 'gst_rate': 5, 'mrp': 10, 'retail_price': 8.1, 'wholesale_price': 7.6, 'purchase_price': 7.2, 'category_id': 1},
    {'name': 'BIKANO CHIPS (1X144 PKT) MRP-10/-', 'hsn': '2106909', 'gst_rate': '5', 'mrp': '10', 'retail_price': '', 'wholesale_price': None},
    {'name': '  Cola   750ml ', 'hsn': '2202', 'gst_rate': 28, 'mrp': 40, 'retail_price': 29.5, 'wholesale_price': 28, 'purchase_price': 25, 'pcs_per_box': 24},
    {'name': 'Basmati Rice 5kg', 'hsn': '1006', 'gst_rate': 5, 'mrp': 650, 'retail_price': 560, 'wholesale_price': 545, 'purchase_price': 520, 'pcs_per_box': '4'},
    {'name': 'Detergent Powder 1kg', 'hsn': '3402', 'mrp': 135, 'retail_price': 105, 'wholesale_price': 100, 'purchase_price': 90, 'pcs_per_box': 20},
    {'name': 'Shampoo Sachet 6ml Rs.2', 'hsn': '3305', 'gst_rate': 18, 'pcs_per_box': 1000, 'purchase_price': 1.1},
    {'name': 'All Time Mix 18G (300 PKT) 5/-', 'hsn': '2106', 'gst_rate': 12},
    {'name': 'Mystery Product Z', 'gst_rate': 18, 'mrp': 0},
    {'name': 'Kurkure Masala @ 20 (1X60)', 'gst_rate': 12, 'mrp': '', 'pcs_per_box': 60},
]
for it in items: post('/items', it)
post('/items', {'name': ''}); post('/items', {'name': 'x' * 121}); post('/items', {'name': 'Bad HSN', 'hsn': '12ab'})
post('/items', {'name': 'Bad GST', 'gst_rate': 41}); post('/items', {'name': 'Bad MRP', 'mrp': -2}); post('/items', {'name': 'Bad Box', 'pcs_per_box': 0})
post('/items', {'name': 'cola 750ML'})                       # duplicate name (any case)
put('/items/3', {'retail_price': 30.25, 'name': 'Cola 750ml (1X24)'}); put('/items/3', {'name': 'basmati rice 5KG'}); put('/items/77', {'name': 'x'})
put('/items/4', {'hsn': '', 'category_id': '', 'gst_rate': ''})
put('/items/4', {'hsn': '1006', 'gst_rate': 5, 'category_id': None})
get('/items'); get('/items', {'q': 'bik'}); get('/items', {'q': '2106'}); get('/items', {'category_id': '1'}); get('/categories'); get('/items', {'all': '1'})

# stock in
post('/batches', {'item_id': 1, 'qty': '600', 'purchase_price': '7.2'}); post('/batches', {'item_id': 1, 'qty': 300, 'batch_no': 'B-EARLY', 'exp_date': cur(12, 31)})
post('/batches', {'item_id': 2, 'qty': 288}); post('/batches', {'item_id': 3, 'qty': 240, 'batch_no': 'CL-1', 'exp_date': cur(11, 30), 'mfg_date': cur(4, 2)})
post('/batches', {'item_id': 3, 'qty': 96, 'batch_no': 'CL-0', 'exp_date': cur(5, 1)})   # expired batch, never sold
post('/batches', {'item_id': 4, 'qty': 40}); post('/batches', {'item_id': 5, 'qty': 80}); post('/batches', {'item_id': 6, 'qty': 3000})
post('/batches', {'item_id': 1, 'qty': 0}); post('/batches', {'qty': 5}); post('/batches', {'item_id': 1, 'qty': 5, 'exp_date': '31-12-2026'})
post('/batches', {'item_id': 1, 'qty': '60'})                 # tops up OPENING
get('/items/1/batches')
post('/schemes', {'item_id': 3, 'type': 'PERCENT', 'buy_qty': '12', 'percent': '5'})
post('/schemes', {'item_id': 1, 'type': 'FREE_QTY', 'buy_qty': 100, 'free_qty': '3', 'valid_from': cur(4, 1), 'valid_to': ''})
post('/schemes', {'item_id': 5, 'type': 'PERCENT', 'buy_qty': 6, 'percent': 3})
post('/schemes', {'item_id': 5, 'type': 'BOGUS'})
post('/schemes', {'item_id': 4, 'type': 'FREE_QTY', 'buy_qty': 10, 'free_qty': 1, 'valid_to': prev(6, 30)})   # expired scheme
get('/schemes'); delete('/schemes/99')

get('/items/mrp-groups'); get('/items/mrp-groups', {'category_id': '1'})
post('/items/auto-mrp'); post('/items/auto-pack'); post('/items/auto-categorize'); get('/items')
post('/items/bulk-prices', {'retail_off': 120}); post('/items/bulk-prices', {})
post('/items/bulk-prices', {'category_id': 1, 'retail_off': '16.67', 'wholesale_off': 21.67, 'preview': True})
post('/items/bulk-prices', {'retail_off': '10', 'preview': 1})
post('/items/bulk-prices-by-mrp', {'tiers': []}); post('/items/bulk-prices-by-mrp', {'tiers': [{'mrp': 0, 'retail': 1}]})
post('/items/bulk-prices-by-mrp', {'tiers': [{'mrp': 10, 'retail': -1}]})
post('/items/bulk-prices-by-mrp', {'tiers': [{'mrp': 10, 'retail': '2500', 'wholesale': 2350}, {'mrp': 5, 'retail': ''}], 'per': 'box', 'include_gst': True, 'preview': True})
post('/items/bulk-prices-by-mrp', {'tiers': [{'mrp': 10, 'retail': '2500', 'wholesale': 2350}], 'per': 'box', 'include_gst': True})
post('/items/bulk-prices-by-mrp', {'category_id': '2', 'tiers': [{'mrp': 40, 'retail': 30}], 'per': 'piece'})
get('/items/mrp-groups')
post('/items/bulk-prices', {'category_id': '', 'wholesale_off': '5.5'})
get('/items')

# ---------------- salesmen, routes, parties
post('/salesmen', {'name': 'Rahul Verma', 'phone': '9810000001', 'monthly_target': 250000}); post('/salesmen', {'name': ''})
post('/salesmen', {'name': 'Imran', 'monthly_target': 'abc'})
put('/salesmen/2', {'phone': '9810000002', 'monthly_target': '180000'}); put('/salesmen/9', {})
post('/routes', {'name': 'Civil Lines Beat', 'salesman_id': '1', 'days': '1,3'}); post('/routes', {'name': 'Station Beat', 'salesman_id': 1, 'days': [5, 3, 3, 9]})
post('/routes', {'name': 'Old style', 'day_of_week': 2}); post('/routes', {'name': ' '})
put('/routes/3', {'days': '0,6'}); get('/routes')
P = [
    {'name': 'Gupta General Store', 'gstin': '09aaapg1111a1z1', 'phone': '9876500001', 'price_tier': 'RETAIL', 'credit_limit': 25000, 'credit_days': 15, 'route_id': 1, 'opening_balance': 4200},
    {'name': 'Singh Kirana', 'mobiles': '9876500002; 9876500003\n9876500002', 'route_id': '1'},
    {'name': 'City Mart Wholesale', 'gstin': '09AAACC2222B1Z2', 'type': 'WHOLESALER', 'price_tier': 'WHOLESALE', 'credit_limit': '100000', 'new_route': {'name': 'Nagina Road', 'salesman_id': 2, 'days': '1'}},
    {'name': 'Delhi Traders', 'gstin': '07AAADT3333C1Z3', 'type': 'WHOLESALER', 'price_tier': 'MRP', 'credit_limit': 1500, 'route_id': 2},
    {'name': 'Ratan Traders', 'gstin': '09AABCR1234M1Z5', 'type': 'SUPPLIER', 'price_tier': 'WHOLESALE', 'tel': '9000011111/9000022222', 'fssai': '10000000000001', 'email': 'accounts@ratan.example', 'opening_balance': -5000},
    {'name': 'Himgiri Enterprise', 'gstin': '05AAAPH1234K1Z2', 'type': 'SUPPLIER', 'mobiles': ['9000033333', ' ', '9000033333']},
]
for p in P: post('/parties', p)
post('/parties', {'name': ''}); post('/parties', {'name': 'Bad GST', 'gstin': '09ABC'}); post('/parties', {'name': 'Bad PAN', 'pan': 'abc'})
post('/parties', {'name': 'Bad FSSAI', 'fssai': '123'}); post('/parties', {'name': 'Bad mail', 'email': 'a@b'}); post('/parties', {'name': 'Bad state', 'state_code': 'U'})
post('/parties', {'name': 'Neg limit', 'credit_limit': -1})
put('/parties/2', {'phone': '9876500009', 'price_tier': 'WHOLESALE'}); put('/parties/2', {'route_id': ''}); put('/parties/2', {'new_route': {'name': 'Fresh Beat', 'days': [2]}})
put('/parties/42', {'name': 'x'})
get('/parties'); get('/parties', {'kind': 'CUSTOMER'}); get('/parties', {'kind': 'SUPPLIER'}); get('/parties', {'q': '98765'}); get('/routes')

# ---------------- purchases
pl = lambda **k: dict({'item_id': 1, 'hsn': '2106909', 'qty': 2, 'unit': 'BOX', 'rate': 2159.22}, **k)
post('/purchases/preview', {'party_id': 5, 'discount': 100, 'cgst': 99, 'sgst': 99, 'round_off': -0.2, 'lines': [pl(), pl(item_id=2, qty=4, rate=1057.38)]})
post('/purchases/preview', {'party_id': 5, 'lines': [pl()]}); post('/purchases/preview', {'party_id': 6, 'lines': [pl(unit='PCS', qty=500, rate=7.2)]})
post('/purchases/preview', {'lines': [pl()]}); post('/purchases/preview', {'party_id': 5, 'lines': []}); post('/purchases/preview', {'party_id': 5, 'lines': [pl(qty=2.5)]})
post('/purchases/preview', {'party_id': 5, 'discount': 999999, 'lines': [pl()]}); post('/purchases/preview', {'party_id': 5, 'round_off': 7, 'lines': [pl()]})
post('/purchases/preview', {'party_id': 5, 'lines': [pl(item_id=None)]}); post('/purchases/preview', {'party_id': 5, 'lines': [pl(rate='abc')]})
post('/purchases/preview', {'party_id': 5, 'printed_total': '4,600', 'cgst': '1,000.50', 'lines': [pl(amount='4,318.44')]})
post('/purchases', {'party_id': 5, 'supplier_invoice_no': 'GINV/1001/26-27', 'date': cur(9, 30), 'discount': '730.39', 'cgst': 590.4, 'sgst': '590.40', 'round_off': 0.39,
                    'printed_total': 24797, 'paid_amount': '1000', 'pay_mode': 'upi', 'source': 'PDF',
                    'lines': [pl(qty=3, rate=2159.22, amount=6477.66), pl(item_id=2, qty=4, rate=1057.38), pl(item_id=6, unit='PCS', qty=1000, rate=1.05, hsn='', exp_date=cur(12, 1), batch_no='SH-1', mrp=2)]})
post('/purchases', {'party_id': 5, 'supplier_invoice_no': 'ginv/1001/26-27', 'lines': [pl()]})
post('/purchases', {'party_id': 5, 'supplier_invoice_no': 'ginv/1001/26-27', 'allow_duplicate': True, 'date': cur(10, 2), 'lines': [pl(qty=1, item_id=5, unit='CASE', rate=1800)], 'update_cost': False})
post('/purchases', {'party_id': 6, 'supplier_invoice_no': '6157', 'date': cur(10, 21), 'igst': 1917.75, 'lines': [pl(item_id=3, unit='PCS', qty=240, rate=24.5), pl(item_id=4, unit='box', qty='2', rate=2000)], 'notes': 'IGST bill'})
post('/purchases', {'party_id': 6, 'date': prev(3, 10), 'lines': [pl(item_id=4, unit='PCS', qty=8, rate=500)]})
get('/purchases/1'); get('/purchases/3'); get('/purchases/77')
put('/purchases/2', {'party_id': 5, 'supplier_invoice_no': 'GINV/1001/26-27', 'allow_duplicate': 1, 'date': cur(10, 2), 'lines': [pl(qty=2, item_id=5, unit='CASE', rate=1750)], 'paid_amount': 500, 'pay_mode': 'CASH'})
put('/purchases/99', {'party_id': 5, 'lines': [pl()]})
get('/items')

# ---------------- billing
L = lambda item, **k: dict({'item_id': item}, **k)
post('/invoices/preview', {'lines': [L(3, boxes=2, pcs=6)]})
post('/invoices/preview', {'party_id': 3, 'lines': [L(1, boxes=1, pcs=0), L(2, qty=12), L(5, boxes='0', pcs='7', disc_pct='2.5')]})
post('/invoices/preview', {'party_id': 4, 'lines': [L(3, pcs=13), L(1, pcs=120)]})     # MRP tier, inter-state (IGST)
post('/invoices/preview', {'party_id': 1, 'lines': [L(1, boxes=1, rate='7.93650794'), L(4, pcs=1, rate=500, disc_pct=150)]})
post('/invoices/preview', {'lines': []}); post('/invoices/preview', {'party_id': 99, 'lines': [L(1, pcs=1)]}); post('/invoices/preview', {'lines': [L(99, pcs=1)]})
post('/invoices/preview', {'lines': [L(1, boxes=0, pcs=0)]}); post('/invoices/preview', {'date': '28-10-2026', 'lines': [L(1, pcs=1)]})
post('/invoices/preview', {'lines': [L(4, boxes=50)]})                                 # not enough stock
post('/invoices', {'pay_mode': 'cash', 'date': D3, 'lines': [L(3, boxes=2, pcs=6)]})
post('/invoices', {'party_id': 1, 'pay_mode': 'CREDIT', 'salesman_id': 1, 'sale_type': 'van', 'date': D3, 'lines': [L(1, boxes=1), L(6, pcs=50)]})
post('/invoices', {'party_id': 1, 'pay_mode': 'CREDIT', 'date': D2, 'lines': [L(4, boxes=8)]})      # exceeds the credit limit
post('/invoices', {'party_id': 1, 'pay_mode': 'CREDIT', 'date': D2, 'override_credit': True, 'lines': [L(4, pcs=3)], 'salesman_id': '1'})
post('/invoices', {'pay_mode': 'CREDIT', 'paid_amount': 10, 'lines': [L(2, pcs=5)]})                  # walk-in must pay in full
post('/invoices', {'party_id': 3, 'pay_mode': 'UPI', 'paid_amount': '5000', 'salesman_id': 2, 'date': D2, 'lines': [L(1, boxes=1, pcs=10), L(2, boxes=1), L(5, pcs=7, disc_pct=2.5)]})
post('/invoices', {'party_id': 4, 'pay_mode': 'CASH', 'date': D2, 'lines': [L(3, pcs=13)], 'paid_amount': 'abc'})
post('/invoices', {'party_id': 4, 'pay_mode': 'CARD', 'date': D2, 'lines': [L(3, pcs=13)]})
post('/invoices', {'party_id': 2, 'pay_mode': 'CREDIT', 'date': prev(3, 15), 'lines': [L(5, pcs=4)]})   # a bill in the previous financial year
post('/invoices', {'party_id': 2, 'pay_mode': 'CREDIT', 'date': cur(4, 1), 'lines': [L(2, pcs=1)]})
get('/invoices', {'date': D2}); get('/invoices/2'); get('/invoices/4'); get('/invoices/55')
put('/invoices/2', {'party_id': 1, 'pay_mode': 'CASH', 'paid_amount': 100, 'lines': [L(1, boxes=1, pcs=5), L(6, pcs=40, disc_pct=1)]})
put('/invoices/2', {'party_id': 1, 'pay_mode': 'CREDIT', 'lines': [L(4, boxes=99)]})   # refused: nothing changes
put('/invoices/88', {'lines': [L(1, pcs=1)]})
delete('/invoices/1'); delete('/invoices/1')
post('/invoices', {'pay_mode': 'CASH', 'date': D2, 'lines': [L(3, boxes=1)]})
delete('/purchases/1')                      # refused: its stock was already sold
get('/items')

# ---------------- print later
get('/bills', {'unprinted': '1'}); post('/invoices/printed', {'ids': [2, 4, 999]}); post('/invoices/printed', {'ids': []}); post('/invoices/printed', {'ids': [4], 'printed': False})
get('/bills', {'unprinted': '1', 'type': 'SALE'})

# ---------------- payments and ledgers
post('/vouchers', {'party_id': 1, 'amount': '1500.555', 'mode': 'upi', 'date': D2, 'reference': 'UTR 123', 'salesman_id': '1'})
post('/vouchers', {'party_id': 5, 'direction': 'paid', 'amount': 2500, 'mode': 'CHEQUE', 'date': D2, 'reference': ''})
post('/vouchers', {'party_id': 5, 'direction': 'SIDEWAYS', 'amount': 1}); post('/vouchers', {'party_id': 1, 'amount': 0}); post('/vouchers', {'party_id': 99, 'amount': 5})
post('/receipts', {'party_id': 3, 'amount': 1000})
get('/vouchers/RCT%2F' + f'{str(fy_start)[2:]}-{str(fy_start + 1)[2:]}' + '%2F00004'); get('/vouchers/PAY%2F' + f'{str(fy_start)[2:]}-{str(fy_start + 1)[2:]}' + '%2F00003'); get('/vouchers/NOPE')
get('/receipts', {'date': D2})
for pid in (1, 2, 3, 5, 6): get(f'/parties/{pid}/ledger')
get('/parties/2/ledger', {'fy': f'{fy_start - 1}-{str(fy_start)[2:]}'}); get('/parties/1/ledger', {'fy': '2026-28'}); get('/parties/1/ledger', {'fy': 'abc'}); get('/parties/77/ledger')

# ---------------- debit notes (goods returned to a supplier)
N = lambda item, **k: dict({'item_id': item}, **k)
post('/debit-notes/preview', {'party_id': 5, 'discount': 10, 'lines': [N(5, qty=1, unit='CASE', rate=1750), N(3, qty=12, rate=24.5)]})
post('/debit-notes/preview', {'party_id': 6, 'lines': [N(3, qty=10, rate='24.50', gst_rate=12)]})
post('/debit-notes/preview', {'lines': [N(3, qty=1, rate=1)]}); post('/debit-notes/preview', {'party_id': 5, 'lines': []})
post('/debit-notes/preview', {'party_id': 5, 'lines': [N(3, qty=1.5, rate=1)]}); post('/debit-notes/preview', {'party_id': 5, 'lines': [N(3, qty=1, rate=1, gst_rate=50)]})
post('/debit-notes/preview', {'party_id': 5, 'discount': 99999, 'lines': [N(3, qty=1, rate=1)]}); post('/debit-notes/preview', {'party_id': 99, 'lines': [N(3, qty=1)]})
post('/debit-notes/preview', {'party_id': 5, 'date': '28-10-2026', 'lines': [N(3, qty=1, rate=1)]}); post('/debit-notes/preview', {'party_id': 5, 'lines': [N(None, qty=1)]})
post('/debit-notes', {'party_id': 5, 'date': D2, 'purchase_id': 2, 'reason': '  Damaged   in transit ', 'lines': [N(5, qty=1, unit='CASE', rate=1750)]})
post('/debit-notes', {'party_id': 6, 'date': D2, 'against_bill': '6157', 'notes': 'short expiry', 'lines': [N(3, qty=20, rate=24.5), N(4, qty=1, unit='box', rate=2000)]})
post('/debit-notes', {'party_id': 6, 'date': D2, 'lines': [N(4, qty=999, unit='BOX', rate=1)]})    # more than the stock
post('/debit-notes', {'party_id': 5, 'date': D2, 'lines': [N(3, qty=1, rate=1, batch_id=9999)]})
post('/debit-notes', {'party_id': 5, 'date': D2, 'lines': [N(3, qty=1, rate=1, batch_id=1)]})
post('/debit-notes', {'party_id': 5, 'date': D2, 'purchase_id': 77, 'lines': [N(3, qty=1, rate=1)]})
get('/debit-notes'); get('/debit-notes', {'q': '6157'}); get('/debit-notes', {'party_id': '5'}); get('/debit-notes', {'from': D1, 'to': D2})
get('/debit-notes/1'); get('/debit-notes/2'); get('/debit-notes/9')
put('/debit-notes/2', {'party_id': 6, 'date': D2, 'against_bill': '6157', 'lines': [N(3, qty=5, rate=24.5)]})
put('/debit-notes/2', {'party_id': 6, 'lines': [N(3, qty=99999, rate=1)]})   # refused: nothing changes
post('/debit-notes', {'party_id': 5, 'date': D2, 'lines': [N(3, qty=2, rate=20)]})
delete('/debit-notes/3'); delete('/debit-notes/3'); put('/debit-notes/42', {'party_id': 5, 'lines': [N(3, qty=1)]})
get('/debit-notes/2'); get('/parties/6/ledger'); get('/parties/5/ledger'); get('/items')
get('/reports/book/debit')

# ---------------- salesmen screens
for d in ('0', '1', '3', '5', 'x'): get('/salesmen/1/beat', {'day': d})
get('/salesmen/2/beat', {'day': '1'}); get('/salesmen/1/performance'); get('/salesmen/2/performance', {'month': month, 'date': D2}); get('/salesmen/9/performance')

# ---------------- reports
get('/fy'); get('/reports/dashboard'); get('/reports/dashboard', {'fy': f'{fy_start - 1}-{str(fy_start)[2:]}'})
get('/reports/profit'); get('/reports/profit', {'from': D1, 'to': D2})
get('/reports/gst-outward'); get('/reports/gst-outward', {'month': month}); get('/reports/gst-outward', {'month': '2026-1'})
get('/reports/gst-outward.xlsx', {'month': month}, to=os.path.join(out_dir, 'gst-{engine}.xlsx'), loose=True)   # compression differs; contents compared part by part
get('/reports/book/sales'); get('/reports/book/purchase', {'from': cur(4, 1), 'to': D2}); get('/reports/book/other', {'from': '2000-01-01', 'to': '2100-01-01'})
get('/bills'); get('/bills', {'type': 'sale', 'unpaid': '1'}); get('/bills', {'type': 'PURCHASE', 'q': 'ginv'}); get('/bills', {'q': 'Gupta', 'from': D1, 'to': D2})
get('/bills', {'fy': f'{fy_start - 1}-{str(fy_start)[2:]}'}); get('/bills', {'type': 'debit_note'})
get('/reports/expiry'); get('/reports/expiry', {'days': '400'}); get('/reports/low-stock'); get('/reports/outstanding'); get('/reports/gst-summary', {'from': cur(4, 1), 'to': D2})
get('/reports/nothing')

# ---------------- deleting and archiving
delete('/items/2'); delete('/items/2', {'force': '1'}); delete('/items/8'); delete('/items/66')
delete('/parties/2'); delete('/parties/6'); post('/parties', {'name': 'Temp Party'}); delete('/parties/7'); delete('/parties/99')
delete('/routes/3'); get('/routes')
get('/items'); get('/parties')

# ---------------- tidy item names, merge duplicates, item lists from the internet
get('/items/clean-preview'); get('/items/clean-preview', {'case': 'title'}); get('/items/clean-preview', {'case': 'upper'})
post('/items', {'name': 'COLA 750 ML (1X24)', 'gst_rate': 18, 'mrp': 40}); post('/items', {'name': 'cola  750ml (1x24)', 'gst_rate': 12})
post('/items', {'name': 'Packaged water 1 ltr', 'gst_rate': 18}); post('/items', {'name': 'Bikano bhujia 200 gm', 'gst_rate': 12})
get('/items/clean-preview')
post('/batches', {'item_id': 11, 'qty': 24, 'batch_no': 'CL-1', 'exp_date': cur(11, 30)}); post('/batches', {'item_id': 11, 'qty': 48, 'batch_no': 'CL-NEW', 'exp_date': cur(12, 31)})
post('/invoices', {'pay_mode': 'cash', 'date': D2, 'lines': [L(11, pcs=6)]})
post('/items/merge', {}); post('/items/merge', {'keep_id': 3}); post('/items/merge', {'keep_id': 3, 'merge_ids': [99]}); post('/items/merge', {'keep_id': 'x', 'merge_ids': [11]})
post('/items/merge', {'keep_id': 3, 'merge_ids': [11, 3]}); post('/items/merge', {'keep_id': 3, 'merge_ids': [11]})
get('/items'); get('/items/3/batches'); get('/items/clean-preview', {'case': 'title'})
post('/items/clean-names', {'case': 'keep', 'ids': [12, 13]}); post('/items', {'name': 'Packaged water 1 L'}); post('/items/clean-names', {'case': 'title'}); get('/items')
PAGE = '''<html><head><title>Bikano Price List</title><style>td{color:red}</style><script>var t="<td>1 kg</td>";</script></head><body>
<h2>Bikano Namkeen &amp; Sweets &#8211; MRP List 2026</h2><!-- <td>Hidden 1 kg</td> -->
<table><tr><th>S.No</th><th>Product</th><th>Pack</th><th>MRP (&#8377;)</th></tr>
<tr><td>1</td><td>Bhujia</td><td>200 gm</td><td>&#8377; 50</td></tr>
<tr><td>2</td><td>BHUJIA 200GMS</td><td></td><td>Rs. 50/-</td></tr>
<tr><td>3</td><td>Aloo Bhujia 1 KG</td><td></td><td>240.00</td></tr>
<tr><td>4</td><td>Navratan Mix 400 g</td><td>1,250</td><td>110</td></tr></table>
<ul><li>12. Moong Dal 150g &amp; more - Rs 40</li><li>Kaju Katli 250 g MRP: 225</li><li>Gift Pack (Assorted)</li><li>Call us on 98765 43210</li></ul>
<p>Copyright &copy; 2026 Bikano. All rights reserved. www.bikano.com</p></body></html>'''
post('/items/online/search', {}); post('/items/online/search', {'company': 'Bikano', 'category': 'Namkeen'}); post('/items/online/fetch', {'url': 'ftp://x'}); post('/items/online/fetch', {'url': 'https://example.com/list.pdf'})
post('/items/online/extract', {'html': PAGE, 'company': 'Bikano'}); post('/items/online/extract', {'html': PAGE, 'case': 'upper'})
post('/items/online/extract', {'text': 'Cola 750ml (1X24) MRP 40\r\nTata Salt 1 Kg Rs 28\rMaggi 70 g\nprice list\n\nSurf Excel 1kg 120'}); post('/items/online/extract', {})
post('/items/bulk-add', {}); post('/items/bulk-add', {'items': [{'name': 'x'}], 'gst_rate': 50})
post('/items/bulk-add', {'category': ' Namkeen ', 'gst_rate': 12, 'items': [{'name': 'Bikano Bhujia 200g', 'mrp': 50}, {'name': 'Bikano Aloo Bhujia 1kg', 'mrp': '240'}, {'name': '  '}, {'name': 'Bikano Navratan Mix (1X24)', 'mrp': 'abc'}]})
get('/items'); get('/categories')

# ---------------- set prices from MRP (what you set is what a bill comes to)
post('/items', {'name': 'Price Box (1X12)', 'gst_rate': 18, 'mrp': 250}); post('/items', {'name': 'Price Single', 'gst_rate': 18, 'mrp': 3000})
post('/items', {'name': 'Price Nil GST', 'gst_rate': 0, 'mrp': 99}); post('/items', {'name': 'Price Small (1X10)', 'gst_rate': 5, 'mrp': 3})
for i in (17, 18, 19, 20): post('/batches', {'item_id': i, 'qty': 120})
get('/items/mrp-table'); get('/items/mrp-table', {'category_id': '1'})
post('/items/set-prices', {}); post('/items/set-prices', {'retail_off': 120}); post('/items/set-prices', {'mode': 'table', 'tiers': [{'mrp': 0, 'retail': 5}]})
post('/items/set-prices', {'mode': 'table', 'tiers': [{'mrp': 250, 'retail': 'x'}]}); post('/items/set-prices', {'mode': 'table', 'tiers': [{'mrp': 250}]})
post('/items/set-prices', {'retail_off': '16.67', 'wholesale_off': 20, 'preview': True})
post('/items/set-prices', {'retail_off': '16.67', 'round': '10', 'preview': True}); post('/items/set-prices', {'retail_off': 16.67, 'round': 'none', 'preview': True})
post('/items/set-prices', {'retail_off': 16.67, 'wholesale_off': '20'})
post('/invoices/preview', {'lines': [{'item_id': 17, 'boxes': 1}, {'item_id': 18, 'pcs': 1}, {'item_id': 19, 'pcs': 1}, {'item_id': 20, 'boxes': 2}]})
post('/items/set-prices', {'mode': 'table', 'per': 'box', 'include_gst': True, 'tiers': [{'mrp': 250, 'retail': '2,400', 'wholesale': 2300}, {'mrp': 3000, 'retail': 2450}, {'mrp': 77, 'retail': 1}]})
post('/items/set-prices', {'mode': 'table', 'per': 'piece', 'include_gst': False, 'item_ids': [19, 20], 'tiers': [{'mrp': 99, 'wholesale': 80}, {'mrp': 3, 'retail': 2.5}]})
post('/items/set-prices', {'mode': 'table', 'include_gst': 'false', 'tiers': [{'mrp': 3, 'wholesale': '2'}], 'category_id': 99})
get('/items/mrp-table')
put('/settings', {'bill_round': '0'}); post('/invoices/preview', {'lines': [{'item_id': 18, 'pcs': 1, 'disc_pct': 3}, {'item_id': 19, 'pcs': 1, 'disc_pct': 3.3}]})
post('/invoices', {'pay_mode': 'cash', 'date': D2, 'lines': [{'item_id': 19, 'pcs': 1, 'disc_pct': 3.3}]}); put('/settings', {'bill_round': '1'})
post('/items', {'name': 'No Wholesale Rate', 'gst_rate': 5, 'retail_price': 9.5, 'mrp': 12}); post('/batches', {'item_id': 21, 'qty': 50})
put('/parties/1', {'type': 'WHOLESALER', 'price_tier': 'WHOLESALE'}); post('/invoices/preview', {'party_id': 1, 'lines': [{'item_id': 21, 'pcs': 2}, {'item_id': 17, 'boxes': 1}]})
put('/parties/1', {'type': 'RETAILER', 'price_tier': 'RETAIL'}); post('/invoices/preview', {'party_id': 1, 'lines': [{'item_id': 21, 'pcs': 2}, {'item_id': 17, 'boxes': 1}]})

# ---------------- e-way bill (portal JSON for one bill, then the number the portal gives)
get('/invoices/2/ewaybill'); get('/invoices/999/ewaybill'); post('/invoices/1/ewaybill', {'distance': 10, 'vehicle_no': 'UP20AB1234'})
post('/invoices/2/ewaybill', {}); post('/invoices/2/ewaybill', {'from_pincode': '246701'}); post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246 701'})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': 'x'}); post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': 35.5})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': '35', 'mode': 'boat'})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': '35', 'mode': 'road'})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': 35, 'vehicle_no': 'UP-1'})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': 35, 'transporter_id': '123'})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': 35, 'mode': 3, 'vehicle_no': 'UP20AB1234'})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': 35, 'vehicle_no': 'up 20-ab 1234', 'trans_doc_date': '30/10/2026'})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': 35, 'vehicle_no': 'up 20-ab 1234', 'transporter_name': 'Shree "Ram" Roadways\nBijnor', 'preview': True})
put('/items/6', {'hsn': '3305'}); put('/items/1', {'hsn': '2106'})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': 35, 'vehicle_no': 'up 20-ab 1234', 'transporter_name': 'Shree "Ram" Roadways\nBijnor', 'preview': True})
post('/invoices/2/ewaybill', {'from_pincode': '246701', 'to_pincode': '246725', 'distance': 35, 'vehicle_no': 'up 20-ab 1234', 'transporter_name': 'Shree "Ram" Roadways\nBijnor'})
get('/invoices/2/ewaybill')
post('/invoices/2/ewaybill', {'distance': '0', 'mode': 'rail', 'transporter_id': '09AAACR1234A1Z5', 'vehicle_type': 'o'})
post('/invoices/2/ewaybill', {'distance': '0', 'mode': 'Rail', 'transporter_id': '09AAACR1234A1Z5', 'trans_doc_no': 'RR-55/2026-27-LONG-NUMBER', 'trans_doc_date': D2})
put('/invoices/2/ewaybill', {'ewb_no': '1234'}); put('/invoices/2/ewaybill', {'ewb_no': '3210 1234 5678', 'ewb_date': D2, 'ewb_valid': '2020-01-01'})
put('/invoices/2/ewaybill', {'ewb_no': '3210 1234 5678', 'ewb_date': '2026/10/30'}); put('/invoices/2/ewaybill', {'ewb_no': '3210 1234 5678', 'ewb_valid': cur(12, 31)})
get('/invoices/2/ewaybill'); get('/invoices/2'); post('/invoices/2/ewaybill', {'distance': 0, 'transporter_id': '09AAACR1234A1Z5'})
put('/invoices/2/ewaybill', {'ewb_no': '321012345679', 'ewb_date': D2}); put('/invoices/999/ewaybill', {}); put('/invoices/2/ewaybill', {'ewb_no': ''}); get('/invoices/2/ewaybill')
put('/settings', {'company_pincode': '246701'}); post('/invoices/3/ewaybill', {'to_pincode': '110006', 'distance': 180, 'vehicle_no': 'DL1LA0001'})

# ---------------- numbering and expiry-warning settings
put('/settings', {'num_INV_prefix': 'AKE', 'num_digits': '4'}); post('/invoices', {'pay_mode': 'cash', 'date': D2, 'lines': [{'item_id': 21, 'pcs': 1}]})
put('/settings', {'num_fy': '0', 'num_RCT_prefix': 'R-', 'num_INV_prefix': 'A'}); post('/receipts', {'party_id': 3, 'amount': 10, 'date': D2}); post('/invoices', {'pay_mode': 'cash', 'date': D2, 'lines': [{'item_id': 21, 'pcs': 1}]})
put('/settings', {'num_INV_prefix': '', 'num_fy': '1', 'num_digits': '9', 'num_RCT_prefix': ''}); post('/invoices', {'pay_mode': 'cash', 'date': D2, 'lines': [{'item_id': 21, 'pcs': 1}]})
# numbering: per-series digits, carrying on after the highest number used, setting the next number
get('/numbering'); get('/numbering', {'date': D2})
put('/settings', {'num_fy': '0', 'num_INV_prefix': 'A', 'num_INV_digits': '6', 'num_DN_prefix': 'DNB', 'num_DN_digits': '5'}); get('/numbering')
post('/invoices', {'pay_mode': 'cash', 'date': D2, 'lines': [{'item_id': 21, 'pcs': 1}]})
put('/numbering', {'series': 'INV', 'next': 50}); get('/numbering'); post('/invoices', {'pay_mode': 'cash', 'date': D2, 'lines': [{'item_id': 21, 'pcs': 1}]})
put('/numbering', {'series': 'INV', 'next': 3}); put('/numbering', {'series': 'INV', 'next': 'x'}); put('/numbering', {'series': 'INV', 'next': '12.5'})
put('/numbering', {'series': 'NOPE', 'next': 5}); put('/numbering', {'series': 'RCT', 'next': '900'}); post('/receipts', {'party_id': 3, 'amount': 10, 'date': D2})
put('/settings', {'num_fy': '1', 'num_INV_prefix': '', 'num_INV_digits': '', 'num_DN_prefix': '', 'num_DN_digits': ''}); get('/numbering')
put('/settings', {'num_digits': ''}); put('/settings', {'expiry_days': '400'}); get('/reports/dashboard'); put('/settings', {'expiry_days': '90'}); get('/reports/dashboard')

# ---------------- similar names (spelling, order, capitals, generic words) but never different packs or MRPs
for n, m in [('Bikano Bhujia 200g', 50), ('BIKANO BHUJIYA 200 GM', 50), ('Bikano Bujia 200gms', 50), ('Bikano Bhujia 400g', 90), ('Bikano Aloo Bhujia 200g', 50),
             ('Bhujia Bikano 200 g', 50), ('Bikano Bhujia 200 g.', 45), ('Parle G 100g', 10), ('Parle-G Biscuit 100g', 10), ('Tata Salt Lite 1kg', 28),
             ('Maggi Masala Noodles 70g (1X96)', 14), ('Maggi Noodles Masala 70 gm', 14), ('Maggi Masala 70g (1X48)', 14)]:
    post('/items', {'name': n, 'mrp': m})
get('/items/clean-preview', {'match': 'exact'}); get('/items/clean-preview'); get('/items/clean-preview', {'match': 'loose', 'case': 'title'}); get('/items/clean-preview', {'match': 'bad'})

# ---------------- payments from a photo of a handwritten sheet
SHEET = """1. Gupta Genral Store 1200, 850 - 2000
City Mart 5OO/-
Delhi Tradrs 1,200.50, 99 paid 1000
Singh Kirana: paid 700
Unknown Party 300
Traders 400

   
Rs 250
Gupta General Store\r
Gupta Store 120 = 0
City Mart Wholesale 1,20,000, 5,000 - 1,25,000
Traders 400
Gupta General Store, Rs. 1,200/- cash 1200"""
post('/receipts/sheet/parse', {'text': SHEET}); post('/receipts/sheet/parse', {}); post('/receipts/sheet/parse', {'text': 'x'})
post('/receipts/sheet', {'rows': []}); post('/receipts/sheet', {})
post('/receipts/sheet', {'date': D2, 'mode': 'upi', 'rows': [{'party_id': 1, 'amount': 2000, 'reference': 'Bills 1200, 850'}, {'party_id': 99, 'amount': 5}]})
post('/receipts/sheet', {'date': D2, 'rows': [{'party_id': 1, 'amount': 2000, 'reference': 'Bills 1200, 850'}, {'party_id': 3, 'amount': 500}, {'party_id': 4, 'amount': -1}]})
post('/receipts/sheet', {'date': D2, 'mode': 'UPI', 'rows': [{'party_id': 1, 'amount': 2000, 'reference': 'Bills 1200, 850'}, {'party_id': 3, 'amount': 500}]})
get('/parties'); get('/receipts', {'date': D2})

# ---------------- financial years as separate books
NY = f'{fy_start + 1}-{str(fy_start + 2)[2:]}'; PY = f'{fy_start - 1}-{str(fy_start)[2:]}'
post('/companies/1/years', {'fy': NY}); post('/companies/1/years', {'fy': NY}); post('/companies/1/years', {}); post('/companies/1/years', {'fy': '2030-35'})
post('/companies/1/years', {'fy': PY, 'carry': False}); post('/companies/77/years', {'fy': PY})
get('/companies'); get('/fy', company=3); get('/fy', company=4)
get('/parties', company=3); get('/items', company=3); get('/parties/1/ledger', company=3); get('/reports/dashboard', company=3); get('/bills', company=4)
put('/companies/1', {'name': 'AK  Enterprises'}); get('/companies')

# ---------------- second company is separate
get('/items', company=2); post('/items', {'name': 'Only In Second', 'gst_rate': 18}, company=2); get('/items', company=2); get('/fy', company=2)
put('/companies/2', {'company_gstin': '', 'invoice_terms': 'Updated'}); get('/companies')

# ---------------- bank details printed on the bill (made-up values)
put('/settings', {'bank_name': 'Example Bank', 'bank_ac_name': 'AK Enterprises', 'bank_ac_no': '000123456789', 'bank_ifsc': 'EXMP0001234',
                  'bank_branch': 'Main Bazar', 'bank_branch_code': '001234', 'bank_address': 'Main Bazar, Bijnor, Uttar Pradesh'}, company=1)

# ---------------- Google Drive backups (offline here: both engines answer the same)
get('/backup/drive'); post('/backup/drive/connect'); post('/backup/drive/poll'); post('/backup/drive/upload')
put('/backup/drive/client', {'client_id': 'abc', 'client_secret': 'x'}); put('/backup/drive/client', {'client_id': '1-a.apps.googleusercontent.com'})
put('/backup/drive/client', {'json': 'not json'}); put('/backup/drive/client', {'json': '{"web": {"client_id": "9-w.apps.googleusercontent.com", "client_secret": "w"}}'})
put('/backup/drive/client', {'json': '{"installed": {"client_id": "5-j.apps.googleusercontent.com"}}'})
put('/backup/drive/client', {'json': '{"installed": {"client_id": "5-j.apps.googleusercontent.com", "client_secret": "j", "project_id": "p"}}'})
put('/backup/drive/client', {'client_id': ' 1-a.apps.googleusercontent.com ', 'client_secret': ' s '})
post('/backup/drive/connect'); post('/backup/drive/upload'); post('/backup/drive/disconnect'); get('/backup/drive'); post('/backup/drive/nope')

# ---------------- Parties › Assign routes: customers without a route get the route named in their name or address
post('/routes', {'name': 'Kotdwar, Najibabad / Dhampur & A1', 'salesman_id': 1, 'days': '4'}, company=1)
for n, ad in [('Verma Store', 'Near railway station, Bijnor'), ('Civil Lines Medical', ''), ('Stationwala Kirana', 'Main bazaar'),
              ('Nagina Road Agency', 'Nagina Road, near Civil Lines'), ('Patel Medical', 'Opp. Civil Hospital'), ('Yadav Dairy', 'Station Road 12'),
              ('Kotdwar Traders', 'Kotdwar'), ('Sharma Agency', 'Station Road, Dhampur'), ('No Match Traders', 'Haridwar')]:
    post('/parties', {'name': n, 'address': ad}, company=1)
post('/routes/auto-assign', {}, company=1); post('/routes/auto-assign', {'apply': False}, company=1)
post('/routes/auto-assign', {'apply': True, 'party_ids': [0]}, company=1); post('/routes/auto-assign', {'apply': True}, company=1)
get('/parties', {'kind': 'CUSTOMER'}, company=1); get('/routes', company=1)

# ---------------- deleting a company (a throwaway one, so the books above stay for the backup tests)
post('/companies', {'name': 'Temp Traders'}); get('/companies')
post('/companies/5/delete', {}); post('/companies/5/delete', {'confirm': 'Wrong Name'}); post('/companies/99/delete', {'confirm': 'x'})
post('/companies/5/activate'); post('/companies/5/delete', {'confirm': ' temp traders '})
get('/companies'); post('/companies/5/activate'); get('/fy', company=5); post('/companies/5/delete', {'confirm': 'Temp Traders'})
dump()
json.dump(S, open(os.path.join(out_dir, 'scenario.json'), 'w'), indent=1)
print(len(S), 'steps')
