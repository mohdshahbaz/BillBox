const router = require('express').Router();
const { ha } = require('../utils/misc');
const U = require('../services/update');

// Settings › Updates: GET /update?version=16.2.11&edition=public&platform=android (services/update.js)
router.get('/update', ha(async (req, res) => res.json(await U.check(req.query || {}))));

module.exports = router;
