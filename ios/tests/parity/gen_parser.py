#!/usr/bin/env python3
"""Parser scenario: every fixture bill, read alone and against a company's stock list, then auto-created (offline)."""
import json, os, sys, re
F = os.path.join(os.path.dirname(__file__), '../../../backend/test/fixtures/private')   # real supplier bills, kept off GitHub
out = sys.argv[1]
def txt(name): return open(os.path.join(F, name)).read().split('\f')
def pages(name): return json.load(open(os.path.join(F, name)))
PRIVATE = os.path.exists(os.path.join(F, 'supplier_a_0485.txt'))
bills = {'supplier_a_0485_txt': [p for i, p in enumerate(txt('supplier_a_0485.txt')) if not (i == len(txt('supplier_a_0485.txt')) - 1 and not p.strip())],
         'supplier_b_5531': txt('supplier_b_5531.txt'), 'supplier_b_6157': pages('supplier_b_6157.pages.json'),
         'supplier_a_0485_pdf': pages('supplier_a_0485.pages.json'), 'supplier_a_0486_pdf': pages('supplier_a_0486.pages.json')} if PRIVATE else {}
# inline bills of the Mac test suite (two Original pages + two Duplicate pages, a label/value split, odd layouts)
smoke = open(os.path.normpath(os.path.join(F, '../../smoke.js'))).read()
S = []
# your own company (the buyer on the bills): its GSTIN is in the private folder; a made-up one stands in without it
GSTIN = json.load(open(os.path.join(F, 'parser_ctx.json')))['companyGstin'] if PRIVATE else '09AAACA0000A1Z5'
ctx = {'companyGstin': GSTIN, 'companyName': 'AK ENTERPRISES'}
for name, pg in bills.items():
    S.append({'op': 'parse', 'pages': pg, 'ctx': ctx, 'note': name})
# odd inputs
S.append({'op': 'parse', 'pages': [], 'ctx': {}})
S.append({'op': 'parse', 'pages': ['', ' \n '], 'ctx': {}})
S.append({'op': 'parse', 'pages': ['DUPLICATE COPY\nSome Traders Pvt Ltd\nInvoice No: AB-12 Date: 3 Sept 2026\nS.No Description Qty Rate Amount\n1 Widget 2 10.00 20.00\nGrand Total 20.00'], 'ctx': {}})
S.append({'op': 'parse', 'pages': ['Bharat Agencies\nGSTIN 09AAACB1234C1Z5 Mob: 098765-43210 and 9123456789 Ph: 0121-2456789\nBill No. 77 Dated 05.11.26\nParticulars HSN Qty Unit Rate Amount\nTea 500g (1X24) 0902 3 BOX 1200 3600\nParle G Rs.5 1905 10PCS 4.5 45\nLess : Discount 45.00\nAdd : CGST @ 2.50 % 90.00\nAdd : SGST @ 2.50 % 90.00\nRound off (-) 0.00\nNet Amount 3780.00'], 'ctx': {'companyGstin': '', 'companyName': ''}})
# supplier blocks with contact details on the name / address lines, a PIN on its own line, the invoice row before the GSTIN
for hdr in [
    'TAX INVOICE\nSHARMA AGENCIES  Email: sharma@gmail.com  Mob: 9876543210\n12, Main Road, Bijnor Tel: 01342-262626\n246701\nGSTIN: 09ABCDE1234F1Z5\nBill To\nAK ENTERPRISES',
    'M/s. Gupta Brothers Ph. 0121-2456789 / 9811122233\nAddress: Shop 4, Sadar Bazar, Meerut\nInvoice No. Invoice Date\n55 01/10/2026\nGSTIN 09AAAPG1234K1Z2 Mobile 9811122233 Email gupta.bros@yahoo.co.in\nwww.guptabros.in\nBILL TO\nAK ENTERPRISES',
    'Shree Ganesh\nNEW KRISHNA STORE E-mail : nks@x.com, Contact 9412345678\nG.T. Road, Moradabad State Code: 09\nCIN: U12345UP2020PTC123456\nBuyer: AK ENTERPRISES',
    'Original Copy\nfrom : Balaji Foods & Co. tel 05842 222333\nNear Bus Stand\nKiratpur\n246731\nFSSAI 12345678901234\nParty Details :',
]:
    S.append({'op': 'parse', 'pages': [hdr + '\nS.No Description Qty Rate Amount\n1 Widget 2 10.00 20.00\nGrand Total 20.00'], 'ctx': ctx})
# against a company's stock: set the company up, then parse + auto-create
setup = [
    {'method': 'PUT', 'path': '/companies/1', 'body': {'name': 'AK ENTERPRISES', 'company_gstin': GSTIN, 'state_code': '09'}},
    {'method': 'POST', 'path': '/items', 'body': {'name': 'BIKANO CHIPS (1X144 PKT) MRP-10/-', 'hsn': '2106909', 'gst_rate': 5}},
    {'method': 'POST', 'path': '/items', 'body': {'name': 'BIKANO BHUJIA (1X300 PKT) MRP-5/-', 'hsn': '2106909', 'gst_rate': 5}},
]
# the real supplier, already in the books (private: real business data)
if PRIVATE: setup += json.load(open(os.path.join(F, 'parser_setup.json')))
S += setup
for name in ('supplier_a_0485_pdf', 'supplier_a_0486_pdf', 'supplier_b_6157', 'supplier_b_5531') if PRIVATE else ():
    S.append({'op': 'autocreate', 'pages': bills[name], 'note': name})
S.append({'method': 'GET', 'path': '/items'}); S.append({'method': 'GET', 'path': '/parties', 'query': {'kind': 'SUPPLIER'}}); S.append({'op': 'dump'})
json.dump(S, open(os.path.join(out, 'parser.json'), 'w'), indent=1)
print(len(S), 'steps')
