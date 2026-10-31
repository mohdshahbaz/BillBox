// pdf-parse's loop over Mozilla pdf.js 1.10.100 (loaded beside the engine, as on the Mac): every page through pagerender,
// a page that fails is left out.
'use strict';
module.exports = async function pdfParse(buf, opts = {}) {
  const P = globalThis.PDFJS;
  if (!P) throw new Error('pdf.js is not loaded');
  P.disableWorker = true;
  const doc = await P.getDocument(new Uint8Array(buf));
  let text = '';
  try {
    for (let i = 1; i <= doc.numPages; i++) {
      try { const page = await doc.getPage(i); text += '\n\n' + (await (opts.pagerender ? opts.pagerender(page) : '')); } catch (e) { /* skipped, as pdf-parse */ }
    }
  } finally { doc.destroy(); }
  return { numpages: doc.numPages, text };
};
