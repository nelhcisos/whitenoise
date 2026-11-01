# Home screen: the book's folder (the book + «Карта пациента») and the card app's window.
import sys
path = sys.argv[1]
s = open(path, encoding="utf-8").read()

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, (n, old[:90])
    s = s.replace(old, new)

CSS = r'''  /* a book's folder: a big 2x2 tile with its apps, opens like an iOS folder */
  .home-app.folder .home-icon {
    display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: auto 1fr; gap: 10px; padding: 14px; box-sizing: border-box;
    background: rgba(255, 255, 255, 0.2); -webkit-backdrop-filter: blur(20px) saturate(1.3); backdrop-filter: blur(20px) saturate(1.3);
  }
  .home-app.folder .home-badge { top: -9px; right: -9px; }
  .home-mini { aspect-ratio: 1; border-radius: 13px; background: #fff center / cover no-repeat; box-shadow: 0 2px 6px rgba(0, 0, 0, 0.25); }
  .home-fstat { grid-column: 1 / span 2; align-self: end; font-size: 12px; line-height: 1.35; font-weight: 600; text-align: left; text-shadow: 0 1px 2px rgba(0, 0, 0, 0.4); }
  .home-fstat i { font-style: normal; opacity: 0.75; font-weight: 500; }
  .home-folder {
    position: absolute; inset: 0; z-index: 4; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 22px;
    background: rgba(20, 16, 40, 0.35); -webkit-backdrop-filter: blur(28px); backdrop-filter: blur(28px);
  }
  .home-folder[hidden] { display: none; }
  .home-folder h2 { margin: 0; font-size: 30px; font-weight: 700; letter-spacing: -0.4px; }
  .home-folder-box {
    display: grid; grid-template-columns: repeat(3, 76px); gap: 26px 24px; padding: 24px 22px; border-radius: 34px;
    background: rgba(255, 255, 255, 0.22); justify-content: center;
  }
  .home-folder-box .home-icon { width: 76px; height: 76px; border-radius: 18px; background-color: #fff; image-rendering: auto; }
  .home-folder-box .home-name { font-size: 12px; max-width: 92px; }
  /* «Карта пациента»: an iOS-style records app */
  .card-app {
    position: fixed; inset: 0; z-index: 98; display: flex; flex-direction: column; background: #f2f2f7; color: #1c1c1e;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  }
  .card-app[hidden] { display: none; }
  .ca-nav { flex: none; display: flex; align-items: center; height: 44px; padding: calc(env(safe-area-inset-top, 0px) + 6px) 8px 0; background: rgba(242, 242, 247, 0.92); border-bottom: 1px solid rgba(60, 60, 67, 0.12); }
  .ca-nav button { border: 0; background: none; color: #007aff; font: inherit; font-size: 17px; padding: 6px 8px; cursor: pointer; }
  .ca-nav button[hidden] { visibility: hidden; display: inline; }
  .ca-nav b { flex: 1; text-align: center; font-size: 17px; font-weight: 600; margin-right: 60px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .card-body { flex: 1; overflow-y: auto; width: 100%; max-width: 560px; margin: 0 auto; box-sizing: border-box; padding: 6px 16px calc(env(safe-area-inset-bottom, 0px) + 48px); -webkit-overflow-scrolling: touch; }
  .ca-h1 { margin: 8px 4px 6px; font-size: 32px; font-weight: 700; line-height: 1.15; font-family: inherit; color: #1c1c1e; letter-spacing: -0.5px; text-shadow: none; text-transform: none; }
  .ca-sub { margin: 0 4px 16px; color: #6c6c70; font-size: 15px; line-height: 1.4; }
  .ca-group { background: #fff; border-radius: 12px; overflow: hidden; }
  .ca-row { display: flex; align-items: center; gap: 12px; width: 100%; padding: 11px 14px; border: 0; background: none; text-align: left; font: inherit; color: inherit; cursor: pointer; }
  .ca-row + .ca-row { border-top: 1px solid rgba(60, 60, 67, 0.12); }
  .ca-row:active { background: #e5e5ea; }
  .ca-av { flex: none; width: 42px; height: 42px; border-radius: 50%; background: linear-gradient(#8e9cff, #5856d6); color: #fff; font-weight: 700; font-size: 16px; line-height: 42px; text-align: center; }
  .ca-row-t { flex: 1; min-width: 0; }
  .ca-row-t b { display: block; font-size: 16px; font-weight: 600; }
  .ca-row-t span { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; font-size: 14px; color: #6c6c70; line-height: 1.35; }
  .ca-st { flex: none; padding: 3px 9px; border-radius: 10px; background: #e5e5ea; color: #3a3a3c; font-size: 13px; font-weight: 600; }
  .ca-st.new { background: #007aff; color: #fff; }
  .ca-st.ok { background: #34c759; color: #fff; }
  .ca-sec { margin-top: 18px; }
  .ca-sec-h { margin: 0 14px 6px; color: #6c6c70; font-size: 13px; text-transform: uppercase; letter-spacing: 0.2px; }
  .ca-text { margin: 0; padding: 12px 14px; background: #fff; border-radius: 12px; font-size: 16px; line-height: 1.45; }
  .ca-fig + .ca-text { margin-top: 8px; }
  .ca-kv { display: flex; justify-content: space-between; gap: 12px; padding: 11px 14px; font-size: 16px; }
  .ca-kv + .ca-kv { border-top: 1px solid rgba(60, 60, 67, 0.12); }
  .ca-kv span { color: #6c6c70; }
  .ca-fig { margin: 0; padding: 10px; background: #fff; border-radius: 12px; }
  .ca-fig img { display: block; width: 100%; height: auto; border-radius: 6px; }
  .ca-fig figcaption { margin-top: 6px; font-size: 13px; color: #6c6c70; }
  .ca-opt { display: flex; align-items: center; gap: 12px; width: 100%; padding: 12px 14px; border: 0; background: none; text-align: left; font: inherit; font-size: 16px; line-height: 1.35; color: inherit; cursor: pointer; }
  .ca-opt + .ca-opt { border-top: 1px solid rgba(60, 60, 67, 0.12); }
  .ca-dot { flex: none; width: 22px; height: 22px; border-radius: 50%; border: 2px solid #c7c7cc; box-sizing: border-box; }
  .ca-opt.sel .ca-dot { border: 7px solid #007aff; }
  .ca-opt.right { background: #e8f8ec; }
  .ca-opt.right .ca-dot { border: 7px solid #34c759; }
  .ca-opt.wrong { background: #ffecec; }
  .ca-opt.wrong .ca-dot { border: 7px solid #ff3b30; }
  .ca-opt:disabled { cursor: default; color: inherit; }
  .ca-fb { margin: 8px 4px 0; font-size: 15px; line-height: 1.45; }
  .ca-fb[hidden] { display: none; }
  .ca-fb.ok b { color: #248a3d; }
  .ca-fb.bad b { color: #d70015; }
  .ca-fb small { display: block; margin-top: 4px; color: #8e8e93; font-size: 13px; }
  .ca-sign { display: block; width: 100%; margin-top: 22px; padding: 15px; border: 0; border-radius: 14px; background: #007aff; color: #fff; font: inherit; font-size: 17px; font-weight: 600; cursor: pointer; }
  .ca-sign:disabled { background: #b4d4ff; cursor: default; }
  .ca-link { display: block; margin: 14px auto 0; border: 0; background: none; color: #007aff; font: inherit; font-size: 16px; cursor: pointer; }
  .ca-concl { margin-top: 18px; }
  .ca-concl[hidden] { display: none; }
  .ca-hand { margin: 0; padding: 14px; background: #fffbe6; border-radius: 12px; border-left: 4px solid #f6b93b; font-size: 16px; line-height: 1.5; font-style: italic; }
  .ca-score { margin: 10px 4px 0; font-weight: 600; font-size: 16px; }

'''
rep("  @media (prefers-reduced-motion: reduce) { .home-icon { transition: none; } }\n",
    CSS + "  @media (prefers-reduced-motion: reduce) { .home-icon { transition: none; } }\n")

