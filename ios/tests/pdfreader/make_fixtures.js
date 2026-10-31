#!/usr/bin/env node
// Rewrites the supplier-PDF fixtures with the Mac's real reader (pdf-parse = pdf.js 1.10.100, worker disabled):
//   backend/test/fixtures/{supplier_b_6157,supplier_a_0485,supplier_a_0486}.pages.json   page texts (the Mac's pagerender)
//   backend/test/fixtures/pdf_text_runs.json                                  the raw text items, for the line-joining parity test
//   node make_fixtures.js <6157.pdf> <0485.pdf> <0486.pdf>
const fs = require('fs');
const path = require('path');
const Module = require('module');
const origResolve = Module._resolveFilename;
Module._resolveFilename = function (req, ...rest) {
  if (req === 'node-ensure') return path.join(__dirname, 'shim/node-ensure.js');
  return origResolve.call(this, req, ...rest);
};
const PDFJS = require('../../BillBox/Resources/PDFReader/pdf.js');
const { pageTextFromItems } = require('../../../backend/src/services/pdfExtract.js');
const FIX = path.join(__dirname, '../../../backend/test/fixtures/private');   // real bills, kept off GitHub
const names = ['supplier_b_6157', 'supplier_a_0485', 'supplier_a_0486'];

(async () => {
  const runs = [];
  for (const [i, f] of process.argv.slice(2).entries()) {
    PDFJS.disableWorker = true;
    const doc = await PDFJS.getDocument(new Uint8Array(fs.readFileSync(f)));
    const texts = [], items = [];
    for (let p = 1; p <= doc.numPages; p++) {
      const tc = await (await doc.getPage(p)).getTextContent({ normalizeWhitespace: true, disableCombineTextItems: false });
      items.push(tc.items.map((it) => ({ str: it.str, transform: it.transform, width: it.width })));
      texts.push(pageTextFromItems(tc.items));
    }
    fs.writeFileSync(path.join(FIX, names[i] + '.pages.json'), JSON.stringify(texts, null, 1));
    runs.push({ op: 'pagetext', pages: items, note: names[i] });
    console.log(names[i], texts.length, 'pages');
  }
  fs.writeFileSync(path.join(FIX, 'pdf_text_runs.json'), JSON.stringify(runs));
})();
