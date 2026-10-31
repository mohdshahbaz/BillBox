#!/usr/bin/env python3
"""Marg ERP import: the real FY 2026-27 CSV backup (zip and unzipped folder), checks, a second import that adds nothing, refusals."""
import json, os, sys, zipfile
out = sys.argv[1]
ZIP = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../../backend/test/fixtures/private/marg_csv_backup_2026-27.zip'))
if not os.path.exists(ZIP):   # the real Marg backup is kept off GitHub
    print('skip: private Marg backup not present'); sys.exit(3)
folder = os.path.join(out, 'marg-folder')
os.makedirs(folder, exist_ok=True)
zipfile.ZipFile(ZIP).extractall(folder)
empty = os.path.join(out, 'marg-empty'); os.makedirs(empty, exist_ok=True)
S = []
post = lambda p, b: S.append({'method': 'POST', 'path': p, 'body': b})
get = lambda p, q=None: S.append({'method': 'GET', 'path': p, 'query': q or {}})
post('/import/marg/preview', {'path': ZIP})
post('/import/marg/preview', {'path': '/no/such/backup'}); post('/import/marg/preview', {'path': empty}); post('/import/marg/preview', {})
post('/import/marg', {'path': ZIP})
post('/import/marg', {'path': folder})
post('/import/marg/preview', {'path': folder})
# new bills carry on Marg's numbering
get('/numbering'); get('/settings')
post('/invoices', {'pay_mode': 'cash', 'date': '2026-10-25', 'lines': [{'item_id': 1, 'pcs': 1}]}); get('/numbering')
get('/items'); get('/parties'); get('/bills', {'fy': '2026-27', 'q': 'P0000'}); get('/debit-notes', {'fy': '2026-27'})
get('/reports/gst-outward', {'month': '2026-05', 'fy': '2026-27'}); get('/reports/dashboard', {'fy': '2026-27'})
get('/parties/1/ledger', {'fy': '2026-27'})
# correcting prices of items already here: nothing to do right after an import; a price worked out per box is put back
post('/import/marg/prices', {'path': ZIP})
S.append({'method': 'PUT', 'path': '/items/1', 'body': {'retail_price': 0.0316, 'wholesale_price': 0.0316}})
S.append({'method': 'PUT', 'path': '/items/2', 'body': {'retail_price': 1}})
post('/import/marg/prices', {'path': ZIP}); post('/import/marg/prices', {'path': ZIP, 'apply': True}); post('/import/marg/prices', {'path': ZIP})
post('/import/marg/prices', {'path': '/no/such/backup'})
# one year's books take only that year's Marg data
post('/companies', {'name': 'Marg Books'})
post('/companies/2/years', {'fy': '2025-26', 'carry': False}); post('/companies/2/years', {'fy': '2026-27', 'carry': False})
S.append({'method': 'POST', 'path': '/import/marg/preview', 'body': {'path': ZIP}, 'company': 3})
S.append({'method': 'POST', 'path': '/import/marg', 'body': {'path': ZIP}, 'company': 4})
S.append({'method': 'GET', 'path': '/fy', 'company': 4})
S.append({'op': 'dump'})
json.dump(S, open(os.path.join(out, 'marg.json'), 'w'), indent=1)
print(len(S), 'steps')