rep('''  <div class="home-spot" id="homeSpot"''', '''  <div class="home-folder" id="homeFolder" role="dialog" aria-label="Папка" hidden>
    <h2 id="homeFolderName"></h2>
    <div class="home-folder-box" id="homeFolderBox"></div>
  </div>
  <div class="home-spot" id="homeSpot"''')
rep('''<button class="home-bar" id="homeBar" type="button" aria-label="На главный экран" hidden></button>''',
    '''<div class="card-app" id="cardApp" role="region" aria-label="Карта пациента" hidden>
  <div class="ca-nav"><button id="cardBack" type="button">‹ Карты</button><b id="cardNavTitle"></b></div>
  <div class="card-body" id="cardBody"></div>
</div>
<button class="home-bar" id="homeBar" type="button" aria-label="На главный экран" hidden></button>''')

# ----- script -----
cards = open(sys.argv[2], encoding="utf-8").read()
rep("  // ---------- Home screen: every book is an app ----------\n", cards + "\n  // ---------- Home screen: every book is an app ----------\n")
rep('''  const BOOKS = [
    { id: "condylography", title: "Кондилография", icon: "assets/books/condylography.webp", big: true },
  ];''', '''  const BOOKS = [
    { id: "condylography", title: "Кондилография", icon: "assets/books/condylography.webp", big: true },
  ];
  // every book lives in its own folder: the book itself and its patient cards
  const CARD_APP = { id: "cards", title: "Карта пациента", icon: "assets/books/patient_card.png" };
  let cardOpenNow = false;''')
