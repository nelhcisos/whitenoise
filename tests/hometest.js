// The home screen: books as apps. Launch, keys guarded, back home, the game keeps its place, swipe, reduced motion.
const { chromium } = require('playwright');
const out = process.argv[2];
const ok = (c, m) => console.log((c ? 'PASS ' : 'FAIL ') + m);
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const errs = [];
  const page = async (opts = {}) => {
    const p = await b.newPage(Object.assign({ viewport: { width: 390, height: 844 } }, opts));
    p.on('pageerror', e => errs.push('pageerror: ' + (e.stack || e.message).split('\n').slice(0, 3).join(' | ')));
    p.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
    p.on('requestfailed', r => errs.push('requestfailed: ' + r.url()));
    await p.addInitScript(() => { if (!sessionStorage.getItem('k')) { try { localStorage.clear(); } catch (e) {} sessionStorage.setItem('k', '1'); } });
    await p.goto('file:///home/user/whitenoise/index.html');
    await p.waitForTimeout(700);
    return p;
  };
  const vis = p => p.$$eval('section.screen', ss => ss.filter(s => !s.hidden).map(s => s.id).join(','));
  let p = await page();
  ok(await p.isVisible('#home'), 'home screen is up on start');
  ok(await p.evaluate(() => window.__home.open()), 'home state is open');
  ok((await p.$eval('.home-name', e => e.textContent)) === 'Кондилография', 'one app: Кондилография');
  ok((await p.$$('.home-app')).length === 1, 'exactly one app');
  ok((await p.$eval('.home-badge', e => e.textContent)) === '8', 'badge: 8 unread scrolls');
  ok(await p.$eval('#s1', e => e.inert), 'the game is inert under the home screen');
  await p.screenshot({ path: `${out}/home_phone.png` });
  // «Поиск»: Spotlight over the book
  await p.click('#homeFind'); await p.waitForTimeout(200);
  ok(await p.isVisible('#homeSpot'), 'search opens');
  ok(await p.evaluate(() => document.activeElement && document.activeElement.id === 'homeSpotInput'), 'search field has the focus');
  await p.screenshot({ path: `${out}/search_empty.png` });
  await p.keyboard.type('брукс'); await p.waitForTimeout(150);
  const t1 = await p.$$eval('#homeSpotList .home-spot-t', es => es.map(e => e.textContent));
  ok(t1.some(t => /Бруксизм/.test(t)), 'search: бруксизм finds the term (' + t1.slice(0, 3).join(' | ') + ')');
  ok(await p.$eval('#homeSpotList', e => !!e.querySelector('mark')), 'search: the match is highlighted');
  await p.screenshot({ path: `${out}/search_brux.png` });
  const row = await p.$('#homeSpotList .home-spot-group:last-of-type .home-spot-row');
  await row.click(); await p.waitForTimeout(100);
  ok(await row.evaluate(e => e.classList.contains('open')), 'a term opens to its full definition');
  await p.fill('#homeSpotInput', 'гнатолог'); await p.waitForTimeout(150);
  const t2 = await p.$$eval('#homeSpotList .home-spot-t', es => es.map(e => e.textContent));
  ok(t2.some(t => /Гнатология/.test(t)), 'search: a scroll by its title (' + t2.slice(0, 3).join(' | ') + ')');
  await p.fill('#homeSpotInput', 'ёжик-в-тумане'); await p.waitForTimeout(150);
  ok(/Ничего не нашлось/.test(await p.$eval('#homeSpotList', e => e.textContent)), 'search: nothing found message');
  ok((await vis(p)) === 's1', 'typing in the search leaves the game alone');
  await p.keyboard.press('Escape'); await p.waitForTimeout(150);
  ok(!(await p.isVisible('#homeSpot')), 'Escape closes the search');
  await p.click('#homeFind'); await p.waitForTimeout(150);
  await p.click('.home-spot-chips button >> nth=0'); await p.waitForTimeout(150);
  ok((await p.$eval('#homeSpotInput', e => e.value)) === 'бруксизм', 'a hint chip fills the search');
  await p.click('#homeSpotCancel'); await p.waitForTimeout(150);
  ok(!(await p.isVisible('#homeSpot')), 'Отменить closes the search');
  // keys must not reach the game
  await p.evaluate(() => document.activeElement && document.activeElement.blur());
  await p.keyboard.press('Enter'); await p.keyboard.press('Space'); await p.waitForTimeout(400);
  ok((await vis(p)) === 's1', 'keys on the home screen leave the game alone (still s1)');
  // launch
  await p.click('.home-app');
  await p.waitForTimeout(180);
  await p.screenshot({ path: `${out}/launch_mid.png` });
  await p.waitForTimeout(500);
  ok((await p.$eval('#appSplashName', e => e.textContent)) === 'КОНДИЛОГРАФИЯ', 'launch screen shows the book title');
  await p.screenshot({ path: `${out}/launch_title.png` });
  await p.waitForTimeout(900);
  ok(!(await p.isVisible('#home')), 'home hidden after launch');
  ok(!(await p.isVisible('#appSplash')), 'launch screen gone');
  ok(await p.isVisible('#homeBar'), 'home bar shown in the book');
  ok((await vis(p)) === 's1' && !(await p.$eval('#s1', e => e.inert)), 'the title screen is live');
  await p.screenshot({ path: `${out}/title_with_bar.png` });
  // into the temple, then home, then back: the game keeps its place
  await p.click('#s1'); await p.waitForTimeout(900);
  ok((await vis(p)) === 's12', 'tap the title: the master');
  for (let i = 0; i < 3; i++) { await p.click('#mBox'); await p.waitForTimeout(150); }
  await p.screenshot({ path: `${out}/temple_with_bar.png` });
  await p.click('#homeBar');
  await p.waitForTimeout(150);
  await p.screenshot({ path: `${out}/back_mid.png` });
  await p.waitForTimeout(700);
  ok(await p.isVisible('#home') && await p.evaluate(() => window.__home.open()), 'home bar: back to the home screen');
  ok(!(await p.isVisible('#homeBar')), 'no home bar on the home screen');
  await p.click('.home-app'); await p.waitForTimeout(1500);
  ok((await vis(p)) === 's12', 'reopened: still at the master');
  // swipe up on the bar
  const bb = await p.$eval('#homeBar', e => { const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
  await p.mouse.move(bb.x, bb.y); await p.mouse.down(); await p.mouse.move(bb.x, bb.y - 20, { steps: 3 }); await p.mouse.move(bb.x, bb.y - 60, { steps: 4 }); await p.mouse.up();
  await p.waitForTimeout(900);
  ok(await p.evaluate(() => window.__home.open()), 'swipe up: home');
  // the master's menu has a way home, and "start over" comes straight back into the book
  await p.click('.home-app'); await p.waitForTimeout(1500);
  for (let i = 0; i < 30 && !(await p.isVisible('#mPanel')); i++) { await p.click('#mBox'); await p.waitForTimeout(120); }
  if (await p.isVisible('.m-panel .m-item:has-text("Практика")')) { console.log('note: a practice panel came first'); }
  await p.click('#mExit').catch(() => {});
  await p.waitForTimeout(400);
  ok(await p.isVisible('.m-panel .m-item:has-text("Главный экран")'), "master's menu: Главный экран item");
  await p.click('.m-panel .m-item:has-text("Главный экран")'); await p.waitForTimeout(900);
  ok(await p.evaluate(() => window.__home.open()), "menu item: home");
  await p.click('.home-app'); await p.waitForTimeout(1500);
  await p.click('.m-panel .m-item:has-text("Начать игру заново")'); await p.click('.m-panel .m-item:has-text("Точно")');
  await p.waitForTimeout(1500);
  ok(!(await p.isVisible('#home')) && (await vis(p)) === 's1', 'start over: back in the book at the title, no home screen');
  await p.close();
  // the book opens from a search result too
  p = await page();
  await p.click('#homeFind'); await p.waitForTimeout(150);
  await p.fill('#homeSpotInput', 'кондил'); await p.waitForTimeout(150);
  await p.click('#homeSpotList .home-spot-row >> nth=0'); await p.waitForTimeout(1500);
  ok(!(await p.isVisible('#home')) && (await vis(p)) === 's1', 'search result: the book opens');
  await p.close();
  // reduced motion: no animation, instant switch
  p = await page({ reducedMotion: 'reduce' });
  await p.click('.home-app'); await p.waitForTimeout(60);
  ok(!(await p.isVisible('#home')) && !(await p.isVisible('#appSplash')), 'reduced motion: opens at once');
  await p.click('#homeBar'); await p.waitForTimeout(60);
  ok(await p.isVisible('#home'), 'reduced motion: home at once');
  await p.close();
  // desktop
  p = await page({ viewport: { width: 1280, height: 800 } });
  await p.screenshot({ path: `${out}/home_desktop.png` });
  await p.click('.home-app'); await p.waitForTimeout(1300);
  await p.screenshot({ path: `${out}/title_desktop.png` });
  await p.close();
  console.log(errs.length ? errs.join('\n') : 'no errors');
  await b.close();
})();
