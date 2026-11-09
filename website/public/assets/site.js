// BillBox website: menu, reveal-on-scroll, videos that play when seen, and download links to the newest release.
(function () {
  const btn = document.querySelector('.menu-btn'), links = document.querySelector('.nav .links');
  if (btn && links) btn.addEventListener('click', () => { links.classList.toggle('open'); btn.setAttribute('aria-expanded', links.classList.contains('open')); });

  const io = 'IntersectionObserver' in window ? new IntersectionObserver((es) => es.forEach((e) => {
    if (e.target.tagName === 'VIDEO') { if (e.isIntersecting) e.target.play().catch(() => {}); else e.target.pause(); return; }
    if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
  }), { threshold: 0.2 }) : null;
  document.querySelectorAll('.reveal').forEach((el) => (io ? io.observe(el) : el.classList.add('in')));
  document.querySelectorAll('video[data-autoplay]').forEach((v) => { v.muted = true; if (io) io.observe(v); else v.play().catch(() => {}); });

  // [data-dl="windows-setup"] etc. point straight at the file in the newest GitHub release
  const want = {
    'mac': /BillBox-mac-(?!.*-(arm64|intel)\.dmg$).*\.dmg$/, 'mac-zip': /BillBox-mac-(?!.*-(arm64|intel)\.zip$).*\.zip$/, 'windows-setup': /BillBox-windows-.*-setup\.exe$/, 'windows-zip': /BillBox-windows-.*\.zip$/,
    'linux-deb': /BillBox-linux-.*\.deb$/, 'linux-tar': /BillBox-linux-.*\.tar\.gz$/, 'android': /BillBox-android-.*\.apk$/, 'iphone': /BillBox-iphone-.*\.ipa$/,
  };
  const els = document.querySelectorAll('[data-dl]');
  if (els.length) {
    fetch('https://api.github.com/repos/mohdshahbaz/BillBox/releases/latest').then((r) => (r.ok ? r.json() : null)).then((rel) => {
      if (!rel) return;
      els.forEach((el) => {
        const a = (rel.assets || []).find((x) => want[el.dataset.dl] && want[el.dataset.dl].test(x.name));
        if (a) { el.href = a.browser_download_url; el.title = `${a.name} · ${(a.size / 1e6).toFixed(0)} MB`; }
      });
      document.querySelectorAll('[data-version]').forEach((el) => { el.textContent = rel.tag_name.replace(/^v/, ''); });
    }).catch(() => {});
  }
})();
