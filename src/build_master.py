# Splice the master's chapter (CSS, s12 markup, lesson content, boards, engine) into index.html.
# Safe to re-run: it recognises both the old single-file master and its own previous output.
import sys, re
SP = sys.argv[1]
path = sys.argv[2] if len(sys.argv) > 2 else "index.html"
s = open(path, encoding="utf-8").read()
rd = lambda n: open(f"{SP}/{n}", encoding="utf-8").read()

def cut(s, start, end, new, keep_end=True):
    i = s.index(start)
    j = s.index(end, i)
    if not keep_end:
        j += len(end)
    return s[:i] + new + s[j:]

# CSS
css = rd("master_css.css")
if "/* ---------- The master's temple (s12) ---------- */" in s:
    s = cut(s, "  /* ---------- The master's temple (s12) ---------- */", "  /* ---------- end of the master's temple ---------- */\n", css, keep_end=False)
else:
    s = cut(s, "  .master-stage .m-sprite {", "  .master-stage.asking .vn-box { min-height: 0; }\n", css, keep_end=False)

# markup
html = rd("master_html.html")
i = s.index('<section class="screen novel" id="s12" hidden>')
j = s.index("</section>\n", i) + len("</section>\n")
s = s[:i] + html + s[j:]

# script
js = rd("master_content.js") + "\n" + rd("boards.js") + "\n"
for extra in ("boards2.js", "voxel.js"):
    try:
        js += rd(extra) + "\n"
    except FileNotFoundError:
        pass
js += rd("master_engine.js") + "\n"
end = "  // ---------- Arc: a visual novel in the office ----------"
for start in ("  // ---------- The master's scrolls: lesson content ----------",
              "  // ---------- The master: four lessons on occlusion and jaw movement ----------"):
    if start in s:
        s = cut(s, start, end, js)
        break
else:
    sys.exit("master block not found")
# ---- days: end of shift, the ride home ----
dcss = rd("days_css.css")
if "/* ---------- Days: end of shift and the ride home (s13) ---------- */" in s:
    s = cut(s, "  /* ---------- Days: end of shift and the ride home (s13) ---------- */", "  /* ---------- end of days ---------- */\n", dcss, keep_end=False)
else:
    k = s.index("  /* ---------- end of the master's temple ---------- */\n") + len("  /* ---------- end of the master's temple ---------- */\n")
    s = s[:k] + dcss + s[k:]
dhtml = rd("days_html.html")
if '<section class="screen" id="s13" hidden>' in s:
    i = s.index('<section class="screen" id="s13" hidden>')
    j = s.index("</section>\n", i) + len("</section>\n")
    s = s[:i] + dhtml + s[j:]
else:
    i = s.index('<section class="screen novel" id="s12" hidden>')
    j = s.index("</section>\n", i) + len("</section>\n")
    s = s[:j] + "\n" + dhtml + s[j:]
if 'id="eyelids"' not in s:
    s = s.replace('<button class="dev-latest" id="latestBtn"', '<div class="eyelids" id="eyelids" aria-hidden="true"><i></i><i></i></div>\n\n<button class="dev-latest" id="latestBtn"', 1)
djs = rd("days.js")
for mark in ("  // ---------- Days: the end of a shift, the barin's pay and the ride home ----------",
             "  // ---------- Days: the end of a shift, the cat's pay and the ride home ----------"):
    if mark in s:
        s = cut(s, mark, "  // ---------- Days end ----------\n", djs, keep_end=False)
        break
else:
    k = s.index("  // ---------- The master's scrolls: lesson content ----------")
    s = s[:k] + djs + "\n" + s[k:]
open(path, "w", encoding="utf-8").write(s)
print("ok", len(s))
