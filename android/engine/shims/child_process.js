// The Mac reads scanned PDFs with poppler (pdftoppm) and tesseract. On Android the same two steps are done by the phone:
// pdftoppm -> AndroidOCR.render (PdfRenderer, one PNG per page), tesseract -> AndroidOCR.recognize (on-device text recognition).
'use strict';
function execFile(cmd, args, opts, cb) {
  if (typeof opts === 'function') { cb = opts; opts = {}; }
  const ocr = globalThis.AndroidOCR;
  setTimeout(() => {
    try {
      if (!ocr) { const e = new Error(`spawn ${cmd} ENOENT`); e.code = 'ENOENT'; return cb(e); }
      if (cmd === 'pdftoppm') { ocr.render(args[args.length - 2], args[args.length - 1]); return cb(null, '', ''); }
      if (cmd === 'tesseract') { const out = ocr.recognize(args[0]); return cb(null, out, ''); }
      const e = new Error(`spawn ${cmd} ENOENT`); e.code = 'ENOENT'; cb(e);
    } catch (err) { cb(err); }
  }, 0);
}
// util.promisify(execFile) resolves to { stdout, stderr } in Node
execFile[Symbol.for('nodejs.util.promisify.custom')] = (cmd, args, opts) => new Promise((ok, no) => execFile(cmd, args, opts || {}, (e, stdout, stderr) => (e ? no(e) : ok({ stdout, stderr }))));
module.exports = { execFile };
