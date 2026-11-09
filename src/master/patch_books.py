# The master's engine learns about books: each book has its own teacher, scrolls, numbering and menu.
#   python3 patch_books.py <scratch dir with master_engine.js and master_css.css>
import sys
SP = sys.argv[1]

def patch(name, pairs):
    p = f"{SP}/{name}"
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, (name, n, old[:90])
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)
    print("patched", name)

patch("master_css.css", [
    ('background-image: url("assets/master/master_walk.png"); background-size: 200% 100%;',
     'background-image: var(--walk, url("assets/master/master_walk.png")); background-size: 200% 100%;'),
])

patch("master_engine.js", [
    # save: met per book
    ('return { stars: Array(n).fill(0), done: Array(n).fill(false), minis: Array(n).fill(false), exam: 0, passed: false, name: "", date: "", met: false, dayEnd: false, sound: true };',
     'return { stars: Array(n).fill(0), done: Array(n).fill(false), minis: Array(n).fill(false), exam: 0, passed: false, name: "", date: "", met: false, posMet: false, dayEnd: false, sound: true };'),
    ('for (const k of ["exam", "passed", "name", "date", "met", "dayEnd", "sound"]) if (typeof s[k] === typeof d[k]) d[k] = s[k];',
     'for (const k of ["exam", "passed", "name", "date", "met", "posMet", "dayEnd", "sound"]) if (typeof s[k] === typeof d[k]) d[k] = s[k];'),
    ('''  const mSave = mLoad();
  function mStore() {''', '''  const mSave = mLoad();
  // ----- books: each has its own teacher, its own scrolls and its own numbering -----
  // A scroll belongs to the book named in its "book" field (Кондилография when there is none).
  const M_BOOKS = {
    condylography: { name: "Мастер", skin: "master", menu: "Свитки мастера", title: "Кондилография" },
    positioning: { name: "Сора", skin: "sora", menu: "Свитки Соры", title: "Позиционирование брекетов" },
  };
  let mBook = "condylography";
  const mBookOf = k => (MASTER_CHAPTERS[k] && MASTER_CHAPTERS[k].book) || "condylography";
  const mKs = (book = mBook) => MASTER_CHAPTERS.map((_, k) => k).filter(k => mBookOf(k) === book);
  const mNum = k => mKs(mBookOf(k)).indexOf(k) + 1;
  const mNextK = (book = mBook) => { const k = mKs(book).find(j => !mSave.done[j]); return k === undefined ? -1 : k; };
  const mT = () => M_BOOKS[mBook] || M_BOOKS.condylography;
  const mGloss = () => (mBook === "positioning" && typeof POS_GLOSSARY !== "undefined" ? POS_GLOSSARY : MASTER_GLOSSARY);
  function mSetBook(b) {
    mBook = M_BOOKS[b] ? b : "condylography";
    mEl.stage.dataset.book = mBook;
    mEl.stage.style.setProperty("--walk", `url("${M_IMG}${mT().skin}_walk.png")`);
    mEl.sprite.setAttribute("aria-label", mT().name);
    setMood("calm");
  }
  function mStore() {'''),
    # the teacher's sprite and name follow the book
    ('''  ["calm", "happy", "stern", "think", "blink", "shock", "walk"].forEach(m => { new Image().src = `${M_IMG}master_${m}.png`; });''',
     '''  ["calm", "happy", "stern", "think", "blink", "shock", "walk"].forEach(m => { for (const b of Object.values(M_BOOKS)) new Image().src = `${M_IMG}${b.skin}_${m}.png`; });'''),
    ('''    mEl.vox.style.setProperty("--spr", `url("${M_IMG}master_${mMood}.png")`);''',
     '''    mEl.vox.style.setProperty("--spr", `url("${M_IMG}${mT().skin}_${mMood}.png")`);'''),
    ('''    mEl.vox.style.setProperty("--spr", `url("${M_IMG}master_blink.png")`);''',
     '''    mEl.vox.style.setProperty("--spr", `url("${M_IMG}${mT().skin}_blink.png")`);'''),
    ('''    mEl.name.textContent = opts.name || "Мастер";''', '''    mEl.name.textContent = opts.name || mT().name;'''),
    ('''name: who === "g" ? g.name : "Мастер",''', '''name: who === "g" ? g.name : mT().name,'''),
    # numbering inside the book
    ('''    mRun(ch.steps, { mode: "chapter", k, title: `Свиток ${k + 1}. ${ch.title}`, onDone: mChapterDone });
    mTitleCard(`Свиток ${k + 1}`, ch.title, ch.pages);''',
     '''    mRun(ch.steps, { mode: "chapter", k, title: `Свиток ${mNum(k)}. ${ch.title}`, onDone: mChapterDone });
    mTitleCard(`Свиток ${mNum(k)}`, ch.title, ch.pages);'''),
    ('''    dayLog("scroll", `Свиток ${k + 1}. ${MASTER_CHAPTERS[k].title}`, ms.right, ms.total, ms.right * payPerStep);''',
     '''    dayLog("scroll", `Свиток ${mNum(k)}. ${MASTER_CHAPTERS[k].title}`, ms.right, ms.total, ms.right * payPerStep);
    const nk = mKs(mBookOf(k)).find(j => j > k);'''),
    ('''      title: `Свиток ${k + 1} пройден`, stars,''', '''      title: `Свиток ${mNum(k)} пройден`, stars,'''),
    ('''        ...(k + 1 < MASTER_CHAPTERS.length ? [["Следующий свиток", () => mStartChapter(k + 1), "main"]] : []),''',
     '''        ...(nk !== undefined ? [["Следующий свиток", () => mStartChapter(nk), "main"]] : []),'''),
    # the end of the day
    ('''    const allNow = mSave.done.every(Boolean) && !mSave.dayEnd;''',
     '''    const allNow = mBook === "condylography" && mKs("condylography").every(k => mSave.done[k]) && !mSave.dayEnd;'''),
    ('''      allNow ? { text: "Все восемь свитков позади. Завтра можешь сдать экзамен.", mood: "happy" } : null,''',
     '''      allNow ? { text: "Все свитки позади. Завтра можешь сдать экзамен.", mood: "happy" } : null,'''),
    # the exam and the certificate stay with the master's book
    ('''    const pools = mShuffle(MASTER_CHAPTERS.map(ch => mShuffle(ch.steps.filter(st => st.q || st.tf))));''',
     '''    const pools = mShuffle(mKs("condylography").map(k => mShuffle(MASTER_CHAPTERS[k].steps.filter(st => st.q || st.tf))));'''),
    ('''    const stars = mSave.stars.reduce((a, b) => a + b, 0);''', '''    const ks = mKs("condylography"), stars = ks.reduce((a, k) => a + mSave.stars[k], 0);'''),
    ('''`Звёзд за свитки: ${stars} из ${mSave.stars.length * 3}.`''', '''`Звёзд за свитки: ${stars} из ${ks.length * 3}.`'''),
    ('''    const rows = MASTER_GLOSSARY.map(([t, d]) => {''', '''    const rows = mGloss().map(([t, d]) => {'''),
])

