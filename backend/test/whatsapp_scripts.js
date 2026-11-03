// Runs the JavaScript that BillBox injects into WhatsApp Web (extracted from WhatsAppWeb.swift) against a small fake of the page,
// for: attaching by paste / drop / file input, pressing Send, falling back to Enter, and refusing to claim success when nothing was sent.
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '../../macos/Sources/DistributorPro/WhatsAppWeb.swift'), 'utf8');
const grab = (name) => { const m = src.match(new RegExp('static let ' + name + ' = #"""\\n([\\s\\S]*?)\\n\\s*"""#')); assert.ok(m, name + ' not found'); return m[1]; };
const prelude = grab('prelude'), prepare = grab('prepareScript'), attach = grab('attachScript'), finish = grab('finishScript'), confirm = grab('confirmScript'), diagnose = grab('diagnose');
const waitComposer = grab('waitComposerScript'), waitPreview = grab('waitPreviewScript'), chatNow = grab('chatNowScript');
// the iPhone file must carry the same scripts as the Mac file the tests read
const iosSrc = fs.readFileSync(path.join(__dirname, '../../ios/BillBox/Shared/WhatsAppWeb.swift'), 'utf8');
for (const name of ['prelude', 'prepareScript', 'attachScript', 'finishScript', 'confirmScript', 'waitComposerScript', 'waitPreviewScript', 'chatNowScript']) {
  const m = iosSrc.match(new RegExp('static let ' + name + ' = #"""\\n([\\s\\S]*?)\\n\\s*"""#')); assert.ok(m && m[1] === grab(name), 'iPhone script differs from the Mac: ' + name);
}
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
let n = 0;
const ok = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { console.log('  FAIL', name, '\n', e.stack); process.exitCode = 1; } };

