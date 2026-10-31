const router = require('express').Router();
const { h, HttpError } = require('../utils/misc');
const D = require('../services/debitNotes');

router.get('/debit-notes', h((req, res) => res.json(D.listDebitNotes({ fy: req.query.fy, from: req.query.from, to: req.query.to, q: req.query.q, party_id: req.query.party_id }))));
router.post('/debit-notes/preview', h((req, res) => res.json(D.previewDebitNote(req.body || {}))));
router.post('/debit-notes', h((req, res) => {
  const id = D.createDebitNote(req.body || {});
  const d = D.getDebitNote(id);
  res.status(201).json({ id, note_no: d.note_no, total: d.total });
}));
router.put('/debit-notes/:id', h((req, res) => {
  const id = D.updateDebitNote(Number(req.params.id), req.body || {});
  const d = D.getDebitNote(id);
  res.json({ id, note_no: d.note_no, total: d.total });
}));
router.delete('/debit-notes/:id', h((req, res) => res.json(D.deleteDebitNote(Number(req.params.id)))));
router.get('/debit-notes/:id', h((req, res) => {
  const d = D.getDebitNote(req.params.id);
  if (!d) throw new HttpError(404, 'Debit note not found');
  res.json(d);
}));

module.exports = router;
