const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const { promisify } = require('util');
const { HttpError } = require('../utils/misc');
const run = promisify(execFile);

/**
 * Watermarks: big faded words printed across the page ("SHREE ENTERPRISE", "PAID", "COPY") are text too, and would land in the
 * middle of item rows. A run is treated as a watermark when its letters are at least 3 times the page's usual text size,
 * or when it is printed on a slant (between 15 and 75 degrees; text turned a full 90 degrees, like a copy label in the margin, is kept).
 * The usual size is the median letter size of the page, counted per character.
 */
const WATERMARK_SCALE = 3;
function runGeometry(t) {
  const size = Math.hypot(t[2], t[3]) || Math.hypot(t[0], t[1]);
  const angle = Math.abs((Math.atan2(t[1], t[0]) * 180) / Math.PI) % 180;
  return { size, angle: angle > 90 ? 180 - angle : angle };
}
function dropWatermarks(items) {
  const runs = items.filter((it) => it && typeof it.str === 'string' && Array.isArray(it.transform));
  const sizes = [];
  for (const it of runs) { const g = runGeometry(it.transform); for (let i = 0; i < it.str.replace(/\s/g, '').length; i++) sizes.push(g.size); }
  if (!sizes.length) return runs;
  sizes.sort((a, b) => a - b);
  const median = sizes[Math.floor(sizes.length / 2)];
  return runs.filter((it) => {
    if (!it.str.trim()) return true;                      // spaces stay where they are
    const g = runGeometry(it.transform);
    if (median > 0 && g.size >= median * WATERMARK_SCALE) return false;
    if (g.angle >= 15 && g.angle <= 75) return false;
    return true;
  });
}

/** One page of pdf.js text items -> text, items on the same visual row joined by spaces (one row of a table = one line). */
function pageTextFromItems(items) {
  const rows = [];
  for (const it of dropWatermarks(items)) {
    const y = Math.round(it.transform[5]);
    let row = rows.find((r) => Math.abs(r.y - y) <= 2);
    if (!row) { row = { y, cells: [] }; rows.push(row); }
    row.cells.push({ x: it.transform[4], w: it.width || 0, s: it.str });
  }
  rows.sort((a, b) => b.y - a.y);
  // Text runs that touch (a word the PDF split in two) are glued; a visible gap becomes a space.
  const joinRow = (cells) => { let out = '', prevEnd = null; for (const c of cells.sort((a, b) => a.x - b.x)) { out += (prevEnd !== null && c.x - prevEnd > 1.2 ? ' ' : '') + c.s; prevEnd = c.x + c.w; } return out; };
  return rows.map((r) => joinRow(r.cells).replace(/\s+/g, ' ').trim()).filter(Boolean).join('\n');
}

function pageRender(pageData) {
  return pageData.getTextContent({ normalizeWhitespace: true, disableCombineTextItems: false }).then((tc) => pageTextFromItems(tc.items));
}

/** Returns { pages: string[], text, method }. Text PDFs: pdf-parse, one string per page. Scans: poppler + tesseract per page. */
async function extractText(buf) {
  let pages = [];
  try {
    const pdfParse = require('pdf-parse/lib/pdf-parse.js'); // the package index runs a debug routine, so require the lib file
    const out = [];
    await pdfParse(buf, { pagerender: (pd) => pageRender(pd).then((t) => { out.push(t); return t; }) });
    pages = out;
  } catch (e) {
    if (e.code === 'MODULE_NOT_FOUND') throw new HttpError(500, 'PDF support is not installed. Run "npm install" in the backend folder.');
    throw new HttpError(422, 'This file could not be read as a PDF.');
  }
  if (pages.join('').replace(/\s/g, '').length >= 40) return { pages, text: pages.join('\f'), method: 'text' };
  const ocrPages = await ocr(buf);
  return { pages: ocrPages, text: ocrPages.join('\f'), method: 'ocr' };
}

async function ocr(buf) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bill-'));
  try {
    const pdf = path.join(dir, 'bill.pdf');
    fs.writeFileSync(pdf, buf);
    await run('pdftoppm', ['-r', '200', '-png', pdf, path.join(dir, 'p')]);
    const pages = fs.readdirSync(dir).filter((f) => f.endsWith('.png')).sort().slice(0, 12);
    const out = [];
    for (const f of pages) out.push((await run('tesseract', [path.join(dir, f), 'stdout', '--psm', '6'], { maxBuffer: 20e6 })).stdout);
    if (!out.join('').trim()) throw new HttpError(422, 'No text could be recognised in this scanned PDF.');
    return out;
  } catch (e) {
    if (e instanceof HttpError) throw e;
    if (e.code === 'ENOENT') throw new HttpError(422, 'This PDF is a scan (no text layer). To read scans, install the OCR tools once: brew install poppler tesseract');
    throw new HttpError(422, 'OCR failed on this PDF.');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

module.exports = { extractText, pageTextFromItems, dropWatermarks };
