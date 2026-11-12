// Buy page: Razorpay checkout → licence key on the page; direct UPI / bank transfer (no fees, owner confirms); find a key again.
(function () {
  const q = new URLSearchParams(location.search);
  const ENV = q.get('test') === '1' ? 'test' : 'live';
  const API = `/api/${ENV}`;
  const $ = (id) => document.getElementById(id);
  const msg = (el, text, kind) => { $(el).innerHTML = text ? `<div class="notice ${kind || ''}">${text}</div>` : ''; };
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  if (ENV === 'test') $('testmode').hidden = false;
  if (q.get('plan')) { const r = document.querySelector(`input[name=plan][value="${q.get('plan')}"]`); if (r) r.checked = true; }
  const plan = () => document.querySelector('input[name=plan]:checked').value;
  let config = null;
  fetch(`${API}/config`).then((r) => r.json()).then((c) => { config = c; if (c.bank) $('bankBtn').hidden = false; }).catch(() => {});

  async function post(path, body) {
    const r = await fetch(API + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error || `Something went wrong (${r.status}).`);
    return j;
  }
  function showKey(r) {
    $('done').hidden = false; ['buy', 'upi', 'bank', 'claim'].forEach((k) => { $(k).hidden = true; });
    $('key').textContent = r.license_key;
    $('keyinfo').textContent = `${r.plan === 'lifetime' ? 'Lifetime licence' : 'Yearly licence, valid till ' + r.expires} · ${r.devices || 2} devices · ${r.email || ''}`;
    $('done').scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
  $('copy').addEventListener('click', () => { navigator.clipboard.writeText($('key').textContent).then(() => { $('copy').textContent = 'Copied ✓'; }); });

  $('pay').addEventListener('click', async () => {
    const email = $('email').value.trim();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return msg('msg', 'Enter your e-mail address: your licence key is kept for it.', 'err');
    msg('msg', 'Opening the payment window…');
    $('pay').disabled = true;
    try {
      const o = await post('/order', { plan: plan(), email, name: $('name').value.trim(), device: q.get('device') || '' });
      if (!window.Razorpay) throw new Error('The payment window could not load. Check the internet connection and try again.');
      const rz = new window.Razorpay({
        key: o.key_id, order_id: o.order_id, amount: o.amount, currency: o.currency, name: 'BillBox', description: o.label,
        image: location.origin + '/assets/icon-192.png', prefill: { email }, theme: { color: '#4f46e5' },
        handler: async (p) => {
          msg('msg', 'Payment received. Making your licence key…');
          try { showKey(await post('/verify', { order_id: p.razorpay_order_id, payment_id: p.razorpay_payment_id, signature: p.razorpay_signature })); msg('msg', ''); }
          catch (e) { msg('msg', `${esc(e.message)}<br>Your payment ID is <b>${esc(p.razorpay_payment_id)}</b>: use “Find my licence key” below in a minute, or write to us.`, 'err'); }
        },
        modal: { ondismiss: () => { msg('msg', ''); $('pay').disabled = false; } },
      });
      rz.on('payment.failed', (r) => msg('msg', esc((r.error && r.error.description) || 'The payment did not go through. Nothing was charged.'), 'err'));
      rz.open();
    } catch (e) { msg('msg', esc(e.message), 'err'); }
    $('pay').disabled = false;
  });

  let method = 'upi';
  function direct(m) {
    const p = config && config.plans[plan()];
    if (!p) return null;
    if (p.currency !== 'INR') { msg('msg', 'UPI and bank transfer work in rupees only. Choose Yearly or Lifetime, or pay by card in US dollars.', 'warn'); return null; }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test($('email').value.trim())) { msg('msg', 'Enter your e-mail address first: your licence key is kept for it.', 'err'); return null; }
    msg('msg', ''); method = m;
    $('upi').hidden = m !== 'upi'; $('bank').hidden = m !== 'bank'; $('claim').hidden = false; $('cmsg').innerHTML = '';
    $('creflabel').textContent = m === 'upi' ? "UPI reference / UTR (12 digits, in your UPI app's payment details)" : 'UTR / reference number of the transfer';
    return (p.amount / 100).toFixed(2);
  }
  const rupees = (amt) => `₹${Number(amt).toLocaleString('en-IN')}`;

  $('upiBtn').addEventListener('click', () => {
    const vpa = config && config.upi_vpa;
    if (!vpa) return msg('msg', `Direct UPI is not set up yet. Write to <a href="mailto:${window.BB_EMAIL}">${window.BB_EMAIL}</a> and we will send the UPI details.`, 'warn');
    const amt = direct('upi'); if (!amt) return;
    const p = config.plans[plan()];
    const link = `upi://pay?pa=${encodeURIComponent(vpa)}&pn=${encodeURIComponent('AK Enterprises')}&am=${amt}&cu=INR&tn=${encodeURIComponent('BillBox ' + p.plan)}`;
    $('vpa').textContent = `${vpa} (${rupees(amt)})`;
    $('qr').innerHTML = '';
    if (window.QRCode) new window.QRCode($('qr'), { text: link, width: 200, height: 200 });
    $('upiApp').innerHTML = /Android|iPhone|iPad/i.test(navigator.userAgent) ? `<a class="btn" href="${link}">Open in my UPI app</a>` : '';
    $('upi').scrollIntoView({ behavior: 'smooth', block: 'center' });
  });

  $('bankBtn').addEventListener('click', () => {
    const b = config && config.bank; if (!b) return;
    const amt = direct('bank'); if (!amt) return;
    $('bamt').textContent = rupees(amt);
    $('bdetails').innerHTML = `Name: ${esc(b.name)}<br>Account: ${esc(b.account)}<br>IFSC: ${esc(b.ifsc)}${b.bank ? '<br>Bank: ' + esc(b.bank) : ''}`;
    $('bank').scrollIntoView({ behavior: 'smooth', block: 'center' });
  });

  $('claimBtn').addEventListener('click', async () => {
    $('claimBtn').disabled = true;
    try {
      const email = $('email').value.trim();
      const r = await post('/claim', { plan: plan(), email, name: $('name').value.trim(), method, ref: $('cref').value });
      if (r.status === 'approved') return showKey(r);
      $('femail').value = email; $('fpay').value = r.ref;
      msg('cmsg', r.status === 'rejected' ? 'This payment could not be found in our account. Write to us with the reference and a screenshot.'
        : `Thank you! We check the payment in our account, usually within a few hours. Then come back here and use “Find my licence key” with <b>${esc(email)}</b> and <b>${esc(r.ref)}</b> (kept filled in below).`, r.status === 'rejected' ? 'err' : '');
    } catch (e) { msg('cmsg', esc(e.message), 'err'); }
    finally { $('claimBtn').disabled = false; }
  });

  $('findBtn').addEventListener('click', async () => {
    try { showKey(await post('/lookup', { email: $('femail').value.trim(), payment_id: $('fpay').value.trim() })); msg('fmsg', ''); }
    catch (e) { msg('fmsg', esc(e.message), 'err'); }
  });
})();
