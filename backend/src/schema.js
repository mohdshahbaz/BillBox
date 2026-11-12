// Per-company schema. Safe to run on every open: creates missing tables, adds missing columns.
const BASE = `
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS counters (key TEXT PRIMARY KEY, value INTEGER NOT NULL DEFAULT 0);

CREATE TABLE IF NOT EXISTS categories (
  id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS items (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  category_id INTEGER REFERENCES categories(id),
  hsn TEXT,
  gst_rate REAL NOT NULL DEFAULT 18,
  unit TEXT DEFAULT 'PCS',
  mrp REAL NOT NULL DEFAULT 0,              -- GST-inclusive, printed on pack
  retail_price REAL NOT NULL DEFAULT 0,     -- ex-GST selling rate
  wholesale_price REAL NOT NULL DEFAULT 0,  -- ex-GST selling rate
  purchase_price REAL NOT NULL DEFAULT 0,   -- ex-GST landing cost
  pcs_per_box INTEGER NOT NULL DEFAULT 1,   -- dual-unit billing: pieces in one box
  active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS batches (
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_no TEXT NOT NULL,
  mfg_date TEXT,
  exp_date TEXT NOT NULL,
  qty INTEGER NOT NULL DEFAULT 0,
  purchase_price REAL,
  mrp REAL,
  UNIQUE(item_id, batch_no)
);
CREATE INDEX IF NOT EXISTS idx_batches_fefo ON batches(item_id, exp_date);

CREATE TABLE IF NOT EXISTS schemes (
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL REFERENCES items(id),
  type TEXT NOT NULL CHECK (type IN ('FREE_QTY','PERCENT')),
  buy_qty INTEGER NOT NULL,        -- FREE_QTY: buy X ; PERCENT: minimum qty
  free_qty INTEGER DEFAULT 0,      -- FREE_QTY: get Y free
  percent REAL DEFAULT 0,          -- PERCENT: discount %
  valid_from TEXT, valid_to TEXT,
  active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS salesmen (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, phone TEXT,
  monthly_target REAL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS routes (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL,
  salesman_id INTEGER REFERENCES salesmen(id),
  day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6)  -- 0 = Sunday
);

CREATE TABLE IF NOT EXISTS parties (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL, gstin TEXT, state_code TEXT, phone TEXT, address TEXT,
  type TEXT NOT NULL DEFAULT 'RETAILER',
  price_tier TEXT NOT NULL DEFAULT 'RETAIL' CHECK (price_tier IN ('WHOLESALE','RETAIL','MRP')),
  credit_limit REAL NOT NULL DEFAULT 0,
  credit_days INTEGER NOT NULL DEFAULT 0,
  route_id INTEGER REFERENCES routes(id),
  active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS invoices (
  id INTEGER PRIMARY KEY,
  invoice_no TEXT UNIQUE NOT NULL,
  date TEXT NOT NULL,
  party_id INTEGER REFERENCES parties(id),
  salesman_id INTEGER REFERENCES salesmen(id),
  sale_type TEXT NOT NULL DEFAULT 'COUNTER',
  pay_mode TEXT NOT NULL DEFAULT 'CASH',
  subtotal REAL, discount REAL, taxable REAL,
  cgst REAL, sgst REAL, igst REAL, round_off REAL,
  total REAL NOT NULL, paid REAL NOT NULL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_inv_date ON invoices(date);
CREATE INDEX IF NOT EXISTS idx_inv_sm ON invoices(salesman_id, date);

CREATE TABLE IF NOT EXISTS invoice_lines (
  id INTEGER PRIMARY KEY,
  invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  qty INTEGER NOT NULL, free_qty INTEGER NOT NULL DEFAULT 0,
  rate REAL NOT NULL, disc_pct REAL NOT NULL DEFAULT 0, disc_amt REAL NOT NULL DEFAULT 0,
  taxable REAL NOT NULL, gst_rate REAL NOT NULL,
  cgst REAL NOT NULL, sgst REAL NOT NULL, igst REAL NOT NULL, amount REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS receipts (
  id INTEGER PRIMARY KEY,
  receipt_no TEXT UNIQUE NOT NULL,
  date TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  salesman_id INTEGER REFERENCES salesmen(id),
  invoice_id INTEGER REFERENCES invoices(id),
  mode TEXT NOT NULL DEFAULT 'CASH',
  amount REAL NOT NULL, reference TEXT
);

-- Party ledger: balance = SUM(debit) - SUM(credit)  (positive = party owes us)
CREATE TABLE IF NOT EXISTS ledger (
  id INTEGER PRIMARY KEY,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  date TEXT NOT NULL,
  type TEXT NOT NULL,   -- OPENING | INVOICE | RECEIPT
  ref_no TEXT, debit REAL NOT NULL DEFAULT 0, credit REAL NOT NULL DEFAULT 0, narration TEXT
);
CREATE INDEX IF NOT EXISTS idx_ledger_party ON ledger(party_id, date);
`;

