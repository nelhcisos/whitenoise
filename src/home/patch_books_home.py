# Home screen: a second book, «Позиционирование», as its own app icon; opening a book switches the
# teacher and the scrolls; the search knows which book a scroll or a term belongs to.
import sys
path = sys.argv[1]
s = open(path, encoding="utf-8").read()

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, (n, old[:90])
    s = s.replace(old, new)

rep('''    { id: "condylography", title: "Кондилография", icon: "assets/books/condylography.webp", big: true },
  ];''', '''    { id: "condylography", title: "Кондилография", icon: "assets/books/condylography.webp", big: true, folder: true },
    { id: "positioning", title: "Позиционирование", icon: "assets/books/positioning.png" },
  ];''')
rep('''  const unreadScrolls = () => (mSave && Array.isArray(mSave.done) ? mSave.done.filter(d => !d).length : 0);''',
    '''  const unreadScrolls = (book = "condylography") => (mSave && Array.isArray(mSave.done) ? mKs(book).filter(k => !mSave.done[k]).length : 0);''')
rep('''    $("homeGrid").replaceChildren(...BOOKS.map(b => {''', '''    $("homeGrid").replaceChildren(...BOOKS.filter(b => b.folder).map(b => {''')
rep('''      const done = MASTER_CHAPTERS.length - left, cdone = CARD_CASES.length - cards;
      stat.innerHTML = `Свитки ${done}/${MASTER_CHAPTERS.length}<br><i>Карты ${cdone}/${CARD_CASES.length}</i>`;''',
    '''      const total = mKs(b.id).length, done = total - left, cdone = CARD_CASES.length - cards;
      stat.innerHTML = `Свитки ${done}/${total}<br><i>Карты ${cdone}/${CARD_CASES.length}</i>`;''')
# the plain book icons come after the two folders
rep('''      btn.addEventListener("click", () => doctorOpen());
      return btn;
    })());
  }''', '''      btn.addEventListener("click", () => doctorOpen());
      return btn;
    })(), ...BOOKS.filter(b => !b.folder).map(b => {
      const btn = appButton(b, "home-app", unreadScrolls(b.id), icon => openBook(b, icon));
      btn.dataset.book = b.id;
      return btn;
    }));
  }''')
# opening another book: its teacher, its scrolls
rep('''  function openBook(b, icon) {
    if (!homeOpen || homeBusy) return;
    homeBusy = true;
    spot.hidden = true;''', '''  function openBook(b, icon) {
    if (!homeOpen || homeBusy) return;
    homeBusy = true;
    spot.hidden = true;
    if (b.id !== mBook) {   // another book: its own teacher and scrolls; the master's book starts at its title the first time
      mSetBook(b.id);
      show(b.id === "condylography" && !mSave.met ? 0 : 11);
    }''')
rep('''      appButton(b, "home-app", unreadScrolls(), icon => { folder.hidden = true; openBook(b, icon); }),''',
    '''      appButton(b, "home-app", unreadScrolls(b.id), icon => { folder.hidden = true; openBook(b, icon); }),''')
rep('''      return spotRow(img, b.title, `Книга · свитков: ${MASTER_CHAPTERS.length}, не прочитано: ${unreadScrolls()}`, q, () => spotOpenBook(b));''',
    '''      return spotRow(img, b.title, `Книга · свитков: ${mKs(b.id).length}, не прочитано: ${unreadScrolls(b.id)}`, q, () => spotOpenBook(b));''')
rep('''      if (scrolls.length) out.push(...spotGroup("Свитки · Кондилография", scrolls.map(({ ch, k }) => {
        const n = document.createElement("span"); n.className = "home-spot-num" + (mSave.done[k] ? " done" : ""); n.textContent = k + 1;
        return spotRow(n, ch.title, `${ch.sub ? ch.sub + " · " : ""}${mSave.done[k] ? "пройден" : "ещё не пройден"}`, q, () => spotOpenBook(BOOKS[0]));
      })));''', '''      for (const bk of BOOKS) {
        const mine = scrolls.filter(({ k }) => mBookOf(k) === bk.id);
        if (mine.length) out.push(...spotGroup(`Свитки · ${bk.title}`, mine.map(({ ch, k }) => {
          const n = document.createElement("span"); n.className = "home-spot-num" + (mSave.done[k] ? " done" : ""); n.textContent = mNum(k);
          return spotRow(n, ch.title, `${ch.sub ? ch.sub + " · " : ""}${mSave.done[k] ? "пройден" : "ещё не пройден"}`, q, () => spotOpenBook(bk));
        })));
      }''')
rep('''      if (terms.length) out.push(...spotGroup("Термины · Кондилография", terms.map(x => spotRow(null, x.t, x.d, q, row => row.classList.toggle("open")))));''',
    '''      if (terms.length) out.push(...spotGroup("Термины · Кондилография", terms.map(x => spotRow(null, x.t, x.d, q, row => row.classList.toggle("open")))));
      const pterms = (typeof POS_GLOSSARY !== "undefined" ? POS_GLOSSARY : []).map(([t, d]) => {
        const nt = spotNorm(t);
        return { t, d, rank: nt.startsWith(q) ? 0 : nt.includes(q) ? 1 : spotNorm(d).includes(q) ? 2 : 9 };
      }).filter(x => x.rank < 9).sort((a, b) => a.rank - b.rank).slice(0, 30);
      if (pterms.length) out.push(...spotGroup("Термины · Позиционирование", pterms.map(x => spotRow(null, x.t, x.d, q, row => row.classList.toggle("open")))));
      terms.push(...pterms);''')
# the search tile for a plain book icon
rep('''    const tile = home.querySelector(`.home-app[data-book="${b.id}"] .home-icon`);''',
    '''    const tile = home.querySelector(`.home-app[data-book="${b.id}"] .home-icon`);   // a folder tile or a plain icon''')
open(path, "w", encoding="utf-8").write(s)
print("ok", len(s))
