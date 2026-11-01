  // ---------- «Осмотр»: the doctor's own folder. A patient comes in, you go through the protocol ----------
  // Like a real chart: the same fixed set of words every time; from case to case you pick different ones.
  // Each case: photos, what the patient answers when asked, and the key for each protocol field.
  // ans: the expected choice(s); for "teeth" — tooth number → findings.
  const EXAM_PHOTOS = ["Улыбка", "Губы в покое", "Фас в прикусе", "Фас, зубы разомкнуты", "Фас снизу: перекрытие", "Справа", "Слева", "Верхняя челюсть", "Нижняя челюсть"];
  const EXAM_PROTOCOL = [
    { id: "midline", label: "Средняя линия", hint: "Сравни середину верхних и нижних резцов на фото в прикусе.",
      o: ["Совпадает", "Нижняя смещена вправо", "Нижняя смещена влево"] },
    { id: "sym", label: "Форма зубных рядов", hint: "Посмотри на окклюзионные фото: одинаковы ли половины дуги.",
      o: ["Симметричные", "Несимметричные"] },
    { id: "molR", label: "Моляры справа · класс по Энглю", hint: "Где мезиально-щёчный бугор верхнего 16 относительно борозды нижнего 46.",
      o: ["I класс", "Тенденция ко II", "II класс", "III класс"] },
    { id: "molL", label: "Моляры слева · класс по Энглю", hint: "То же для 26 и 36.",
      o: ["I класс", "Тенденция ко II", "II класс", "III класс"] },
    { id: "canR", label: "Клыки справа", hint: "Где верхний 13 относительно нижних 43 и 44.",
      o: ["I класс", "Тенденция ко II", "II класс", "III класс", "Не определить: клык вне дуги"] },
    { id: "canL", label: "Клыки слева", hint: "Где верхний 23 относительно нижних 33 и 34.",
      o: ["I класс", "Тенденция ко II", "II класс", "III класс", "Не определить: клык вне дуги"] },
    { id: "ob", label: "Перекрытие по вертикали", hint: "На сколько верхние резцы закрывают нижние.",
      o: ["Норма (до 1/3)", "Глубокое", "Прямое (краевое)", "Открытый прикус"] },
    { id: "oj", label: "Сагиттальная щель", hint: "Расстояние от верхних резцов до нижних спереди назад.",
      o: ["Норма", "Увеличена", "Обратная"] },
    { id: "crowdU", label: "Скученность вверху", o: ["Нет", "Лёгкая", "Средняя", "Выраженная"] },
    { id: "crowdL", label: "Скученность внизу", o: ["Нет", "Лёгкая", "Средняя", "Выраженная"] },
    { id: "teeth", label: "Положение отдельных зубов", hint: "Нажми на зуб в формуле и отметь, что с ним. Без находок — пропусти.", teeth: true },
    { id: "eights", label: "Зубы мудрости (восьмёрки)", hint: "На фото их не видно — спроси пациента.",
      o: ["Есть, прорезались", "Нет зачатков", "Уточнить по ОПТГ"] },
  ];
  const TOOTH_FINDINGS = ["Ротация", "Вестибулярно", "Нёбно / язычно", "Экструзия", "Интрузия (не дошёл до плоскости)", "Нет зуба"];
  const EXAM_CASES = [
    { id: "e1", name: "Пациентка А.", age: "подросток", photos: "assets/exam/p1_", n: 9, draft: true,
      complaint: "Мама привела: «Клык вырос не на месте, и зубы кривые».",
      asks: [
        ["Что беспокоит?", "Клык слева торчит, когда улыбаюсь. И передние зубы неровные."],
        ["Есть ли зубы мудрости?", "Не знаю… Сзади ничего не болит и не режется."],
        ["Носили брекеты или пластинку?", "Нет, никогда."],
        ["Дышите носом или ртом?", "Носом. Ну, ночью, может, ртом — мама говорит, сплю с открытым."],
      ],
      ans: { midline: "Совпадает", sym: "Несимметричные", molR: "I класс", molL: "I класс", canR: "I класс", canL: "Не определить: клык вне дуги",
        ob: "Норма (до 1/3)", oj: "Норма", crowdU: "Выраженная", crowdL: "Средняя", eights: "Уточнить по ОПТГ",
        teeth: { 23: ["Вестибулярно", "Интрузия (не дошёл до плоскости)"], 22: ["Нёбно / язычно"], 21: ["Ротация"] } },
      why: {
        sym: "Слева клык 23 вне дуги, ему не хватило места — половины дуги разные.",
        canL: "Клык 23 стоит вестибулярно и высоко, по нему класс не определить.",
        crowdU: "Клыку 23 не хватило места, 22 смещён нёбно, 21 повёрнут.",
        crowdL: "Нижние резцы и клыки стоят неровно, им тесно.",
        eights: "На фото восьмёрок не видно, пациентка не знает — нужна ортопантомограмма.",
        teeth: "23 — вестибулярно и высоко; 22 — нёбно; 21 — ротация.",
      } },
  ];
  const EXAM_KEY = "ortho-exam-v1";
  const examSave = (() => { try { const s = JSON.parse(localStorage.getItem(EXAM_KEY) || "null"); return s && s.done ? s : { done: {} }; } catch (e) { return { done: {} }; } })();
  const examStore = () => { try { localStorage.setItem(EXAM_KEY, JSON.stringify(examSave)); } catch (e) { /* ignore */ } };
  const examsLeft = () => EXAM_CASES.filter(c => !examSave.done[c.id]).length;
  const UP = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28], LO = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];
  function examList() {
    $("cardBack").hidden = true; $("cardNavTitle").textContent = "";
    const out = [el("h1", "ca-h1", "Приём"), el("p", "ca-sub", "Ты врач. Пациент в кресле — проведи осмотр по протоколу и подпиши его.")];
    const g = el("div", "ca-group");
    for (const c of EXAM_CASES) {
      const r = el("button", "ca-row"); r.type = "button";
      const av = el("span", "ca-av ex-av"); av.style.backgroundImage = `url("${c.photos}1.png")`;
      const t = el("span", "ca-row-t"); t.append(el("b", null, `${c.name}, ${c.age}`), el("span", null, c.complaint));
      const d = examSave.done[c.id];
      r.append(av, t, el("span", d ? (d.right === d.total ? "ca-st ok" : "ca-st") : "ca-st new", d ? `${d.right}/${d.total}` : "ждёт"));
      r.addEventListener("click", () => examOpen(c));
      g.append(r);
    }
    out.push(g, el("p", "ca-sub ex-more", "Новые пациенты появятся, когда будут их фото."));
    cardBody.replaceChildren(...out); cardBody.scrollTop = 0;
  }
  // full-screen photo viewer: tap the sides or swipe to flip
  function examViewer(c, i) {
    const v = el("div", "ex-view"), img = el("img"), cap = el("p", "ex-view-cap"), x = el("button", "ex-view-x", "✕");
    x.type = "button";
    const set = k => { i = (k + c.n) % c.n; img.src = `${c.photos}${i + 1}.png`; img.alt = EXAM_PHOTOS[i]; cap.textContent = `${i + 1} / ${c.n} · ${EXAM_PHOTOS[i]}`; };
    let sx = null;
    v.addEventListener("pointerdown", e => { sx = e.clientX; });
    v.addEventListener("pointerup", e => {
      if (e.target === x) return;
      const dx = sx === null ? 0 : e.clientX - sx; sx = null;
      if (Math.abs(dx) > 40) set(i + (dx < 0 ? 1 : -1)); else set(i + (e.clientX < innerWidth / 2 ? -1 : 1));
    });
    const close = () => { v.remove(); document.removeEventListener("keydown", key, true); };
    const key = e => { if (e.key === "Escape") { e.preventDefault(); close(); } else if (e.key === "ArrowLeft") set(i - 1); else if (e.key === "ArrowRight") set(i + 1); };
    x.addEventListener("click", close);
    document.addEventListener("keydown", key, true);
    v.append(img, cap, x); set(i); cardApp.append(v);
  }
  function examOpen(c) {
    $("cardBack").hidden = false; $("cardNavTitle").textContent = c.name;
    const pick = {}, teeth = {};
    let step = 0;
    const strip = el("div", "ex-strip");
    for (let i = 0; i < c.n; i++) {
      const b = el("button", "ex-thumb"); b.type = "button";
      const im = el("img"); im.src = `${c.photos}${i + 1}.png`; im.alt = EXAM_PHOTOS[i];
      b.append(im, el("span", null, EXAM_PHOTOS[i])); b.addEventListener("click", () => examViewer(c, i));
      strip.append(b);
    }
    const chat = el("div", "ex-chat");
    const asks = el("div", "ca-group ex-asks");
    for (const [q, a] of c.asks) {
      const b = el("button", "ca-opt"); b.type = "button"; b.append(el("span", null, `— ${q}`));
      b.addEventListener("click", () => {
        b.disabled = true;
        chat.append(el("p", "ex-q", q), el("p", "ex-a", a));
      });
      asks.append(b);
    }
    const steps = el("div", "ex-steps");
    const counter = el("p", "ex-count");
    const sign = el("button", "ca-sign", "Подписать осмотр"); sign.type = "button"; sign.hidden = true;
    const result = el("div", "ex-result"); result.hidden = true;
    const stepEls = EXAM_PROTOCOL.map((p, k) => {
      const box = el("section", "ca-sec ex-step"); box.hidden = true;
      const h = el("p", "ca-sec-h", `${k + 1}. ${p.label}`);
      const body = el("div");
      if (p.teeth) {
        const chart = el("div", "ca-group ex-chart");
        const menu = el("div", "ex-menu"); menu.hidden = true;
        let cur = null;
        const row = list => { const r = el("div", "ex-trow"); for (const n of list) {
          const t = el("button", "ex-tooth"); t.type = "button"; t.textContent = n; t.dataset.n = n;
          t.addEventListener("click", () => {
            if (box.dataset.locked) return;
            cur = n; chart.querySelectorAll(".ex-tooth").forEach(x => x.classList.toggle("cur", +x.dataset.n === n));
            menu.hidden = false; menu.querySelector(".ex-menu-h").textContent = `Зуб ${n}`;
            menu.querySelectorAll(".ex-chip").forEach(ch => ch.classList.toggle("on", (teeth[n] || []).includes(ch.textContent)));
          });
          r.append(t);
        } return r; };
        chart.append(row(UP), el("div", "ex-tsep"), row(LO));
        menu.append(el("p", "ex-menu-h"));
        for (const f of TOOTH_FINDINGS) {
          const ch = el("button", "ex-chip", f); ch.type = "button";
          ch.addEventListener("click", () => {
            if (cur === null || box.dataset.locked) return;
            const s = new Set(teeth[cur] || []); s.has(f) ? s.delete(f) : s.add(f);
            if (s.size) teeth[cur] = [...s]; else delete teeth[cur];
            ch.classList.toggle("on", s.has(f));
            chart.querySelector(`.ex-tooth[data-n="${cur}"]`).classList.toggle("marked", !!teeth[cur]);
          });
          menu.append(ch);
        }
        const next = el("button", "ca-sign ex-next", "Готово, дальше"); next.type = "button";
        next.addEventListener("click", () => { if (box.dataset.locked) return; next.hidden = true; advance(k); });
        body.append(chart, menu, next);
      } else {
        const g = el("div", "ca-group ca-opts");
        for (const o of p.o) {
          const b = el("button", "ca-opt"); b.type = "button"; b.dataset.v = o;
          b.append(el("span", "ca-dot"), el("span", null, o));
          b.addEventListener("click", () => {
            if (box.dataset.locked) return;
            const first = pick[p.id] === undefined;
            pick[p.id] = o;
            g.querySelectorAll(".ca-opt").forEach(x => x.classList.toggle("sel", x.dataset.v === o));
            if (first) advance(k);
          });
          g.append(b);
        }
        body.append(g);
      }
      if (p.hint) body.prepend(el("p", "ex-hint", p.hint));
      box.append(h, body);
      return box;
    });
    stepEls.forEach(s => steps.append(s));
    function advance(k) {
      step = Math.max(step, k + 1);
      counter.textContent = `Протокол: ${Math.min(step, EXAM_PROTOCOL.length)} из ${EXAM_PROTOCOL.length}`;
      if (step < EXAM_PROTOCOL.length) {
        stepEls[step].hidden = false;
        if (!homeCalm()) stepEls[step].animate([{ opacity: 0, transform: "translateY(8px)" }, { opacity: 1, transform: "none" }], { duration: 220 });
        setTimeout(() => stepEls[step].scrollIntoView({ behavior: homeCalm() ? "auto" : "smooth", block: "nearest" }), 30);
      } else { sign.hidden = false; setTimeout(() => sign.scrollIntoView({ behavior: "smooth", block: "nearest" }), 30); }
    }
    sign.addEventListener("click", () => {
      if (sign.dataset.done) return;
      sign.dataset.done = "1";
      let right = 0, total = 0;
      const lines = [];
      EXAM_PROTOCOL.forEach((p, k) => {
        const box = stepEls[k]; box.dataset.locked = "1";
        let ok, mine, key;
        if (p.teeth) {
          const want = c.ans.teeth, nums = new Set([...Object.keys(want), ...Object.keys(teeth)]);
          ok = [...nums].every(n => (want[n] || []).every(f => (teeth[n] || []).includes(f)) && (teeth[n] || []).every(f => (want[n] || []).includes(f)));
          mine = Object.keys(teeth).length ? Object.entries(teeth).map(([n, f]) => `${n}: ${f.join(", ").toLowerCase()}`).join("; ") : "без находок";
          key = Object.entries(want).map(([n, f]) => `${n}: ${f.join(", ").toLowerCase()}`).join("; ");
          box.querySelectorAll(".ex-tooth").forEach(t => { const n = t.dataset.n; if (want[n]) t.classList.add((teeth[n] || []).length ? "hit" : "miss"); else if (teeth[n]) t.classList.add("extra"); });
        } else {
          mine = pick[p.id]; key = c.ans[p.id]; ok = mine === key;
          box.querySelectorAll(".ca-opt").forEach(x => { x.disabled = true; x.classList.toggle("right", x.dataset.v === key); x.classList.toggle("wrong", x.dataset.v === mine && !ok); });
        }
        total++; if (ok) right++;
        const fb = el("div", "ca-fb " + (ok ? "ok" : "bad"));
        fb.append(el("b", null, ok ? "Совпадает с эталоном." : `Эталон: ${key}.`));
        if (c.why[p.id]) fb.append(el("span", null, ` ${c.why[p.id]}`));
        box.append(fb);
        lines.push(`${p.label}: ${mine}.`);
      });
      const prev = examSave.done[c.id];
      if (!prev || right > prev.right) examSave.done[c.id] = { right, total };
      examStore();
      const pay = right * payPerStep;
      if (!prev) dayLog("shift", `Осмотр: ${c.name}`, right, total, pay);
      result.hidden = false;
      result.replaceChildren(
        el("div", "ex-stamp" + (right === total ? " ok" : ""), right === total ? "ОСМОТР ПРИНЯТ" : right >= total * 0.7 ? "ПРИНЯТ С ЗАМЕЧАНИЯМИ" : "НА ДОРАБОТКУ"),
        el("p", "ca-sec-h", "Протокол осмотра"),
        el("p", "ca-hand", `${c.name}. Жалобы: ${c.complaint} ` + lines.join(" ")),
        el("p", "ca-score", `Совпало с эталоном ${right} из ${total}` + (prev ? "" : ` · +${rub(pay)} ₽ в зарплату дня`)));
      if (c.draft) result.append(el("p", "ex-hint", "Эталон этого случая — черновик по фото, его проверяет автор игры."));
      const again = el("button", "ca-link", "Осмотреть заново"); again.type = "button"; again.addEventListener("click", () => examOpen(c));
      result.append(again);
      result.scrollIntoView({ behavior: homeCalm() ? "auto" : "smooth", block: "start" });
    });
    cardBody.replaceChildren(
      el("h1", "ca-h1", c.name),
      el("section", "ca-sec", ""),
      strip,
      el("p", "ex-hint ex-tap", "Нажми на фото — откроется крупно, листай свайпом."),
      (() => { const s = el("section", "ca-sec"); s.append(el("p", "ca-sec-h", "Жалобы"), el("p", "ca-text", c.complaint)); return s; })(),
      (() => { const s = el("section", "ca-sec"); s.append(el("p", "ca-sec-h", "Спросить пациента"), asks, chat); return s; })(),
      counter, steps, sign, result);
    stepEls[0].hidden = false;
    counter.textContent = `Протокол: 0 из ${EXAM_PROTOCOL.length}`;
    cardBody.scrollTop = 0;
  }
