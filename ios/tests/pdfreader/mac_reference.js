#!/usr/bin/env node
// The Mac's way of reading a supplier PDF, outside the app: pdf-parse 1.1.1 = pdf.js 1.10.100 with the worker disabled,
// each page through the pagerender of backend/src/services/pdfExtract.js. Prints JSON: { file: [page texts] }.
//   node mac_reference.js a.pdf b.pdf ...
const fs = require('fs');
const path = require('path');
const Module = require('module');
const origResolve = Module._resolveFilename;
Module._resolveFilename = function (req, ...rest) {
  if (req === 'node-ensure') return path.join(__dirname, 'shim/node-ensure.js');
  return origResolve.call(this, req, ...rest);
};
const PDFJS = require('../../BillBox/Resources/PDFReader/pdf.js');   // the same file the iPhone loads
const { pageTextFromItems } = require('../../../backend/src/services/pdfExtract.js');
const pageRender = (pd) => pd.getTextContent({ normalizeWhitespace: true, disableCombineTextItems: false }).then((tc) => pageTextFromItems(tc.items));

(async () => {
  const out = {};
  for (const f of process.argv.slice(2)) {
    PDFJS.disableWorker = true;
    const doc = await PDFJS.getDocument(new Uint8Array(fs.readFileSync(f)));
    const pages = [];
    for (let i = 1; i <= doc.numPages; i++) {
      await doc.getPage(i).then((pd) => pageRender(pd).then((t) => { pages.push(t); return t; })).catch(() => '');
    }
    out[path.basename(f)] = pages;
  }
  process.stdout.write(JSON.stringify(out, null, 1));
})();
