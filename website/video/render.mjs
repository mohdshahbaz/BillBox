// Renders website/public/videos/<platform>.mp4 (and a poster .jpg) from scene.html: node website/video/render.mjs [platform…]
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const HERE = path.dirname(new URL(import.meta.url).pathname);
const OUT = path.join(HERE, '..', 'public', 'videos');
fs.mkdirSync(OUT, { recursive: true });
const FPS = 30, SECONDS = 12.5;
const list = process.argv.slice(2).length ? process.argv.slice(2) : ['mac', 'windows', 'linux', 'iphone', 'android'];
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
for (const p of list) {
  await page.goto('file://' + path.join(HERE, 'scene.html') + '?p=' + p);
  const tmp = path.join(OUT, `.${p}.tmp.mp4`);
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '24', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', tmp], { stdio: ['pipe', 'inherit', 'inherit'] });
  const frames = Math.round(FPS * SECONDS);
  for (let f = 0; f < frames; f++) {
    await page.evaluate((t) => window.render(t), f / FPS);
    const jpg = await page.screenshot({ type: 'jpeg', quality: 92 });
    if (!ff.stdin.write(jpg)) await new Promise((r) => ff.stdin.once('drain', r));
    if (f === Math.round(FPS * 2.9)) fs.writeFileSync(path.join(OUT, `${p}.jpg`), await page.screenshot({ type: 'jpeg', quality: 85 }));
  }
  ff.stdin.end();
  const code = await new Promise((r) => ff.on('close', r));
  if (code !== 0) throw new Error(`ffmpeg failed for ${p}`);
  fs.renameSync(tmp, path.join(OUT, `${p}.mp4`));
  console.log('made', p, (fs.statSync(path.join(OUT, `${p}.mp4`)).size / 1e6).toFixed(2), 'MB');
}
await browser.close();