# the menu: only this book's scrolls
p = f"{SP}/master_engine.js"
s = open(p, encoding="utf-8").read()
i = s.index('    const list = [mNode("h2", "m-h", `Свитки мастера · день ${day}`)];')
j = s.index('    list.push(mItem(`Звук:', i)
s = s[:i] + '''    const condy = mBook === "condylography";
    const list = [mNode("h2", "m-h", condy ? `${mT().menu} · день ${day}` : `${mT().menu} · ${mT().title}`)];
    const nextK = mNextK();
    mKs().forEach((k, n) => {
      const ch = MASTER_CHAPTERS[k];
      if (ch.part && (n === 0 || MASTER_CHAPTERS[mKs()[n - 1]].part !== ch.part)) list.push(mNode("p", "m-part", ch.part));
      list.push(mItem(`${n + 1}. ${ch.title}`, ch.sub, mStars(mSave.stars[k]), () => mStartChapter(k), k === nextK ? "next" : ""));
    });
    if (condy) list.push(mItem("Экзамен мастера", mSave.exam ? `лучший результат: ${mSave.exam} из ${M_EXAM}` : `${M_EXAM} вопросов из всех свитков, нужно ${M_PASS}`,
      null, () => (nextK === -1 || mSave.passed ? mStartExam() : mConfirmExam()), "exam"));
    list.push(mItem("Свиток терминов", `${mGloss().length} понятий с объяснениями`, null, mGlossary));
    if (condy && mSave.passed) list.push(mItem("Свиток ученика", "твой сертификат", null, mCertificate, "cert"));
''' + s[j:]
# start: per book, with its own first meeting
i = s.index("    if (mSave.met) {\n      const back = mBack, morning = mMorning;")
j = s.index("  // ----- small animations -----", i)
s = s[:i] + '''    const condy = mBook === "condylography", met = condy ? mSave.met : mSave.posMet;
    if (met) {
      const back = mBack, morning = mMorning;
      mBack = false; mMorning = false;
      const next = mNextK();
      if (back && dayFull()) return mGoHome(pick(["Руки поработали — молодец.", "Практика засчитана.", "С возвращением. Руки помнят — голова учит."]));
      if (back || morning) {
        const greet = morning
          ? pick([`Утро, ученик. День ${day}.`, `Новый день — новые свитки. День ${day}.`, `День ${day}. Чай остыл, свитки ждут.`])
          : pick(["Руки поработали — теперь голова.", "С возвращением. Руки помнят — голова учит.", "Практика — хорошо. Теперь теория."]);
        if (next < 0) return mMenu(condy ? `${greet} Все свитки пройдены — экзамен ждёт.` : `${greet} Все свитки пройдены.`);
        ms = null;
        mLeaveLesson();
        setMood(morning ? "calm" : "happy");
        return mLines([{ text: `${greet} Свиток ${mNum(next)}: «${MASTER_CHAPTERS[next].title}».` }], () => mStartChapter(next));
      }
      return mMenu(pick(["С возвращением, ученик.", "Ты вернулся. Хорошо.", "Свитки ждут."]));
    }
    if (condy) mSave.met = true; else mSave.posMet = true;
    mStore();
    ms = null;
    mLeaveLesson();
    setMood("calm");
    const intro = condy ? MASTER_INTRO : POS_INTRO;
    mLines(intro.map((st, i) => ({ text: st.s, narr: st.narr, mood: st.m, fn: i === 1 ? mSpin : null })), () => mStartChapter(mKs()[0]));
  }

''' + s[j:]
open(p, "w", encoding="utf-8").write(s)
print("patched menu and start")
