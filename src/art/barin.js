  // ---------- The barin: a kind Armenian gentleman who owns the clinic (pixel art) ----------
  // A 32x50 sprite in a carved armchair. The room: pink tuff stone, a carpet on the wall, Ararat in
  // the window, coffee and pomegranates on the table. One scene per canvas (each keeps its own
  // steam); BARIN_SRC is a still for <img>.
  const BARIN = [
    "...........KKKKKKKKKK...........",
    ".........KKhhhhhhhhhhKK.........",
    "........KhhhhHHhhHHhhhhK........",
    "........KhhHhhhhhhhhHhhK........",
    "........KhHSSSSSSSSSSHhK........",
    "........KhSSSSSSSSSSSShK........",
    "........KhSBBBSSSSBBBShK........",
    ".......KSSSSESSSSSSESSSSK.......",
    ".......KsSSSESSssSSESSSsK.......",
    "........KSCCSSsSSsSSCCSK........",
    "........KSSSMMMMMMMMSSSK........",
    "........KSSMMMMMMMMMMSSK........",
    "........KSSSLSSSSSSLSSSK........",
    "........KSSSSLLLLLLSSSSK........",
    ".........KsSSSSSSSSSSsK.........",
    "..........KKSSSSSSSSKK..........",
    "...........KssssssssK...........",
    "......KKKRRRGWssssWGRRRKKK......",
    "....KKRRRRRRGWWssWWGRRRRRRKK....",
    "...KRRRRRRRRGWWWWWWGRRRRRRRRK...",
    "..KRRrRRRRRRRGWWWWGRRRRRRRQRRK..",
    "..KRRrRRRRRRRGWwwWGRRRRRRRQRRK..",
    "..KRRrRRRRRRRRGWWGRRRRRRRRQRRK..",
    "..KRRrRRRRRRRRGWWGRRRRRRRRQRRK..",
    "..KRRrKRRRRRRRRGGRRRRRRRRKQRRK..",
    "..KRRrKRRRRRRRRRRRRRRRRRRKQRRK..",
    "..KRRrKRRRgGGGGGGGGGGGGgRKQRRK..",
    "..KRRrKRRRgGGGGGGGGGGGGgRKQRRK..",
    "..KRRrKRRRRRRRRRRRRRRRRRRKQRRK..",
    "..KRRRRKKRRRRRRRRRRRRRRKKRRRRK..",
    "..KKRRRRRRKKRRRRRRRRRKKRRRRRKK..",
    "...KSSSRRRRRKKRRRRRKKRRRRRSSSK..",
    "...KSSSSKRRRRRKKKKKRRRRRKSSSSK..",
    "...KSSSSKPPPPPPPPPPPPPPPKSSSSK..",
    "....KKKKPPPPPPPPPPPPPPPPPKKKK...",
    "......KPPPPPPPPPpPPPPPPPPPPK....",
    "......KPPPPPPPPPpPPPPPPPPPPK....",
    "......KRRPPPPPPPpPPPPPPPPRRK....",
    "......KRRRPPPPPPpPPPPPPPRRRK....",
    "......KRRRKPPPPKpKPPPPKRRRRK....",
    "......KRRRKPPPPK.KPPPPKRRRRK....",
    ".......KRRKPPPPK.KPPPPKRRRK.....",
    ".......KRRKPPPPK.KPPPPKRRRK.....",
    "........KKKPPPPK.KPPPPKKKK......",
    "..........KPPPPK.KPPPPK.........",
    "..........KPPPPK.KPPPPK.........",
    "..........KPPPPK.KPPPPK.........",
    ".........KNNNNNK.KNNNNNK........",
    "........KNnNNNNK.KNNNNnNK.......",
    "........KKKKKKKK.KKKKKKKK.......",
  ];
  const BARIN_PAL = {
    K: "#2a1610", H: "#4a403a", h: "#a9a39b", S: "#e8b48c", s: "#c98f66", B: "#2b211d", E: "#2a1610", C: "#ec9a86",
    M: "#3a312c", L: "#a8463c", T: "#fff8ee", O: "#5a1a18", W: "#f4efe4", w: "#cfc8bb",
    R: "#8a2232", r: "#5e1622", Q: "#b23c4a", G: "#e6b84a", g: "#a87c24", P: "#33303e", p: "#22202a", N: "#5a3420", n: "#8a5a3a",
  };
  // Faces drawn over the head ("." keeps the pixel underneath): [row, patch]
  const BARIN_FACES = {
    blink: [[7, "............S......S............"], [8, "...........EE......EE..........."]],
    talk: [[12, "............LTTTTTTL............"], [13, ".............LOOOOL............."]],
    laugh: [[8, "...........ESE....ESE..........."], [12, "...........LTTTTTTTTL..........."],
      [13, "............LOOOOOOL............"], [14, ".............LLLLLL............."]],
  };
  const BARIN_HEAD = 17;   // rows 0-16: head and neck, they nod a pixel while he breathes
  const barinParts = (() => {
    const cv = (w, h) => { const c = document.createElement("canvas"); c.width = w; c.height = h; return c; };
    const head = face => {
      const c = cv(32, BARIN_HEAD), x = c.getContext("2d");
      drawSprite(x, BARIN.slice(0, BARIN_HEAD), 0, 0, BARIN_PAL);
      for (const [row, patch] of BARIN_FACES[face] || []) drawSprite(x, [patch], 0, row, BARIN_PAL);
      return c;
    };
    const body = cv(32, BARIN.length - BARIN_HEAD);
    drawSprite(body.getContext("2d"), BARIN.slice(BARIN_HEAD), 0, 0, BARIN_PAL);
    return { body, head: { base: head(), blink: head("blink"), talk: head("talk"), laugh: head("laugh") } };
  })();
  // x, y: top-left of the sprite. o: { face: "talk" | "laugh" | "blink", nod: 0 | 1, beads: swing }
  function drawBarin(c, x, y, o = {}) {
    c.drawImage(barinParts.head[o.face] || barinParts.head.base, x, y + (o.nod || 0));
    c.drawImage(barinParts.body, x, y + BARIN_HEAD);
    // amber prayer beads hanging from his right hand, with a red tassel
    const sw = o.beads || 0;
    for (let i = 0; i < 8; i++) {
      c.fillStyle = i % 2 ? "#b86a10" : "#f0a030";
      c.fillRect(x + 5 + Math.round(sw * i / 7), y + 34 + i, 1, 1);
    }
    const tx = x + 5 + Math.round(sw);
    c.fillStyle = "#e6b84a"; c.fillRect(tx, y + 42, 1, 1);
    c.fillStyle = "#c0282c"; c.fillRect(tx - 1, y + 43, 3, 2);
    c.fillStyle = "#8a1418"; c.fillRect(tx - 1, y + 45, 1, 1); c.fillRect(tx + 1, y + 45, 1, 1);
  }
  // The room is drawn once; the scene only adds the steam, the beads and the barin himself.
  function drawBarinRoom(c) {
    const r = (col, x, y, w, h) => { c.fillStyle = col; c.fillRect(x, y, w, h); };
    const arch = (cx, top, rad, bottom, fill) => {   // an arched opening, filled row by row
      for (let y = top; y < bottom; y++) {
        const dy = y - (top + rad), hw = dy < 0 ? Math.floor(Math.sqrt(rad * rad - dy * dy)) : rad;
        fill(y, cx - hw, cx + hw);
      }
    };
    const diamond = (cx, cy, h, col) => { for (let dy = -h; dy <= h; dy++) { const w = h - Math.abs(dy); r(col, cx - w, cy + dy, w * 2 + 1, 1); } };
    // walls of pink tuff, the stone Yerevan is built of
    r("#d49c86", 0, 0, 160, 100);
    for (let row = 0; row < 13; row++) {
      const y = row * 8, off = row % 2 ? 9 : 0;
      r("#b8806a", 0, y + 7, 160, 1);
      for (let x = off - 18; x < 160; x += 18) {
        if ((row * 5 + x * 3) % 7 === 0) r("#c98f78", x + 1, y + 1, 17, 6);
        r("#b8806a", x, y, 1, 7);
        r("#e3b29c", x + 1, y, 17, 1);
      }
    }
    // floor and baseboard
    r("#6b3f22", 0, 100, 160, 20);
    for (let y = 104; y < 120; y += 5) r("#5a3319", 0, y, 160, 1);
    r("#4a2a14", 0, 99, 160, 2); r("#8a5a36", 0, 98, 160, 1);
    // the window: an arch with Ararat in it, big Masis and little Sis
    arch(133, 12, 19, 62, (y, a, b) => r("#5a341c", a, y, b - a + 1, 1));
    const sky = ["#7fbfe9", "#8cc7ec", "#9ad0ef", "#a9d8f2", "#b9e0f4", "#cae8f6", "#d9eff8"];
    arch(133, 15, 16, 59, (y, a, b) => {
      r(sky[Math.min(sky.length - 1, Math.floor((y - 15) / 6))], a, y, b - a + 1, 1);
      const span = (px, py, sl, sr) => y < py ? null : [Math.max(a, Math.round(px - (y - py) * sl)), Math.min(b, Math.round(px + (y - py) * sr))];
      const masis = span(127, 26, 1.7, 1.45), sis = span(143, 39, 1.3, 1.4);
      for (const [m, py, snow] of [[masis, 26, 11], [sis, 39, 4]]) {
        if (!m || m[0] > m[1]) continue;
        const mid = Math.round((m[0] + m[1]) / 2) + 1, jag = (y * 7) % 3;
        const snowy = y - py < snow + jag;
        r(snowy ? "#ffffff" : "#8a86b4", m[0], y, m[1] - m[0] + 1, 1);
        r(snowy ? "#d3dbef" : "#6e6a9c", mid, y, m[1] - mid + 1, 1);
      }
      if (y >= 52) {   // the valley: orchards, a few ripe apricots
        r(y < 54 ? "#7aa65a" : "#5f8f45", a, y, b - a + 1, 1);
        for (let x = a + ((y * 5) % 4); x <= b; x += 5) r(y % 2 ? "#e8962e" : "#4a7a36", x, y, 1, 1);
      }
    });
    r("#7a4a2a", 111, 59, 45, 3); r("#9a6a40", 111, 59, 45, 1);   // window sill
    // a grapevine over the window, with two bunches
    for (let x = 108; x < 158; x += 6) { r("#4f8f3e", x, 9 + (x % 4 === 0 ? 1 : 0), 5, 3); r("#3a7030", x + 1, 11, 3, 2); r("#6aae52", x + 1, 9, 2, 1); }
    r("#5a3a1c", 106, 12, 52, 1);
    const grapes = (gx, gy, n) => {
      for (let i = 0; i < n; i++) {
        const w = Math.max(1, n - i - 1);
        for (let j = 0; j < w; j++) r((i + j) % 2 ? "#5b2a6e" : "#7c3f92", gx - (w >> 1) + j, gy + i, 1, 1);
      }
    };
    grapes(150, 13, 6); grapes(113, 13, 5);
    // the carpet: red field, blue border, a medallion of diamonds, fringe at the bottom
    r("#1f2a5c", 8, 8, 43, 61);
    r("#e0a040", 10, 10, 39, 57);
    r("#9a1c26", 11, 11, 37, 55);
    for (let x = 10; x < 50; x += 4) { r("#e0a040", x, 8, 1, 1); r("#e0a040", x + 2, 67, 1, 1); }
    for (let y = 12; y < 66; y += 4) { r("#e0a040", 8, y, 1, 1); r("#e0a040", 50, y + 2, 1, 1); }
    diamond(29, 38, 13, "#e8a848"); diamond(29, 38, 10, "#1f2a5c"); diamond(29, 38, 7, "#9a1c26");
    diamond(29, 38, 4, "#f2e2c0"); diamond(29, 38, 1, "#1f2a5c");
    for (const y of [17, 59]) { diamond(29, y, 4, "#e8a848"); diamond(29, y, 1, "#1f2a5c"); }
    for (const [x, y] of [[16, 17], [42, 17], [16, 59], [42, 59], [16, 38], [42, 38]]) { diamond(x, y, 2, "#f2e2c0"); r("#9a1c26", x, y, 1, 1); }
    for (let x = 9; x < 51; x += 2) r("#efe3c8", x, 69, 1, 3);
    // the table: coffee in a small cup, a copper bowl of pomegranates and apricots
    r("#9a6236", 13, 84, 36, 3); r("#b77a44", 15, 84, 32, 1); r("#6a3c20", 13, 87, 36, 2);
    r("#5a3319", 29, 89, 4, 14); r("#6a3c20", 23, 102, 16, 2); r("#5a3319", 21, 104, 20, 2);
    r("#f4efe4", 16, 83, 11, 1);
    r("#f4efe4", 18, 78, 7, 5); r("#e6b84a", 18, 78, 7, 1); r("#3a2214", 19, 78, 5, 1);
    r("#2b6cb0", 18, 80, 7, 1); r("#d9d2c4", 18, 82, 7, 1); r("#f4efe4", 25, 79, 2, 1); r("#f4efe4", 26, 80, 1, 2);
    const fruit = (x, y, body, light, crown) => {
      r(body, x + 1, y, 3, 1); r(body, x, y + 1, 5, 3); r(body, x + 1, y + 4, 3, 1); r(light, x + 1, y + 1, 1, 1);
      if (crown) { r(crown, x + 2, y - 1, 1, 1); r(crown, x + 1, y - 2, 1, 1); r(crown, x + 3, y - 2, 1, 1); }
    };
    fruit(37, 74, "#b4202a", "#e85a5a", "#6a1018");
    fruit(32, 76, "#b4202a", "#e85a5a", "#6a1018");
    fruit(41, 77, "#f09a32", "#ffd07a");
    r("#b5652e", 30, 80, 17, 4); r("#d98a46", 30, 80, 17, 1); r("#8a4a20", 32, 84, 13, 1);
    // the carved armchair: green velvet, buttons, gold knobs
    const wood = "#6a3a1c", woodL = "#9a5a2c", woodD = "#45230f", vel = "#2f6b4b", velL = "#3f8a5f", velD = "#1f4a34", gold = "#e6b84a";
    arch(80, 34, 22, 99, (y, a, b) => { r(woodD, a, y, b - a + 1, 1); r(wood, a + 1, y, b - a - 1, 1); });
    arch(80, 38, 18, 96, (y, a, b) => { r(vel, a, y, b - a + 1, 1); r(velL, a, y, 2, 1); r(velD, b - 1, y, 2, 1); });
    for (let y = 46; y < 94; y += 8) for (let x = 66 + ((y >> 3) % 2) * 4; x < 96; x += 8) { r(velD, x, y, 1, 1); r(gold, x, y - 1, 1, 1); }
    r(gold, 77, 35, 7, 3); r("#b08420", 78, 37, 5, 1); r("#c0282c", 79, 36, 3, 1);
    for (const px of [55, 101]) {
      r(woodD, px, 44, 5, 60); r(wood, px + 1, 44, 3, 60); r(woodL, px + 1, 44, 1, 60);
      r(gold, px, 39, 5, 5); r("#fff2b0", px + 1, 40, 1, 1); r("#b08420", px, 43, 5, 1);
    }
    r(velD, 59, 95, 43, 4); r(vel, 59, 95, 43, 1);
    r(woodD, 57, 99, 47, 4); r(woodL, 58, 99, 45, 1);
    r(woodD, 59, 103, 4, 4); r(woodD, 98, 103, 4, 4); r(woodD, 58, 106, 3, 2); r(woodD, 100, 106, 3, 2);
    // a rug on the floor
    r("#1f2a5c", 34, 109, 92, 11); r("#9a1c26", 37, 111, 86, 9);
    for (let x = 39; x < 118; x += 6) { r("#e0a040", x, 113, 2, 1); r("#e0a040", x + 3, 116, 2, 1); }
  }
  // returns draw(ctx, t, o): t is a frame counter; o: { talk, laugh }. He breathes, blinks, his beads sway.
  function makeBarinScene() {
    const bg = document.createElement("canvas");
    bg.width = 160; bg.height = 120;
    drawBarinRoom(bg.getContext("2d"));
    let steam = [];
    return (c, t, o = {}) => {
      c.drawImage(bg, 0, 0);
      if (t % 9 === 0) steam.push({ x: 21 + Math.random() * 2, y: 77, life: 0 });
      steam = steam.filter(s => s.life < 34);
      for (const s of steam) {
        s.life++; s.y -= 0.35; s.x += Math.sin((s.life + s.x * 3) * 0.2) * 0.25;
        c.fillStyle = s.life < 18 ? "rgba(255,255,255,0.75)" : "rgba(255,255,255,0.4)";
        c.fillRect(Math.round(s.x), Math.round(s.y), 1, 1);
      }
      const face = o.laugh ? "laugh" : o.talk && (t >> 3) % 2 ? "talk" : t % 210 < 7 ? "blink" : null;
      const shake = o.laugh ? (t >> 1) % 2 : 0;
      drawBarin(c, 64 + shake, 57, { face, nod: o.laugh ? (t >> 2) % 2 : (t >> 5) % 2, beads: Math.sin(t / 24) * (o.laugh ? 2 : 1.2) });
    };
  }
  const BARIN_SRC = (() => {
    const cv = document.createElement("canvas");
    cv.width = 160; cv.height = 120;
    const c = cv.getContext("2d"), draw = makeBarinScene();
    for (let i = 1; i <= 90; i++) draw(c, i);   // let the steam rise
    try { return cv.toDataURL(); } catch (e) { return ""; }
  })();