rep('''  window.addEventListener("keydown", e => { if ((homeOpen || homeBusy) && !home.contains(e.target)) e.stopImmediatePropagation(); }, true);''',
    '''  window.addEventListener("keydown", e => {
    if ((homeOpen || homeBusy || cardOpenNow) && !home.contains(e.target) && !cardApp.contains(e.target)) e.stopImmediatePropagation();
    if (homeOpen && !folder.hidden && e.key === "Escape") { e.preventDefault(); folderClose(); }
  }, true);''')
# render: one big folder tile per book
a = s.index("  function renderHome() {")
b = s.index("  function openBook(b, icon) {")
s = s[:a] + '''  const folder = $("homeFolder");
  function appButton(app, cls, badgeN, onClick) {
    const btn = document.createElement("button");
    btn.type = "button"; btn.className = cls; btn.dataset.app = app.id;
    btn.setAttribute("aria-label", badgeN ? `${app.title}. Новых: ${badgeN}` : app.title);
    const icon = document.createElement("span");
    icon.className = "home-icon";
    icon.style.backgroundImage = `url("${app.icon}")`;
    if (badgeN) { const badge = document.createElement("span"); badge.className = "home-badge"; badge.textContent = badgeN; icon.append(badge); }
    const name = document.createElement("span");
    name.className = "home-name"; name.textContent = app.title;
    btn.append(icon, name);
    btn.addEventListener("click", () => onClick(icon));
    return btn;
  }
  function renderHome() {
    const left = unreadScrolls(), cards = cardsLeft();
    $("homeGrid").replaceChildren(...BOOKS.map(b => {
      const btn = document.createElement("button");
      btn.type = "button"; btn.className = "home-app big folder"; btn.dataset.book = b.id;
      btn.setAttribute("aria-label", `Папка ${b.title}: книга и карты пациентов`);
      const icon = document.createElement("span");
      icon.className = "home-icon";
      const m1 = document.createElement("span"); m1.className = "home-mini"; m1.style.backgroundImage = `url("${b.icon}")`;
      const m2 = document.createElement("span"); m2.className = "home-mini"; m2.style.backgroundImage = `url("${CARD_APP.icon}")`;
      const stat = document.createElement("span"); stat.className = "home-fstat";
      const done = MASTER_CHAPTERS.length - left, cdone = CARD_CASES.length - cards;
      stat.innerHTML = `Свитки ${done}/${MASTER_CHAPTERS.length}<br><i>Карты ${cdone}/${CARD_CASES.length}</i>`;
      icon.append(m1, m2, stat);
      if (left + cards) { const badge = document.createElement("span"); badge.className = "home-badge"; badge.textContent = left + cards; icon.append(badge); }
      const name = document.createElement("span");
      name.className = "home-name"; name.textContent = b.title;
      btn.append(icon, name);
      btn.addEventListener("click", () => folderOpen(b));
      return btn;
    }));
  }
  function folderOpen(b) {
    if (!homeOpen || homeBusy) return;
    $("homeFolderName").textContent = b.title;
    $("homeFolderBox").replaceChildren(
      appButton(b, "home-app", unreadScrolls(), icon => { folder.hidden = true; openBook(b, icon); }),
      appButton(CARD_APP, "home-app", cardsLeft(), icon => { folder.hidden = true; openCards(icon); }));
    folder.hidden = false;
    if (!homeCalm()) folder.animate([{ opacity: 0, transform: "scale(0.9)" }, { opacity: 1, transform: "scale(1)" }], { duration: 220, easing: "ease-out" });
    folder.querySelector(".home-app")?.focus({ preventScroll: true });
  }
  function folderClose() {
    folder.hidden = true;
    home.querySelector(".home-app")?.focus({ preventScroll: true });
  }
  folder.addEventListener("click", e => { if (e.target === folder || e.target.id === "homeFolderName") folderClose(); });
  // the card app opens over everything, like the book, and the home bar brings you back
  function openCards(icon) {
    if (!homeOpen || homeBusy) return;
    homeBusy = true;
    spot.hidden = true;
    const done = () => {
      homeAnim?.cancel(); homeAnim = null;
      home.hidden = true; homeOpen = false; homeBusy = false;
      cardOpenNow = true;
      cardApp.hidden = false;
      homeBar.hidden = false;
      cardList();
      $("cardBody").focus?.({ preventScroll: true });
    };
    if (homeCalm()) return done();
    const r = icon.getBoundingClientRect(), rad = getComputedStyle(icon).borderTopLeftRadius;
    cardApp.hidden = false; cardList();
    cardApp.animate([
      { clipPath: `inset(${r.top}px ${innerWidth - r.right}px ${innerHeight - r.bottom}px ${r.left}px round ${rad})`, opacity: 0.6 },
      { clipPath: "inset(0px 0px 0px 0px round 0px)", opacity: 1 },
    ], { duration: 400, easing: "cubic-bezier(.2, .8, .2, 1)" }).onfinish = done;
    homeAnim = home.animate([{ transform: "scale(1)", filter: "brightness(1)" }, { transform: "scale(1.08)", filter: "brightness(0.55)" }], { duration: 400, easing: "ease-in", fill: "forwards" });
  }
''' + s[b:]
rep('''  function goHome() {
    if (homeOpen || homeBusy) return;
    homeBusy = true;
    musicWasOn = !music.paused;
    music.pause();''', '''  function goHome() {
    if (homeOpen || homeBusy) return;
    homeBusy = true;
    if (cardOpenNow) {   // back from the card app: the game underneath stays as it was
      cardOpenNow = false;
      renderHome();
      homeAnim?.cancel(); homeAnim = null;
      home.hidden = false; homeBar.hidden = true;
      startWall();
      const fin = () => { cardApp.hidden = true; homeOpen = true; homeBusy = false; home.querySelector(".home-app")?.focus({ preventScroll: true }); };
      if (homeCalm()) return fin();
      const tile = home.querySelector(".home-icon"), r = tile.getBoundingClientRect(), rad = getComputedStyle(tile).borderTopLeftRadius;
      cardApp.animate([
        { clipPath: "inset(0px 0px 0px 0px round 0px)", opacity: 1 },
        { clipPath: `inset(${r.top}px ${innerWidth - r.right}px ${innerHeight - r.bottom}px ${r.left}px round ${rad})`, opacity: 0 },
      ], { duration: 380, easing: "cubic-bezier(.3, .7, .2, 1)" }).onfinish = fin;
      home.animate([{ transform: "scale(1.08)", filter: "brightness(0.55)" }, { transform: "scale(1)", filter: "brightness(1)" }], { duration: 380, easing: "ease-out" });
      return;
    }
    musicWasOn = !music.paused;
    music.pause();''')
