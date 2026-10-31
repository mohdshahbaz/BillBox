// Buy page: Razorpay checkout → licence key on the page; direct UPI (no fees); find a key again.
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
  fetch(`${API}/config`).then((r) => r.json()).then((c) => { config = c; }).catch(() => {});

  async function post(path, body) {
    const r = await fetch(API + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error || `Something went wrong (${r.status}).`);
    return j;
  }
  function showKey(r) {
    $('done').hidden = false; $('buy').hidden = true; $('upi').hidden = true;
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

  $('upiBtn').addEventListener('click', () => {
    const vpa = config && config.upi_vpa;
    if (!vpa) return msg('msg', `Direct UPI is not set up yet. Write to <a href="mailto:${window.BB_EMAIL}">${window.BB_EMAIL}</a> and we will send the UPI details.`, 'warn');
    const p = config.plans[plan()];
    if (p.currency !== 'INR') return msg('msg', 'UPI works in rupees only. Choose Yearly or Lifetime, or pay by card in US dollars.', 'warn');
    const amt = (p.amount / 100).toFixed(2);
    const link = `upi://pay?pa=${encodeURIComponent(vpa)}&pn=${encodeURIComponent('AK Enterprises')}&am=${amt}&cu=INR&tn=${encodeURIComponent('BillBox ' + p.plan)}`;
    $('upi').hidden = false; $('vpa').textContent = `${vpa} (₹${Number(amt).toLocaleString('en-IN')})`;
    const sub = encodeURIComponent(`BillBox ${p.plan} licence — UPI payment`);
    const body = encodeURIComponent(`UPI reference: \nE-mail for the licence: ${$('email').value}\nBusiness: ${$('name').value}\nPlan: ${p.plan} (₹${amt})`);
    $('mailto').href = `mailto:${window.BB_EMAIL}?subject=${sub}&body=${body}`; $('mailto').textContent = window.BB_EMAIL;
    $('qr').innerHTML = '';
    if (window.QRCode) new window.QRCode($('qr'), { text: link, width: 200, height: 200 });
    if (/Android|iPhone|iPad/i.test(navigator.userAgent)) $('qr').insertAdjacentHTML('afterend', `<p><a class="btn" href="${link}">Open in my UPI app</a></p>`);
    $('upi').scrollIntoView({ behavior: 'smooth', block: 'center' });
  });

  $('findBtn').addEventListener('click', async () => {
    try { showKey(await post('/lookup', { email: $('femail').value.trim(), payment_id: $('fpay').value.trim() })); msg('fmsg', ''); }
    catch (e) { msg('fmsg', esc(e.message), 'err'); }
  });
})();