// ---- a tiny fake WhatsApp page ----
// Like the real one it has an always-present search box (a contenteditable OUTSIDE the chat footer) and an always-present plain "Send" label,
// plus the chat box. Attaching a file mounts the preview: a caption box and the real send button.
function makePage(opts) {
  const t0 = Date.now();
  const st = { preview: false, out: 0, pending: 0, attachVia: null, caption: '', composerAt: 0, qr: false, ...opts };
  const composerUp = () => Date.now() - t0 >= st.composerAt;
  const el = (kind, extra = {}) => ({
    kind, text: '', closest(sel) { return sel.includes('footer') && kind === 'composer' ? this : (sel.includes('button') ? this : null); },
    getBoundingClientRect: () => ({ width: 10, height: 10 }), focus() { st.focused = kind; },
    getAttribute: (a) => (a === 'aria-label' ? (kind === 'send' ? 'Send 1 selected' : kind === 'decoy' ? 'Send' : 'x') : null),
    dispatchEvent(ev) { return handle(kind, ev); }, click() { if (kind === 'send') { st.clicks = (st.clicks || 0) + 1; if (st.clickWorks) send(); } },
    get innerText() { return this.text; }, ...extra,
  });
  const decoy = el('decoy'), sendEl = el('send'), composer = el('composer'), cap = el('caption'), search = el('search'), input = el('input', { accept: '*', files: null });
  const send = () => { if (!st.preview) return; st.preview = false; st.out++; st.pending = 1; st.sentCaption = cap.text; setTimeout(() => { st.pending = 0; }, 300); };
  function handle(kind, ev) {
    if (ev.type === 'paste' && st.attachVia === 'paste' && kind === 'composer') { if (st.previewDelay) setTimeout(() => { st.preview = true; }, st.previewDelay); else st.preview = true; }
    if (ev.type === 'drop' && st.attachVia === 'drop') st.preview = true;
    if (ev.type === 'change' && kind === 'input' && st.attachVia === 'input') st.preview = true;
    if (ev.type === 'click' && kind === 'send') { st.clicks = (st.clicks || 0) + 1; if (st.mouseWorks) { if (st.sendDelay) setTimeout(send, st.sendDelay); else send(); } }
    if (ev.type === 'keydown' && ev.key === 'Enter' && kind === 'caption' && st.enterWorks) send();
    return true;
  }
  const document = {
    body: { get innerText() { return st.out ? 'BillBox-test.pdf' : ''; } },
    execCommand(c, _u, text) { if (st.focused === 'search') st.searchText = (st.searchText || '') + text; if (st.focused === 'caption') cap.text += text; return true; },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
    querySelectorAll(sel) {
      const r = [];
      if (/^footer div\[contenteditable/.test(sel) && composerUp()) r.push(composer);
      if (st.qr && /canvas\[aria-label\]/.test(sel)) r.push({});
      if (/contenteditable="true"\], \[contenteditable=""\]/.test(sel)) { r.push(search, composer); if (st.preview) r.push(cap); }
      if (/aria-label\^="Send"/.test(sel)) { r.push(decoy); if (st.preview) r.push(sendEl); }   // the plain "Send" never goes away; "Send 1 selected" only with the preview
      if (/data-icon\^="msg-"/.test(sel)) for (let i = 0; i < st.out; i++) r.push({});
      if (/msg-time/.test(sel) && st.pending) r.push({});
      if (/input\[type="file"\]/.test(sel)) r.push(input);
      if (/#main/.test(sel)) r.push(composer);
      return r;
    },
  };
  const win = {};
  const globals = {
    document, window: win,
    MouseEvent: class { constructor(t) { this.type = t; } }, KeyboardEvent: class { constructor(t, o) { this.type = t; Object.assign(this, o); } },
    ClipboardEvent: class { constructor(t) { this.type = t; } }, DragEvent: class { constructor(t) { this.type = t; } }, Event: class { constructor(t) { this.type = t; } },
    DataTransfer: class { constructor() { this.items = { add() {} }; this.files = []; } setData() {} }, File: class {}, atob: (s) => Buffer.from(s, 'base64').toString('binary'),
  };
  const run = async (body, args = {}) => {
    const names = [...Object.keys(globals), ...Object.keys(args)];
    const vals = [...Object.values(globals), ...Object.values(args)];
    return new AsyncFunction(...names, prelude + '\n' + body)(...vals);
  };
  const prep = () => run(prepare, { b64: 'AAAA', name: 'BillBox-test.pdf' });
  return { st, run, prep, cap, search };
}

(async () => {
  await ok('all injected scripts are valid JavaScript', async () => {
    for (const s of ['', prepare, attach, finish, confirm, diagnose]) new AsyncFunction('b64', 'name', 'caption', 'method', prelude + '\n' + s);
  });
  for (const via of ['paste', 'drop', 'input']) {
    await ok(`attach by ${via} opens the preview, Send is clicked, the bill is confirmed`, async () => {
      const { st, run, prep, cap, search } = makePage({ attachVia: via, mouseWorks: true });
      await prep();
      assert.strictEqual(await run(attach, { method: via }), 'tried');
      assert.ok(st.preview, 'preview open');
      assert.strictEqual(await run(finish, { caption: 'Hello Shahbaz, your bill is attached' }), 'clicked');
      assert.strictEqual(st.out, 1);
      assert.strictEqual(st.sentCaption, 'Hello Shahbaz, your bill is attached', 'the caption went out with the bill');
      assert.ok(!st.searchText, 'nothing was typed into the left-hand search box');
      assert.strictEqual(await run(confirm, { name: 'BillBox-test.pdf' }), 'sent');
    });
  }
  await ok('when the scripted click is ignored but Enter works, it still sends (once)', async () => {
    const { st, run, prep, cap, search } = makePage({ attachVia: 'paste', mouseWorks: false, clickWorks: false, enterWorks: true });
    await prep(); await run(attach, { method: 'paste' });
    assert.strictEqual(await run(finish, { caption: '' }), 'clicked');
    assert.strictEqual(st.out, 1);
  });
  await ok('when nothing sends the bill it reports preview-stayed instead of claiming success', async () => {
    const { st, run, prep, cap, search } = makePage({ attachVia: 'paste', mouseWorks: false, clickWorks: false, enterWorks: false });
    await prep(); await run(attach, { method: 'paste' });
    assert.strictEqual(await run(finish, { caption: '' }), 'preview-stayed');
    assert.strictEqual(await run(confirm, { name: 'BillBox-test.pdf' }), 'preview-stayed');
    assert.strictEqual(st.out, 0);
  });

  // ---- speed: the waiting happens inside the page and answers as soon as the thing is there ----
  const timed = async (fn) => { const t = Date.now(); const v = await fn(); return [v, Date.now() - t]; };
  await ok('waitComposer answers as soon as the chat box mounts (no 300 ms app-side polling)', async () => {
    const { run } = makePage({ composerAt: 200 });
    const [v, ms] = await timed(() => run(waitComposer, { ms: 2500 }));
    assert.strictEqual(v, 'composer'); assert.ok(ms >= 150 && ms < 450, 'took ' + ms + ' ms');
  });
  await ok('waitComposer gives up with loading when the chat never opens, so the app can decide', async () => {
    const { run } = makePage({ composerAt: 99999 });
    const [v, ms] = await timed(() => run(waitComposer, { ms: 300 }));
    assert.strictEqual(v, 'loading'); assert.ok(ms >= 280 && ms < 700, 'took ' + ms + ' ms');
  });
  await ok('waitComposer returns at once when the QR code shows (the person has to act)', async () => {
    const { run } = makePage({ composerAt: 99999, qr: true });
    const [v, ms] = await timed(() => run(waitComposer, { ms: 2500 }));
    assert.strictEqual(v, 'qr'); assert.ok(ms < 150, 'took ' + ms + ' ms');
  });
  await ok('chatNow reports the chat box and heading in one answer, or none', async () => {
    assert.strictEqual(await makePage({}).run(chatNow), 'composer|');
    assert.strictEqual(await makePage({ composerAt: 99999 }).run(chatNow), 'none');
  });
  await ok('waitPreview returns y the moment the preview opens, n when it never does', async () => {
    const a = makePage({ attachVia: 'paste', mouseWorks: true });
    await a.prep(); await a.run(attach, { method: 'paste' });
    const [y, ms] = await timed(() => a.run(waitPreview, { ms: 3000 }));
    assert.strictEqual(y, 'y'); assert.ok(ms < 150, 'took ' + ms + ' ms');
    const b = makePage({ attachVia: 'none' });
    await b.prep();
    const [no, ms2] = await timed(() => b.run(waitPreview, { ms: 300 }));
    assert.strictEqual(no, 'n'); assert.ok(ms2 >= 280 && ms2 < 700, 'took ' + ms2 + ' ms');
  });
  await ok('typing the caption and pressing Send takes well under a second (no fixed sleeps)', async () => {
    const { st, run, prep } = makePage({ attachVia: 'paste', mouseWorks: true });
    await prep(); await run(attach, { method: 'paste' });
    const [v, ms] = await timed(() => run(finish, { caption: 'Hello Shahbaz, your bill is attached' }));
    assert.strictEqual(v, 'clicked'); assert.strictEqual(st.out, 1); assert.ok(ms < 250, 'took ' + ms + ' ms');
  });

  // ---- slow phone / slow WhatsApp: the cases where giving up early re-attaches or sends the bill twice ----
  await ok('a preview that draws after 4 s (slow phone) is still found within the 5 s the app waits', async () => {
    const { st, run, prep } = makePage({ attachVia: 'paste', previewDelay: 4000 });
    await prep(); await run(attach, { method: 'paste' });
    const [v, ms] = await timed(() => run(waitPreview, { ms: 5000 }));
    assert.strictEqual(v, 'y'); assert.ok(ms >= 3800 && ms < 5000, 'took ' + ms + ' ms');
  });
  await ok('a slow Send (the bill appears 2.5 s after the click) is pressed once, not twice', async () => {
    const { st, run, prep } = makePage({ attachVia: 'paste', mouseWorks: true, sendDelay: 2500 });
    await prep(); await run(attach, { method: 'paste' });
    st.preview = true;
    assert.strictEqual(await run(finish, { caption: '' }), 'clicked');
    assert.strictEqual(st.clicks, 1, 'Send was clicked ' + st.clicks + ' times');
    assert.strictEqual(st.out, 1);
  });
  await ok('the app waits long enough for a slow preview and cannot hang on one stuck step (both Swift files)', async () => {
    for (const [name, text] of [['Mac', src], ['iPhone', iosSrc]]) {
      const m = text.match(/previewOpen\(seconds: method == "input" \? (\d+) : (\d+)\)/); assert.ok(m, name + ': preview wait not found');
      assert.ok(+m[1] >= 8 && +m[2] >= 5, name + ': preview wait too short (' + m[1] + '/' + m[2] + ' s)');
      assert.ok(/abortAt = Date\(\)\.addingTimeInterval\(\d+\)/.test(text) && /if overtime \{ break \}/.test(text), name + ': no time limit on attaching');
      assert.ok(/waitSettled\(maxSeconds: \d+\)/.test(text), name + ': the wait for the previous bill is not capped');
      assert.ok(/if status == "Sending…" \{ status = /.test(text), name + ': status can stay on Sending…');
      assert.ok(/The bill is attached in the chat\. (Tap|Click) the green Send icon/.test(text), name + ': no tap-Send fallback');
    }
  });
  console.log(`\n${n} WhatsApp script checks passed`);
})();
