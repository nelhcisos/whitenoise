  // ---------- The master: lesson engine ----------
  // A menu of scrolls with stars (saved in localStorage), a lesson runner with a typewriter bubble,
  // four question types, a review round for mistakes, an exam with a certificate and a glossary.
  // Random interruptions (guests, an ad, a phone call) and small ambient animations keep it light.
  const M_IMG = "assets/master/";
  const M_KEY = "ortho-master-v2";
  const M_EXAM = 12, M_PASS = 10;
  const mCalm = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  const mEl = {};
  for (const id of ["Stage", "Top", "Chapter", "Exit", "Prog", "ProgFill", "Board", "Fig", "Walker", "Sprite", "Vox", "Guest",
    "Panel", "Box", "Name", "Text", "More", "Choices", "Fx", "Ad", "Card", "Meme", "Combo"]) mEl[id[0].toLowerCase() + id.slice(1)] = $("m" + id);

  // ----- progress, saved between visits -----
  function mFresh() {
    const n = MASTER_CHAPTERS.length;
    return { stars: Array(n).fill(0), done: Array(n).fill(false), minis: Array(n).fill(false), exam: 0, passed: false, name: "", date: "", met: false, dayEnd: false, sound: true };
  }
  function mLoad() {
    const d = mFresh();
    try {
      const s = JSON.parse(localStorage.getItem(M_KEY) || "null");
      if (s && typeof s === "object") {
        for (const k of ["exam", "passed", "name", "date", "met", "dayEnd", "sound"]) if (typeof s[k] === typeof d[k]) d[k] = s[k];
        for (const k of ["stars", "done", "minis"]) if (Array.isArray(s[k])) d[k] = d[k].map((v, i) => (typeof s[k][i] === typeof v ? s[k][i] : v));
      }
    } catch (e) { /* no storage: play without saving */ }
    return d;
  }
  const mSave = mLoad();
  function mStore() { try { localStorage.setItem(M_KEY, JSON.stringify(mSave)); } catch (e) { /* ignore */ } }
  // practice after scroll k is done: the master picks up from there
  let mBack = false;
  function mMiniDone(k) {
    if (k >= 0 && k < mSave.minis.length) mSave.minis[k] = true;
    mStore();
    mBack = true;
  }

  // ----- small helpers -----
  function mShuffle(a) {
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
    return a;
  }
  function mNode(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function mBtn(cls, text, onClick) {
    const b = mNode("button", cls, text);
    b.type = "button";
    b.addEventListener("click", e => { e.stopPropagation(); onClick(e); });
    return b;
  }
  function mStars(n, total = 3) {
    const s = mNode("span", "m-stars");
    for (let i = 0; i < total; i++) s.append(mNode("i", i < n ? "on" : "off", "★"));
    s.setAttribute("aria-label", `звёзд: ${n} из ${total}`);
    return s;
  }
  function mItem(title, sub, right, onClick, cls) {
    const b = mBtn("m-item" + (cls ? " " + cls : ""), null, onClick);
    b.append(mNode("span", "m-item-t", title));
    if (right) b.append(right);
    if (sub) b.append(mNode("small", null, sub));
    return b;
  }

  // ----- sound: short synthesized blips (no files) -----
  let mAC = null;
  function mTone(ac, f0, f1, t0, dur, type = "triangle", vol = 0.07) {
    const o = ac.createOscillator(), g = ac.createGain(), t = ac.currentTime + t0;
    o.type = type;
    o.frequency.setValueAtTime(f0, t);
    if (f1) o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.012);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(ac.destination);
    o.start(t); o.stop(t + dur + 0.03);
  }
  const M_SFX = {
    yes: ac => { mTone(ac, 660, 0, 0, 0.1); mTone(ac, 990, 0, 0.09, 0.18); },
    no: ac => mTone(ac, 200, 130, 0, 0.28, "square", 0.045),
    drop: ac => mTone(ac, 900, 110, 0, 0.7, "sine", 0.07),
    star: ac => [784, 988, 1175, 1568].forEach((f, i) => mTone(ac, f, 0, i * 0.11, 0.22)),
    beads: ac => [0, 0.1, 0.18, 0.31, 0.39].forEach(t0 => mTone(ac, 2100, 1500, t0, 0.04, "triangle", 0.045)),
    knock: ac => [0, 0.17, 0.34].forEach(t0 => mTone(ac, 150, 60, t0, 0.09, "square", 0.07)),
    ding: ac => { mTone(ac, 1320, 0, 0, 0.35, "sine", 0.06); mTone(ac, 990, 0, 0.18, 0.45, "sine", 0.05); },
    ring: ac => { for (let i = 0; i < 8; i++) mTone(ac, i % 2 ? 480 : 440, 0, i * 0.1 + (i > 3 ? 0.4 : 0), 0.09, "square", 0.03); },
    rumble: ac => { mTone(ac, 60, 38, 0, 1.3, "sawtooth", 0.06); mTone(ac, 45, 30, 0.2, 1.1, "square", 0.03); },
    jingle: ac => [523, 659, 784, 1047, 784, 1047].forEach((f, i) => mTone(ac, f, 0, i * 0.12, 0.16, "square", 0.035)),
    click: ac => mTone(ac, 2400, 700, 0, 0.05, "square", 0.06),
    gong: ac => { mTone(ac, 110, 98, 0, 2.2, "sine", 0.1); mTone(ac, 220, 196, 0, 1.6, "sine", 0.04); },
    train: ac => [0, 0.14, 0.7, 0.84, 1.4, 1.54, 2.1, 2.24].forEach(t0 => mTone(ac, 95, 55, t0, 0.07, "square", 0.05)),
    chime: ac => [1047, 1319, 1568, 2093, 1568, 2637].forEach((f, i) => mTone(ac, f, 0, i * 0.1, 0.55, "sine", 0.035)),
    coin: ac => [0, 0.16, 0.32].forEach(t0 => { mTone(ac, 988, 0, t0, 0.07, "square", 0.035); mTone(ac, 1319, 0, t0 + 0.06, 0.16, "square", 0.035); }),
    thud: ac => { mTone(ac, 140, 38, 0, 0.3, "sine", 0.14); mTone(ac, 70, 30, 0.02, 0.25, "square", 0.04); },
  };
  function mSfx(name) {
    if (!mSave.sound || !M_SFX[name]) return;
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      mAC = mAC || new AC();
      if (mAC.state === "suspended") mAC.resume();
      M_SFX[name](mAC);
    } catch (e) { /* audio unavailable */ }
  }

  // ----- the master's sprite: moods and blinking -----
  ["calm", "happy", "stern", "think", "blink", "shock", "walk"].forEach(m => { new Image().src = `${M_IMG}master_${m}.png`; });
  ["barin", "patient", "courier"].forEach(g => { new Image().src = `${M_IMG}guest_${g}.png`; });
  let mMood = "calm";
  function setMood(m) {
    mMood = m || "calm";
    mEl.vox.style.setProperty("--spr", `url("${M_IMG}master_${mMood}.png")`);
  }
  setInterval(() => {
    if (current !== 11 || mMood !== "calm" || mCalm) return;
    mEl.vox.style.setProperty("--spr", `url("${M_IMG}master_blink.png")`);
    setTimeout(() => { if (mMood === "calm") setMood("calm"); }, 150);
  }, 3700);
  // 3D in pixel style: the master's sprite, stacked in layers, turns around once
  function mSpin() {
    if (mCalm) return;
    const v = mEl.vox;
    v.classList.remove("on"); void v.offsetWidth; v.classList.add("on");
    clearTimeout(mSpin.t);
    mSpin.t = setTimeout(() => v.classList.remove("on"), 1600);
  }
  function mVoxNode(cls) {
    const v = mNode("div", "m-vox " + cls);
    for (let i = 0; i < 7; i++) v.append(mNode("i"));
    return v;
  }
  function mComboFlash(n) {
    const c = mEl.combo;
    c.textContent = `Комбо ×${n}!`;
    c.hidden = false;
    c.style.animation = "none"; void c.offsetWidth; c.style.animation = "";
    clearTimeout(mComboFlash.t);
    mComboFlash.t = setTimeout(() => { c.hidden = true; }, 1500);
    mSpin();
    mSfx("star");
  }

  // ----- the chalkboard: redrawn every frame while visible, so boards can animate -----
  let mBoardId = null, mBoardT0 = 0, mRaf = 0;
  function setBoard(id) {
    id = id || null;
    mEl.board.hidden = !id;
    mEl.stage.classList.toggle("has-board", !!id);
    const book = !!(id && BOOK[id]);
    mEl.stage.classList.toggle("has-figure", book);
    mEl.board.classList.toggle("zoomable", book);
    mEl.board.setAttribute("aria-label", book ? `${BOOK[id].n}, страница ${BOOK[id].p}: ${BOOK[id].t}. Нажми, чтобы увеличить` : "Доска мастера");
    if (id !== mBoardId) { mBoardId = id; mBoardT0 = performance.now(); }
    if (id && !mRaf) mRaf = requestAnimationFrame(mBoardLoop);
  }
  function mRedrawBoard() {
    if (current === 11 && mBoardId) drawBoardFrame(mEl.board, mBoardId, mCalm ? 60 : Math.max(0, (performance.now() - mBoardT0) / 1000));
  }
  function mBoardLoop(now) {
    mRaf = 0;
    if (current !== 11 || !mBoardId) return;
    // a frame's timestamp can be a moment older than the board itself: never hand the boards a negative time
    drawBoardFrame(mEl.board, mBoardId, mCalm ? 60 : Math.max(0, (now - mBoardT0) / 1000));
    if (!mCalm) mRaf = requestAnimationFrame(mBoardLoop);
  }

  // ----- the speech bubble: typewriter text; a tap finishes the line, the next tap moves on -----
  let mTyping = null, mOnNext = null, mBusy = false;
  function mSay(text, opts = {}) {
    clearInterval(mTyping && mTyping.timer);
    mTyping = null;
    const narr = !!opts.narr;
    mEl.box.classList.toggle("narration", narr);
    mEl.box.classList.toggle("guest", !!opts.guest);
    mEl.name.hidden = narr;
    mEl.name.textContent = opts.name || "Мастер";
    mOnNext = opts.next || null;
    mEl.more.hidden = true;
    const shown = mNode("span"), ghost = mNode("span", "m-ghost");
    mEl.text.replaceChildren(shown, ghost);
    if (mCalm || opts.instant) { shown.textContent = text; mTypeDone(); return; }
    ghost.textContent = text;   // the not-yet-typed rest keeps the bubble from growing line by line
    const t = mTyping = { full: text, n: 0, shown, ghost };
    t.timer = setInterval(() => {
      t.n = Math.min(t.full.length, t.n + 2);
      t.shown.textContent = t.full.slice(0, t.n);
      t.ghost.textContent = t.full.slice(t.n);
      if (t.n >= t.full.length) mFinishTyping();
    }, 24);
  }
  function mFinishTyping() {
    const t = mTyping;
    if (!t) return;
    clearInterval(t.timer);
    t.shown.textContent = t.full; t.ghost.textContent = "";
    mTyping = null;
    mTypeDone();
  }
  function mTypeDone() { mEl.more.hidden = !mOnNext; }
  function mTap() {
    if (mTyping) return mFinishTyping();
    if (mBusy || !mOnNext) return;
    const f = mOnNext;
    mOnNext = null; mEl.more.hidden = true;
    f();
  }
  // several lines in a row; each line: text or { text, narr, name, guest, mood, fn }
  function mLines(lines, done) {
    const list = lines.filter(Boolean).map(l => (typeof l === "string" ? { text: l } : l));
    let i = 0;
    const step = () => {
      if (i >= list.length) return done();
      const l = list[i++];
      if (l.mood) setMood(l.mood);
      if (l.fn) l.fn();
      mSay(l.text, Object.assign({}, l, { next: step }));
    };
    step();
  }

  // ----- layout states -----
  function mClearChoices() {
    mEl.choices.hidden = true;
    mEl.choices.className = "m-choices";
    mEl.choices.replaceChildren();
  }
  function mLeaveLesson() {
    mEl.top.hidden = true;
    mClearChoices();
    setBoard(null);
    mEl.stage.classList.remove("asking", "answered", "pacing", "menu", "paneled");
    mEl.panel.hidden = true;
  }
  function mPanel(nodes, opts = {}) {
    mEl.panel.replaceChildren(...nodes);
    mEl.panel.hidden = false;
    mEl.panel.scrollTop = 0;
    mEl.stage.classList.toggle("menu", !!opts.fig);
    mEl.stage.classList.toggle("paneled", !opts.fig);
  }
  function mTitleCard(kicker, title, sub) {
    const c = mEl.card;
    c.replaceChildren(mNode("small", null, kicker), mNode("b", null, title));
    if (sub) c.append(mNode("span", null, sub));
    c.hidden = false;
    c.classList.remove("go"); void c.offsetWidth; c.classList.add("go");
    clearTimeout(mTitleCard.t);
    mTitleCard.t = setTimeout(() => { c.hidden = true; }, mCalm ? 1200 : 1950);
  }

  // ----- the lesson runner -----
  let ms = null;   // { mode, k, title, steps, i, right, total, wrong, phase, counting, onDone, sinceGag, gags }
  function mRun(steps, opts) {
    ms = Object.assign({ steps, i: -1, right: 0, total: 0, wrong: [], phase: "learn", counting: true, sinceGag: 0, gags: 0 }, opts);
    mLeaveLesson();
    mEl.stage.classList.remove("dusk");
    mEl.top.hidden = false;
    mEl.chapter.textContent = ms.title;
    mEl.prog.classList.remove("review");
    mNext();
  }
  function mProgress() {
    const n = ms.steps.length;
    mEl.progFill.style.width = `${Math.min(100, Math.round((100 * Math.max(0, ms.i)) / Math.max(1, n)))}%`;
  }
  function mNext() {
    if (!ms) return;
    ms.i++;
    mProgress();
    const st = ms.steps[ms.i];
    if (!st) return ms.onDone();
    if (mMaybeGag(st)) return;
    mRender(st);
  }
  function mRender(st) {
    mClearChoices();
    mEl.stage.classList.remove("asking", "answered", "pacing");
    if (st.s !== undefined) {
      setBoard(st.b);
      setMood(st.m || "calm");
      if (st.sfx) mSfx(st.sfx);
      mSay(st.s, { narr: st.narr, name: st.name, next: mNext });
      return;
    }
    // A question. The board often shows the answer, so it appears only with the explanation.
    setBoard(null);
    if (ms.counting) ms.total++;
    mEl.stage.classList.add("asking");
    if (!mCalm) mEl.stage.classList.add("pacing");
    setMood("think");
    mAmbient();
    if (st.q) mAskChoice(st);
    else if (st.tf) mAskTF(st);
    else if (st.ord) mAskOrder(st);
    else if (st.mt) mAskMatch(st);
  }
  const M_YES = ["Верно!", "Точно.", "Именно так.", "Правильно.", "Да. Хорошо."];
  const M_NO = ["Нет.", "Мимо.", "Не так.", "Увы, нет."];
  function mAnswer(st, ok, lines) {
    mEl.stage.classList.add("answered");
    mEl.stage.classList.remove("pacing");
    if (ms.counting) { if (ok) ms.right++; else ms.wrong.push(st); }
    ms.streak = ok ? (ms.streak || 0) + 1 : 0;
    if (ms.streak >= 3 && ms.streak % 3 === 0) setTimeout(() => mComboFlash(ms ? ms.streak : 3), 250);
    mSfx(ok ? "yes" : "no");
    if (ok) { setMood("happy"); mSparkle(); }
    else if (!mCalm && Math.random() < 0.3) {
      setMood("shock"); mSfx("drop");
      setTimeout(() => { if (mMood === "shock") setMood("stern"); }, 1400);
    } else setMood("stern");
    setBoard(st.b);
    mLines(lines, mNext);
  }
  function mButtons(labels, onPick) {
    mEl.choices.hidden = false;
    let done = false;
    const btns = labels.map((label, i) => mBtn("m-opt", label, () => {
      if (done) return;
      done = true;
      btns.forEach(x => { x.disabled = true; });
      mFinishTyping();
      onPick(i);
    }));
    mEl.choices.replaceChildren(...btns);
    return btns;
  }
  function mAskChoice(st) {
    mSay(st.q);
    const opts = mShuffle(st.o.map((text, k) => ({ text, k })));
    const btns = mButtons(opts.map(o => o.text), idx => {
      const o = opts[idx], ok = o.k === 0;
      btns.forEach((b, j) => {
        if (opts[j].k === 0) b.classList.add("ok");
        else if (j === idx) b.classList.add("bad");
        else b.classList.add("gone");
      });
      const why = !ok && st.why && st.why[o.k];
      mAnswer(st, ok, ok
        ? [`${pick(M_YES)} ${st.e}`, st.x]
        : [`${pick(M_NO)} ${why ? why + " " : ""}Правильный ответ: «${st.o[0]}».`, st.x ? `${st.e} ${st.x}` : st.e]);
    });
  }
  function mAskTF(st) {
    mSay(st.tf);
    mEl.choices.classList.add("tf");
    const btns = mButtons(["Правда", "Миф"], idx => {
      const ok = (idx === 0) === st.t;
      btns[idx].classList.add(ok ? "ok" : "bad");
      if (!ok) btns[1 - idx].classList.add("ok");
      const verdict = st.t ? "Это правда." : "Это миф.";
      mAnswer(st, ok, ok
        ? [`${pick(M_YES)} ${verdict} ${st.e}`, st.x]
        : [`${pick(M_NO)} ${verdict}`, st.x ? `${st.e} ${st.x}` : st.e]);
    });
  }
  function mAskOrder(st) {
    mSay(`${st.ord} Нажимай по порядку.`);
    const n = st.items.length, picked = [];
    let order;
    do { order = mShuffle([...Array(n).keys()]); } while (order.every((v, i) => v === i));
    mEl.choices.hidden = false;
    mEl.choices.classList.add("ord");
    const reset = mBtn("m-mini", "↺ Сбросить", () => {
      if (picked.length === n) return;
      picked.length = 0;
      btns.forEach(b => { b.classList.remove("sel"); b.firstChild.textContent = "·"; });
      reset.hidden = true;
    });
    reset.hidden = true;
    const btns = order.map(k => {
      const b = mBtn("m-opt", null, () => {
        if (picked.includes(k) || picked.length === n) return;
        picked.push(k);
        b.firstChild.textContent = String(picked.length);
        b.classList.add("sel");
        reset.hidden = false;
        if (picked.length === n) finish();
      });
      b.append(mNode("span", "num", "·"), document.createTextNode(st.items[k][0]));
      return b;
    });
    mEl.choices.replaceChildren(...btns, reset);
    function finish() {
      mFinishTyping();
      const placed = picked.filter((k, i) => k === i).length, ok = placed === n;
      mEl.choices.replaceChildren(...st.items.map(([label, tag], i) => {
        const r = mNode("div", "m-row " + (picked[i] === i ? "ok" : "bad"));
        r.append(mNode("span", "num", String(i + 1)), document.createTextNode(label));
        if (tag) r.append(mNode("span", "tag", tag));
        return r;
      }));
      mAnswer(st, ok, ok
        ? [`${pick(M_YES)} Порядок точный. ${st.e}`]
        : [`${pick(M_NO)} На своих местах: ${placed} из ${n}. Вот как правильно — сверху вниз.`, st.e]);
    }
  }
  function mAskMatch(st) {
    mSay(`${st.mt} Выбери слева, потом справа.`);
    const n = st.pairs.length, link = Array(n).fill(-1);
    const right = mShuffle([...Array(n).keys()]);
    let sel = 0;
    mEl.choices.hidden = false;
    mEl.choices.classList.add("mt");
    const grid = mNode("div", "m-match");
    const L = st.pairs.map(([l], i) => {
      const b = mBtn("m-opt m-l", null, () => { sel = i; refresh(); });
      b.append(mNode("span", "num", String(i + 1)), document.createTextNode(l));
      return b;
    });
    const R = right.map(r => {
      const b = mBtn("m-opt m-r", null, () => {
        if (sel < 0) return;
        link.forEach((v, i) => { if (v === r) link[i] = -1; });
        link[sel] = r;
        sel = link.indexOf(-1);
        refresh();
      });
      b.append(mNode("span", "num", "·"), document.createTextNode(st.pairs[r][1]));
      return b;
    });
    L.forEach((b, i) => grid.append(b, R[i]));
    const check = mBtn("m-mini go", "Проверить", () => finish());
    check.hidden = true;
    mEl.choices.replaceChildren(grid, check);
    function refresh() {
      L.forEach((b, i) => { b.classList.toggle("sel", i === sel); });
      R.forEach((b, j) => {
        const i = link.indexOf(right[j]);
        b.firstChild.textContent = i >= 0 ? String(i + 1) : "·";
        b.classList.toggle("linked", i >= 0);
      });
      check.hidden = link.includes(-1);
    }
    refresh();
    function finish() {
      mFinishTyping();
      const good = link.filter((r, i) => r === i).length, ok = good === n;
      mEl.choices.replaceChildren(...st.pairs.map(([l, r], i) => {
        const row = mNode("div", "m-row " + (link[i] === i ? "ok" : "bad"));
        row.append(mNode("b", null, l), document.createTextNode(` — ${r}`));
        return row;
      }));
      mAnswer(st, ok, ok
        ? [`${pick(M_YES)} Все пары на месте. ${st.e}`]
        : [`${pick(M_NO)} Верных пар: ${good} из ${n}. Вот как правильно.`, st.e]);
    }
  }

  // ----- chapters, results, the end of the day -----
  function mStartChapter(k) {
    const ch = MASTER_CHAPTERS[k];
    mRun(ch.steps, { mode: "chapter", k, title: `Свиток ${k + 1}. ${ch.title}`, onDone: mChapterDone });
    mTitleCard(`Свиток ${k + 1}`, ch.title, ch.pages);
  }
  function mChapterDone() {
    if (ms.phase === "learn" && ms.wrong.length) {
      ms.phase = "review"; ms.counting = false;
      ms.steps = [{ s: pick(["Повторим то, где ты ошибся.", "Теперь — работа над ошибками.", "Вернёмся к трудным местам."]), m: "stern" }, ...ms.wrong];
      ms.i = -1;
      mEl.prog.classList.add("review");
      mEl.chapter.textContent = `${ms.title} · ошибки`;
      return mNext();
    }
    const k = ms.k, pct = ms.total ? ms.right / ms.total : 1;
    const stars = pct >= 0.9 ? 3 : pct >= 0.7 ? 2 : pct >= 0.4 ? 1 : 0;
    mSave.stars[k] = Math.max(mSave.stars[k], stars);
    mSave.done[k] = true;
    mStore();
    // the day ends after two scrolls (or four scored tasks): the master sends you home
    dayLog("scroll", `Свиток ${k + 1}. ${MASTER_CHAPTERS[k].title}`, ms.right, ms.total, ms.right * payPerStep);
    const over = dayFull(), practice = !mSave.minis[k];
    const words = ["Не спеши. Пройди свиток ещё раз.", "Ты ступил на путь. Перечитай свиток.", "Хорошо. Но путь ещё не окончен.", "Безупречно. Ты понял суть."];
    mResults({
      title: `Свиток ${k + 1} пройден`, stars, score: `С первого раза: ${ms.right} из ${ms.total}`,
      line: practice ? `${words[stars]} А теперь — практика в клинике.` : over ? `${words[stars]} А на сегодня — хватит.` : words[stars],
      buttons: practice ? [[`Практика: ${MINIS[Math.min(k, MINIS.length - 1)].title}`, () => startMini(k), "main"]]
        : over ? [["Закончить день", () => mGoHome(), "main"]] : [
        ...(k + 1 < MASTER_CHAPTERS.length ? [["Следующий свиток", () => mStartChapter(k + 1), "main"]] : []),
        ["Пройти ещё раз", () => mStartChapter(k)],
        ["К свиткам", () => mMenu()],
      ],
    });
    if (stars === 3) mSfx("star");
  }
  function mResults({ title, stars, score, line, buttons, after, trophy }) {
    ms = null;
    mLeaveLesson();
    const box = mNode("div", "m-res");
    box.append(mNode("h2", "m-h", title));
    if (stars === 3 || trophy) { const t = mNode("div", "m-trophy"); t.append(mVoxNode("on loop")); box.append(t); setTimeout(mSpin, 300); }
    if (stars != null) { const s = mStars(stars); s.classList.add("big"); box.append(s); }
    if (score) box.append(mNode("p", "m-score", score));
    const row = mNode("div", "m-btns");
    buttons.forEach(([label, fn, cls]) => row.append(mItem(label, null, null, fn, cls)));
    box.append(row);
    mPanel([box], { fig: true });
    setMood(stars == null ? "calm" : stars >= 2 ? "happy" : stars === 1 ? "calm" : "stern");
    mSay(line, { next: after || null });
  }
  // The master sends you home at dusk; then the end of the day: recap, pay, the ride home, morning.
  let mMorning = false;
  function mGoHome(first) {
    ms = null;
    mLeaveLesson();
    mEl.stage.classList.add("dusk");
    mSfx("gong");
    const allNow = mSave.done.every(Boolean) && !mSave.dayEnd;
    if (allNow) { mSave.dayEnd = true; mStore(); }
    mLines([
      first ? { text: first, mood: "happy" } : null,
      { text: "Солнце садится за крышу храма. Во дворе зажигаются фонари.", narr: true },
      { text: pick(["На сегодня хватит, ученик. Иди отдыхай.", "Два свитка за день — достаточно. Голова не бездонная.", "Всё. Остальное — завтра. Иди спать."]), mood: "calm" },
      allNow ? { text: "Все восемь свитков позади. Завтра можешь сдать экзамен.", mood: "happy" } : null,
    ], () => endDay({ onDone: goMorning }));
  }

  // ----- exam, certificate, glossary -----
  function mStartExam() {
    const pools = MASTER_CHAPTERS.map(ch => mShuffle(ch.steps.filter(st => st.q || st.tf)));
    const qs = [];
    pools.forEach(p => { if (p.length && qs.length < M_EXAM) qs.push(p.shift()); });
    const rest = mShuffle(pools.filter(p => p.length));
    while (qs.length < M_EXAM && rest.length) {
      const p = rest.shift();
      qs.push(p.shift());
      if (p.length) rest.push(p);
    }
    mShuffle(qs);
    mRun([{ s: `Экзамен. ${qs.length} вопросов из всех свитков. ${M_PASS} верных — и свиток ученика твой.`, m: "stern" }, ...qs],
      { mode: "exam", title: "Экзамен мастера", onDone: mExamDone });
  }
  function mConfirmExam() {
    ms = null;
    mLeaveLesson();
    setMood("think");
    mSay("Ты прошёл не все свитки. Экзамен будет трудным. Всё равно начнём?");
    mButtons(["Начать экзамен", "Сначала свитки"], i => (i === 0 ? mStartExam() : mMenu("Мудрое решение.")));
  }
  function mExamDone() {
    const right = ms.right, total = ms.total, pass = right >= Math.min(M_PASS, total);
    mSave.exam = Math.max(mSave.exam, right);
    if (pass) { mSave.passed = true; mSave.date = new Date().toLocaleDateString("ru-RU"); }
    mStore();
    dayLog("exam", "Экзамен мастера", right, total, right * payPerStep);
    const over = dayFull();
    mResults({
      title: pass ? "Экзамен сдан" : "Экзамен не сдан", stars: null, score: `Верных: ${right} из ${total}`,
      line: pass ? "Ты достоин свитка ученика. Впиши в него своё имя." : `Нужно ${M_PASS} верных. Перечитай свитки — и возвращайся.`,
      buttons: [...(pass ? [["Свиток ученика", mCertificate, "main"]] : []),
        ...(over ? [["Закончить день", mGoHome, pass ? "" : "main"]] : [["Сдать ещё раз", mStartExam], ["К свиткам", () => mMenu()]])],
      trophy: pass,
    });
    mSfx(pass ? "star" : "no");
  }
  function mCertificate() {
    ms = null;
    mLeaveLesson();
    const w = mNode("div", "m-cert");
    w.append(mNode("p", "m-cert-k", "Храм окклюзии"), mNode("h2", "m-cert-h", "Свиток ученика"), mNode("p", "m-cert-s", "первая ступень"),
      mNode("p", null, "Сим удостоверяется, что"));
    const name = mNode("input", "m-cert-name");
    name.type = "text"; name.maxLength = 40; name.placeholder = "впиши своё имя"; name.value = mSave.name;
    name.setAttribute("aria-label", "Имя ученика");
    name.addEventListener("input", () => { mSave.name = name.value.trim(); mStore(); });
    name.addEventListener("click", e => e.stopPropagation());
    const stars = mSave.stars.reduce((a, b) => a + b, 0);
    w.append(name,
      mNode("p", null, `прошёл(а) восемь свитков мастера окклюзии и выдержал(а) экзамен: ${mSave.exam} из ${M_EXAM}.`),
      mNode("p", null, `Звёзд за свитки: ${stars} из ${mSave.stars.length * 3}.`),
      mNode("p", "m-cert-date", mSave.date || new Date().toLocaleDateString("ru-RU")),
      mNode("div", "m-seal", "МАСТЕР"),
      mNode("p", "m-cert-fn", "* Свиток действителен в стенах храма. Смотреть пункт «Специальные условия»."),
      mItem("К свиткам", null, null, () => mMenu()));
    mPanel([w]);
    setMood("happy");
    mSay("Носи с честью. Но помни: свиток — ещё не диплом.");
  }
  function mGlossary() {
    ms = null;
    mLeaveLesson();
    const w = mNode("div", "m-gloss");
    const q = mNode("input", "m-search");
    q.type = "search"; q.placeholder = "Найти термин…"; q.setAttribute("aria-label", "Найти термин");
    q.addEventListener("click", e => e.stopPropagation());
    const dl = mNode("dl", "m-dl");
    const rows = MASTER_GLOSSARY.map(([t, d]) => {
      const dt = mNode("dt", null, t), dd = mNode("dd", null, d);
      dl.append(dt, dd);
      return [`${t} ${d}`.toLowerCase(), dt, dd];
    });
    q.addEventListener("input", () => {
      const v = q.value.trim().toLowerCase();
      rows.forEach(([txt, dt, dd]) => { dt.hidden = dd.hidden = !!v && !txt.includes(v); });
    });
    w.append(mNode("h2", "m-h", "Свиток терминов"), q, dl, mItem("К свиткам", null, null, () => mMenu()));
    mPanel([w]);
    setMood("calm");
    mSay("Здесь все понятия свитков. Забыл слово — загляни.");
  }

  // ----- the menu of scrolls -----
  function mMenu(greet) {
    ms = null;
    mBusy = false;
    mZoomClose();
    mHideGuest(true);
    mEl.ad.hidden = true;
    mEl.meme.hidden = true;
    mLeaveLesson();
    mEl.stage.classList.remove("dusk");
    const list = [mNode("h2", "m-h", `Свитки мастера · день ${day}`)];
    const nextK = mSave.done.indexOf(false);
    MASTER_CHAPTERS.forEach((ch, k) => {
      list.push(mItem(`${k + 1}. ${ch.title}`, ch.sub, mStars(mSave.stars[k]), () => mStartChapter(k), k === nextK ? "next" : ""));
    });
    list.push(mItem("Экзамен мастера", mSave.exam ? `лучший результат: ${mSave.exam} из ${M_EXAM}` : `${M_EXAM} вопросов из всех свитков, нужно ${M_PASS}`,
      null, () => (nextK === -1 || mSave.passed ? mStartExam() : mConfirmExam()), "exam"));
    list.push(mItem("Свиток терминов", `${MASTER_GLOSSARY.length} понятий с объяснениями`, null, mGlossary));
    if (mSave.passed) list.push(mItem("Свиток ученика", "твой сертификат", null, mCertificate, "cert"));
    list.push(mItem(`Звук: ${mSave.sound ? "вкл" : "выкл"}`, null, null, () => {
      mSave.sound = !mSave.sound; mStore(); mMenu(mSave.sound ? "Пусть звенит." : "Тишина — тоже учитель.");
    }, "small"));
    list.push(mItem("Главный экран", "книга запомнит, где ты остановился", null, () => goHome(), "small"));
    // start over: two taps, then the saved stars, days and pay are wiped and the game reloads
    const reset = mItem("Начать игру заново", "сотрёт звёзды, дни и зарплату", null, () => {
      if (!reset.dataset.sure) { reset.dataset.sure = "1"; reset.querySelector(".m-item-t").textContent = "Точно? Нажми ещё раз"; return; }
      try { localStorage.removeItem(M_KEY); localStorage.removeItem(DAY_KEY); } catch (e) { /* ignore */ }
      try { sessionStorage.setItem("ortho-reopen", "1"); } catch (e) { /* ignore */ }   // come back straight into the book
      location.reload();
    }, "small");
    list.push(reset);
    mPanel(list, { fig: true });
    setMood("calm");
    mSay(greet || pick(["Какой свиток откроем?", "Выбирай свиток, ученик.", "Знание любит порядок. Но выбор за тобой."]));
  }

  function startMaster() {
    mZoom.el.hidden = true;
    clearInterval(mTyping && mTyping.timer);
    mTyping = null;
    mBusy = false;
    mHideGuest(true);
    mEl.ad.hidden = true;
    mEl.meme.hidden = true;
    mEl.card.hidden = true;
    if (mSave.met) {
      const back = mBack, morning = mMorning;
      mBack = false; mMorning = false;
      const next = mSave.done.indexOf(false);
      if (back && dayFull()) return mGoHome(pick(["Руки поработали — молодец.", "Практика засчитана.", "С возвращением. Руки помнят — голова учит."]));
      if (back || morning) {
        const greet = morning
          ? pick([`Утро, ученик. День ${day}.`, `Новый день — новые свитки. День ${day}.`, `День ${day}. Чай остыл, свитки ждут.`])
          : pick(["Руки поработали — теперь голова.", "С возвращением. Руки помнят — голова учит.", "Практика — хорошо. Теперь теория."]);
        if (next < 0) return mMenu(`${greet} Все свитки пройдены — экзамен ждёт.`);
        ms = null;
        mLeaveLesson();
        setMood(morning ? "calm" : "happy");
        return mLines([{ text: `${greet} Свиток ${next + 1}: «${MASTER_CHAPTERS[next].title}».` }], () => mStartChapter(next));
      }
      return mMenu(pick(["С возвращением, ученик.", "Ты вернулся. Хорошо.", "Свитки ждут."]));
    }
    mSave.met = true; mStore();
    ms = null;
    mLeaveLesson();
    setMood("calm");
    mLines(MASTER_INTRO.map((st, i) => ({ text: st.s, narr: st.narr, mood: st.m, fn: i === 1 ? mSpin : null })), () => mStartChapter(0));
  }

  // ----- small animations -----
  const M_SVG = {
    butterfly: '<svg viewBox="0 0 9 7" shape-rendering="crispEdges"><g class="w"><rect x="0" y="0" width="3" height="3" fill="#ff8ad8"/><rect x="1" y="3" width="3" height="3" fill="#ffd36e"/><rect x="6" y="0" width="3" height="3" fill="#ff8ad8"/><rect x="5" y="3" width="3" height="3" fill="#ffd36e"/></g><rect x="4" y="1" width="1" height="5" fill="#3a2a2a"/></svg>',
    bird: '<svg viewBox="0 0 7 3" shape-rendering="crispEdges"><path fill="#2a2030" d="M0 0h1v1h1v1h1v1h1V2h1V1h1V0h1v1H6v1H5v1H2V2H1V1H0z"/></svg>',
    cloud: '<svg viewBox="0 0 16 6" shape-rendering="crispEdges"><path fill="#fff" d="M3 2h2V1h2V0h4v1h2v1h1v1h2v3H0V4h1V3h2z"/></svg>',
  };
  const M_AMBIENT = ["butterfly", "sun", "birds", "gust", "fireflies", "cloud", "star", "butterfly"];
  let mAmbBag = [];
  function mAmbient() {
    if (mCalm) return;
    if (!mAmbBag.length) mAmbBag = mShuffle([...M_AMBIENT]);
    mFx(mAmbBag.pop());
  }
  function mFx(kind) {
    const add = (cls, life, html) => {
      const n = mNode("div", "fx " + cls);
      if (html) n.innerHTML = html;
      mEl.fx.append(n);
      setTimeout(() => n.remove(), life);
      return n;
    };
    const rnd = (a, b) => a + Math.random() * (b - a);
    if (kind === "butterfly") {
      const n = add("fx-butterfly", 9000, M_SVG.butterfly);
      n.style.top = `${rnd(30, 62)}%`;
      if (Math.random() < 0.5) n.classList.add("rtl");
    } else if (kind === "birds") {
      for (let i = 0; i < 3; i++) {
        const n = add("fx-bird", 8000, M_SVG.bird);
        n.style.top = `${8 + i * 4 + rnd(0, 3)}%`;
        n.style.animationDelay = `${i * 0.35}s`;
      }
    } else if (kind === "cloud") add("fx-cloud", 16000, M_SVG.cloud);
    else if (kind === "sun") add("fx-sun", 9500);
    else if (kind === "star") add("fx-star", 1700);
    else if (kind === "gust") {
      for (let i = 0; i < 14; i++) {
        const n = add("fx-petal", 3600);
        n.style.left = `${rnd(-5, 40)}%`; n.style.top = `${rnd(10, 70)}%`;
        n.style.setProperty("--dx", `${rnd(260, 520)}px`); n.style.setProperty("--dy", `${rnd(-60, 120)}px`);
        n.style.animationDelay = `${rnd(0, 0.8)}s`;
      }
    } else if (kind === "fireflies") {
      for (let i = 0; i < 9; i++) {
        const n = add("fx-firefly", 5400);
        n.style.left = `${rnd(5, 92)}%`; n.style.top = `${rnd(45, 85)}%`;
        n.style.setProperty("--dx", `${rnd(-30, 30)}px`);
        n.style.animationDelay = `${rnd(0, 0.9)}s`;
      }
    }
  }
  function mSparkle() {
    if (mCalm) return;
    for (let i = 0; i < 10; i++) {
      const s = mNode("i", "m-spark", "✦"), a = (i / 10) * Math.PI * 2;
      s.style.setProperty("--dx", `${Math.cos(a) * 80}px`);
      s.style.setProperty("--dy", `${Math.sin(a) * 50 - 18}px`);
      s.style.animationDelay = `${(i % 3) * 40}ms`;
      mEl.box.append(s);
      setTimeout(() => s.remove(), 1100);
    }
  }

  // ----- interruptions: guests, a phone call, an ad -----
  const M_GUEST = { barin: { img: "guest_barin.png" }, patient: { img: "guest_patient.png" }, courier: { img: "guest_courier.png" }, bot: { cls: "small" } };
  let mBotUrl = "";
  function mBotPic() {
    if (!mBotUrl) {
      const cv = document.createElement("canvas");
      cv.width = 30; cv.height = 18;
      const c = cv.getContext("2d");
      drawSprite(c, BOT, 0, 1, TOOL_PAL);
      drawSprite(c, ROSE_ICON, 17, 5, TOOL_PAL);
      try { mBotUrl = cv.toDataURL(); } catch (e) { mBotUrl = ""; }
    }
    return mBotUrl;
  }
  function mShowGuest(kind, side) {
    const g = mEl.guest, info = M_GUEST[kind];
    g.className = `m-guest from-${side}${info.cls ? " " + info.cls : ""}`;
    g.style.backgroundImage = `url("${kind === "bot" ? mBotPic() : M_IMG + info.img}")`;
    g.hidden = false;
    mEl.stage.classList.add("guesting", `guest-${side}`);
  }
  function mHideGuest(now) {
    const g = mEl.guest;
    if (g.hidden) return;
    const done = () => { g.hidden = true; mEl.stage.classList.remove("guesting", "guest-left", "guest-right"); };
    if (now || mCalm) return done();
    g.classList.add("leaving");
    setTimeout(done, 480);
  }
  // Lines: [who, text, master's mood, sound] — who: "n" narration, "m" master, "g" the guest.
  const M_GAGS = {
    barin: { guest: "barin", side: "right", name: "Барин", sfx: "beads", lines: [
      ["n", "Во двор неспешно входит барин в бордовом халате. В одной руке — корзина абрикосов, в другой — чётки."],
      ["g", "Мастер-джан, барев! Абрикосы из моего сада. Сладкие, как правильная окклюзия."],
      ["m", "Спасибо. Только сахар — враг эмали.", "stern"],
      ["g", "Ай, один абрикос — это не сахар, это витамин! Как там наш ученик? Голова работает?"],
      ["m", "Голова работает. Руки догоняют.", "happy"],
      ["g", "Вот! Я ему так и сказал. Ещё вопрос: жена говорит, я ночью зубами скриплю. Это бруксизм?"],
      ["m", "Бруксизм. Так организм сбрасывает стресс.", "think"],
      ["g", "Стресс? У меня? Я самый спокойный человек в Ереване! …Ладно, учитесь, дорогие. Не мешаю."],
    ] },
    patient: { guest: "patient", side: "left", name: "Пациент", sfx: "knock", lines: [
      ["n", "Дверь приоткрывается. Заглядывает парень с перевязанной щекой."],
      ["g", "Ой… извините. Я, кажется, не туда зашёл. Тут гигиенист принимает?"],
      ["m", "Тут храм окклюзии.", "stern"],
      ["g", "А… окклюзия — это больно?"],
      ["m", "Окклюзия — это когда всё сходится. Тебе в клинику, второй этаж.", "happy"],
      ["g", "Спасибо! А можно я тоже послушаю? …Нет? Понял, ухожу."],
    ] },
    courier: { guest: "courier", side: "right", name: "Курьер", sfx: "ding", lines: [
      ["n", "Во двор бодро заходит курьер с огромным жёлтым рюкзаком."],
      ["g", "Доставка! Заказ на имя «Мастер»: рис, палочки и зубная нить — три упаковки."],
      ["m", "Я ничего не заказывал.", "stern"],
      ["g", "Тут написано: «Храм, кресло во дворе, дед в оранжевом». Это же вы?"],
      ["m", "…Оставь у кресла. Зубная нить — это мудро.", "think"],
      ["g", "Оцените доставку! Пять звёзд, как за свиток!"],
    ] },
    bot: { guest: "bot", side: "left", name: "Бот-ортодонт", lines: [
      ["n", "Мимо проезжает бот-ортодонт. В манипуляторе — та самая роза с тысячей."],
      ["g", "Мастер, это вам! В знак уважения к окклюзии!"],
      ["m", "Это щипцы Де Ла Роса?", "think"],
      ["g", "Нет. Это Де Ла Роза. Щипцы — Де Ла Роса. Я уже выучил."],
      ["m", "Мудро. Поставь у кресла. Тысячу оставь себе.", "happy"],
    ] },
    phone: { sfx: "ring", lines: [
      ["n", "В рукаве у мастера звонит телефон."],
      ["m", "Да. Нет. Я на уроке.", "stern"],
      ["m", "Нет, мама, я не забыл. Рис куплю.", "think"],
      ["m", "…И зубную нить. Да. Всё, пока.", "calm"],
      ["m", "Продолжим. Ты ничего не слышал.", "stern"],
    ] },
    quake: { sfx: "rumble", shake: true, lines: [
      ["n", "Храм мелко трясётся. С крыши сыплется пыль."],
      ["m", "Спокойно. Это не землетрясение.", "stern"],
      ["m", "Это монах этажом выше. Ночной бруксизм. Днём досыпает.", "think"],
      ["m", "Чувствуешь, какая сила? Вот об этом и свитки.", "happy"],
    ] },
    spin: { lines: [
      ["m", "Смотри, ученик. Я освоил 3D.", "happy", null, "spin"],
      ["m", "Студенты любят 3D. Но окклюзию я люблю больше.", "calm"],
      ["m", "Ладно, ещё разок.", "happy", null, "spin"],
    ] },
    meme: { meme: true },
    yawn: { lines: [
      ["n", "Мастер широко зевает. Раздаётся громкий щелчок."],
      ["m", "Ой.", "shock", "click"],
      ["m", "Щелчок при открывании рта. Farrar бы оценил.", "stern"],
      ["m", "Шучу. Сустав в порядке. Наверное.", "happy"],
    ] },
    ad: { ad: true },
  };
  const M_ADS = [
    { h: "Летим в Вену!", p: "Родина аксиографа и австрийской гнатологии. Билеты дешевле, чем полурегулируемый артикулятор*",
      fine: "* Мыщелок в багаж не сдаётся. Ручная кладь — не больше 4 дюймов между мыщелками." },
    { h: "Горящий тур в Калифорнию!", p: "По следам гнатологического общества 1926 года. Пантограф в подарок*",
      fine: "* Шесть записывающих пластин в стоимость не входят." },
  ];
  let mGagBag = [];
  function mMaybeGag(st) {
    if (!ms || ms.mode !== "chapter" || ms.phase !== "learn") return false;
    ms.sinceGag++;
    if (ms.gags >= (ms.steps.length > 40 ? 3 : 2) || ms.sinceGag < 7 || ms.i < 3 || ms.i > ms.steps.length - 3) return false;
    const forced = !ms.gags && ms.i >= Math.floor(ms.steps.length * 0.55);
    if (!forced && Math.random() > 0.15) return false;
    if (!mGagBag.length) mGagBag = mShuffle([...Object.keys(M_GAGS), "meme"]);   // memes come up twice as often
    ms.gags++; ms.sinceGag = 0;
    mGag(mGagBag.pop(), () => mRender(st));
    return true;
  }
  function mGag(id, done) {
    const g = M_GAGS[id];
    setBoard(null);
    mClearChoices();
    mEl.stage.classList.remove("asking", "answered", "pacing");
    if (g.ad) return mAdBreak(done);
    if (g.meme) {
      setMood("happy");
      return mLines([{ text: pick(["Пять минут перерыва. Даже мастер иногда листает мемы.", "Перерыв. Смотри, что мне прислали из учебника.", "Отдохни глазами. Мем из той самой книги."]) }], () => mMemeBreak(done));
    }
    setMood("calm");
    if (g.guest) mShowGuest(g.guest, g.side);
    if (g.sfx) mSfx(g.sfx);
    if (g.shake && !mCalm) {
      mEl.stage.classList.remove("shake"); void mEl.stage.offsetWidth; mEl.stage.classList.add("shake");
      setTimeout(() => mEl.stage.classList.remove("shake"), 1300);
    }
    mLines(g.lines.map(([who, text, mood, sfx, fx]) => ({
      text, narr: who === "n", guest: who === "g", name: who === "g" ? g.name : "Мастер",
      mood: who === "m" ? mood || "calm" : undefined,
      fn: sfx || fx ? () => { if (sfx) mSfx(sfx); if (fx === "spin") mSpin(); } : null,
    })), () => { mHideGuest(); setTimeout(done, mCalm ? 0 : 420); });
  }
  // Meme breaks: photos from the book itself, in a demotivator frame. Captions joke about student life, not about the people.
  const M_MEMES = [
    { id: "f15_9", cap: "Понедельник, 8:00. Первая пара — гнатология" },
    { id: "f15_11", cap: "Когда сказали: «это займёт пять минут»" },
    { id: "f13_5", cap: "Мы с другом идём сдавать окклюзию" },
    { id: "f13_4", cap: "Когда ассистент «просто подержит»" },
    { id: "f16_12", cap: "Артикулятор, который настраивали дольше, чем шла сессия" },
    { id: "f55_12", cap: "Ты ночью: «я сплю спокойно». Твоя капа утром:" },
    { id: "f40_7", cap: "Мой уровень стресса: семестр — и неделя перед экзаменом" },
  ];
  let mMemeBag = [];
  function mMemeBreak(done) {
    if (!mMemeBag.length) mMemeBag = mShuffle([...M_MEMES]);
    const mm = mMemeBag.pop(), f = BOOK[mm.id], img = $("mMemeImg");
    img.src = `assets/master/fig/${mm.id}.png`;
    img.alt = `${f.n}, страница ${f.p}: ${f.t}`;
    $("mMemeCap").textContent = mm.cap;
    $("mMemeSrc").textContent = `${f.n}, с. ${f.p} · ${f.t}`;
    mBusy = true;
    mEl.meme.hidden = false;
    mSfx("ding");
    $("mMemeOk").onclick = e => {
      e.stopPropagation();
      mEl.meme.hidden = true;
      mBusy = false;
      mLines([{ text: pick(["Смешно. А теперь — к делу.", "Мемы — тоже наука. Но на экзамене их не будет.", "Я этого не видел. Продолжаем.", "Хе-хе. Так, на чём мы остановились?"]), mood: pick(["happy", "stern"]) }], done);
    };
    $("mMemeOk").focus();
  }
  function mAdBreak(done) {
    const ad = M_ADS[Math.floor(Math.random() * M_ADS.length)], skip = $("mAdSkip");
    $("mAdH").textContent = ad.h; $("mAdP").textContent = ad.p; $("mAdFine").textContent = ad.fine;
    mBusy = true;
    mEl.ad.hidden = false;
    mSfx("jingle");
    let left = 5;
    skip.disabled = true;
    skip.textContent = `Пропустить через ${left}`;
    clearInterval(mAdBreak.t);
    mAdBreak.t = setInterval(() => {
      left--;
      if (left > 0) { skip.textContent = `Пропустить через ${left}`; return; }
      clearInterval(mAdBreak.t);
      skip.disabled = false;
      skip.textContent = "Пропустить ▶";
    }, 1000);
    skip.onclick = e => {
      e.stopPropagation();
      mEl.ad.hidden = true;
      mBusy = false;
      mLines([{ text: pick(["Кто включил рекламу посреди урока?..", "Реклама. В храме. Куда катится мир.", "Даже здесь реклама. Хотя Вена и правда красивая."]), mood: "stern" }], done);
    };
  }

  // ----- a book figure, enlarged with its full translated caption -----
  const mZoom = { el: $("mZoom"), img: $("mZoomImg"), h: $("mZoomH"), cap: $("mZoomCap"), big: $("mZoomBig"), box: $("mZoomBox") };
  function mZoomOpen(id) {
    const f = BOOK[id];
    if (!f) return;
    mZoom.el.classList.remove("big");
    mZoom.big.textContent = "Крупнее";
    mZoom.img.src = `assets/master/fig/${id}_z.webp`;
    mZoom.img.alt = `${f.n}, страница ${f.p}: ${f.t}`;
    mZoom.h.textContent = `${f.n}, с. ${f.p} · ${f.t}`;
    mZoom.cap.textContent = f.cap;
    mZoom.el.hidden = false;
    mZoom.box.scrollTop = 0; mZoom.box.scrollLeft = 0;
    $("mZoomX").focus();
  }
  function mZoomClose() {
    if (mZoom.el.hidden) return;
    mZoom.el.hidden = true;
    mEl.box.focus();
  }
  $("mZoomX").addEventListener("click", e => { e.stopPropagation(); mZoomClose(); });
  mZoom.big.addEventListener("click", e => {
    e.stopPropagation();
    const on = mZoom.el.classList.toggle("big");
    mZoom.big.textContent = on ? "Целиком" : "Крупнее";
  });
  mZoom.el.addEventListener("click", e => e.stopPropagation());   // taps inside never move the lesson on
  mEl.board.addEventListener("click", e => {
    if (!BOOK[mBoardId]) return;
    e.stopPropagation();
    mZoomOpen(mBoardId);
  });

  // dev build only: a hook for automated checks of the interruptions
  if (SKIP_TO_DIAGNOSTICS) window.__master = { gag: id => { mLeaveLesson(); mGag(id, () => mMenu("Проверка окончена.")); }, spin: () => mSpin() };

  // ----- input -----
  mEl.stage.addEventListener("click", e => {
    if (e.target.closest("button, input, .m-panel, .m-ad, .m-meme, .m-zoom")) return;
    mTap();
  });
  mEl.box.addEventListener("keydown", e => {
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); mTap(); }
  });
  mEl.exit.addEventListener("click", e => {
    e.stopPropagation();
    clearInterval(mAdBreak.t);
    mMenu("Свиток подождёт.");
  });
  document.addEventListener("keydown", e => {
    if (current !== 11 || e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey) return;
    if (!mZoom.el.hidden) {
      if (e.key === "Escape") { e.preventDefault(); mZoomClose(); }
      return;
    }
    const t = e.target;
    if (t && t.closest && t.closest("input, textarea")) return;
    if (/^[1-9]$/.test(e.key)) {
      const b = [...mEl.choices.querySelectorAll("button.m-opt:not(:disabled)")][Number(e.key) - 1];
      if (b) { e.preventDefault(); b.click(); }
      return;
    }
    if (t && t.closest && t.closest("button, [role=button]")) return;
    if (e.key === "Enter" || e.key === " " || e.key === "ArrowRight") { e.preventDefault(); mTap(); }
  });
