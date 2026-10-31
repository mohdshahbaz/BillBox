// What the npm package node-ensure does for pdf.js under Node: run the callback with this module's require.
module.exports = function (deps, cb) { cb(require); };
