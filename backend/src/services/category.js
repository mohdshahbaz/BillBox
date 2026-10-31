/**
 * Works out an item's category from its name.
 *   1. keyword rules (instant, works offline, tuned for Indian FMCG names)
 *   2. when no rule fits: the free Open Food Facts product database on the internet (4 second limit, never blocks saving)
 * Results are remembered per brand + product words while the server runs.
 */
const db = require('../db');

const RULES = [
  ['Namkeen & Snacks', /\b(all\s*time\s*mix|bikano|namkeen|bhujia|mixture|mixt|chips|wafer|papad|kurkure|puffs?|chakli|sev|moong\s*dal|peanut|katori|ringz?|cheese\s*ball|munchy|crunchy|nachos|popcorn|chivda|aloo|khatta\s*meetha|lachha|navratan|tadka|chatax|snack)/i],
  ['Biscuits & Cookies', /\b(biscuit|cookie|cracker|rusk|marie|glucose|bourbon|cream\s*roll)/i],
  ['Noodles & Pasta', /\b(noodle|maggi|pasta|macaroni|vermicelli|yippee|chowmein)/i],
  ['Beverages', /\b(cola|pepsi|coke|soda|juice|drink|water|lemonade|energy|squash|sharbat|tea|coffee|frooti|maaza|slice|sprite|fanta|thums)/i],
  ['Dairy', /\b(milk|curd|dahi|paneer|butter|cheese|ghee|cream|lassi|buttermilk)/i],
  ['Chocolates & Confectionery', /\b(chocolate|candy|toffee|lollipop|gum|mint|eclairs?|jelly|cadbury|dairy\s*milk|kitkat)/i],
  ['Staples & Grains', /\b(rice|atta|flour|maida|suji|rava|dal\b|pulses?|poha|besan|sugar|salt|wheat|oats|cornflakes?|muesli)/i],
  ['Oils & Ghee', /\b(oil|refined|mustard\s*oil|sunflower|vanaspati)/i],
  ['Spices & Masala', /\b(masala|spice|turmeric|haldi|chilli|mirch|jeera|coriander|dhaniya|garam)/i],
  ['Sauces & Spreads', /\b(ketchup|sauce|jam|mayonnaise|spread|pickle|achar|vinegar|chutney)/i],
  ['Personal Care', /\b(soap|shampoo|toothpaste|toothbrush|face\s*wash|cream|lotion|deodorant|deo|talc|powder|hair|razor|sanitary|napkin|facewash|oil\s*hair|conditioner|handwash)/i],
  ['Home Care', /\b(detergent|dishwash|cleaner|phenyl|bleach|harpic|vim|surf|ariel|rin\b|wheel|floor|toilet|mop|scrub|freshener|agarbatti|incense|mosquito|coil)/i],
  ['Stationery & General', /\b(pen|pencil|notebook|battery|bulb|candle|match)/i],
];

/** Items that must always sit in a given category, whatever else their name matches. */
const PINNED = [
  [/all\s*time\s*mix/i, 'Namkeen & Snacks'],
];
function pinned(name) { for (const [re, cat] of PINNED) if (re.test(name || '')) return cat; return null; }

const cache = new Map();

/** Remove size, MRP, bracket and punctuation noise: "BIKANO CHIPS (1X144 PKT) MRP-10/-" -> "bikano chips" */
function cleanQuery(name) {
  return String(name || '').replace(/\(.*?\)/g, ' ').replace(/\bMRP\b.*$/i, ' ').replace(/\d+\s*[xX*]\s*\d+/g, ' ').replace(/\b\d+(\.\d+)?\s*(g|gm|kg|ml|ltr|l|pkt|pcs)\b/gi, ' ')
    .replace(/[^A-Za-z ]+/g, ' ').replace(/\s+/g, ' ').trim().toLowerCase();
}

function byRules(text) {
  for (const [cat, re] of RULES) if (re.test(text)) return cat;
  return null;
}

async function fromInternet(query) {
  if (!query || typeof fetch !== 'function') return null;
  try {
    const url = 'https://world.openfoodfacts.org/cgi/search.pl?search_simple=1&action=process&json=1&page_size=6&fields=product_name,categories&search_terms=' + encodeURIComponent(query);
    const r = await fetch(url, { signal: AbortSignal.timeout(4000), headers: { 'User-Agent': 'DistributorPro/3 (local desktop app)' } });
    if (!r.ok) return null;
    const j = await r.json();
    const cats = (j.products || []).map((p) => String(p.categories || '')).filter(Boolean);
    if (!cats.length) return null;
    for (const c of cats) { const m = byRules(c); if (m) return m; }                 // map the database's wording to our category names
    const first = cats[0].split(',').map((x) => x.trim()).filter(Boolean)[0];
    return first ? first.replace(/^[a-z]{2}:/i, '').slice(0, 40) : null;
  } catch (_) { return null; }                                                       // offline or slow: just no suggestion
}

/** -> { name, source: 'rules' | 'internet' } or { name: null } */
async function guessCategory(itemName, { online = true } = {}) {
  const pin = pinned(itemName);
  if (pin) return { name: pin, source: 'rules' };
  const q = cleanQuery(itemName);
  const key = q.split(' ').slice(0, 3).join(' ');
  if (cache.has(key)) return cache.get(key);
  let out = { name: byRules(itemName) || byRules(q), source: 'rules' };
  if (!out.name && online) { const n = await fromInternet(q); out = n ? { name: n, source: 'internet' } : { name: null }; }
  if (!out.name) out = { name: null };
  if (out.name) cache.set(key, out);
  return out;
}

/** Existing category with that name (any case), or a new one. Returns its id. */
function ensureCategory(name) {
  if (!name) return null;
  const row = db.prepare('SELECT id FROM categories WHERE lower(name)=lower(?)').get(name);
  if (row) return row.id;
  return Number(db.prepare('INSERT INTO categories(name) VALUES(?)').run(name).lastInsertRowid);
}

module.exports = { pinned, guessCategory, ensureCategory, cleanQuery, byRules };