const V2 = `
CREATE TABLE IF NOT EXISTS purchases (
  id INTEGER PRIMARY KEY,
  purchase_no TEXT UNIQUE NOT NULL,
  supplier_invoice_no TEXT,
  date TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  subtotal REAL, discount REAL, taxable REAL, cgst REAL, sgst REAL, igst REAL, round_off REAL,
  total REAL NOT NULL, paid REAL NOT NULL DEFAULT 0, pay_mode TEXT, notes TEXT,
  source TEXT NOT NULL DEFAULT 'MANUAL',
  created_at TEXT DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_pur_date ON purchases(date);
CREATE INDEX IF NOT EXISTS idx_pur_party ON purchases(party_id, supplier_invoice_no);

CREATE TABLE IF NOT EXISTS purchase_lines (
  id INTEGER PRIMARY KEY,
  purchase_id INTEGER NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_id INTEGER REFERENCES batches(id),
  batch_no TEXT NOT NULL, mfg_date TEXT, exp_date TEXT NOT NULL,
  qty INTEGER NOT NULL, free_qty INTEGER NOT NULL DEFAULT 0,
  rate REAL NOT NULL, disc_pct REAL NOT NULL DEFAULT 0, disc_amt REAL NOT NULL DEFAULT 0, mrp REAL,
  taxable REAL NOT NULL, gst_rate REAL NOT NULL,
  cgst REAL NOT NULL, sgst REAL NOT NULL, igst REAL NOT NULL, amount REAL NOT NULL
);

-- Money paid OUT to a party (supplier payments). Money received lives in receipts.
CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY,
  voucher_no TEXT UNIQUE NOT NULL,
  date TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  purchase_id INTEGER REFERENCES purchases(id),
  mode TEXT NOT NULL DEFAULT 'CASH',
  amount REAL NOT NULL, reference TEXT
);
CREATE INDEX IF NOT EXISTS idx_inv_party ON invoices(party_id);
CREATE INDEX IF NOT EXISTS idx_invl_inv ON invoice_lines(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invl_item ON invoice_lines(item_id);
CREATE INDEX IF NOT EXISTS idx_purl_pur ON purchase_lines(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purl_item ON purchase_lines(item_id);
CREATE INDEX IF NOT EXISTS idx_batches_item ON batches(item_id);
CREATE INDEX IF NOT EXISTS idx_receipts_inv ON receipts(invoice_id);
CREATE INDEX IF NOT EXISTS idx_receipts_date ON receipts(date);
CREATE INDEX IF NOT EXISTS idx_parties_name ON parties(name);
CREATE INDEX IF NOT EXISTS idx_items_name ON items(name);
`;

/**
 * v3: sku, barcode and reorder_level were removed from items. SQLite cannot drop UNIQUE columns in place,
 * so the table is rebuilt (the documented 12-step procedure) with foreign keys off. All ids are preserved,
 * so batches, schemes and bill lines keep pointing at the right items.
 */
function migrateItems(db) {
  const cols = db.prepare('PRAGMA table_info(items)').all().map((c) => c.name);
  if (!['sku', 'barcode', 'reorder_level'].some((c) => cols.includes(c))) return false;
  const ppb = cols.includes('pcs_per_box') ? 'pcs_per_box' : '1';
  db.pragma('foreign_keys = OFF');
  try {
    db.exec('BEGIN');
    db.exec(`CREATE TABLE items_new (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, category_id INTEGER REFERENCES categories(id), hsn TEXT,
      gst_rate REAL NOT NULL DEFAULT 18, unit TEXT DEFAULT 'PCS', mrp REAL NOT NULL DEFAULT 0,
      retail_price REAL NOT NULL DEFAULT 0, wholesale_price REAL NOT NULL DEFAULT 0, purchase_price REAL NOT NULL DEFAULT 0,
      pcs_per_box INTEGER NOT NULL DEFAULT 1, active INTEGER NOT NULL DEFAULT 1)`);
    db.exec(`INSERT INTO items_new(id,name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box,active)
             SELECT id,name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,${ppb},active FROM items`);
    db.exec('DROP TABLE items');
    db.exec('ALTER TABLE items_new RENAME TO items');
    const bad = db.prepare('PRAGMA foreign_key_check').all();
    if (bad.length) throw new Error('Item migration would break references; nothing was changed.');
    db.exec('COMMIT');
  } catch (e) {
    try { db.exec('ROLLBACK'); } catch { /* not in a transaction */ }
    throw e;
  } finally {
    db.pragma('foreign_keys = ON');
  }
  return true;
}

