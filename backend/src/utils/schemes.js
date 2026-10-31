/**
 * Scheme engine. For one item line it picks the best active scheme of each kind:
 *  - FREE_QTY : "Buy X get Y free" -> floor(qty / X) * Y free units
 *  - PERCENT  : percentage discount once qty >= minimum qty
 * Both kinds can apply together. Free units are physical stock and come out of batches.
 */
function applySchemes(qty, schemes) {
  let freeQty = 0;
  let discPct = 0;
  const applied = [];
  for (const s of schemes) {
    if (s.type === 'FREE_QTY' && s.buy_qty > 0 && qty >= s.buy_qty) {
      const f = Math.floor(qty / s.buy_qty) * s.free_qty;
      if (f > freeQty) { freeQty = f; applied.push(`Buy ${s.buy_qty} get ${s.free_qty} free`); }
    } else if (s.type === 'PERCENT' && qty >= s.buy_qty && s.percent > discPct) {
      discPct = s.percent;
      applied.push(`${s.percent}% off on ${s.buy_qty}+`);
    }
  }
  return { freeQty, discPct, applied };
}

module.exports = { applySchemes };
