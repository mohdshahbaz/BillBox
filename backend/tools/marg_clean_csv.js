#!/usr/bin/env node
// Writes the cleaned Marg data as plain CSV files (items, parties, bills, bill_rows, money) plus checks.txt:
//   node tools/marg_clean_csv.js <Marg CSV backup .zip or folder> <output folder>
const fs = require('fs'), path = require('path');
const { cleanTables } = require('../src/services/margImport');
const [src, out] = process.argv.slice(2).map((p) => p && path.resolve(p));
if (!src || !out) { console.error('usage: node tools/marg_clean_csv.js <backup.zip|folder> <output folder>'); process.exit(1); }
const t = cleanTables(src);
fs.mkdirSync(out, { recursive: true });
const cell = (v) => { const s = String(v ?? ''); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
for (const k of ['items', 'parties', 'bills', 'bill_rows', 'money']) {
  const rows = t[k];
  const cols = rows.length ? Object.keys(rows[0]) : [];
  fs.writeFileSync(path.join(out, k + '.csv'), '﻿' + [cols.join(','), ...rows.map((r) => cols.map((c) => cell(r[c])).join(','))].join('\r\n') + '\r\n');
}
const s = t.summary, c = s.checks;
fs.writeFileSync(path.join(out, 'checks.txt'), [
  `Period: ${s.period ? s.period.from + ' to ' + s.period.to : '-'}`,
  `Found: ${JSON.stringify(s.found)}`, `Totals: ${JSON.stringify(s.totals)}`,
  `Bill totals: ${c.bills.ok} of ${c.bills.checked} match`, ...c.bills.problems,
  `Party closing balances: ${c.party_balances.ok} of ${c.party_balances.checked} match`, ...c.party_balances.problems,
  `Item closing stock: ${c.stock.ok} of ${c.stock.checked} match`, ...c.stock.problems,
  '', 'Cleaned up:', ...s.cleaning, ...s.warnings, ''].join('\n'));
console.log(`Written to ${out}`);