function addColumn(db, table, col, def) {
  const cols = db.prepare(`PRAGMA table_info(${table})`).all();
  if (!cols.some((c) => c.name === col)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${col} ${def}`);
}

const DEFAULT_SETTINGS = {
  company_name: 'My Company',
  company_gstin: '',
  state_code: '09',
  company_address: '',
  company_phone: '',
  invoice_terms: 'Goods once sold will not be taken back.',
  print_layout: 'halfSheets',   // halfSheets | a4TwoUp | single | a4Full | a4FullOriginal
  print_printer: '',
  print_auto: '0',
  low_stock_qty: '10',   // alert when stock of a stocked item is at or below this many pieces
};

function applySchema(db, settings = {}) {
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.pragma('synchronous = NORMAL');
  db.exec(BASE);
  migrateItems(db);
  db.exec(V2);
  // v6: a route can be visited on several weekdays ("1,3,5"); day_of_week keeps the first one for older data
  addColumn(db, 'routes', 'days', 'TEXT');
  db.exec("UPDATE routes SET days=CAST(day_of_week AS TEXT) WHERE days IS NULL AND day_of_week IS NOT NULL");
  addColumn(db, 'items', 'pcs_per_box', 'INTEGER NOT NULL DEFAULT 1');
  // v3: supplier / party details
  for (const c of ['tel', 'mobiles', 'fssai', 'pan', 'email']) addColumn(db, 'parties', c, 'TEXT');
  // v3: purchase lines carry the printed unit and the piece count that went into stock
  addColumn(db, 'purchase_lines', 'unit', "TEXT DEFAULT 'PCS'");
  addColumn(db, 'purchase_lines', 'pcs_qty', 'INTEGER');
  // v3: manual discount typed on the bill, kept apart from scheme discount so an edited bill does not double-count schemes
  addColumn(db, 'invoice_lines', 'manual_disc', 'REAL NOT NULL DEFAULT 0');
  // v8: bills kept to print later (1 = printed since it was saved or last edited)
  addColumn(db, 'invoices', 'printed', 'INTEGER NOT NULL DEFAULT 0');
  // v9: e-way bill (number from the portal, its date and validity, and the transport details used for it)
  for (const c of ['ewb_no', 'ewb_date', 'ewb_valid', 'ewb_transport']) addColumn(db, 'invoices', c, 'TEXT');
  db.exec(V7);
  // v16.3: a party can be on several routes. parties.route_id stays the first one; party_routes holds the others.
  db.exec(`CREATE TABLE IF NOT EXISTS party_routes (
  id INTEGER PRIMARY KEY,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  route_id INTEGER NOT NULL REFERENCES routes(id)
);
CREATE INDEX IF NOT EXISTS idx_party_routes_party ON party_routes(party_id);
CREATE INDEX IF NOT EXISTS idx_party_routes_route ON party_routes(route_id);`);
  const ins = db.prepare('INSERT OR IGNORE INTO settings(key,value) VALUES(?,?)');
  const up = db.prepare('INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value');
  for (const [k, v] of Object.entries(DEFAULT_SETTINGS)) ins.run(k, v);
  for (const [k, v] of Object.entries(settings)) up.run(k, String(v));
}


// v7: debit notes (goods returned to a supplier). debit_note_stock records which batches the returned pieces left.
const V7 = `
CREATE TABLE IF NOT EXISTS debit_notes (
  id INTEGER PRIMARY KEY,
  note_no TEXT UNIQUE NOT NULL,
  date TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  purchase_id INTEGER REFERENCES purchases(id),
  against_bill TEXT, reason TEXT,
  subtotal REAL, discount REAL, taxable REAL, cgst REAL, sgst REAL, igst REAL, round_off REAL,
  total REAL NOT NULL, notes TEXT,
  source TEXT NOT NULL DEFAULT 'MANUAL',
  created_at TEXT DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_dn_date ON debit_notes(date);
CREATE INDEX IF NOT EXISTS idx_dn_party ON debit_notes(party_id);
CREATE TABLE IF NOT EXISTS debit_note_lines (
  id INTEGER PRIMARY KEY,
  note_id INTEGER NOT NULL REFERENCES debit_notes(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_id INTEGER REFERENCES batches(id),
  qty INTEGER NOT NULL, unit TEXT NOT NULL DEFAULT 'PCS', pcs_qty INTEGER NOT NULL,
  rate REAL NOT NULL, amount REAL NOT NULL, taxable REAL NOT NULL, gst_rate REAL NOT NULL,
  cgst REAL NOT NULL DEFAULT 0, sgst REAL NOT NULL DEFAULT 0, igst REAL NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_dnl_note ON debit_note_lines(note_id);
CREATE INDEX IF NOT EXISTS idx_dnl_item ON debit_note_lines(item_id);
CREATE TABLE IF NOT EXISTS debit_note_stock (
  id INTEGER PRIMARY KEY,
  line_id INTEGER NOT NULL REFERENCES debit_note_lines(id) ON DELETE CASCADE,
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  qty INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dns_line ON debit_note_stock(line_id);
`;

module.exports = { applySchema, migrateItems, DEFAULT_SETTINGS };
