const router = require('express').Router();
const db = require('../db');
const { h, HttpError } = require('../utils/misc');
const { previewPurchase, createPurchase, updatePurchase, deletePurchase, getPurchase } = require('../services/purchases');
const { extractText } = require('../services/pdfExtract');
const { parseInvoicePages } = require('../services/pdfParser');
const { settings } = require('../services/billing');
const { createMissing } = require('../services/autoCreate');

router.post('/purchases/preview', h((req, res) => res.json(previewPurchase(req.body))));

router.post('/purchases', h((req, res) => {
  const id = createPurchase(req.body);
  const p = getPurchase(id);
  res.status(201).json({ id, purchase_no: p.purchase_no, total: p.total });
}));

router.put('/purchases/:id', h((req, res) => {
  const id = updatePurchase(Number(req.params.id), req.body || {});
  const p = getPurchase(id);
  res.json({ id, purchase_no: p.purchase_no, total: p.total });
}));

router.delete('/purchases/:id', h((req, res) => res.json(deletePurchase(Number(req.params.id)))));

router.get('/purchases/:id', h((req, res) => {
  const p = getPurchase(req.params.id);
  if (!p) throw new HttpError(404, 'Purchase bill not found');
  res.json(p);
}));

/** Body: { pdf_base64 }. Returns suggested bill fields for the user to review, never saves anything. */
router.post('/purchases/parse-pdf', async (req, res, next) => {
  try {
    const b64 = req.body && req.body.pdf_base64;
    if (!b64) throw new HttpError(400, 'No PDF received');
    const buf = Buffer.from(b64, 'base64');
    if (buf.length < 100 || buf.slice(0, 4).toString() !== '%PDF') throw new HttpError(422, 'That file is not a PDF');
    const { pages, text, method } = await extractText(buf);
    const co = settings();
    const result = parseInvoicePages(pages, {
      items: db.prepare('SELECT id,name,hsn,gst_rate FROM items WHERE active=1').all(),
      parties: db.prepare(`SELECT id,name,gstin FROM parties WHERE active=1 AND type='SUPPLIER'`).all(),
      companyGstin: co.company_gstin, companyName: co.company_name,
    });
    if (req.body.create_missing) await createMissing(result, { online: req.body.online !== false });
    res.json({ ...result, method, raw_text: text.replace(/\f/g, '\n---- page ----\n').slice(0, 8000) });
  } catch (e) { next(e); }
});

module.exports = router;
