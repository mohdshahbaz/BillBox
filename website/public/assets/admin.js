// Owner's licence page: confirm direct UPI / bank payments, issue (for cash sales), list and revoke, through /api/<env>/admin/… with the admin token.
(function () {
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  try { $('tok').value = localStorage.getItem('bbAdmin') || ''; } catch (_) {}
  $('tok').addEventListener('change', () => { try { localStorage.setItem('bbAdmin', $('tok').value); } catch (_) {} });
  const env = () => document.querySelector('input[name=env]:checked').value;
  async function call(method, path, body) {
    const r = await fetch(`/api/${env()}/admin/${path}`, { method, headers: { 'content-type': 'application/json', authorization: 'Bearer ' + $('tok').value.trim() }, body: body ? JSON.stringify(body) : undefined });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error || r.status);
    return j;
  }
  $('issue').addEventListener('click', async () => {
    try {
      const r = await call('POST', 'issue', { plan: $('iplan').value, days: Number($('idays').value), devices: Number($('idev').value), email: $('iemail').value, name: $('iname').value, note: $('inote').value });
      $('imsg').innerHTML = `<div class="notice">Licence ${esc(r.license_id)} (${esc(r.plan)}${r.expires ? ', till ' + esc(r.expires) : ''}) — send this key:</div><div class="keybox">${esc(r.license_key)}</div>`;
    } catch (e) { $('imsg').innerHTML = `<div class="notice err">${esc(e.message)}</div>`; }
  });
  async function load() {
    try {
      const rows = await call('GET', 'list');
      $('list').innerHTML = '<tr><th align=left>Created</th><th align=left>E-mail</th><th align=left>Plan</th><th align=left>Till</th><th>Devices</th><th align=left>By</th><th></th></tr>' + rows.map((r) =>
        `<tr style="border-top:1px solid var(--line)"><td>${esc(r.created.slice(0, 10))}</td><td>${esc(r.email)}<div style="color:var(--muted);font-size:12px">${esc(r.name)} ${esc(r.note)}</div></td><td>${esc(r.plan)}</td><td>${r.exp ? esc(new Date(r.exp).toISOString().slice(0, 10)) : '—'}</td><td align=center>${r.seats}/${r.devices}</td><td>${esc(r.by)}${r.payment ? '<div style="font-size:12px;color:var(--muted)">' + esc(r.payment) + '</div>' : ''}</td><td><button class="btn ghost" data-id="${esc(r.id)}" data-undo="${r.revoked ? 1 : ''}">${r.revoked ? 'Restore' : 'Revoke'}</button></td></tr>`).join('');
      $('list').querySelectorAll('[data-id]').forEach((b) => b.addEventListener('click', async () => { await call('POST', 'revoke', { id: b.dataset.id, undo: !!b.dataset.undo }); load(); }));
    } catch (e) { $('list').innerHTML = `<tr><td><div class="notice err">${esc(e.message)}</div></td></tr>`; }
  }
  async function loadClaims() {
    try {
      const rows = await call('GET', 'claims');
      $('claims').innerHTML = rows.length ? '<tr><th align=left>Sent</th><th align=left>E-mail</th><th align=left>Plan</th><th align=left>Reference</th><th align=left>Status</th><th></th></tr>' + rows.map((r) =>
        `<tr style="border-top:1px solid var(--line)"><td>${esc(r.created.slice(0, 16).replace('T', ' '))}</td><td>${esc(r.email)}<div style="color:var(--muted);font-size:12px">${esc(r.name)}</div></td><td>${esc(r.plan)} ₹${(r.amount / 100).toLocaleString('en-IN')}</td><td><b>${esc(r.ref)}</b><div style="color:var(--muted);font-size:12px">${esc(r.method.toUpperCase())}</div></td><td>${esc(r.status)}</td><td>${r.status === 'pending' ? `<button class="btn" data-ok="${esc(r.ref)}">Confirm</button> <button class="btn ghost" data-no="${esc(r.ref)}">Not received</button>` : ''}</td></tr>`).join('')
        : '<tr><td style="color:var(--muted)">No UPI or bank payments sent yet.</td></tr>';
      $('claims').querySelectorAll('[data-ok]').forEach((b) => b.addEventListener('click', async () => { await call('POST', 'approve', { ref: b.dataset.ok }); loadClaims(); }));
      $('claims').querySelectorAll('[data-no]').forEach((b) => b.addEventListener('click', async () => { await call('POST', 'reject', { ref: b.dataset.no }); loadClaims(); }));
    } catch (e) { $('claims').innerHTML = `<tr><td><div class="notice err">${esc(e.message)}</div></td></tr>`; }
  }
  $('loadClaims').addEventListener('click', loadClaims);
  $('load').addEventListener('click', load);
})();
