// Scrolls: swipe left steps back a line, swipe right forward; arrows too; no double counting.
const { chromium } = require('playwright');
const ok = (c, m) => console.log((c ? 'PASS ' : 'FAIL ') + m);
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, hasTouch: false });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.addInitScript(() => { try { localStorage.setItem('ortho-master-v2', JSON.stringify({ met: true })); } catch (e) {} });
  await p.goto('file:///home/user/whitenoise/index.html'); await p.waitForTimeout(400);
  await p.click('.home-app.folder >> nth=0'); await p.waitForTimeout(350); await p.click('#homeFolderBox .home-app >> nth=0'); await p.waitForTimeout(1400);
  await p.click('#s1'); await p.waitForTimeout(1200);
  for (let i = 0; i < 10 && !(await p.isVisible('#mPanel')); i++) { await p.click('#mBox', { force: true }); await p.waitForTimeout(150); }
  await p.click('.m-panel .m-item >> nth=0'); await p.waitForTimeout(2300);
  const txt = () => p.$eval('#mText', e => e.textContent);
  const swipe = async dx => { const r = await p.$eval('#mStage', e => { const b = e.getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height * 0.75]; });
    await p.mouse.move(r[0], r[1]); await p.mouse.down(); await p.mouse.move(r[0] + dx / 2, r[1], { steps: 3 }); await p.mouse.move(r[0] + dx, r[1], { steps: 3 }); await p.mouse.up(); await p.waitForTimeout(500);
    await p.click('#mBox', { force: true }); await p.waitForTimeout(80); };   // finish typing
  await p.click('#mBox', { force: true }); await p.waitForTimeout(80);
  const l1 = await txt(); console.log('L1', l1.slice(0,50));
  await swipe(150); const l2 = await txt(); console.log('L2', l2.slice(0,50));
  ok(l2 !== l1, 'swipe right: next line');
  await swipe(150); const l3 = await txt();
  await swipe(-150);
  ok((await txt()) === l2, 'swipe left: one line back');
  await swipe(-150);
  ok((await txt()) === l1, 'swipe left again: back to the first');
  await p.keyboard.press('ArrowRight'); await p.waitForTimeout(150); await p.click('#mBox', { force: true }); await p.waitForTimeout(80);
  ok((await txt()) === l2, 'arrow right: forward');
  await p.keyboard.press('ArrowLeft'); await p.waitForTimeout(150); await p.click('#mBox', { force: true }); await p.waitForTimeout(80);
  ok((await txt()) === l1, 'arrow left: back');
  console.log(errs.length ? errs.join('\n') : 'no errors');
  await b.close();
})();
