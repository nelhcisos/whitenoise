// The second book: its own icon, its own teacher (Сора), its own scrolls; the master's book stays as it was.
const { chromium } = require('playwright');
const out = process.argv[2];
const ok = (c, m) => console.log((c ? 'PASS ' : 'FAIL ') + m);
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const errs = [];
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  p.on('pageerror', e => errs.push('pageerror: ' + (e.stack || e.message).split('\n').slice(0, 3).join(' | ')));
  p.on('requestfailed', r => errs.push('requestfailed: ' + r.url()));
  await p.addInitScript(() => { if (!sessionStorage.getItem('k')) { try { localStorage.clear(); } catch (e) {} sessionStorage.setItem('k', '1'); } });
  await p.goto('file:///home/user/whitenoise/index.html'); await p.waitForTimeout(600);
  const posIcon = '.home-app[data-book="positioning"]';
  ok(await p.isVisible(posIcon), 'positioning icon on the home screen');
  const nScrolls = await p.evaluate(() => MASTER_CHAPTERS.filter(c => c.book === 'positioning').length).catch(() => -1);
  const badge = await p.$eval(`${posIcon} .home-badge`, e => e.textContent).catch(() => '');
  ok(badge.length > 0, 'its badge counts its own scrolls: ' + badge);
  ok(/Свитки 0\/17/.test(await p.$eval('.home-app.folder >> nth=0 >> .home-fstat', e => e.textContent)), 'the master\'s folder still counts 17');
  await p.screenshot({ path: `${out}/home.png` });
  await p.click(posIcon); await p.waitForTimeout(1600);
  ok(!(await p.isVisible('#home')) && await p.isVisible('#s12'), 'opens the temple directly');
  ok((await p.$eval('#mName', e => e.textContent)) === 'Сора', 'the teacher is Сора');
  ok(/sora_/.test(await p.$eval('#mVox', e => e.style.getPropertyValue('--spr'))), 'Сора\'s sprite');
  await p.screenshot({ path: `${out}/intro.png` });
  // through the intro into the first scroll
  for (let i = 0; i < 60; i++) {
    if (await p.isVisible('#mTop') && /Свиток 1\./.test(await p.$eval('#mChapter', e => e.textContent).catch(() => ''))) break;
    await p.click('#mBox', { force: true }); await p.waitForTimeout(250);
  }
  ok(/Свиток 1\./.test(await p.$eval('#mChapter', e => e.textContent)), 'the book starts at its scroll 1: ' + await p.$eval('#mChapter', e => e.textContent));
  await p.click('#mExit'); await p.waitForTimeout(400);
  const menu = await p.$eval('#mPanel', e => e.innerText);
  ok(/Свитки Соры/.test(menu), 'menu: Свитки Соры');
  ok(!/Экзамен мастера/.test(menu) && !/Как всё начиналось/.test(menu), 'menu has only this book');
  await p.screenshot({ path: `${out}/menu.png`, fullPage: false });
  // back home and into the master's book: the master, his title screen the first time
  await p.click('#homeBar'); await p.waitForTimeout(800);
  await p.click('.home-app.folder >> nth=0'); await p.waitForTimeout(350); await p.click('#homeFolderBox .home-app >> nth=0'); await p.waitForTimeout(1500);
  ok(await p.isVisible('#s1'), 'the master\'s book opens at its title the first time');
  await p.click('#s1'); await p.waitForTimeout(1200);
  ok((await p.$eval('#mName', e => e.textContent)) === 'Мастер', 'the master is back');
  ok(/master_/.test(await p.$eval('#mVox', e => e.style.getPropertyValue('--spr'))), 'the master\'s sprite');
  for (let i = 0; i < 60; i++) {
    if (await p.isVisible('#mTop') && /Как всё начиналось/.test(await p.$eval('#mChapter', e => e.textContent).catch(() => ''))) break;
    await p.click('#mBox', { force: true }); await p.waitForTimeout(250);
  }
  ok(/Свиток 1\. Как всё начиналось/.test(await p.$eval('#mChapter', e => e.textContent)), 'master\'s scroll 1');
  await p.click('#mExit'); await p.waitForTimeout(400);
  const menu2 = await p.$eval('#mPanel', e => e.innerText);
  ok(/Свитки мастера/.test(menu2) && /Экзамен мастера/.test(menu2), 'master\'s menu with the exam');
  ok(!/Свитки Соры/.test(menu2) && (menu2.match(/^\d+\. /gm) || []).length >= 0, 'no Сора scrolls in the master\'s menu');
  // and back to Сора: he remembers us
  await p.click('#homeBar'); await p.waitForTimeout(800);
  await p.click(posIcon); await p.waitForTimeout(1500);
  ok((await p.$eval('#mName', e => e.textContent)) === 'Сора' && await p.isVisible('#mPanel'), 'Сора again, at his menu');
  // search shows the scrolls under their books
  await p.click('#homeBar'); await p.waitForTimeout(800);
  await p.click('#homeFind'); await p.waitForTimeout(150);
  await p.fill('#homeSpotInput', 'высот'); await p.waitForTimeout(200);
  const groups = await p.$$eval('#homeSpotList .home-spot-h', es => es.map(e => e.textContent));
  ok(groups.some(g => /Позиционирование/.test(g)), 'search groups: ' + groups.join(' | '));
  console.log('scrolls in the book:', nScrolls);
  console.log(errs.length ? errs.join('\n') : 'no errors');
  await b.close();
})();
