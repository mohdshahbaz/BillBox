const router = require('express').Router();
const { h, ha } = require('../utils/misc');
const B = require('../services/backup');
const D = require('../services/drive');

router.get('/backup', h((req, res) => res.json({ config: B.config(), backups: B.listBackups() })));
router.put('/backup/config', h((req, res) => res.json(B.saveConfig(req.body))));
router.post('/backup/run', h((req, res) => {
  const r = B.backupNow({ reason: 'manual' });
  D.afterBackup(r.folder); // to Google Drive too, when it is connected (in the background)
  res.json({ folder: r.folder, files: r.files.length, config: B.config(), backups: B.listBackups() });
}));

// Google Drive (services/drive.js)
router.get('/backup/drive', h((req, res) => res.json(D.status())));
router.put('/backup/drive/client', h((req, res) => res.json(D.saveClient(req.body || {}))));
router.post('/backup/drive/connect', ha(async (req, res) => res.json(await D.connect())));
router.post('/backup/drive/poll', ha(async (req, res) => res.json(await D.poll())));
router.post('/backup/drive/disconnect', h((req, res) => res.json(D.disconnect())));
router.post('/backup/drive/upload', ha(async (req, res) => res.json(await D.upload(req.body || {}))));

router.delete('/backup/:name', h((req, res) => { const r = B.deleteBackup(req.params.name); res.json({ ...r, backups: B.listBackups() }); }));
router.post('/backup/restore', h((req, res) => res.json(B.restore(req.body || {}))));

module.exports = router;
