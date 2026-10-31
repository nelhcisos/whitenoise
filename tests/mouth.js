// Patients without photos: the note and the mouth at arrival, and the straight teeth at the end.
const { chromium } = require('playwright');
const out = process.argv[2];
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const errs = [];
  const seen = new Set();
  for (let run = 0; run < 7 && seen.size < 5; run++) {
    const p = await b.newPage({ viewport: { width: 390, height: 844 } });
    p.on('pageerror', e => errs.push(e.message));
    await p.goto('file:///home/user/whitenoise/index.html'); await p.waitForTimeout(300);
    await p.click('.home-app'); await p.waitForTimeout(1300);
    await p.click('#latestBtn'); await p.waitForTimeout(400);
    await p.click('#s2'); await p.waitForTimeout(200);
    await p.click('#assistBtn'); await p.waitForTimeout(700);
    const note = await p.$eval('#patientLine', e => e.textContent);
    if (!seen.has(note)) {
      seen.add(note);
      await p.$eval('#mouth', e => e.scrollIntoView());
      await p.locator('#mouth').screenshot({ path: `${out}/arrive_${seen.size}.png` });
      console.log(seen.size, note);
    }
    if (run === 0) {
      // play this patient to the end and catch the straight teeth
      for (let i = 0; i < 60; i++) {
        const want = await p.evaluate(() => window.__clinic.want());
        if (!want) break;
        await p.click('#tray .tool[data-id="suction"]'); await p.waitForTimeout(80);
        await p.click(`#tray .tool[data-id="${want}"]`); await p.waitForTimeout(800);
      }
      await p.waitForTimeout(4200);
      console.log('end line:', await p.$eval('#patientLine', e => e.textContent));
      await p.locator('#mouth').screenshot({ path: `${out}/straight.png` });
      await p.waitForTimeout(3200);
      console.log('after:', await p.$$eval('section.screen', ss => ss.filter(s => !s.hidden).map(s => s.id).join(',')));
    }
    await p.close();
  }
  console.log(errs.length ? errs.join('\n') : 'no errors');
  await b.close();
})();
