const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;

/** Split GST on a taxable value. intra=true -> CGST+SGST (half each), else IGST. */
function splitTax(taxable, rate, intra) {
  const tax = r2((taxable * rate) / 100);
  if (intra) {
    const c = r2(tax / 2);
    return { cgst: c, sgst: r2(tax - c), igst: 0 };
  }
  return { cgst: 0, sgst: 0, igst: tax };
}

module.exports = { r2, splitTax };
