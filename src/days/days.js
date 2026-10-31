  // ---------- Days: the end of a shift, the barin's pay and the ride home ----------
  // A day ends after two of the master's scrolls, after four scored tasks, or when you ask for
  // another shift. Then: a quick recap, the barin names the pay, the ride home (how it goes depends on
  // how well you answered today) and a new day. A bad day leaves you sleepy the next morning.
  const DAY_KEY = "ortho-days-v1";
  const DAYS = { day: 1, wallet: 0, lastPay: 0, today: [] };
  try {
    const s = JSON.parse(localStorage.getItem(DAY_KEY) || "null");
    if (s && typeof s === "object") {
      if (Number.isInteger(s.day) && s.day >= 1 && s.day < 1000) DAYS.day = s.day;
      if (typeof s.wallet === "number" && s.wallet >= 0) DAYS.wallet = Math.round(s.wallet);
      if (typeof s.lastPay === "number" && s.lastPay >= 0) DAYS.lastPay = Math.round(s.lastPay);
      if (Array.isArray(s.today)) DAYS.today = s.today.filter(x => x && typeof x.title === "string").slice(0, 40);
    }
  } catch (e) { /* no storage: days start over */ }
  day = DAYS.day;
  const DAY_BASE = 10000;   // the barin pays for the day itself, on top of every right answer and action
  function dayStore() {
    try { localStorage.setItem(DAY_KEY, JSON.stringify({ day: DAYS.day, wallet: DAYS.wallet, lastPay: DAYS.lastPay, today: DAYS.today })); } catch (e) { /* ignore */ }
  }
  // kind: "shift" | "quiz" | "scroll" | "exam" (scored) or "story" (no score, listed once a day)
  function dayLog(kind, title, right = 0, total = 0, pay = 0) {
    if (kind === "story" && DAYS.today.some(x => x.title === title)) return;
    DAYS.today.push({ kind, title, right: Math.max(0, right | 0), total: Math.max(0, total | 0), pay: Math.max(0, Math.round(pay)) });
    dayStore();
  }
  function dayFull() {
    return DAYS.today.filter(x => x.kind === "scroll").length >= 2 || DAYS.today.filter(x => x.total > 0).length >= 4;
  }
  function dayStats(items) {
    const right = items.reduce((a, x) => a + x.right, 0), total = items.reduce((a, x) => a + x.total, 0);
    const pay = DAY_BASE + items.reduce((a, x) => a + x.pay, 0), pct = total ? right / total : null;
    return { right, total, pay, pct, mood: pct === null ? "normal" : pct >= 0.8 ? "good" : pct < 0.5 ? "bad" : "normal" };
  }

  // ----- sleepiness: the screen sways and blurs, the eyelids close now and then -----
  const lids = $("eyelids");
  const calmMotion = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  let sleepyBlink = 0, sleepyEnd = 0;
  function blinkOnce(ms = 1300) {
    if (calmMotion) return;
    lids.style.setProperty("--blink", `${ms}ms`);
    lids.classList.remove("blink"); void lids.offsetWidth; lids.classList.add("blink");
  }
  function sleepy(level, forMs) {   // 0 — awake, 1 — a bit sleepy, 2 — badly sleep-deprived
    clearInterval(sleepyBlink); clearTimeout(sleepyEnd);
    document.body.classList.toggle("woozy", level > 0);
    document.body.classList.toggle("hard", level === 2);
    if (!level) return;
    sleepyBlink = setInterval(() => blinkOnce(level === 2 ? 1600 : 1100), level === 2 ? 3600 : 11000);
    if (forMs) sleepyEnd = setTimeout(() => sleepy(0), forMs);
  }

  // ----- pixel scenes for the end of the day (160x120 canvas) -----
  const dayCtx = $("dayScene").getContext("2d");
  const R = (c, col, x, y, w, h) => { c.fillStyle = col; c.fillRect(Math.round(x), Math.round(y), w, h); };
  const hash = n => { const x = Math.sin(n * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
  // a strip of things scrolling to the left: draw(x, n) for each item n
  function strip(x0, w, T, speed, W, draw) {
    const off = T * speed, first = Math.floor(off / W) - 1;
    for (let n = first; n * W - off < w + W; n++) draw(Math.round(x0 + n * W - off), n);
  }
  function pxText(c, s, x, y, col, size = 6, align = "left") {
    c.fillStyle = col; c.font = `${size}px "Press Start 2P", monospace`; c.textAlign = align; c.textBaseline = "top";
    c.fillText(s, x, y); c.textAlign = "left";
  }
  // The hero, facing us. o: { pose: "sit" | "stand", eyes: "open" | "half" | "closed" | "wide", mouth: "smile" | "flat" | "o" | "yawn", nod, bags }
  function drawHero(c, x, y, o = {}) {
    const SK = "#f0c49a", SKd = "#d9a77a", HR = "#3a2618", TL = "#1fa9b8", TLd = "#127c88", PN = "#2a3550", PNd = "#1d2540", SH = "#151515", K = "#1a1418";
    const hx = x, hy = y + (o.nod || 0);
    R(c, HR, hx + 3, hy, 14, 4); R(c, HR, hx + 2, hy + 2, 16, 5); R(c, HR, hx + 5, hy - 1, 3, 1); R(c, HR, hx + 11, hy - 1, 4, 1);
    R(c, SK, hx + 4, hy + 4, 12, 10); R(c, SKd, hx + 4, hy + 12, 12, 2);
    R(c, SK, hx + 3, hy + 7, 1, 3); R(c, SK, hx + 16, hy + 7, 1, 3);
    R(c, HR, hx + 4, hy + 4, 12, 2); R(c, HR, hx + 4, hy + 6, 3, 1); R(c, HR, hx + 13, hy + 6, 3, 1);
    const e = o.eyes || "open";
    if (e === "open") { R(c, K, hx + 6, hy + 8, 2, 2); R(c, K, hx + 12, hy + 8, 2, 2); R(c, "#fff", hx + 6, hy + 8, 1, 1); R(c, "#fff", hx + 12, hy + 8, 1, 1); }
    else if (e === "half") { R(c, SKd, hx + 5, hy + 8, 4, 1); R(c, SKd, hx + 11, hy + 8, 4, 1); R(c, K, hx + 6, hy + 9, 2, 1); R(c, K, hx + 12, hy + 9, 2, 1); }
    else if (e === "closed") { R(c, K, hx + 5, hy + 9, 3, 1); R(c, K, hx + 12, hy + 9, 3, 1); }
    else if (e === "wide") { R(c, "#fff", hx + 5, hy + 7, 3, 3); R(c, "#fff", hx + 12, hy + 7, 3, 3); R(c, K, hx + 6, hy + 8, 1, 1); R(c, K, hx + 13, hy + 8, 1, 1); }
    if (o.bags) { R(c, "#a77a9a", hx + 5, hy + 10, 3, 1); R(c, "#a77a9a", hx + 12, hy + 10, 3, 1); }
    const m = o.mouth || "flat";
    if (m === "smile") { R(c, K, hx + 8, hy + 12, 4, 1); R(c, K, hx + 7, hy + 11, 1, 1); R(c, K, hx + 12, hy + 11, 1, 1); }
    else if (m === "flat") R(c, K, hx + 8, hy + 11, 4, 1);
    else if (m === "o") { R(c, K, hx + 9, hy + 10, 2, 3); }
    else if (m === "yawn") { R(c, K, hx + 8, hy + 10, 4, 4); R(c, "#c0505a", hx + 9, hy + 12, 2, 2); }
    R(c, SKd, x + 8, y + 14, 4, 2);
    R(c, TL, x + 2, y + 16, 16, 13); R(c, TLd, x + 2, y + 16, 2, 13); R(c, TLd, x + 16, y + 16, 2, 13);
    R(c, SKd, x + 8, y + 16, 4, 2); R(c, SKd, x + 9, y + 18, 2, 1);
    R(c, "#e8eef2", x + 13, y + 19, 3, 1);   // a pen in the pocket
    R(c, TL, x, y + 17, 2, 9); R(c, TL, x + 18, y + 17, 2, 9); R(c, SK, x, y + 26, 2, 2); R(c, SK, x + 18, y + 26, 2, 2);
    if ((o.pose || "sit") === "sit") {
      // knees toward us, shins down to the floor, a backpack on the lap
      R(c, PN, x + 1, y + 29, 8, 6); R(c, PN, x + 11, y + 29, 8, 6);
      R(c, "#3a4870", x + 2, y + 33, 6, 2); R(c, "#3a4870", x + 12, y + 33, 6, 2);
      R(c, PNd, x + 3, y + 35, 5, 6); R(c, PNd, x + 12, y + 35, 5, 6);
      R(c, SH, x + 2, y + 41, 7, 2); R(c, SH, x + 11, y + 41, 7, 2);
      if (!o.noBag) {
        R(c, "#8a3a3a", x + 2, y + 24, 16, 9); R(c, "#6a2a2a", x + 2, y + 31, 16, 2);
        R(c, "#a85050", x + 4, y + 26, 12, 3); R(c, "#d9b23a", x + 9, y + 27, 2, 1);
        R(c, SK, x + 1, y + 26, 3, 2); R(c, SK, x + 16, y + 26, 3, 2);   // hands on the bag
      }
    } else {
      R(c, PN, x + 3, y + 29, 6, 14); R(c, PN, x + 11, y + 29, 6, 14);
      R(c, SH, x + 2, y + 43, 7, 2); R(c, SH, x + 11, y + 43, 7, 2);
    }
  }
  function zzz(c, x, y, t, col = "#e8eef7") {
    for (let i = 0; i < 3; i++) {
      const p = (t * 0.6 + i / 3) % 1;
      pxText(c, "z", x + i * 5 + p * 6, y - p * 18, col, 6 + i);
    }
  }
  // what is outside the train window
  function drawOutside(c, x0, y0, w, h, T, kind) {
    const bottom = y0 + h;
    if (kind === "city" || kind === "dark") {
      R(c, kind === "dark" ? "#05060c" : "#0b1530", x0, y0, w, h);
      if (kind === "dark") {
        strip(x0, w, T, 140, 70, (x, n) => { if (hash(n) > 0.4) R(c, "#1c2340", x, y0 + 8 + hash(n + 3) * 24, 30, 2); });
        return;
      }
      R(c, "#14204a", x0, bottom - 18, w, 18);
      for (let i = 0; i < 12; i++) if (hash(i + 90) > 0.3) R(c, "#c8d4ff", x0 + hash(i) * w, y0 + 2 + hash(i + 40) * 10, 1, 1);
      strip(x0, w, T, 8, 14, (x, n) => {
        const bh = 12 + Math.floor(hash(n) * 20);
        R(c, "#1a2550", x, bottom - bh, 12, bh);
        for (let yy = bottom - bh + 3; yy < bottom - 2; yy += 4) for (let xx = 2; xx < 11; xx += 3)
          if (hash(n * 13 + yy * 7 + xx) > 0.58) R(c, "#ffd86b", x + xx, yy, 1, 2);
      });
      strip(x0, w, T, 26, 22, (x, n) => {
        const bh = 8 + Math.floor(hash(n + 50) * 16);
        R(c, "#0c1229", x, bottom - bh, 18, bh);
        for (let yy = bottom - bh + 3; yy < bottom - 2; yy += 5) if (hash(n * 3 + yy) > 0.6) R(c, "#ffe9a6", x + 4 + (yy % 3) * 4, yy, 2, 2);
      });
      strip(x0, w, T, 110, 52, x => { R(c, "#04060d", x, y0, 3, h); R(c, "#04060d", x - 20, y0 + 5, 60, 1); });
    } else if (kind === "mountains" || kind === "molars" || kind === "aurora") {
      const bands = ["#24184a", "#3d2560", "#6a3466", "#b0545e", "#e38a58"];
      bands.forEach((col, i) => R(c, col, x0, y0 + i * (h / 5), w, Math.ceil(h / 5)));
      R(c, "#f6efd8", x0 + w - 26, y0 + 5, 7, 7); R(c, "#f6efd8", x0 + w - 27, y0 + 6, 9, 5);
      if (kind === "aurora") {
        for (let i = 0; i < w; i += 2) {
          const yy = y0 + 6 + Math.sin(i / 11 + T * 1.3) * 4 + Math.sin(i / 5 + T * 2.1) * 2;
          R(c, "rgba(110, 255, 170, 0.55)", x0 + i, yy, 2, 6 + Math.sin(i / 7 + T) * 3);
          R(c, "rgba(140, 120, 255, 0.35)", x0 + i, yy + 8, 2, 4);
        }
      }
      if (kind === "molars") {
        // the mountains are molars: crowns with cusps, one is a gold crown
        strip(x0, w, T, 6, 40, (x, n) => {
          const base = bottom - 6, cw = 30, ch = 14 + Math.floor(hash(n) * 8), gold = hash(n + 7) > 0.82;
          const col = gold ? "#ffcc33" : "#f4efe0", sh = gold ? "#c8941a" : "#cfc6b0";
          R(c, col, x, base - ch, cw, ch);
          R(c, col, x + 2, base - ch - 4, 8, 4); R(c, col, x + 12, base - ch - 5, 7, 5); R(c, col, x + 21, base - ch - 4, 8, 4);
          R(c, sh, x + cw - 4, base - ch - 3, 4, ch + 3);
          R(c, sh, x + 10, base - ch - 1, 1, 4); R(c, sh, x + 19, base - ch - 1, 1, 4);
        });
      } else {
        strip(x0, w, T, 5, 44, (x, n) => {
          const ph = 18 + Math.floor(hash(n) * 12), half = 22;
          for (let dx = -half; dx <= half; dx++) {
            const hh = Math.max(0, Math.round(ph * (1 - Math.abs(dx) / half)));
            if (!hh) continue;
            R(c, "#4b3f6b", x + dx, bottom - hh, 1, hh);
            const snow = Math.round(hh * 0.3);
            if (hh > ph * 0.55) R(c, "#eef0f6", x + dx, bottom - hh, 1, Math.max(1, snow - Math.round(ph * 0.55 * 0.3)));
          }
        });
      }
      R(c, "#22183a", x0, bottom - 6, w, 6);
      strip(x0, w, T, 46, 13, (x, n) => {
        const th = 7 + Math.floor(hash(n + 30) * 8);
        for (let i = 0; i < th; i++) R(c, "#13201f", x + 6 - Math.floor(i / 2), bottom - i, 1 + Math.floor(i / 2) * 2, 1);
      });
    } else if (kind === "tunnel") {
      R(c, "#0a0a0c", x0, y0, w, h);
      strip(x0, w, T, 180, 34, x => { R(c, "#ffb347", x, y0 + 8, 5, 2); R(c, "rgba(255, 179, 71, 0.25)", x - 14, y0 + 7, 14, 4); });
    } else if (kind === "cave") {
      R(c, "#061a20", x0, y0, w, h);
      R(c, "#0a2a32", x0, y0, w, 8);
      strip(x0, w, T, 12, 9, (x, n) => {
        const len = 4 + Math.floor(hash(n) * 10);
        for (let i = 0; i < len; i++) R(c, i > len - 3 ? "#2f7a83" : "#134049", x + Math.floor(i / 3), y0 + 6 + i, Math.max(1, 5 - Math.floor(i / 2)), 1);
      });
      const water = bottom - 12;
      R(c, "#0b5c63", x0, water, w, 12);
      for (let i = 0; i < w; i += 3) {
        const yy = water + 2 + Math.round(Math.sin(i / 6 + T * 2) * 1.5);
        R(c, "#22d3c5", x0 + i, yy, 2, 1);
      }
      for (let i = 0; i < 24; i++) {
        const tw = Math.sin(T * 3 + i * 1.7) > 0.3;
        if (tw) R(c, i % 3 ? "#7cf9e8" : "#bff7ef", x0 + hash(i + 200) * w, y0 + 10 + hash(i + 300) * (h - 24), 1, 1);
      }
      // a jellyfish drifting up
      const jx = x0 + 20 + ((T * 7) % (w - 30)), jy = water - 4 - ((T * 5) % 18);
      R(c, "#ff9de0", jx, jy, 5, 2); R(c, "#ff9de0", jx + 1, jy - 1, 3, 1);
      R(c, "#ffc4ec", jx, jy + 2, 1, 2); R(c, "#ffc4ec", jx + 2, jy + 2, 1, 3); R(c, "#ffc4ec", jx + 4, jy + 2, 1, 2);
    } else if (kind === "sea") {
      R(c, "#0a1430", x0, y0, w, h);
      for (let i = 0; i < 14; i++) if (Math.sin(T * 2 + i) > -0.3) R(c, "#e8eeff", x0 + hash(i + 7) * w, y0 + 2 + hash(i + 70) * 12, 1, 1);
      R(c, "#f6efd8", x0 + 22, y0 + 4, 6, 6);
      const sea = y0 + Math.round(h * 0.55);
      R(c, "#0e2a4a", x0, sea, w, bottom - sea);
      for (let yy = sea + 1; yy < bottom; yy += 3) {
        const off = ((T * 20 + yy * 5) % 12);
        for (let xx = -12; xx < w; xx += 12) R(c, "#2a5a8a", x0 + xx + off, yy, 5, 1);
        R(c, "#f6efd8", x0 + 23 + Math.round(Math.sin(T * 3 + yy) * 2), yy, 4, 1);   // moonlight path
      }
      // the whale: jumps every few seconds
      const ph = (T % 5) / 5;
      if (ph < 0.5) {
        const k = ph / 0.5, wx = x0 + 70 + k * 40, wy = sea - Math.sin(k * Math.PI) * 14;
        R(c, "#1a2a40", wx, wy, 16, 5); R(c, "#1a2a40", wx + 2, wy - 2, 10, 2); R(c, "#1a2a40", wx + 15, wy - 3, 3, 3); R(c, "#1a2a40", wx + 17, wy - 5, 3, 2);
        R(c, "#9fb8d8", wx + 2, wy + 3, 8, 1);
        if (k > 0.85 || k < 0.15) for (let i = 0; i < 6; i++) R(c, "#e8f4ff", wx + i * 3, sea - 2 - (i % 3), 1, 1);
      }
    }
  }
  function drawCar(c, t, T, out, hero) {
    const jolt = Math.sin(T * 9) > 0.96 ? 1 : 0;
    c.save(); c.translate(0, jolt);
    R(c, "#b9c4cf", 0, -2, 160, 124);
    R(c, "#e8edf2", 0, 0, 160, 8); R(c, "#fffbe8", 20, 2, 50, 3); R(c, "#fffbe8", 90, 2, 50, 3);
    c.save(); c.beginPath(); c.rect(6, 14, 148, 42); c.clip();
    drawOutside(c, 6, 14, 148, 42, T, out);
    R(c, "rgba(255, 255, 255, 0.06)", 6, 14, 148, 42);
    for (const sx of [20, 110]) for (let i = 0; i < 16; i++) R(c, "rgba(255, 255, 255, 0.07)", sx + i, 14 + i * 2.6, 2, 3);
    c.restore();
    R(c, "#7d8894", 4, 12, 152, 2); R(c, "#7d8894", 4, 56, 152, 3); R(c, "#7d8894", 54, 12, 4, 46); R(c, "#7d8894", 102, 12, 4, 46);
    R(c, "#5d6672", 4, 12, 2, 46); R(c, "#5d6672", 154, 12, 2, 46);
    for (let x = 14; x < 160; x += 24) { R(c, "#9aa3ad", x, 8, 1, 3); R(c, "#d0d6dc", x - 2, 11, 5, 3); R(c, "#b9c4cf", x - 1, 12, 3, 1); }
    R(c, "#2f4e8f", 4, 60, 152, 22); R(c, "#3a5ea8", 4, 80, 152, 10); R(c, "#24407a", 4, 89, 152, 2);
    for (let x = 4; x < 156; x += 30) R(c, "#24407a", x, 60, 1, 30);
    R(c, "#6b6f78", 0, 92, 160, 30); R(c, "#d9b23a", 0, 106, 160, 1);
    R(c, "#d8dde3", 30, 8, 2, 84); R(c, "#9aa3ad", 31, 8, 1, 84);
    drawHero(c, 70, 52, Object.assign({ pose: "sit" }, hero));
    if (hero && hero.eyes === "closed") zzz(c, 92, 52, t);
    if (hero && hero.eyes === "wide") { pxText(c, "!", 92, 44, "#ffe27a", 8); pxText(c, "!", 98, 42, "#ffe27a", 8); }
    c.restore();
  }
  function drawCoast(c, t, T) {
    const bands = ["#1b1640", "#2c1d55", "#4a2a63", "#7a3d63"];
    bands.forEach((col, i) => R(c, col, 0, i * 20, 160, 20));
    for (let i = 0; i < 20; i++) if (Math.sin(T * 2 + i) > -0.2) R(c, "#e8eeff", hash(i + 3) * 160, hash(i + 33) * 40, 1, 1);
    R(c, "#f6efd8", 24, 10, 8, 8); R(c, "#f6efd8", 23, 11, 10, 6);
    R(c, "#0e2a4a", 0, 80, 160, 40);
    for (let yy = 82; yy < 120; yy += 4) { const off = (T * 14 + yy * 3) % 16; for (let x = -16; x < 160; x += 16) R(c, "#2a5a8a", x + off, yy, 6, 1); }
    // the bridge
    R(c, "#5b4a3a", 0, 74, 126, 2);
    for (let x = 4; x < 124; x += 12) { R(c, "#3a2f28", x, 76, 2, 10); R(c, "#3a2f28", x - 5, 80, 12, 1); }
    // the train heads into the sea cave
    const tx = -84 + Math.min(1, t / 5.5) * 230;
    for (let k = 0; k < 3; k++) {
      const x = tx + k * 27;
      R(c, "#c84b4b", x, 64, 25, 10); R(c, "#8f2f35", x, 72, 25, 2);
      for (let wx = 3; wx < 22; wx += 6) R(c, "#ffe27a", x + wx, 66, 4, 3);
      R(c, "#1a1418", x + 4, 74, 4, 2); R(c, "#1a1418", x + 17, 74, 4, 2);
    }
    const front = tx + 3 * 27 - 2;
    R(c, "#c84b4b", front, 66, 4, 8); R(c, "#ffe27a", front + 3, 68, 2, 2);
    c.fillStyle = "rgba(255, 236, 160, 0.25)"; c.beginPath(); c.moveTo(front + 5, 68); c.lineTo(front + 40, 60); c.lineTo(front + 40, 78); c.closePath(); c.fill();
    // the cliff with a glowing cave
    R(c, "#3b3048", 112, 26, 48, 94); R(c, "#2b2236", 112, 26, 4, 94);
    for (let i = 0; i < 18; i++) R(c, "#4a3d5a", 116 + hash(i + 5) * 40, 30 + hash(i + 50) * 80, 3, 1);
    const glow = 0.55 + 0.25 * Math.sin(T * 2.4);
    R(c, "#03070a", 118, 58, 30, 30); R(c, "#03070a", 121, 54, 24, 4); R(c, "#03070a", 125, 51, 16, 3);
    R(c, `rgba(34, 211, 197, ${glow})`, 124, 74, 20, 14); R(c, `rgba(124, 249, 232, ${glow * 0.6})`, 128, 70, 12, 4);
    for (let i = 0; i < 5; i++) R(c, "#2b2236", 122 + i * 5, 54 + (i % 2) * 2, 2, 4);
    R(c, "#0e2a4a", 112, 88, 48, 32);
    R(c, `rgba(34, 211, 197, ${glow * 0.5})`, 118, 90, 30, 2);
  }
  function drawHome(c, t, mode) {
    R(c, "#2a2440", 0, 0, 160, 120); R(c, "#3a2f28", 0, 96, 160, 24);
    R(c, "#0b1530", 14, 16, 34, 32); R(c, "#f6efd8", 36, 21, 6, 6); R(c, "#8a7a6a", 12, 14, 38, 2); R(c, "#8a7a6a", 12, 48, 38, 2);
    R(c, "#8a7a6a", 12, 14, 2, 36); R(c, "#8a7a6a", 48, 14, 2, 36); R(c, "#8a7a6a", 30, 14, 2, 36);
    R(c, "#6a3a5a", 8, 12, 6, 44); R(c, "#6a3a5a", 48, 12, 6, 44);
    R(c, "#6b4a2a", 60, 70, 92, 4); R(c, "#6b4a2a", 60, 74, 4, 22); R(c, "#6b4a2a", 148, 62, 4, 34);
    R(c, "#4a6fb8", 64, 74, 84, 14); R(c, "#3a5a9a", 64, 86, 84, 2);
    R(c, "#f4efe0", 126, 66, 20, 8); R(c, "#d8d0bc", 126, 72, 20, 2);
    if (mode === "collapse") {
      const k = Math.min(1, t / 0.6);
      if (k < 1) drawHero(c, 64, 46 + k * 10, { pose: "stand", eyes: "closed", mouth: "flat" });
      else {
        // face down on top of the blanket, shoes still on
        R(c, "#1fa9b8", 88, 68, 36, 8); R(c, "#127c88", 88, 74, 36, 2);
        R(c, "#2a3550", 64, 70, 26, 6); R(c, "#151515", 60, 70, 5, 6);
        R(c, "#3a2618", 124, 64, 10, 10); R(c, "#f0c49a", 125, 72, 3, 2);
        R(c, "#f0c49a", 92, 76, 4, 6); R(c, "#f0c49a", 114, 76, 4, 6);
        if (t < 1.4) pxText(c, "БУХ!", 84, 50, "#ffe27a", 7);
        zzz(c, 136, 56, t);
      }
    } else {
      R(c, "#3a2618", 128, 60, 10, 8); R(c, "#f0c49a", 130, 64, 7, 5); R(c, "#1a1418", 131, 66, 3, 1);
      R(c, "#5a7fc8", 64, 72, 70, 4);
      zzz(c, 138, 52, t);
    }
  }
  function drawMorning(c, t, mode) {
    R(c, "#f3e2c0", 0, 0, 160, 120); R(c, "#b88a5a", 0, 96, 160, 24);
    R(c, "#9fd8ff", 14, 16, 34, 32); R(c, "#ffe27a", 36, 20, 7, 7); R(c, "#ffffff", 18, 30, 10, 3); R(c, "#ffffff", 20, 28, 6, 2);
    R(c, "#c8a87a", 12, 14, 38, 2); R(c, "#c8a87a", 12, 48, 38, 2); R(c, "#c8a87a", 12, 14, 2, 36); R(c, "#c8a87a", 48, 14, 2, 36); R(c, "#c8a87a", 30, 14, 2, 36);
    if (mode === "good") for (let i = 0; i < 4; i++) R(c, "rgba(255, 236, 160, 0.35)", 50 + i * 6, 20 + i * 10, 40, 3);
    R(c, "#6b4a2a", 60, 70, 92, 4); R(c, "#6b4a2a", 60, 74, 4, 22); R(c, "#6b4a2a", 148, 62, 4, 34);
    R(c, "#4a6fb8", 64, 74, 84, 14); R(c, "#f4efe0", 126, 66, 20, 8);
    drawHero(c, 96, 40, { pose: "sit", noBag: true, eyes: mode === "bad" ? "half" : mode === "good" ? "open" : "open", mouth: mode === "good" ? "smile" : mode === "bad" ? "flat" : "flat", bags: mode === "bad" });
    R(c, "#4a6fb8", 64, 70, 84, 18);   // the blanket over the legs
    R(c, "#8a5a3a", 28, 76, 22, 20); R(c, "#6b4a2a", 28, 76, 22, 2);
    const ring = mode !== "good" && t < 4;
    const sx = ring ? Math.round(Math.sin(t * 60)) : 0;
    R(c, "#e04848", 33 + sx, 66, 12, 10); R(c, "#ffffff", 35 + sx, 68, 8, 6); R(c, "#1a1418", 38 + sx, 69, 1, 3); R(c, "#1a1418", 39 + sx, 71, 2, 1);
    R(c, "#e04848", 32 + sx, 64, 3, 2); R(c, "#e04848", 43 + sx, 64, 3, 2);
    if (ring && Math.sin(t * 10) > 0) pxText(c, "ДЗЫНЬ!", 22, 52, "#e04848", 7);
    if (mode === "good" && Math.sin(t * 4) > 0) { pxText(c, "♪", 60, 18, "#3a8a4a", 8); }
  }
  function drawLeave(c, t) {
    R(c, "#d8d0c0", 0, 0, 160, 120); R(c, "#8a7a6a", 0, 96, 160, 24); R(c, "#6a5a4a", 0, 95, 160, 1);
    // the exit door
    R(c, "#5a6a7a", 10, 30, 34, 66); R(c, "#7a8a9a", 13, 33, 28, 60); R(c, "#d8dde3", 36, 62, 3, 6);
    R(c, "#2a9a4a", 12, 18, 30, 9); pxText(c, "ВЫХОД", 14, 20, "#ffffff", 5);
    // a window with the sunset
    R(c, "#e38a58", 104, 20, 44, 34); R(c, "#b0545e", 104, 20, 44, 12); R(c, "#ffd86b", 134, 40, 8, 8);
    R(c, "#8a7a6a", 102, 18, 48, 2); R(c, "#8a7a6a", 102, 54, 48, 2); R(c, "#8a7a6a", 102, 18, 2, 38); R(c, "#8a7a6a", 148, 18, 2, 38); R(c, "#8a7a6a", 125, 18, 2, 38);
    const yawn = (t % 3) < 1.4;
    drawHero(c, 66, 50, { pose: "stand", eyes: yawn ? "closed" : "half", mouth: yawn ? "yawn" : "flat" });
    if (yawn) pxText(c, "ааа…", 88, 46, "#5a4a3a", 5);
  }
  // the barin in his armchair; coins pile up on the floor to the right, the sum floats up top
  const drawPayRoom = makeBarinScene();
  let payRoomT = 0;
  function drawBarinPay(c, t, pay) {
    c.imageSmoothingEnabled = false;
    drawPayRoom(c, ++payRoomT, { talk: t < 2.5 });
    const coins = Math.max(1, Math.min(24, Math.round(Math.log10(pay + 1) * 6)));
    for (let i = 0; i < coins; i++) {
      const t0 = i * 0.12, k = Math.min(1, Math.max(0, (t - t0) / 0.5));
      if (t < t0) continue;
      const px = 112 + (i % 6) * 6, py = 113 - Math.floor(i / 6) * 3;
      const y = -6 + (py + 6) * k * k;
      R(c, "#ffcc33", px, y, 4, 3); R(c, "#b8860b", px, y + 2, 4, 1);
    }
    if (t > 0.4) {
      const s = `+${rub(pay)} ₽`, y = Math.round(16 - Math.min(8, t * 5));
      c.font = '6px "Press Start 2P", monospace';
      const w = Math.ceil(c.measureText(s).width);
      R(c, "rgba(42, 22, 16, 0.85)", 80 - (w >> 1) - 3, y - 2, w + 6, 10);
      pxText(c, s, 80, y, "#ffe27a", 6, "center");
    }
  }
  function drawDayCard(c, t, n) {
    R(c, "#000", 0, 0, 160, 120);
    const k = Math.min(1, t / 0.5), y = 30 - Math.round((1 - k) * 12);
    R(c, "#f4efe0", 50, y, 60, 64); R(c, "#d0141e", 50, y, 60, 14); R(c, "#9a0e16", 50, y + 13, 60, 1);
    R(c, "#1a1418", 60, y - 4, 4, 8); R(c, "#1a1418", 96, y - 4, 4, 8);
    pxText(c, "ДЕНЬ", 80, y + 4, "#ffffff", 6, "center");
    pxText(c, String(n), 80, y + 26, "#1a1418", n > 99 ? 14 : 20, "center");
  }
  function drawDayScene(c, st, t, T) {
    c.save();
    c.imageSmoothingEnabled = false;
    if (st.scene === "leave") drawLeave(c, t);
    else if (st.scene === "barin") drawBarinPay(c, t, st.pay || 0);
    else if (st.scene === "car") drawCar(c, t, T, st.out, st.hero);
    else if (st.scene === "coast") drawCoast(c, t, T);
    else if (st.scene === "home") drawHome(c, t, st.mode);
    else if (st.scene === "morning") drawMorning(c, t, st.mode);
    else if (st.scene === "day") drawDayCard(c, t, st.n);
    c.restore();
  }

  // ----- the end-of-day sequence -----
  let de = null;   // { steps, i, t0, start, onDone, demo, stats, items, pay, mood }
  function barinPayLine(stats, left) {
    const sum = `Зарплата за день — ${rub(stats.pay)} ₽. До миллиарда осталось ${rub(left)} ₽.`;
    if (stats.mood === "good") return `Ай, молодец, какой день! Верных ответов — ${stats.right} из ${stats.total}. ${sum} Иди отдыхай, джан.`;
    if (stats.mood === "bad") return `Тяжёлый день, джан, бывает. Плачу, как обещал. ${sum} Иди выспись, завтра будет легче.`;
    return `Хорошо поработал, дорогой. ${sum} Не трать всё на брекеты!`;
  }
  function rideSteps(mood) {
    const S = [];
    if (mood === "good") {
      const v = Math.floor(Math.random() * 3);
      S.push({ scene: "car", out: "city", hero: { eyes: "open" }, line: "Вечерний поезд. За окном огни города.", alt: "Вагон поезда, за окном ночной город", sfx: "train" });
      if (v === 0) {
        S.push({ scene: "car", out: "mountains", hero: { eyes: "open", mouth: "o" }, who: "ТЫ:", line: "Стоп. Откуда тут горы? Это точно не моя ветка.", alt: "За окном вместо города — горы" });
        S.push({ scene: "coast", line: "Поезд ныряет в тоннель — и выезжает к морю, прямо в светящуюся пещеру.", alt: "Поезд едет по мосту над морем в светящуюся пещеру", sfx: "chime" });
        S.push({ scene: "car", out: "cave", hero: { eyes: "wide", mouth: "o" }, who: "ТЫ:", line: "Ничего себе…", alt: "За окном морская пещера, вода светится" });
        S.push({ scene: "car", out: "cave", hero: { eyes: "open" }, who: "ТЫ:", line: "Так. Это либо магия окклюзии, либо недосып. Ладно, надо идти спать, у меня уже глюки.", alt: "Пещера за окном" });
      } else if (v === 1) {
        S.push({ scene: "car", out: "molars", hero: { eyes: "open", mouth: "o" }, who: "ТЫ:", line: "Горы… в форме моляров? С буграми, с фиссурами. Одна даже с золотой коронкой.", alt: "За окном горы в форме зубов" });
        S.push({ scene: "car", out: "sea", hero: { eyes: "wide", mouth: "o" }, who: "ТЫ:", line: "А теперь море. И кит. Кит машет хвостом. Мне.", alt: "За окном ночное море и кит", sfx: "chime" });
        S.push({ scene: "car", out: "sea", hero: { eyes: "open" }, who: "ТЫ:", line: "Ничего себе… Ладно. Надо идти спать, у меня уже глюки.", alt: "Море за окном" });
      } else {
        S.push({ scene: "car", out: "tunnel", hero: { eyes: "open" }, line: "Тоннель. Длинный. Слишком длинный для нашей ветки.", alt: "Поезд в тоннеле" });
        S.push({ scene: "car", out: "aurora", hero: { eyes: "wide", mouth: "o" }, who: "ТЫ:", line: "Северное сияние. Над горами. В нашем городе.", alt: "За окном горы и северное сияние", sfx: "chime" });
        S.push({ scene: "car", out: "aurora", hero: { eyes: "open" }, who: "ТЫ:", line: "Ничего себе… Всё. Надо идти спать, у меня уже глюки.", alt: "Северное сияние за окном" });
      }
      S.push({ scene: "home", mode: "sleep", line: "Дома ты засыпаешь, едва коснувшись подушки. Снится что-то хорошее.", alt: "Ночь, герой спит" });
      S.push({ scene: "morning", mode: "good", who: "ТЫ:", line: "Выспался. Странно, но приятно.", alt: "Солнечное утро" });
    } else if (mood === "bad") {
      S.push({ scene: "car", out: "city", hero: { eyes: "half", nod: 1 }, line: "Поезд качает. Глаза закрываются сами.", alt: "Герой засыпает в вагоне", sfx: "train", fx: () => sleepy(1) });
      S.push({ scene: "car", out: "dark", hero: { eyes: "closed", nod: 2 }, line: "…Ты проехал свою станцию. Пришлось возвращаться.", alt: "Герой спит в вагоне", fx: () => blinkOnce(1800) });
      S.push({ scene: "home", mode: "collapse", line: "Дошёл. Не раздеваясь — лицом в подушку. Отрубился.", alt: "Герой падает на кровать", sfx: "thud" });
      S.push({ scene: "morning", mode: "bad", who: "ТЫ:", line: "ДЗЫНЬ! Голова кружится. Всё плывёт… Недосып.", alt: "Утро, звонит будильник", sfx: "ring", fx: () => sleepy(2) });
    } else {
      S.push({ scene: "car", out: "city", hero: { eyes: "open" }, line: "Вечерний поезд. Огни города. Всё как обычно.", alt: "Вагон поезда, за окном ночной город", sfx: "train" });
      S.push({ scene: "car", out: "city", hero: { eyes: "half" }, line: "Глаза слипаются. Главное — не проспать станцию.", alt: "Герой клюёт носом" });
      S.push({ scene: "home", mode: "sleep", line: "Дом. Душ. Кровать. Сон без снов.", alt: "Ночь, герой спит" });
      S.push({ scene: "morning", mode: "normal", who: "ТЫ:", line: "Будильник. Встаём.", alt: "Утро, звонит будильник", sfx: "ring" });
    }
    return S;
  }
  function daySteps(items, stats, n) {
    const left = Math.max(0, 1e9 - (DAYS.wallet + stats.pay));
    return [
      { scene: "leave", recap: true, who: "ТЫ:", title: `КОНЕЦ СМЕНЫ · ДЕНЬ ${n}`,
        line: pick(["Ладно. Смена окончена, я пошёл спать.", "Всё. На сегодня хватит. Я домой.", "Смена закончилась. Ноги гудят. Домой, спать."]), alt: "Герой зевает у выхода" },
      { scene: "barin", who: "БАРИН:", title: "ЗАРПЛАТА", pay: stats.pay, line: barinPayLine(stats, left), alt: "Барин в кресле, на пол падают монетки", sfx: "coin" },
      ...rideSteps(stats.mood).map(s => Object.assign({ title: "ДОРОГА ДОМОЙ" }, s)),
      { scene: "day", n: n + 1, title: `ДЕНЬ ${n + 1}`, alt: `Календарь: день ${n + 1}`,
        line: stats.mood === "good" ? "Бодрый и отдохнувший. Вперёд!" : stats.mood === "bad" ? "Ладно… Как-нибудь доживу до вечера." : "Новый день — новые зубы." },
    ];
  }
  // opts: { onDone, demo }
  function endDay(opts) {
    de = { onDone: opts.onDone || goMorning, demo: !!opts.demo, i: 0, steps: [] };
    if (de.demo) {
      de.steps = [{ scene: "leave", title: "КОНЕЦ ДНЯ · ПРЕВЬЮ", alt: "Герой зевает у выхода", line: "Тестовая версия: выбери, как прошёл день, — от этого зависит дорога домой.",
        buttons: [["ХОРОШО", () => dayDemo("good")], ["НОРМАЛЬНО", () => dayDemo("normal")], ["ПЛОХО", () => dayDemo("bad")]] }];
    } else {
      de.items = DAYS.today.slice();
      de.stats = dayStats(de.items);
      de.steps = daySteps(de.items, de.stats, DAYS.day);
    }
    show(12);
  }
  function dayDemo(mood) {
    const sample = {
      good: [["Свиток 1. Как всё начиналось", 10, 11], ["Свиток 2. Гнатология: взлёт и падение", 12, 13]],
      normal: [["Свиток 1. Как всё начиналось", 8, 11], ["Свиток 2. Гнатология: взлёт и падение", 9, 13]],
      bad: [["Свиток 1. Как всё начиналось", 4, 11], ["Свиток 2. Гнатология: взлёт и падение", 5, 13]],
    }[mood];
    de.items = [{ kind: "story", title: "Урок барина: этапы лечения на брекетах", right: 0, total: 0, pay: 0 },
      ...sample.map(([title, right, total]) => ({ kind: "scroll", title, right, total, pay: right * payPerStep }))];
    de.stats = dayStats(de.items);
    de.steps = daySteps(de.items, de.stats, DAYS.day);
    de.i = 0;
    dayRender();
  }
  function startDayEnd() {
    if (!de) return show(2);
    de.start = performance.now();
    sleepy(0);
    dayRender();
    requestAnimationFrame(dayLoop);
  }
  function dayRender() {
    const st = de.steps[de.i], last = de.i === de.steps.length - 1;
    de.t0 = performance.now();
    $("dayTitle").textContent = st.title || "";
    $("dayWho").textContent = st.who || "";
    $("dayLine").textContent = st.line || "";
    $("dayScene").setAttribute("aria-label", st.alt || "");
    const recap = $("dayRecap");
    recap.hidden = !st.recap;
    if (st.recap) renderRecap(recap, de.items, de.stats, DAYS.day);
    if (st.sfx && typeof mSfx === "function") mSfx(st.sfx);
    if (st.fx) st.fx();
    const btns = st.buttons || [[last ? "НАЧАТЬ ДЕНЬ ▶" : "ДАЛЬШЕ ▶", dayNext]];
    $("dayBtns").replaceChildren(...btns.map(([text, fn]) => {
      const b = document.createElement("button");
      b.type = "button"; b.className = "btn"; b.textContent = text;
      b.addEventListener("click", e => { e.stopPropagation(); fn(); });
      return b;
    }));
  }
  function renderRecap(box, items, stats, n) {
    const mk = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
    const ul = mk("ul", "dr-list");
    const list = items.length ? items : [{ title: "Ничего не сделано. Но устал, как будто сделал всё.", total: 0 }];
    list.forEach((x, i) => {
      const li = mk("li");
      li.style.animationDelay = `${0.15 + i * 0.3}s`;
      li.append(mk("span", "dr-tick", "✓"), mk("span", "dr-t", x.title));
      if (x.total) li.append(mk("span", "dr-s", `${x.right}/${x.total}`));
      ul.append(li);
    });
    const parts = [mk("p", "dr-h", `ИТОГИ ДНЯ ${n}`), ul];
    if (stats.total) parts.push(mk("p", "dr-sum", `ВЕРНО: ${stats.right} ИЗ ${stats.total} · ${Math.round(stats.pct * 100)}%`));
    const stamp = mk("p", `dr-stamp ${stats.mood}`, stats.mood === "good" ? "ДЕНЬ УДАЛСЯ" : stats.mood === "bad" ? "ТЯЖЁЛЫЙ ДЕНЬ" : "ОБЫЧНЫЙ ДЕНЬ");
    stamp.style.animationDelay = `${0.3 + list.length * 0.3}s`;
    parts.push(stamp);
    box.replaceChildren(...parts);
  }
  function dayNext() {
    if (de.i < de.steps.length - 1) { de.i++; return dayRender(); }
    const mood = de.stats ? de.stats.mood : "normal", done = de.onDone;
    if (!de.demo) {
      DAYS.wallet += de.stats.pay;
      DAYS.lastPay = de.stats.pay;
      DAYS.day += 1;
      DAYS.today = [];
      dayStore();
      day = DAYS.day;
    }
    de = null;
    sleepy(mood === "bad" ? 1 : 0, mood === "bad" ? 45000 : 0);   // a bad night lingers into the morning
    done();
  }
  function dayLoop(now) {
    if (current !== 12 || !de) return;
    const st = de.steps[de.i];
    drawDayScene(dayCtx, st, (now - de.t0) / 1000, (now - de.start) / 1000);
    requestAnimationFrame(dayLoop);
  }
  // A new day can open with a short scene before the master: the barin's lesson on braces (day 2),
  // the office (day 3), the visitor in black (day 4). Each of them ends in the temple.
  function goMorning() {
    mMorning = true;
    const scene = { 2: 9, 3: 10, 4: 8 }[day];
    show(scene === undefined ? 11 : scene);
  }

  // ---------- Practice between the master's scrolls ----------
  // After each scroll: one short task in the clinic, then back to the master. Learning comes first;
  // these are the mini-games. Practice pays like everything else.
  const MINIS = [
    { kind: "assist", level: 0, title: "один пациент, бот подсказывает" },
    { kind: "pliers", title: "щипцы для дуги" },
    { kind: "causes", title: "причины открытого прикуса" },
    { kind: "assist", level: 1, title: "пациент, бот подсказывает реже" },
    { kind: "pliers", title: "щипцы для дуги" },
    { kind: "assist", level: 2, title: "пациент, экзамен: бот молчит" },
    { kind: "causes", title: "причины открытого прикуса" },
    { kind: "assist", level: 2, title: "пациент, экзамен: бот молчит" },
  ];
  let mini = null;   // { k, kind, level, title, dev }
  function newPracticeGame(level) {
    const pool = PATIENTS.map((_, i) => i).sort(() => Math.random() - 0.5);
    game = { idx: level || 0, next: 0, pool, hours: 0, money: 0, mistakesTotal: 0, mini: true };
  }
  function startMini(k, opts = {}) {
    mini = Object.assign({ k }, MINIS[Math.min(k, MINIS.length - 1)], opts);
    if (mini.kind === "assist") return k === 0 || mini.dev ? show(1) : startAssist();   // the barin opens the very first one
    if (mini.kind === "pliers") { newPracticeGame(0); return show(4); }
    newPracticeGame(0);
    show(6);   // the barin asks who you should thank → the assistant's assistant → the causes
  }
  function startAssist() {
    newPracticeGame(mini ? mini.level : 0);
    show(2, true);
  }
  function miniDone() {
    const m = mini;
    mini = null;
    if (m && !m.dev && game) {
      if (m.kind === "assist") {
        const acts = Math.round(game.money / payPerStep);
        dayLog("shift", "Практика: пациент", acts, acts + game.mistakesTotal, game.money);
      } else if (m.kind === "pliers") {
        dayLog("shift", "Практика: щипцы для дуги", TOOL_TASKS.length, TOOL_TASKS.length + game.mistakesTotal, game.money);
      }   // the causes log themselves when all groups are found
      mMiniDone(m.k);
    }
    show(11);
  }
  // ---------- Days end ----------
