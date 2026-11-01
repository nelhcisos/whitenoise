// The book's folder and the «Карта пациента» app: open, fill a card right and wrong, back home, the book still opens.
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
  ok((await p.$$('.home-app.folder')).length === 1, 'one folder tile');
  ok((await p.$eval('.home-app.folder .home-badge', e => e.textContent)) === String(17 + 8), 'badge: 17 scrolls + 8 cards');
  await p.screenshot({ path: `${out}/home.png` });
  await p.click('.home-app.folder'); await p.waitForTimeout(400);
  ok(await p.isVisible('#homeFolder'), 'folder opens');
  ok((await p.$$eval('#homeFolderBox .home-name', es => es.map(e => e.textContent))).join('|') === 'Кондилография|Карта пациента', 'folder: book and card app');
  await p.screenshot({ path: `${out}/folder.png` });
  await p.keyboard.press('Escape'); await p.waitForTimeout(150);
  ok(!(await p.isVisible('#homeFolder')), 'Escape closes the folder');
  await p.click('.home-app.folder'); await p.waitForTimeout(300);
  await p.click('#homeFolderBox .home-app >> nth=1'); await p.waitForTimeout(700);
  ok(await p.isVisible('#cardApp') && await p.evaluate(() => window.__home.cards()), 'card app opens');
  ok((await p.$$('#cardBody .ca-row')).length === 8, 'eight patient cards');
  await p.screenshot({ path: `${out}/list.png` });
  // card 1: answer everything right (option text equals the data's first option)
  await p.click('#cardBody .ca-row >> nth=0'); await p.waitForTimeout(300);
  ok((await p.$eval('#cardNavTitle', e => e.textContent)) === 'Анна К.', 'card 1 opens');
  ok(await p.$eval('.ca-sign', b => b.disabled), 'sign disabled until all filled');
  const rights = ['Changing character', 'Стадия 1', 'У точки перегиба, на 2–3 мм впереди'];
  for (const t of rights) await p.click(`.ca-opt:has-text("${t}")`);
  await p.screenshot({ path: `${out}/card_filled.png`, fullPage: false });
  await p.click('.ca-sign'); await p.waitForTimeout(500);
  ok(/Верно 3 из 3/.test(await p.$eval('.ca-concl', e => e.textContent)), 'all right: 3 of 3');
  ok((await p.$$('.ca-opt.wrong')).length === 0 && (await p.$$('.ca-opt.right')).length === 3, 'right answers marked');
  await p.screenshot({ path: `${out}/card_signed.png` });
  // next card: a wrong answer shows its reason
  await p.click('.ca-concl .ca-sign'); await p.waitForTimeout(300);
  ok((await p.$eval('#cardNavTitle', e => e.textContent)) === 'Игорь М.', 'next card');
  await p.click('.ca-opt:has-text("ΔY-shift")'); await p.click('.ca-opt:has-text("Стадия 2")'); await p.click('.ca-opt:has-text("Сразу перед щелчком закрывания")');
  await p.click('.ca-sign'); await p.waitForTimeout(400);
  ok(/Верно 2 из 3/.test(await p.$eval('.ca-concl', e => e.textContent)), 'one wrong: 2 of 3');
  ok(/Нет: ΔY-shift/.test(await p.$eval('.ca-fb.bad', e => e.textContent)), 'wrong answer explained');
  await p.screenshot({ path: `${out}/card_wrong.png` });
  await p.click('#cardBack'); await p.waitForTimeout(200);
  ok((await p.$$eval('.ca-st', es => es.map(e => e.textContent))).slice(0, 2).join(',') === '3/3,2/3', 'list shows results');
  // back home: the badge dropped by two
  await p.click('#homeBar'); await p.waitForTimeout(700);
  ok(await p.evaluate(() => window.__home.open()) && !(await p.isVisible('#cardApp')), 'home bar: back home');
  ok((await p.$eval('.home-app.folder .home-badge', e => e.textContent)) === '23', 'badge now 23');
  ok(/Карты 2\/8/.test(await p.$eval('.home-fstat', e => e.textContent)), 'tile shows Карты 2/8');
  // saved across reloads; the day log counts the cards
  await p.reload(); await p.waitForTimeout(600);
  ok(/Карты 2\/8/.test(await p.$eval('.home-fstat', e => e.textContent)), 'cards saved after reload');
  ok(/Карта пациента: Анна/.test(await p.evaluate(() => localStorage.getItem('ortho-days-v1'))), 'card logged in the day');
  // the book still opens from the folder
  await p.click('.home-app.folder'); await p.waitForTimeout(300);
  await p.click('#homeFolderBox .home-app >> nth=0'); await p.waitForTimeout(1500);
  ok(!(await p.isVisible('#home')) && await p.isVisible('#s1'), 'book opens from the folder');
  await p.click('#homeBar'); await p.waitForTimeout(800);
  ok(await p.evaluate(() => window.__home.open()), 'back home from the book');
  // search finds the card app
  await p.click('#homeFind'); await p.waitForTimeout(150);
  await p.fill('#homeSpotInput', 'карта'); await p.waitForTimeout(150);
  await p.click('#homeSpotList .home-spot-row:has-text("Карта пациента")'); await p.waitForTimeout(700);
  ok(await p.isVisible('#cardApp'), 'search opens the card app');
  await p.screenshot({ path: `${out}/desktop_dummy.png` });
  console.log(errs.length ? errs.join('\n') : 'no errors');
  await b.close();
})();