rep('''    const tile = home.querySelector(`.home-app[data-book="${b.id}"] .home-icon`);''',
    '''    const tile = home.querySelector(`.home-app[data-book="${b.id}"] .home-icon`);
    folder.hidden = true;''')
# search: the card app is findable too
rep('''    const books = BOOKS.filter(b => !q || spotNorm(b.title).includes(q));''',
    '''    const books = BOOKS.filter(b => !q || spotNorm(b.title).includes(q));
    const cardHit = !q || "карта пациента карты пациентов".includes(q) || CARD_CASES.some(c => spotNorm(c.name).includes(q));''')
rep('''    if (!q) {
      const h = document.createElement("p"); h.className = "home-spot-h"; h.textContent = "Попробуй найти";''', '''    if (cardHit) out.push(...spotGroup("Приложения", [(() => {
      const img = document.createElement("img"); img.src = CARD_APP.icon; img.alt = "";
      return spotRow(img, CARD_APP.title, `Кондилография · карт: ${CARD_CASES.length}, не заполнено: ${cardsLeft()}`, q, () => {
        spot.hidden = true; openCards(home.querySelector(".home-app .home-icon"));
      });
    })()]));
    if (!q) {
      const h = document.createElement("p"); h.className = "home-spot-h"; h.textContent = "Попробуй найти";''')
rep('''      if (!books.length && !scrolls.length && !terms.length) {''', '''      if (!books.length && !scrolls.length && !terms.length && !cardHit) {''')
rep('''  function showHomeNow() {
    homeOpen = true; homeBusy = false;''', '''  function showHomeNow() {
    homeOpen = true; homeBusy = false; cardOpenNow = false; cardApp.hidden = true; folder.hidden = true;''')
rep('''  function enterGameNow() {
    homeOpen = false; homeBusy = false;''', '''  function enterGameNow() {
    homeOpen = false; homeBusy = false; cardOpenNow = false; cardApp.hidden = true; folder.hidden = true;''')
rep('''window.__home = { open: () => homeOpen, busy: () => homeBusy, back: () => goHome() };''',
    '''window.__home = { open: () => homeOpen, busy: () => homeBusy, back: () => goHome(), cards: () => cardOpenNow };''')
open(path, "w", encoding="utf-8").write(s)
print("ok", len(s))
