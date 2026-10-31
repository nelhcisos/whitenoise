// End to end: from the title through all 8 scrolls, every practice, every end of day and morning, to the exam.
const { chromium } = require('playwright');
const [,, out] = process.argv;
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const errs = [];
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  p.on('pageerror', e => errs.push('pageerror: ' + e.message));
  p.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
  await p.addInitScript(() => { if (!sessionStorage.getItem('k')) { try { localStorage.clear(); } catch (e) {} sessionStorage.setItem('k', '1'); } });
  await p.addInitScript(() => document.addEventListener('DOMContentLoaded', () => { const st = document.createElement('style'); st.textContent = 'body.woozy .screen { animation: none !important; } .eyelids { display: none !important; }'; document.head.append(st); }));
  await p.goto('file:///home/user/whitenoise/index.html');
  await p.waitForTimeout(300); if (await p.isVisible('#home')) { await p.click('.home-app'); await p.waitForTimeout(1300); }
  await p.waitForTimeout(500);
  const vis = () => p.$$eval('section.screen', ss => ss.filter(s => !s.hidden).map(s => s.id).join(','));
  const visible = sel => p.isVisible(sel);
  const log = [];
  let last = '', scrolls = 0, practices = 0, dayEnds = 0, mornings = [];
  await p.click('#s1');
  for (let step = 0; step < 6000; step++) {
    const v = await vis();
    if (v !== last) { log.push(v); last = v; }
    if (v === 's12') {
      if (await visible('#mMeme')) { await p.click('#mMemeOk'); continue; }
      if (await visible('#mAd')) { await p.waitForTimeout(5200); await p.click('#mAdSkip'); continue; }
      if (await visible('#mPanel')) {
        const txt = await p.$eval('#mPanel', e => e.innerText);
        if (/Практика:/.test(txt)) { practices++; await p.click('.m-panel .m-item:has-text("Практика")'); continue; }
        if (/Закончить день/.test(txt)) { await p.click('.m-panel .m-item:has-text("Закончить день")'); continue; }
        if (/пройден/.test(txt)) { scrolls++; }
        if (/Свитки мастера/.test(txt) && !/Свиток \d пройден/.test(txt)) {
          // the menu: done when every scroll is done
          const header = await p.$eval('.m-h', e => e.textContent);
          log.push('MENU ' + header);
          break;
        }
        if (/Следующий свиток/.test(txt)) { await p.click('.m-panel .m-item:has-text("Следующий свиток")'); continue; }
        await p.click('.m-panel .m-item >> nth=0'); continue;
      }
      const asking = (await visible('#mChoices')) && !(await p.$eval('#mStage', e => e.classList.contains('answered')));
      if (asking) {
        const cls = await p.$eval('#mChoices', e => e.className);
        if (cls.includes('mt')) { for (let i = 0; i < 8; i++) { const r = await p.$$('#mChoices .m-r:not(.linked)'); if (!r.length) break; await r[0].click(); } await p.click('#mChoices .m-mini.go'); }
        else { const btns = await p.$$('#mChoices button.m-opt'); if (cls.includes('ord')) { for (const bt of btns) await bt.click(); } else await btns[0].click(); }
        await p.waitForTimeout(40);
      }
      await p.click('#mBox', { timeout: 3000 }).catch(() => {});
      await p.waitForTimeout(25);
      continue;
    }
    if (v === 's2') { await p.click('#s2'); await p.waitForTimeout(100); if (await visible('#assistBtn')) await p.click('#assistBtn'); continue; }
    if (v === 's3') {
      const want = await p.evaluate(() => window.__clinic.want());
      if (want) { await p.click('#tray .tool[data-id="suction"]'); await p.waitForTimeout(120); const btn = await p.$(`#tray .tool[data-id="${want}"]`); if (btn) await btn.click(); }
      await p.waitForTimeout(700);
      continue;
    }
    if (v === 's4') { await p.click('#nextBtn'); await p.waitForTimeout(300); continue; }
    if (v === 's5') {
      const id = await p.evaluate(() => window.__clinic.tool());
      if (id && await p.$eval('#giveBtn', b => b.disabled) === true) { await p.evaluate(x => window.__clinic.select(x), id); }
      if (!(await p.$eval('#giveBtn', b => b.disabled))) await p.click('#giveBtn');
      await p.waitForTimeout(900);
      continue;
    }
    if (v === 's7') {
      if (await visible('#thanksChoices')) await p.click('#thanksChoices button >> nth=0');
      else if (await visible('#meetBtn')) await p.click('#meetBtn');
      await p.waitForTimeout(200);
      continue;
    }
    if (v === 's8') {
      if (await visible('#aaAgainBtn')) { await p.click('#aaAgainBtn'); continue; }
      if (await visible('#aaBtn')) { await p.click('#aaBtn'); await p.waitForTimeout(150); continue; }
      const btns = await p.$$('#causeChoices button');
      if (btns.length) await btns[0].click({ force: true });
      await p.waitForTimeout(80);
      continue;
    }
    if (v === 's13') {
      const title = await p.$eval('#dayTitle', e => e.textContent);
      if (/КОНЕЦ СМЕНЫ/.test(title)) { dayEnds++; log.push(title + ' | ' + (await p.$eval('#dayRecap', e => e.innerText.replace(/\s+/g, ' '))).slice(0, 220)); }
      if (/ЗАРПЛАТА/.test(title)) log.push('PAY ' + (await p.$eval('#dayLine', e => e.textContent)).slice(0, 90));
      await p.click('#dayBtns button', { force: true }); await p.waitForTimeout(120);
      continue;
    }
    if (v === 's10') { if (!mornings.includes('lesson')) mornings.push('lesson'); await p.click('#payBtns button'); await p.waitForTimeout(150); continue; }
    if (v === 's11') {
      if (!mornings.includes('novel')) mornings.push('novel');
      if (await visible('#vnChoices')) { await p.click('#vnChoices button >> nth=0'); await p.waitForTimeout(150); continue; }
      await p.click('#vnBox'); await p.waitForTimeout(120); continue;
    }
    if (v === 's9') { if (!mornings.includes('boss')) mornings.push('boss'); await p.click('#bossNext'); await p.waitForTimeout(250); continue; }
    if (v === 's6') { if (await visible('#leaveBtn')) await p.click('#leaveBtn'); await p.waitForTimeout(500); continue; }
    await p.waitForTimeout(200);
  }
  await p.screenshot({ path: `${out}/e2e_end.png` });
  console.log('screens:', log.filter(x => !x.startsWith('КОНЕЦ') && !x.startsWith('PAY')).join(' > ').slice(0, 900));
  console.log(log.filter(x => x.startsWith('КОНЕЦ') || x.startsWith('PAY')).join('\n'));
  console.log('scroll results seen:', scrolls, '| practices:', practices, '| day ends:', dayEnds, '| mornings:', mornings.join(','));
  console.log('saved:', await p.evaluate(() => localStorage.getItem('ortho-master-v2')));
  console.log('days:', await p.evaluate(() => localStorage.getItem('ortho-days-v1')));
  console.log(errs.length ? errs.slice(0, 10).join('\n') : 'no errors');
  await b.close();
})();
