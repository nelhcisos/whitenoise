  // ---------- BOARDS-START: the master's chalkboard ----------
  // Chalk diagrams for the master's lessons, drawn on a 640x400 canvas. Each board is a
  // function (c, t) where t is seconds since the board appeared, so some of them animate.
  const CHALK = {
    white: "rgba(244, 244, 232, 0.95)", dim: "rgba(244, 244, 232, 0.4)", yellow: "#ffe27a",
    pink: "#ff9db0", blue: "#9fd8ff", green: "#9be7a0", red: "#ff7b7b", orange: "#ffb870",
    board: "#21402f", boardDark: "#1a3426",
  };
  const bd = {
    clear(c) {
      c.setTransform(1, 0, 0, 1, 0, 0);
      c.fillStyle = CHALK.board; c.fillRect(0, 0, 640, 400);
      // faint chalk dust so it reads as a board, not a flat fill
      c.fillStyle = "rgba(255, 255, 255, 0.025)";
      for (let i = 0; i < 90; i++) c.fillRect((i * 97) % 640, (i * 53) % 400, 40 + (i % 5) * 9, 2);
    },
    line(c, x1, y1, x2, y2, col = CHALK.white, w = 3, dash) {
      c.save(); c.strokeStyle = col; c.lineWidth = w; c.lineCap = "round";
      if (dash) c.setLineDash(dash);
      c.beginPath(); c.moveTo(x1, y1); c.lineTo(x2, y2); c.stroke(); c.restore();
    },
    path(c, pts, col = CHALK.white, w = 3, opts = {}) {
      c.save(); c.strokeStyle = col; c.lineWidth = w; c.lineCap = "round"; c.lineJoin = "round";
      if (opts.dash) c.setLineDash(opts.dash);
      c.beginPath(); c.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length; i++) c.lineTo(pts[i][0], pts[i][1]);
      if (opts.close) c.closePath();
      if (opts.fill) { c.fillStyle = opts.fill; c.fill(); }
      c.stroke(); c.restore();
    },
    curve(c, pts, col = CHALK.white, w = 3, opts = {}) {
      // smooth curve through points (quadratic midpoints)
      c.save(); c.strokeStyle = col; c.lineWidth = w; c.lineCap = "round"; c.lineJoin = "round";
      if (opts.dash) c.setLineDash(opts.dash);
      c.beginPath(); c.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length - 1; i++) {
        const mx = (pts[i][0] + pts[i + 1][0]) / 2, my = (pts[i][1] + pts[i + 1][1]) / 2;
        c.quadraticCurveTo(pts[i][0], pts[i][1], mx, my);
      }
      const l = pts[pts.length - 1]; c.lineTo(l[0], l[1]);
      if (opts.fill) { c.fillStyle = opts.fill; c.fill(); }
      c.stroke(); c.restore();
    },
    arrow(c, x1, y1, x2, y2, col = CHALK.white, w = 3, head = 12) {
      bd.line(c, x1, y1, x2, y2, col, w);
      const a = Math.atan2(y2 - y1, x2 - x1);
      bd.path(c, [[x2 - head * Math.cos(a - 0.45), y2 - head * Math.sin(a - 0.45)], [x2, y2],
        [x2 - head * Math.cos(a + 0.45), y2 - head * Math.sin(a + 0.45)]], col, w);
    },
    circle(c, x, y, r, col = CHALK.white, w = 3, fill, dash) {
      c.save(); c.strokeStyle = col; c.lineWidth = w; if (dash) c.setLineDash(dash);
      c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2);
      if (fill) { c.fillStyle = fill; c.fill(); }
      if (w) c.stroke(); c.restore();
    },
    ellipse(c, x, y, rx, ry, rot, col = CHALK.white, w = 3, fill, dash) {
      c.save(); c.strokeStyle = col; c.lineWidth = w; if (dash) c.setLineDash(dash);
      c.beginPath(); c.ellipse(x, y, rx, ry, rot, 0, Math.PI * 2);
      if (fill) { c.fillStyle = fill; c.fill(); }
      if (w) c.stroke(); c.restore();
    },
    arc(c, x, y, r, a0, a1, col = CHALK.white, w = 3, ccw = false) {
      c.save(); c.strokeStyle = col; c.lineWidth = w; c.beginPath(); c.arc(x, y, r, a0, a1, ccw); c.stroke(); c.restore();
    },
    text(c, s, x, y, col = CHALK.white, size = 22, align = "center", weight = 700) {
      c.save(); c.fillStyle = col; c.font = `${weight} ${size}px "Nunito", "Segoe UI", system-ui, sans-serif`;
      c.textAlign = align; c.textBaseline = "middle"; c.fillText(s, x, y); c.restore();
    },
    title(c, s) { bd.text(c, s, 320, 28, CHALK.yellow, 24, "center", 800); },
    dot(c, x, y, r = 6, col = CHALK.red) { bd.circle(c, x, y, r, col, 0, col); },
    // top view of a lower jaw (horseshoe): condyles at the top, incisors at the bottom
    mandibleTop(c, cx, cy, s = 1, col = CHALK.white, rot = 0, dx = 0, sy = 1) {
      const pts = [[-120, -150], [-112, -60], [-95, 20], [-60, 80], [0, 102], [60, 80], [95, 20], [112, -60], [120, -150]];
      const out = pts.map(([x, y0]) => {
        const y = y0 * sy;
        const xr = x * Math.cos(rot) - y * Math.sin(rot), yr = x * Math.sin(rot) + y * Math.cos(rot);
        return [cx + dx + xr * s, cy + yr * s];
      });
      bd.curve(c, out, col, 4);
      return { left: out[0], right: out[out.length - 1], incisal: out[4] };
    },
    // side view of a lower jaw rotating around (ax, ay); face looks to the right
    mandibleSide(c, ax, ay, ang, col = CHALK.white) {
      const pts = [[0, 0], [8, 40], [14, 120], [30, 150], [120, 160], [230, 158], [282, 140], [290, 110], [284, 92]];
      const out = pts.map(([x, y]) => [ax + x * Math.cos(ang) - y * Math.sin(ang), ay + x * Math.sin(ang) + y * Math.cos(ang)]);
      bd.curve(c, out, col, 4);
      return out;
    },
    tooth(c, x, y, w, h, up, col = CHALK.white, fill = "rgba(244,244,232,0.12)") {
      // a simple crown: up=true hangs from the top (upper tooth), else stands (lower tooth)
      const r = Math.min(8, w / 3);
      c.save(); c.strokeStyle = col; c.lineWidth = 3; c.fillStyle = fill; c.beginPath();
      if (up) { c.moveTo(x, y); c.lineTo(x, y + h - r); c.quadraticCurveTo(x, y + h, x + r, y + h); c.lineTo(x + w - r, y + h); c.quadraticCurveTo(x + w, y + h, x + w, y + h - r); c.lineTo(x + w, y); }
      else { c.moveTo(x, y + h); c.lineTo(x, y + r); c.quadraticCurveTo(x, y, x + r, y); c.lineTo(x + w - r, y); c.quadraticCurveTo(x + w, y, x + w, y + r); c.lineTo(x + w, y + h); }
      c.fill(); c.stroke(); c.restore();
    },
    wave(t, period = 3) { return (Math.sin(t * Math.PI * 2 / period - Math.PI / 2) + 1) / 2; },  // 0..1..0
  };

  const BOARDS = {
    workside(c, t) {
      bd.title(c, "Боковое движение вправо (вид сверху)");
      const dx = 26 * bd.wave(t, 3);
      const m = bd.mandibleTop(c, 320, 220, 1, CHALK.white, -0.08 * bd.wave(t, 3), dx);
      bd.circle(c, m.left[0], m.left[1], 14, CHALK.white, 3);
      bd.circle(c, m.right[0], m.right[1], 14, CHALK.white, 3);
      bd.arrow(c, 270, 360, 400, 360, CHALK.yellow, 4);
      bd.text(c, "движение", 335, 385, CHALK.yellow, 18);
      bd.text(c, "рабочая", 520, 160, CHALK.green, 22); bd.text(c, "сторона", 520, 186, CHALK.green, 22);
      bd.text(c, "нерабочая", 115, 160, CHALK.pink, 22); bd.text(c, "(балансирующая)", 115, 186, CHALK.pink, 18);
    },
    luce(c, t) {
      bd.title(c, "Luce: центр вращения смещается");
      // articular fossa and eminence
      bd.curve(c, [[110, 110], [170, 70], [230, 80], [290, 130], [360, 150], [420, 140]], CHALK.dim, 4);
      const p = bd.wave(t, 4);
      // condyle slides forward-down along the eminence while the jaw rotates open
      const cx = 175 + 150 * p, cy = 102 + 42 * p;
      const ang = 0.15 + 0.55 * p;
      bd.circle(c, cx, cy, 18, CHALK.white, 3, "rgba(244,244,232,0.12)");
      bd.line(c, cx, cy + 18, cx + 300 * Math.cos(ang), cy + 18 + 300 * Math.sin(ang), CHALK.white, 5);
      bd.text(c, "нижняя челюсть", 520, 120, CHALK.dim, 16);
      // trail of instantaneous centres of rotation (they do not stay in one place)
      for (let i = 0; i <= 10; i++) {
        const q = i / 10, x = 230 + 60 * q, y = 260 - 70 * q + 25 * Math.sin(q * 3);
        bd.dot(c, x, y, q <= p ? 6 : 3, q <= p ? CHALK.red : CHALK.dim);
      }
      bd.text(c, "центр вращения", 130, 250, CHALK.red, 20);
      bd.text(c, "всё время смещается", 130, 276, CHALK.red, 20);
      bd.text(c, "челюсть — не дверь на одной петле", 320, 375, CHALK.yellow, 20);
    },
    taxis(c, t) {
      bd.title(c, "Терминальная шарнирная ось (McCollum, 1921)");
      bd.curve(c, [[90, 120], [140, 80], [190, 90], [240, 130]], CHALK.dim, 4);
      const ang = 0.25 * bd.wave(t, 3);
      bd.mandibleSide(c, 160, 115, 0, "rgba(244,244,232,0.25)");
      bd.mandibleSide(c, 160, 115, ang, CHALK.white);
      bd.circle(c, 160, 115, 22, CHALK.white, 3);
      bd.dot(c, 160, 115, 8, CHALK.red);
      bd.arc(c, 160, 115, 60, 0.3, 0.3 + ang + 0.01, CHALK.yellow, 3);
      bd.text(c, "ось", 120, 165, CHALK.red, 20, "center", 800);
      bd.text(c, "чистое вращение вокруг оси", 430, 70, CHALK.yellow, 20);
      bd.text(c, "точка отсчёта для записи движений", 400, 372, CHALK.green, 19);
    },
    balanced(c, t) {
      bd.title(c, "Сбалансированная окклюзия");
      for (let i = 0; i < 6; i++) {
        bd.tooth(c, 90 + i * 76, 110, 60, 80, true);
        bd.tooth(c, 96 + i * 76, 196, 60, 80, false);
        const on = (Math.floor(t * 2) + i) % 2 === 0;
        bd.text(c, "✱", 126 + i * 76, 194, on ? CHALK.red : CHALK.pink, 24, "center", 800);
      }
      bd.text(c, "контакты везде — и на рабочей, и на нерабочей стороне", 320, 318, CHALK.white, 18);
      bd.text(c, "большинство таких работ — неудача", 320, 358, CHALK.red, 22, "center", 800);
    },
    organic(c, t) {
      bd.title(c, "Передние ведут — жевательные размыкаются");
      const p = bd.wave(t, 3.2);
      // upper teeth: fixed
      for (let i = 0; i < 3; i++) bd.tooth(c, 100 + i * 80, 100, 66, 80, true);
      bd.path(c, [[430, 96], [440, 196], [472, 214], [470, 96]], CHALK.white, 3, { fill: "rgba(244,244,232,0.12)" });
      // lower teeth move forward and down, guided by the upper incisor
      const dx = 30 * p, dy = 26 * p;
      c.save(); c.translate(dx, dy);
      for (let i = 0; i < 3; i++) bd.tooth(c, 100 + i * 80, 184, 66, 80, false);
      bd.path(c, [[406, 262], [418, 196], [436, 186], [440, 262]], CHALK.white, 3, { fill: "rgba(244,244,232,0.12)" });
      c.restore();
      bd.arrow(c, 450, 300, 450 + 50, 300 + 40, CHALK.yellow, 3);
      bd.text(c, "передние ведут", 520, 280, CHALK.yellow, 18);
      if (p > 0.3) bd.text(c, "зазор!", 230, 182 + dy / 2, CHALK.green, 20, "center", 800);
      bd.text(c, "в ICP у передних зазор ≈ 25 мкм,", 320, 340, CHALK.white, 18);
      bd.text(c, "вертикальную нагрузку несут жевательные", 320, 366, CHALK.white, 18);
    },
    cuspfossa(c, t) {
      bd.title(c, "«Бугор — ямка» (Thomas, 1949)");
      // section: upper tooth with a fossa, lower cusp sitting in it
      bd.path(c, [[80, 80], [80, 180], [130, 200], [175, 160], [220, 200], [270, 180], [270, 80]], CHALK.white, 3, { fill: "rgba(244,244,232,0.1)" });
      bd.path(c, [[90, 320], [90, 230], [140, 215], [175, 172], [210, 215], [260, 230], [260, 320]], CHALK.white, 3, { fill: "rgba(244,244,232,0.1)" });
      bd.dot(c, 156, 184, 7, CHALK.red); bd.dot(c, 195, 184, 7, CHALK.red);
      bd.text(c, "в разрезе", 175, 350, CHALK.dim, 18);
      // top view: three contact points around the cusp tip
      bd.circle(c, 460, 210, 90, CHALK.white, 3, "rgba(244,244,232,0.06)");
      bd.circle(c, 460, 210, 34, CHALK.dim, 2, null, [6, 6]);
      const pulse = 7 + 2 * Math.sin(t * 4);
      for (let i = 0; i < 3; i++) {
        const a = -Math.PI / 2 + i * Math.PI * 2 / 3;
        bd.dot(c, 460 + 34 * Math.cos(a), 210 + 34 * Math.sin(a), pulse, CHALK.red);
      }
      bd.text(c, "ямка сверху: 3 точки контакта", 460, 330, CHALK.yellow, 18);
      bd.text(c, "зуб к зубу", 460, 360, CHALK.green, 18);
    },
    axiograph(c, t) {
      bd.title(c, "Аксиограф: запись пути мыщелка");
      // head profile
      bd.curve(c, [[200, 330], [170, 260], [160, 180], [190, 100], [270, 60], [360, 70], [420, 120], [440, 170], [470, 200], [450, 215], [455, 250], [430, 270], [440, 300], [410, 330]], CHALK.dim, 4);
      // recording flag near the joint
      c.save(); c.strokeStyle = CHALK.blue; c.lineWidth = 3; c.strokeRect(220, 140, 110, 90); c.restore();
      for (let i = 1; i < 4; i++) { bd.line(c, 220 + i * 27, 140, 220 + i * 27, 230, "rgba(159,216,255,0.35)", 1); bd.line(c, 220, 140 + i * 22, 330, 140 + i * 22, "rgba(159,216,255,0.35)", 1); }
      const k = (t * 0.4) % 1, pts = [];
      for (let i = 0; i <= 30 * k; i++) { const q = i / 30; pts.push([235 + 80 * q, 160 + 50 * q * q + 10 * q]); }
      if (pts.length > 1) bd.curve(c, pts, CHALK.pink, 4);
      bd.line(c, 330, 185, 470, 210, CHALK.yellow, 4);
      bd.text(c, "дуга", 500, 228, CHALK.yellow, 18);
      bd.text(c, "+ полурегулируемый артикулятор", 320, 368, CHALK.green, 19);
    },
    icprp(c, t) {
      bd.title(c, "ICP и RP (вперёд → вправо)");
      bd.line(c, 60, 210, 600, 210, CHALK.white, 3);
      for (let mm = -4; mm <= 6; mm++) bd.line(c, 300 + mm * 40, 202, 300 + mm * 40, 218, CHALK.dim, 2);
      bd.text(c, "1 мм", 320, 240, CHALK.dim, 15);
      bd.dot(c, 300, 210, 10, CHALK.red); bd.text(c, "RP", 300, 178, CHALK.red, 24, "center", 800);
      const x = 340 + 40 * bd.wave(t, 3);
      bd.dot(c, x, 210, 9, CHALK.blue); bd.text(c, "ICP", x, 178, CHALK.blue, 22, "center", 800);
      bd.text(c, "обычно 1–2 мм впереди RP", 420, 120, CHALK.blue, 19);
      bd.arrow(c, 280, 290, 150, 290, CHALK.pink, 4);
      bd.text(c, "при дисфункции ВНЧС", 190, 322, CHALK.pink, 18); bd.text(c, "челюсть чаще смещена назад", 190, 346, CHALK.pink, 18);
      bd.text(c, "RP: без нагрузки на сустав", 470, 300, CHALK.yellow, 18); bd.text(c, "и воспроизводимо", 470, 324, CHALK.yellow, 18);
    },
    clock(c, t) {
      bd.title(c, "Сутки: жевание и сон");
      const C = [220, 215], R = 140;
      bd.circle(c, C[0], C[1], R, CHALK.white, 3);
      // night (23:00–07:00) shaded
      const hourA = h => -Math.PI / 2 + h / 24 * Math.PI * 2;
      c.save(); c.fillStyle = "rgba(159,216,255,0.3)"; c.beginPath(); c.moveTo(C[0], C[1]); c.arc(C[0], C[1], R, hourA(23), hourA(31)); c.closePath(); c.fill(); c.restore();
      for (let h = 0; h < 24; h += 3) { const a = hourA(h); bd.line(c, C[0] + (R - 10) * Math.cos(a), C[1] + (R - 10) * Math.sin(a), C[0] + R * Math.cos(a), C[1] + R * Math.sin(a), CHALK.dim, 2); bd.text(c, String(h), C[0] + (R + 20) * Math.cos(a), C[1] + (R + 20) * Math.sin(a), CHALK.dim, 14); }
      // 15 minutes of chewing contacts in the whole day
      const a0 = hourA(13);
      c.save(); c.fillStyle = CHALK.yellow; c.beginPath(); c.moveTo(C[0], C[1]); c.arc(C[0], C[1], R, a0, a0 + 0.25 / 24 * Math.PI * 2); c.closePath(); c.fill(); c.restore();
      const pulse = 0.6 + 0.4 * Math.sin(t * 4);
      bd.arrow(c, 470, 240, C[0] + R * Math.cos(a0) + 8, C[1] + R * Math.sin(a0), `rgba(255,226,122,${pulse})`, 3);
      bd.text(c, "жевание: ≈ 15 мин", 500, 260, CHALK.yellow, 20, "center", 800);
      bd.text(c, "(McHorris)", 500, 286, CHALK.dim, 16);
      bd.text(c, "сон — ночной бруксизм:", 490, 120, CHALK.blue, 18); bd.text(c, "самое сильное усилие", 490, 144, CHALK.blue, 18);
    },
  };
  function drawBoardFrame(canvas, id, t) {
    const c = canvas.getContext("2d");
    bd.clear(c);
    if (BOOK[id]) return bd.figure(c, id, t);
    const f = BOARDS[id];
    if (!f) return;
    f(c, t);
    // a chalk sketch, not a figure from the book: say so
    bd.text(c, "схема мастера, не из книги", 632, 392, "rgba(244,244,232,0.38)", 11, "right", 700);
  }
  // ---------- BOARDS-END ----------
