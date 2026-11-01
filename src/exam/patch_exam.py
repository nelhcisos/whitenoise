# The doctor's folder «Врач» with the «Осмотр» app (exam protocol over the patient's photos).
import sys
path, exam_js = sys.argv[1], sys.argv[2]
s = open(path, encoding="utf-8").read()

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, (n, old[:90])
    s = s.replace(old, new)

CSS = r'''  /* «Осмотр» */
  .home-app.big.doctor { grid-column: 3 / span 2; }
  .home-app.doctor .home-icon { background: rgba(255, 255, 255, 0.2); }
  .ex-av { background: #ddd center / cover no-repeat; image-rendering: pixelated; color: transparent; }
  .ex-more { margin-top: 14px; }
  .ex-strip { display: flex; gap: 8px; overflow-x: auto; padding: 4px 2px 8px; margin: 0 -16px; padding-left: 16px; scroll-snap-type: x mandatory; -webkit-overflow-scrolling: touch; }
  .ex-thumb { flex: none; width: 132px; border: 0; padding: 0; background: none; font: inherit; color: #3a3a3c; text-align: left; cursor: pointer; scroll-snap-align: start; }
  .ex-thumb img { display: block; width: 132px; height: 88px; object-fit: cover; border-radius: 10px; image-rendering: pixelated; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.2); }
  .ex-thumb span { display: block; margin-top: 4px; font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .ex-hint { margin: 0 4px 8px; color: #8e8e93; font-size: 13px; line-height: 1.4; }
  .ex-tap { margin-top: 2px; }
  .ex-chat { display: flex; flex-direction: column; gap: 6px; margin-top: 8px; }
  .ex-q, .ex-a { margin: 0; padding: 9px 13px; border-radius: 18px; font-size: 15px; line-height: 1.35; max-width: 80%; }
  .ex-q { align-self: flex-end; background: #007aff; color: #fff; }
  .ex-a { align-self: flex-start; background: #e5e5ea; }
  .ex-asks .ca-opt:disabled { color: #8e8e93; }
  .ex-count { margin: 22px 4px 0; font-weight: 700; font-size: 15px; color: #c8501e; letter-spacing: 0.3px; }
  .ex-step[hidden] { display: none; }
  .ex-chart { padding: 10px 6px; }
  .ex-trow { display: grid; grid-template-columns: repeat(16, 1fr); gap: 2px; }
  .ex-tsep { height: 1px; margin: 6px 0; background: #c7c7cc; }
  .ex-tooth { padding: 7px 0; border: 1px solid #d1d1d6; border-radius: 6px; background: #fff; font: inherit; font-size: 11px; font-weight: 600; color: #3a3a3c; cursor: pointer; }
  .ex-tooth.cur { outline: 2px solid #007aff; }
  .ex-tooth.marked { background: #ffe8a3; border-color: #f6b93b; }
  .ex-tooth.hit { background: #c9f2d3; border-color: #34c759; }
  .ex-tooth.miss { background: #ffd6d6; border-color: #ff3b30; }
  .ex-tooth.extra { background: #e5e5ea; text-decoration: line-through; }
  .ex-menu { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
  .ex-menu[hidden] { display: none; }
  .ex-menu-h { width: 100%; margin: 0 4px; font-weight: 700; font-size: 15px; }
  .ex-chip { border: 1px solid #c7c7cc; border-radius: 15px; padding: 6px 11px; background: #fff; font: inherit; font-size: 14px; color: #1c1c1e; cursor: pointer; }
  .ex-chip.on { background: #007aff; border-color: #007aff; color: #fff; }
  .ex-next[hidden] { display: none; }
  .ex-result[hidden] { display: none; }
  .ex-stamp { margin: 26px auto 16px; width: max-content; max-width: 100%; padding: 8px 16px; border: 4px solid #d70015; border-radius: 8px; color: #d70015;
    font-family: var(--pixel); font-size: 13px; transform: rotate(-6deg); letter-spacing: 1px; }
  .ex-stamp.ok { border-color: #248a3d; color: #248a3d; }
  .ex-view { position: absolute; inset: 0; z-index: 5; display: flex; flex-direction: column; align-items: center; justify-content: center; background: #000; touch-action: pan-y; }
  .ex-view img { width: 100%; max-height: 80vh; object-fit: contain; image-rendering: pixelated; }
  .ex-view-cap { margin: 12px 0 0; color: #fff; font-size: 15px; }
  .ex-view-x { position: absolute; top: calc(env(safe-area-inset-top, 0px) + 12px); right: 12px; width: 40px; height: 40px; border: 0; border-radius: 50%; background: rgba(255, 255, 255, 0.2); color: #fff; font-size: 18px; cursor: pointer; }

'''
rep("  @media (prefers-reduced-motion: reduce) { .home-icon { transition: none; } }\n",
    CSS + "  @media (prefers-reduced-motion: reduce) { .home-icon { transition: none; } }\n")

