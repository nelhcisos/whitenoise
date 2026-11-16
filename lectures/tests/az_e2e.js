// The aligners book (no teacher) from the icon to the end: all scrolls, no practice, no days.
const { chromium } = require('playwright');
const out = process.argv[2];
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = [];
  let where = 'start';
  p.on('pageerror', e => errs.push('pageerror @' + where + ': ' + (e.stack || e.message).split('\n').slice(0, 4).join(' | ')));
  p.on('requestfailed', r => errs.push('requestfailed: ' + r.url()));
  await p.addInitScript(() => { if (!sessionStorage.getItem('k')) { try { localStorage.clear(); } catch (e) {} sessionStorage.setItem('k', '1'); } });
  await p.addInitScript(() => document.addEventListener('DOMContentLoaded', () => { const st = document.createElement('style'); st.textContent = 'body.woozy .screen { animation: none !important; } .eyelids { display: none !important; }'; document.head.append(st); }));
  await p.goto('file:///home/user/whitenoise/index.html');
  await p.waitForTimeout(500);
  await p.screenshot({ path: `${out}/az_home.png` });
  await p.click('.home-app[data-book="az"]');
  await p.waitForTimeout(1500);
  await p.screenshot({ path: `${out}/az_intro.png` });
  console.log('sprite hidden:', !(await p.isVisible('#mWalker')), '| name hidden:', !(await p.isVisible('#mName')));
  const vis = () => p.$$eval('section.screen', ss => ss.filter(s => !s.hidden).map(s => s.id).join(','));
  const log = [], titles = new Set(), secs = new Set();
  let last = '', shots = 0, practices = 0, dayEnds = 0, results = 0;
  for (let step = 0; step < 5000; step++) {
    const v = await vis();
    if (v !== last) { log.push(v); last = v; }
    where = v + ' #' + step;
    if (v === 's12') {
      const ch = await p.$eval('#mChapter', e => e.textContent).catch(() => '');
      if (ch) { titles.add(ch.split(' · ')[0]); if (ch.includes(' · ')) secs.add(ch); }
      const asks = (await p.isVisible('#mChoices')) && !(await p.$eval('#mStage', e => e.classList.contains('answered')));
      if (/Свиток 3\./.test(ch) && await p.isVisible('#mBoard') && ((shots === 0 && !asks) || (shots === 1 && asks))) {
        shots++;
        await p.waitForTimeout(700);
        await p.screenshot({ path: `${out}/az_board_${shots}.png` });
      }
      if (await p.isVisible('#mMeme')) { await p.click('#mMemeOk'); continue; }
      if (await p.isVisible('#mAd')) { await p.waitForTimeout(5200); await p.click('#mAdSkip'); continue; }
      if (await p.isVisible('#mPanel')) {
        const txt = await p.$eval('#mPanel', e => e.innerText);
        if (/Практика:/.test(txt)) { practices++; await p.click('.m-panel .m-item:has-text("Практика")'); continue; }
        if (/Закончить день/.test(txt)) { await p.click('.m-panel .m-item:has-text("Закончить день")'); continue; }
        if (/Элайнеры от А до Я/.test(txt)) {
          log.push('MENU ' + (await p.$eval('.m-h', e => e.textContent)));
          await p.screenshot({ path: `${out}/az_menu_end.png` });
          break;
        }
        if (/Практика:|Закончить день/.test(txt)) errs.push('a practice or a day end in a book without a teacher: ' + txt.slice(0, 80));
        if (/Следующий свиток/.test(txt)) { if (!results++) await p.screenshot({ path: `${out}/az_results.png` }); await p.click('.m-panel .m-item:has-text("Следующий свиток")'); continue; }
        if (/К свиткам/.test(txt)) { results++; await p.click('.m-panel .m-item:has-text("К свиткам")'); continue; }
        await p.click('.m-panel .m-item >> nth=0');
        continue;
      }
      const asking = (await p.isVisible('#mChoices')) && !(await p.$eval('#mStage', e => e.classList.contains('answered')));
      if (asking) {
        const cls = await p.$eval('#mChoices', e => e.className);
        if (cls.includes('mt')) {
          for (let i = 0; i < 8; i++) { const r = await p.$$('#mChoices .m-r:not(.linked)'); if (!r.length) break; await r[0].click(); }
          await p.click('#mChoices .m-mini.go');
        } else {
          const btns = await p.$$('#mChoices button.m-opt');
          if (cls.includes('ord')) { for (const bt of btns) await bt.click(); } else await btns[0].click();
        }
        await p.waitForTimeout(40);
      }
      await p.click('#mBox', { timeout: 3000 }).catch(() => {});
      await p.waitForTimeout(25);
      continue;
    }
    if (v === 's2') { await p.click('#s2'); await p.waitForTimeout(100); if (await p.isVisible('#assistBtn')) await p.click('#assistBtn'); continue; }
    if (v === 's3') {
      const want = await p.evaluate(() => window.__clinic.want());
      if (want) {
        await p.click('#tray .tool[data-id="suction"]');
        await p.waitForTimeout(120);
        const btn = await p.$(`#tray .tool[data-id="${want}"]`);
        if (btn) await btn.click();
      }
      await p.waitForTimeout(700);
      continue;
    }
    if (v === 's4') { await p.click('#nextBtn'); await p.waitForTimeout(300); continue; }
    if (v === 's13') {
      const title = await p.$eval('#dayTitle', e => e.textContent);
      if (/КОНЕЦ СМЕНЫ/.test(title)) dayEnds++;
      await p.click('#dayBtns button', { force: true });
      await p.waitForTimeout(120);
      continue;
    }
    if (v === 's10') { await p.click('#payBtns button'); await p.waitForTimeout(150); continue; }
    if (v === 's11') {
      if (await p.isVisible('#vnChoices')) { await p.click('#vnChoices button >> nth=0'); continue; }
      await p.click('#vnBox'); await p.waitForTimeout(120);
      continue;
    }
    if (v === 's9') { await p.click('#bossNext'); await p.waitForTimeout(250); continue; }
    await p.waitForTimeout(200);
  }
  console.log('screens:', log.join(' > ').slice(0, 600));
  console.log('scroll titles seen:', [...titles].filter(t => /^Свиток/.test(t)).join(' | '));
  console.log('subchapters seen:', secs.size, '| results:', results, '| practices:', practices, '| day ends:', dayEnds);
  console.log('saved:', await p.evaluate(() => localStorage.getItem('ortho-master-v2')));
  console.log(errs.length ? errs.slice(0, 10).join('\n') : 'no errors');
  await b.close();
})();
