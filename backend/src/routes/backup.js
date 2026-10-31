const router = require('express').Router();
const { h } = require('../utils/misc');
const B = require('../services/backup');

router.get('/backup', h((req, res) => res.json({ config: B.config(), backups: B.listBackups() })));
router.put('/backup/config', h((req, res) => res.json(B.saveConfig(req.body))));
router.post('/backup/run', h((req, res) => {
  const r = B.backupNow({ reason: 'manual' });
  res.json({ folder: r.folder, files: r.files.length, config: B.config(), backups: B.listBackups() });
}));

router.delete('/backup/:name', h((req, res) => { const r = B.deleteBackup(req.params.name); res.json({ ...r, backups: B.listBackups() }); }));
router.post('/backup/restore', h((req, res) => res.json(B.restore(req.body || {}))));

module.exports = router;
