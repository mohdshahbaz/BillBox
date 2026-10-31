// Line-for-line JavaScript copy of macos/Sources/DistributorPro/BillMath.swift (same operations in the same order).
const r2 = (x) => Math.floor((x + Number.EPSILON) * 100 + 0.5) / 100;
const totalPcs = (boxes, ppb, pcs) => Math.max(0, boxes) * Math.max(1, ppb) + Math.max(0, pcs);
function line(i, intra) {
  const r = { totalPcs: totalPcs(i.boxes, i.ppb, i.pcs), cgst: 0, sgst: 0, igst: 0 };
  r.rate = i.typedRate !== undefined && i.typedRate !== null ? i.typedRate : i.listRate;
  const pct = Math.min(100, Math.max(0, i.discPct));
  r.gross = r2(r.rate * r.totalPcs);
  r.discount = r2((r.gross * pct) / 100);
  r.taxable = r2(r.gross - r.discount);
  const tax = r2((r.taxable * i.gstRate) / 100);
  if (intra) { r.cgst = r2(tax / 2); r.sgst = r2(tax - r.cgst); } else { r.igst = tax; }
  r.amount = r2(r.taxable + r.cgst + r.sgst + r.igst);
  return r;
}
function compute(inputs, intra) {
  const o = { lines: [], pieces: 0, subtotal: 0, discount: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0 };
  for (const i of inputs) {
    const l = line(i, intra); o.lines.push(l); o.pieces += l.totalPcs;
    o.subtotal += l.gross; o.discount += l.discount; o.taxable += l.taxable; o.cgst += l.cgst; o.sgst += l.sgst; o.igst += l.igst;
  }
  for (const k of ['subtotal', 'discount', 'taxable', 'cgst', 'sgst', 'igst']) o[k] = r2(o[k]);
  const grand = r2(o.taxable + o.cgst + o.sgst + o.igst);
  o.total = Math.floor(grand + 0.5);
  o.roundOff = r2(o.total - grand);
  return o;
}
module.exports = { r2, totalPcs, line, compute };
