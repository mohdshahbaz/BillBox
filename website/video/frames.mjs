import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
import path from 'node:path';
const HERE = path.dirname(new URL(import.meta.url).pathname);
const b = await chromium.launch(); const pg = await b.newPage({ viewport: { width: 1280, height: 720 } });
for (const [p, t] of [['mac', 3.2], ['mac', 7.2], ['windows', 9.2], ['iphone', 7.0], ['android', 9.3], ['linux', 10.8]]) {
  await pg.goto('file://' + path.join(HERE, 'scene.html') + '?p=' + p); await pg.evaluate((t) => window.render(t), t);
  await pg.screenshot({ path: `/tmp/claude-0/-home-claude/eaa52d7c-fbd9-558b-be83-df757edad880/scratchpad/f-${p}-${t}.jpg`, type: 'jpeg', quality: 80 });
}
await b.close();