js = open(exam_js, encoding="utf-8").read()
rep('  $("cardBack").addEventListener("click", cardList);\n', js + '\n')
rep('''  let cardOpenNow = false;''', '''  const EXAM_APP = { id: "exam", title: "Осмотр", icon: "assets/books/exam.png" };
  let cardOpenNow = false;''')
# the second folder: the doctor's
rep('''      btn.addEventListener("click", () => folderOpen(b));
      return btn;
    }));
  }''', '''      btn.addEventListener("click", () => folderOpen(b));
      return btn;
    }), (() => {
      const btn = document.createElement("button");
      btn.type = "button"; btn.className = "home-app big folder doctor"; btn.dataset.folder = "doctor";
      btn.setAttribute("aria-label", "Папка Врач: осмотр пациентов");
      const icon = document.createElement("span"); icon.className = "home-icon";
      const m1 = document.createElement("span"); m1.className = "home-mini"; m1.style.backgroundImage = `url("${EXAM_APP.icon}")`;
      const m2 = document.createElement("span"); m2.className = "home-mini"; m2.style.cssText = "background: rgba(255,255,255,.18); box-shadow: none";
      const stat = document.createElement("span"); stat.className = "home-fstat";
      stat.innerHTML = `Приём<br><i>Осмотры ${EXAM_CASES.length - examsLeft()}/${EXAM_CASES.length}</i>`;
      icon.append(m1, m2, stat);
      if (examsLeft()) { const badge = document.createElement("span"); badge.className = "home-badge"; badge.textContent = examsLeft(); icon.append(badge); }
      const name = document.createElement("span"); name.className = "home-name"; name.textContent = "Врач";
      btn.append(icon, name);
      btn.addEventListener("click", () => doctorOpen());
      return btn;
    })());
  }
  function doctorOpen() {
    if (!homeOpen || homeBusy) return;
    $("homeFolderName").textContent = "Врач";
    $("homeFolderBox").replaceChildren(appButton(EXAM_APP, "home-app", examsLeft(), icon => { folder.hidden = true; openCards(icon, examList, "‹ Приём"); }));
    folder.hidden = false;
    if (!homeCalm()) folder.animate([{ opacity: 0, transform: "scale(0.9)" }, { opacity: 1, transform: "scale(1)" }], { duration: 220, easing: "ease-out" });
    folder.querySelector(".home-app")?.focus({ preventScroll: true });
  }''')
# one window for both apps: what it shows and where «back» goes
rep('''  function openCards(icon) {
    if (!homeOpen || homeBusy) return;''', '''  function openCards(icon, render = cardList, back = "‹ Карты") {
    if (!homeOpen || homeBusy) return;
    const cardList = render;
    $("cardBack").textContent = back;
    $("cardBack").onclick = render;''')
rep('''    if (cardHit) out.push(...spotGroup("Приложения", [(() => {''', '''    if (!q || "осмотр врач приём пациент".includes(q)) out.push(...spotGroup("Врач", [(() => {
      const img = document.createElement("img"); img.src = EXAM_APP.icon; img.alt = "";
      return spotRow(img, EXAM_APP.title, `Приём · пациентов: ${EXAM_CASES.length}`, q, () => {
        spot.hidden = true; openCards(home.querySelector(".home-app.doctor .home-icon"), examList, "‹ Приём");
      });
    })()]));
    if (cardHit) out.push(...spotGroup("Приложения", [(() => {''')
open(path, "w", encoding="utf-8").write(s)
print("ok", len(s))
