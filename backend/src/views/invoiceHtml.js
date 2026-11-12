const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => Number(n).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const { words } = require('../utils/words');

function invoiceHtml(inv, co) {
  const intra = inv.igst === 0;
  const byRate = {};
  for (const l of inv.lines) {
    const g = (byRate[l.gst_rate] ||= { taxable: 0, cgst: 0, sgst: 0, igst: 0 });
    g.taxable += l.taxable; g.cgst += l.cgst; g.sgst += l.sgst; g.igst += l.igst;
  }
  const lines = inv.lines.map((l, i) => `
    <tr><td>${i + 1}</td><td>${esc(l.item_name)}<br><small>Batch ${esc(l.batch_no)} · Exp ${esc(l.exp_date)}</small></td>
    <td>${esc(l.hsn)}</td><td class="r">${l.qty}${l.free_qty ? ` + ${l.free_qty} free` : ''}</td>
    <td class="r">${money(l.mrp)}</td><td class="r">${money(l.rate)}</td><td class="r">${l.disc_pct ? l.disc_pct + '%' : ''}</td>
    <td class="r">${money(l.taxable)}</td><td class="r">${l.gst_rate}%</td><td class="r">${money(l.amount)}</td></tr>`).join('');
  const taxRows = Object.entries(byRate).map(([rate, g]) => `
    <tr><td>${rate}%</td><td class="r">${money(g.taxable)}</td>
    ${intra ? `<td class="r">${money(g.cgst)}</td><td class="r">${money(g.sgst)}</td>` : `<td class="r">${money(g.igst)}</td>`}</tr>`).join('');
  const due = Math.round((inv.total - inv.paid) * 100) / 100;

  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(inv.invoice_no)}</title>
<style>
  body{font:12px -apple-system,Helvetica,Arial,sans-serif;color:#1b2a2f;margin:24px}
  h1{font-size:18px;margin:0} table{width:100%;border-collapse:collapse;margin-top:10px}
  th,td{border:1px solid #9aa8aa;padding:4px 6px;vertical-align:top} th{background:#eef2f0}
  .r{text-align:right;font-variant-numeric:tabular-nums} .head{display:flex;justify-content:space-between;gap:24px}
  .box{border:1px solid #9aa8aa;padding:8px;flex:1} small{color:#556} .tot td{font-weight:600}
  @media print{body{margin:8mm}.noprint{display:none}}
</style></head><body>
<button class="noprint" onclick="window.print()">Print</button>
<div class="head">
  <div class="box"><h1>${esc(co.company_name)}</h1>${esc(co.company_address)}<br>GSTIN: ${esc(co.company_gstin)} · State code ${esc(co.state_code)}<br>${esc(co.company_phone)}</div>
  <div class="box"><b>TAX INVOICE</b><br>No: ${esc(inv.invoice_no)}<br>Date: ${esc(inv.date)}<br>Payment: ${esc(inv.pay_mode)}<br>Salesman: ${esc(inv.salesman_name || '-')}</div>
</div>
<div class="box" style="margin-top:10px"><b>Bill to:</b> ${esc(inv.party_name || 'Cash customer')}<br>${esc(inv.party_address || '')}<br>
${inv.party_gstin ? 'GSTIN: ' + esc(inv.party_gstin) + ' · ' : ''}${inv.party_state ? 'State code ' + esc(inv.party_state) : ''}${inv.party_pan ? ' · PAN: ' + esc(inv.party_pan) : ''}
${(() => { const ph = [...new Set([inv.party_phone, ...String(inv.party_mobiles || '').split(/[,;\/]/)].map((x) => String(x || '').trim()).filter(Boolean))];
  const bits = [ph.length ? 'Ph: ' + esc(ph.join(', ')) : '', inv.party_tel ? 'Tel: ' + esc(inv.party_tel) : '', inv.party_email ? 'Email: ' + esc(inv.party_email) : '', inv.party_fssai ? 'FSSAI: ' + esc(inv.party_fssai) : ''].filter(Boolean);
  return bits.length ? '<br>' + bits.join(' · ') : ''; })()}
${intra ? '<br><small>Intra-state supply: CGST + SGST</small>' : '<br><small>Inter-state supply: IGST</small>'}</div>
<table><tr><th>#</th><th>Item</th><th>HSN</th><th>Qty</th><th>MRP</th><th>Rate</th><th>Disc</th><th>Taxable</th><th>GST</th><th>Amount</th></tr>${lines}</table>
<div class="head"><table style="flex:1"><tr><th>GST rate</th><th>Taxable</th>${intra ? '<th>CGST</th><th>SGST</th>' : '<th>IGST</th>'}</tr>${taxRows}</table>
<table style="flex:1" class="tot"><tr><td>Items total</td><td class="r">${money(inv.subtotal)}</td></tr>
<tr><td>Discount</td><td class="r">- ${money(inv.discount)}</td></tr><tr><td>Taxable value</td><td class="r">${money(inv.taxable)}</td></tr>
${intra ? `<tr><td>CGST</td><td class="r">${money(inv.cgst)}</td></tr><tr><td>SGST</td><td class="r">${money(inv.sgst)}</td></tr>` : `<tr><td>IGST</td><td class="r">${money(inv.igst)}</td></tr>`}
<tr><td>Invoice total</td><td class="r">₹ ${money(inv.total)}</td></tr>
<tr><td>Paid</td><td class="r">${money(inv.paid)}</td></tr><tr><td>Balance due on this bill</td><td class="r">${money(due)}</td></tr></table></div>
<p><b>Amount in words:</b> Rupees ${words(Math.round(inv.total))} Only</p>
<p><small>${esc(co.invoice_terms)}</small></p>
<p style="text-align:right;margin-top:40px">For ${esc(co.company_name)}<br><br>Authorised signatory</p>
<script>if(location.search.includes('autoprint'))window.addEventListener('load',()=>setTimeout(()=>window.print(),200));</script>
</body></html>`;
}

module.exports = { invoiceHtml };
