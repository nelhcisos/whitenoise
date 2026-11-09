  // ---------- «Карта пациента»: fill in a patient's record from what the scrolls taught ----------
  // Each case: who came, the complaint, the condylogram (a figure from the book) and the record's
  // fields. In every field the first option is the right one; options are shuffled on screen.
  // k: the scroll (1-based) where the answer is explained.
  const CARD_CASES = [
    { id: "c1", name: "Анна К.", age: 24, job: "студентка", fig: "f110_13",
      complaint: "Иногда тихо щёлкает в суставе при открывании рта. Не болит, рот открывается свободно.",
      history: "Заметила полгода назад. Других жалоб нет.",
      trace: "При открывании в первые 1–3 мм кривая выпуклая, потом вогнутая.",
      fields: [
        { label: "Находка на кондилограмме", o: ["Changing character", "Чрезмерное вращение (over rotation)", "Восьмёрка реципрокного щелчка", "Мыщелок не уходит от RP"],
          why: [null, "Over rotation — лишний поворот у максимального открывания, а здесь изгиб в самом начале.", "Восьмёрки здесь нет — щелчок лёгкий, кривая одна.", "Мыщелок уходит нормально."],
          e: "Выпуклый изгиб в начале открывания — changing character.", k: 12 },
        { label: "Стадия нарушения", o: ["Стадия 1", "Стадия 3", "Стадия 4", "Стадия 5"],
          why: [null, "На 3-й стадии уже боль, заклинивание и ограничение.", "На 4-й диск не вправляется и меняются кости.", "5-я — остеоартроз с болью и хрустом."],
          e: "Лёгкий безболезненный щелчок без ограничения, changing character на записи.", k: 16 },
        { label: "Где искать лечебное положение (ThP)", o: ["У точки перегиба, на 2–3 мм впереди", "В самом заднем положении", "На максимальном открывании", "Там, где пациенту удобно"],
          why: [null, "Заднее положение и есть проблема.", "Слишком далеко.", "Удобство — не критерий."],
          e: "Где выпуклая кривая переходит в вогнутую.", k: 15 },
      ] },
    { id: "c2", name: "Игорь М.", age: 31, job: "менеджер", fig: "f113_3",
      complaint: "Щёлкает и когда открываю рот, и когда закрываю. Иногда больно, бывает, челюсть заклинивает. Голова болит.",
      history: "Щелчок два года, заклинивать стало в последние месяцы.",
      trace: "Пути открывания и закрывания перекрещиваются «восьмёркой»; щелчок закрывания ближе к RP.",
      fields: [
        { label: "Вид щелчка", o: ["Реципрокный", "Щелчок вращения", "Over-rotational", "ΔY-shift"],
          why: [null, "Щелчок вращения — при вращении, без восьмёрки.", "Over-rotational — в самом конце открывания разболтанного сустава.", "ΔY-shift — сдвиг по оси Y, сбоку его не видно."],
          e: "Щелчок при открывании и при закрывании, след — восьмёрка.", k: 16 },
        { label: "Стадия нарушения", o: ["Стадия 2", "Стадия 1", "Стадия 4", "Стадия 5"],
          why: [null, "На 1-й щелчок лёгкий и без боли.", "На 4-й диск уже не вправляется.", "5-я — остеоартроз."],
          e: "Диск ещё вправляется, но временами больно и заклинивает; чёткая восьмёрка.", k: 16 },
        { label: "Лечебное положение (ThP)", o: ["Сразу перед щелчком закрывания", "Сразу после щелчка открывания", "В RP", "На максимальном открывании"],
          why: [null, "Ориентир — щелчок закрывания.", "В RP диск смещён.", "Слишком далеко."],
          e: "Щелчок закрывания ближе к RP — ThP прямо перед ним.", k: 16 },
      ] },
    { id: "c3", name: "Марина С.", age: 28, job: "бухгалтер", fig: "f119_11",
      complaint: "Утром не смогла открыть рот широко. Больно. Раньше щёлкало, а теперь щелчок пропал.",
      history: "Открывание 27 мм. Вращение есть, дальше не идёт.",
      trace: "При открывании и движении вперёд мыщелок топчется возле RP.",
      fields: [
        { label: "Диагноз", o: ["Острый закрытый замок", "Частичный замок", "Хронический свободный замок", "Норма"],
          why: [null, "При частичном движение вперёд свободно, а здесь и оно ограничено.", "Хронический — без острой боли и с большим открыванием.", "Открывание 27 мм — не норма."],
          e: "Диск не вправляется, скольжения нет, открывание только вращением.", k: 16 },
        { label: "Почему пропал щелчок", o: ["Диск перестал вправляться", "Сустав выздоровел", "Щелчок ушёл в ось Y", "Его заглушили мышцы"],
          why: [null, "Пропавший щелчок с ограничением — не выздоровление.", "ΔY-shift — другое.", "Мышцы щелчок не глушат."],
          e: "Смещение диска с вправлением перешло в смещение без вправления — closed lock.", k: 16 },
        { label: "Чем ограничено открывание", o: ["Только вращением: 25–30 мм", "Ничем", "Скольжением в нижнем отделе", "Наружной связкой при движении вперёд"],
          why: [null, "Ограничено, и заметно.", "Скольжения как раз нет.", "Вперёд тоже не идёт — дело не только в связке."],
          e: "При остром тугом замке открывание 25–30 мм.", k: 16 },
      ] },
    { id: "c4", name: "Олег П.", age: 35, job: "водитель", fig: "f119_11",
      complaint: "Рот открывается не полностью. А челюсть вперёд и в стороны двигается нормально.",
      history: "Давно щёлкало слева, потом щелчок стал реже.",
      trace: "Открывание ограничено несколькими миллиметрами; движение вперёд и медиотрузия свободны.",
      fields: [
        { label: "Диагноз", o: ["Частичный (связочный) замок", "Острый закрытый замок", "Разболтанность без замка", "Норма"],
          why: [null, "При остром ограничено и движение вперёд.", "Разболтанность даёт больший ход, а не ограничение.", "Открывание ограничено — не норма."],
          e: "Ограничено только движение с вращением.", k: 16 },
        { label: "Механизм", o: ["Наружный полюс мыщелка упирается в натянутую латеральную связку, диск смещён вперёд-внутрь", "Диск смещён назад", "Спазм височной мышцы", "Зубы мешают смыканию"],
          why: [null, "Назад диск уходит при щелчке вращения.", "Мышечное ограничение обычно с болью в мышце, и вперёд тоже трудно.", "Зубы тут ни при чём."],
          e: "При вращении связка натягивается — скольжение вперёд невозможно.", k: 16 },
        { label: "Как выглядит запись", o: ["Открывание коротко, движение вперёд и вбок почти норма", "Всё одинаково ограничено", "Ход больше нормы", "Восьмёрка"],
          why: [null, "Это острый тугой замок.", "Это скорее разболтанность.", "Восьмёрка — реципрокный щелчок."],
          e: "Движения без вращения связку не натягивают.", k: 16 },
      ] },
    { id: "c5", name: "Светлана В.", age: 42, job: "певица", fig: "f116_6",
      complaint: "Когда широко открываю рот, в конце что-то щёлкает, будто челюсть выскакивает.",
      history: "Однажды не могла закрыть рот несколько минут.",
      trace: "Ход мыщелка увеличен. У максимального открывания скольжение почти закончилось, а мыщелок доворачивается примерно на 15°.",
      fields: [
        { label: "Вид щелчка", o: ["Over-rotational (щелчок бугорка)", "Реципрокный", "Щелчок вращения в начале открывания", "ΔY-shift"],
          why: [null, "Реципрокный — при открывании и закрывании, восьмёрка.", "Здесь щелчок в самом конце, а не в начале.", "Сдвиг по Y здесь не главное."],
          e: "Чрезмерный поворот в конце открывания разболтанного сустава.", k: 16 },
        { label: "Что это говорит о суставе", o: ["Сустав разболтан", "Сустав в норме", "Острый замок", "Ось найдена неверно"],
          why: [null, "Лишний поворот — не норма.", "При замке ход меньше, а здесь больше.", "Ось может давать странную кривую, но тут классическая картина."],
          e: "Over rotation подтверждают анализом Trans/Rot.", k: 12 },
        { label: "Чем грозит, если не лечить", o: ["Вывихом: рот не закрыть", "Ростом мыщелка", "Кариесом", "Ничем"],
          why: [null, "Мыщелок не растёт от этого.", "Кариес ни при чём.", "Риск есть."],
          e: "Книга: дальше — luxation, рот не закрывается.", k: 16 },
      ] },
    { id: "c6", name: "Дмитрий Л.", age: 26, job: "программист", fig: "f116_8",
      complaint: "Почти ничего не беспокоит, иногда неприятно в суставе при открывании.",
      history: "Сбоку на записи щелчка не видно.",
      trace: "В сагиттальной проекции кривая чистая, а по оси Y — чёткий сдвиг около 1 мм.",
      fields: [
        { label: "Находка", o: ["Поперечный щелчок (ΔY-shift)", "Всё в норме", "Реципрокный щелчок", "Начальный угол Фишера"],
          why: [null, "Сдвиг 1 мм по Y — находка.", "Восьмёрки нет.", "Угол Фишера ищут наложением движения вперёд и медиотрузии."],
          e: "Щелчок бывает только по горизонтали.", k: 16 },
        { label: "Где лечебное положение", o: ["Перед последним сдвигом при закрывании", "В RP", "На середине открывания", "Где пациенту удобно"],
          why: [null, "RP здесь смещено.", "Ориентир — сдвиг при закрывании.", "Удобство — не критерий."],
          e: "Как в примере книги (красный кружок).", k: 16 },
      ] },
    { id: "c7", name: "Елена Г.", age: 50, job: "преподаватель", fig: "f114_5",
      complaint: "Сильная боль в суставе, хрустит. Рот открывается плохо. Болят шея и плечи, шумит в ушах.",
      history: "Проблемы с суставом много лет. На снимках мыщелок за несколько лет сильно уменьшился.",
      trace: "Хронический замок с ограничением движения.",
      fields: [
        { label: "Стадия нарушения", o: ["Стадия 5 — остеоартроз", "Стадия 1", "Стадия 2", "Стадия 3"],
          why: [null, "На 1-й лёгкий щелчок без боли.", "На 2-й диск ещё вправляется.", "На 3-й кости ещё не меняются."],
          e: "Дегенерация мыщелка и бугорка, крепитация, вегетативные симптомы.", k: 16 },
        { label: "Как называется хруст", o: ["Крепитация", "Реципрокный щелчок", "Щелчок бугорка", "Бруксизм"],
          why: [null, "Реципрокный — щелчок, а не хруст.", "Это over-rotational click.", "Бруксизм — скрежет зубами."],
          e: "Хруст — признак остеоартроза.", k: 16 },
        { label: "Что видно на цефалограмме таких пациентов", o: ["Крутая задняя окклюзионная плоскость (POP)", "Пологая POP", "Идеальный I класс", "Ничего особенного"],
          why: [null, "В примере книги — наоборот, крутая.", "Не обязательно.", "Как раз есть на что обратить внимание."],
          e: "Книга просит обратить внимание на крутую POP.", k: 16 },
      ] },
    { id: "c8", name: "Пациент на записи", age: 33, job: "инженер", fig: "f77_6",
      complaint: "Жалоб нет. Пришёл на плановую кондилографию.",
      history: "Запись только что сделал новый ассистент.",
      trace: "Кривая открывания странная, ни на что не похожая.",
      fields: [
        { label: "Первое действие", o: ["Проверить, точно ли найдена шарнирная ось", "Сразу ставить диагноз", "Записать только с компьютерной осью", "Отпустить пациента"],
          why: [null, "С неверной осью диагноз будет неточным.", "Компьютерная ось — только проверка.", "Сначала разберись с записью."],
          e: "Сдвиг оси на 10 мм заметно меняет форму кривой.", k: 11 },
        { label: "Как найти ось правильно", o: ["Методом проб и ошибок: вращение без скольжения, пока штифт не крутится на месте", "Попросить пациента жевать", "Поставить штифт у уха на глаз", "Доверить компьютеру"],
          why: [null, "При жевании есть скольжение.", "На глаз — неточно.", "Компьютер найдёт центр даже неправильного вращения."],
          e: "Ось примерно в 3 раза дальше хода штифта.", k: 11 },
        { label: "Сколько раз повторять каждую запись", o: ["2–3 раза", "Один", "10 раз", "Не важно"],
          why: [null, "Нужно проверить воспроизводимость.", "Слишком много.", "Важно — по стандарту."],
          e: "Стандарт записи: каждое движение 2–3 раза.", k: 11 },
      ] },
  ];
  const CARD_KEY = "ortho-cards-v1";
  const cardSave = (() => { try { const s = JSON.parse(localStorage.getItem(CARD_KEY) || "null"); return s && typeof s.done === "object" && s.done ? s : { done: {} }; } catch (e) { return { done: {} }; } })();
  const cardStore = () => { try { localStorage.setItem(CARD_KEY, JSON.stringify(cardSave)); } catch (e) { /* ignore */ } };
  const cardsLeft = () => CARD_CASES.filter(c => !cardSave.done[c.id]).length;
  const cardApp = $("cardApp"), cardBody = $("cardBody");
  const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; };
  function cardList() {
    $("cardBack").hidden = true;
    $("cardNavTitle").textContent = "";
    const done = CARD_CASES.length - cardsLeft();
    const out = [el("h1", "ca-h1", "Карты пациентов"),
      el("p", "ca-sub", `Кондилография · заполнено ${done} из ${CARD_CASES.length}. Заполни карту по знаниям из свитков мастера.`)];
    const g = el("div", "ca-group");
    for (const c of CARD_CASES) {
      const r = el("button", "ca-row"); r.type = "button";
      const av = el("span", "ca-av", c.name.split(" ").map(w => w[0]).join("").slice(0, 2));
      const t = el("span", "ca-row-t");
      t.append(el("b", null, `${c.name}, ${c.age}`), el("span", null, c.complaint));
      const d = cardSave.done[c.id];
      const st = el("span", d ? (d.right === d.total ? "ca-st ok" : "ca-st") : "ca-st new", d ? `${d.right}/${d.total}` : "новая");
      r.append(av, t, st);
      r.addEventListener("click", () => cardOpen(c));
      g.append(r);
    }
    out.push(g);
    cardBody.replaceChildren(...out);
    cardBody.scrollTop = 0;
  }
  function cardOpen(c) {
    $("cardBack").hidden = false;
    $("cardNavTitle").textContent = c.name;
    const f = BOOK[c.fig];
    const picks = c.fields.map(() => -1);
    const orders = c.fields.map(fd => mShuffle(fd.o.map((_, i) => i)));
    const sec = (title, ...kids) => { const s = el("section", "ca-sec"); s.append(el("p", "ca-sec-h", title), ...kids); return s; };
    const info = el("div", "ca-group ca-info");
    for (const [k, v] of [["Пациент", c.name], ["Возраст", `${c.age}`], ["Профессия", c.job]]) { const r = el("div", "ca-kv"); r.append(el("span", null, k), el("b", null, v)); info.append(r); }
    const fig = el("figure", "ca-fig");
    const img = el("img"); img.src = `assets/master/fig/${c.fig}_z.webp`; img.alt = f ? `${f.n}: ${f.t}` : "";
    fig.append(img, el("figcaption", null, f ? `${figSrc(f)} · ${f.t}` : ""));
    const sign = el("button", "ca-sign", "Подписать карту"); sign.type = "button"; sign.disabled = true;
    const fieldEls = c.fields.map((fd, i) => {
      const g = el("div", "ca-group ca-opts");
      orders[i].forEach(j => {
        const b = el("button", "ca-opt"); b.type = "button"; b.dataset.j = j;
        b.append(el("span", "ca-dot"), el("span", null, fd.o[j]));
        b.addEventListener("click", () => {
          if (sign.dataset.signed) return;
          picks[i] = j;
          g.querySelectorAll(".ca-opt").forEach(x => x.classList.toggle("sel", +x.dataset.j === j));
          sign.disabled = picks.includes(-1);
        });
        g.append(b);
      });
      const fb = el("div", "ca-fb"); fb.hidden = true;
      return { g, fb, sec: sec(fd.label, g, fb) };
    });
    const concl = el("div", "ca-concl"); concl.hidden = true;
    sign.addEventListener("click", () => {
      if (sign.dataset.signed || picks.includes(-1)) return;
      sign.dataset.signed = "1";
      let right = 0;
      c.fields.forEach((fd, i) => {
        const ok = picks[i] === 0; if (ok) right++;
        const { g, fb } = fieldEls[i];
        g.querySelectorAll(".ca-opt").forEach(x => { const j = +x.dataset.j; x.disabled = true; x.classList.toggle("right", j === 0); x.classList.toggle("wrong", j === picks[i] && !ok); });
        fb.hidden = false;
        fb.className = "ca-fb " + (ok ? "ok" : "bad");
        fb.replaceChildren(el("b", null, ok ? "Верно." : `Нет: ${fd.why[picks[i]] || ""}`), el("span", null, ` ${fd.e}`), el("small", null, `Свиток ${fd.k}. ${MASTER_CHAPTERS[fd.k - 1] ? MASTER_CHAPTERS[fd.k - 1].title : ""}`));
      });
      const pay = right * payPerStep;
      const prev = cardSave.done[c.id];
      if (!prev || right > prev.right) cardSave.done[c.id] = { right, total: c.fields.length };
      cardStore();
      if (!prev) dayLog("shift", `Карта пациента: ${c.name}`, right, c.fields.length, pay);
      concl.hidden = false;
      concl.replaceChildren(el("p", "ca-sec-h", "Заключение"),
        el("p", "ca-hand", `${c.name}, ${c.age} л. Жалобы: «${c.complaint}» ` + c.fields.map((fd, i) => `${fd.label}: ${fd.o[picks[i]]}.`).join(" ")),
        el("p", "ca-score", `Верно ${right} из ${c.fields.length}` + (prev ? "" : ` · +${rub(pay)} ₽ в зарплату дня`)));
      sign.textContent = right === c.fields.length ? "Карта подписана ✓" : "Карта подписана";
      const again = el("button", "ca-link", "Заполнить заново"); again.type = "button";
      again.addEventListener("click", () => cardOpen(c));
      const next = CARD_CASES[(CARD_CASES.indexOf(c) + 1) % CARD_CASES.length];
      const nb = el("button", "ca-sign", `Следующий: ${next.name}`); nb.type = "button";
      nb.addEventListener("click", () => cardOpen(next));
      concl.append(nb, again);
      concl.scrollIntoView({ behavior: homeCalm() ? "auto" : "smooth", block: "start" });
    });
    cardBody.replaceChildren(
      el("h1", "ca-h1", c.name),
      sec("Паспорт", info),
      sec("Жалобы", el("p", "ca-text", c.complaint)),
      sec("Анамнез", el("p", "ca-text", c.history)),
      sec("Кондилограмма", fig, el("p", "ca-text", c.trace)),
      ...fieldEls.map(x => x.sec),
      sign, concl);
    cardBody.scrollTop = 0;
  }
  $("cardBack").addEventListener("click", cardList);
