#!/usr/bin/env python3
"""Google Play feature graphic (1024 x 500), from the same cut pieces as the screenshots.

    python3 feature.py WORK OUT [variant ...] [lang ...]

Renders each variant (default: CHOSEN below, or all ten when none is chosen) in each language (default: all
seven) to
OUT/google-play/feature-graphic/<locale>/<variant>.png, and its HTML to WORK/html/feature/.
Designed at 2048 x 1000 and scaled down (sharper). Play's rules: opaque, no alpha; keep the name, the line
and the key visual inside the centred 924 x 400 safe zone (checked); no price, ranking or "new".
"""
import json, math, pathlib, re, sys
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import compose as C  # shared: CSS, fonts, pieces, French typography, Chrome

FW, FH = 2048, 1000            # design canvas (2x)
SAFE = 100                      # 50 px at 1x
INK, MUTE, MUTE_N = "#0E0F0C", "#55595E", "#B8BCC2"
NB = " "

# Retired lines (WORDING.md §7.2, 2026-10-01), kept only for the alternative variants: T1 "Meet me on the start
# line.", T2 "Turn your matches into sessions.", T4 "Dating, with a start time."
T1 = {"en": "Meet me on the start line.", "fr": "Rendez-vous au départ.", "es": "Nos vemos en la salida.",
      "de": "Wir sehen uns am Start.", "it": "Ci vediamo alla partenza.", "pt": "Encontramo-nos na partida.",
      "nl": "Zie je bij de start."}
T2 = {"en": "Turn your matches into sessions.", "fr": "Transforme tes matchs en séances.", "es": "Convierte tus matches en sesiones.",
      "de": "Mach aus deinen Matches Sessions.", "it": "Trasforma i tuoi match in sessioni.", "pt": "Transforma os teus matches em sessões.",
      "nl": "Maak van je matches sessies."}
T4 = {"en": "Dating, with a start time.", "fr": "Des rencontres avec une heure de départ.", "es": "Citas con hora de salida.",
      "de": "Dating mit Startzeit.", "it": "Appuntamenti con un orario di partenza.", "pt": "Encontros com hora de partida.",
      "nl": "Daten met een starttijd."}
# WORDING.md §7.2, the Line (2026-10-01): says "dating" and the shared rhythm at a glance, neutral wording.
T0 = {"en": "Meet someone who gets your rhythm.", "fr": "Rencontre quelqu'un qui comprend ton rythme.",
      "es": "Conoce a alguien que entienda tu ritmo.", "de": "Triff jemanden, der deinen Rhythmus versteht.",
      "it": "Incontra qualcuno che capisce il tuo ritmo.", "pt": "Conhece alguém que perceba o teu ritmo.",
      "nl": "Ontmoet iemand die jouw ritme begrijpt."}
DAY = {"en": "Saturday", "fr": "Samedi", "es": "Sábado", "de": "Samstag", "it": "Sabato", "pt": "Sábado", "nl": "Zaterdag"}

PAGE, NIGHT, WHITE, GRAPHITE = C.PAGE, C.NIGHT, C.WHITE, C.GRAPHITE


def el(name, cx, cy, s=1.0, r=0.0, z=2, trail=None, tc=None, tk=1):
    return dict(k="el", name=name, cx=cx, cy=cy, s=s, r=r, z=z, trail=trail, tc=tc, tk=tk)


def tx(t, x, y, w, size, color=INK, align="left", mx=2, lh=.95, z=5, ls=-.024, key=True):
    # key text is checked against the safe zone
    return dict(k="tx", t=t, x=x, y=y, w=w, size=size, color=color, align=align, mx=mx, lh=lh, z=z, ls=ls, key=key)


def raw(html, z=1):
    return dict(k="raw", html=html, z=z)


def wm(x, y, size, color=INK):
    # The logo: the word alone, never a drafting trail (DESIGN.md).
    return raw(f'<div class="wm" data-safe="wordmark" style="position:absolute;left:{x}px;top:{y}px;font-size:{size}px;color:{color};z-index:6"><span>drafft</span></div>', 6)


def photo(name, x, y, w, h, extra=""):
    p = next((C.ASSETS / f"{name}.imageset").glob("*.jpg")).as_uri()
    return raw(f'<div style="position:absolute;left:{x}px;top:{y}px;width:{w}px;height:{h}px;background:url({p}) center/cover;{extra}"></div>', 0)


def burst(cx, cy, k=1.0):
    out = ""
    for i in range(7):
        a = math.radians(i / 7 * 360 - 90)
        size = (10 + (i % 3) * 3) * 5.2 * k
        x, y = cx + math.cos(a) * 175 * k, cy + math.sin(a) * 175 * k
        col = "#9fe870" if i % 2 == 0 else "#CDFFAD"
        out += (f'<svg viewBox="0 0 24 24" style="position:absolute;left:{x - size / 2:.0f}px;top:{y - size / 2:.0f}px;width:{size:.0f}px;height:{size:.0f}px;'
                f'z-index:8;transform:rotate({(i * 23) % 40 - 20}deg);filter:drop-shadow(0 10px 18px rgba(0,0,0,.35))"><path d="{C.HEART}" fill="{col}"/></svg>')
    return raw(out, 8)


# The variant picked for the store (its name, e.g. "07-ticket"). None: render all ten to choose.
CHOSEN = "01-deck"

TR = (60, -28)
LIT = dict(tc="brightness(0) invert(1)", tk=.5)


def variants(lang):
    fr = lang == "fr"
    t0, t1, t2, t4, day, hour = T0[lang], T1[lang], T2[lang], T4[lang], DAY[lang], C.HOUR[lang]
    icon = (C.ASSETS / "AppIcon.appiconset/icon.png").as_uri()
    return {
        # 1. The deck: the line on the left, the real Discover cards and the like on the right.
        "01-deck": (PAGE, [wm(150, 250, 110), tx(t0, 140, 420, 900, 132, mx=3),
                           el("card_thomas", 1330, 520, .36, -10, 2), el("card_maya", 1510, 480, .38, -2, 3),
                           el("card_lea", 1680, 520, .41, 7, 4), el("like", 1850, 780, 1.1, 0, 6)]),
        # 2. The times: three cards tumbling on graphite, the precise promise in white.
        "02-creneaux": (GRAPHITE, [tx(t4, 140, 300, 960, 124, WHITE, mx=3), wm(150, 760, 80, WHITE),
                                   el("time1", 1280, 320, 1.12, -12, 4), el("time2", 1530, 500, 1.12, 4, 5),
                                   el("time3", 1760, 680, 1.08, 12, 6)]),
        # 3. The photo: a runner at sunset, full bleed, the name and line in white over a scrim.
        "03-photo": (NIGHT, [photo("sport_sunsetrun", 0, 0, FW, FH), raw('<div style="position:absolute;inset:0;background:linear-gradient(90deg,rgba(14,15,12,.78) 0%,rgba(14,15,12,.35) 55%,rgba(14,15,12,0) 80%);z-index:1"></div>', 1),
                             wm(150, 280, 120, WHITE), tx(t1, 140, 460, 1000, 128, WHITE, mx=3), el("like", 1800, 760, 1.15, 0, 6)]),
        # 4. The wordmark: the logo huge, the line under it. Brand only.
        "04-logo": (PAGE, [wm(560, 250, 330), tx(t1, 124, 690, 1800, 96, MUTE, align="center", mx=1)]),
        # 5. The icon and the voice: night, the app icon, the voice intro and the like burst.
        "05-voix": (NIGHT, [raw(f'<img data-safe="icon" src="{icon}" style="position:absolute;left:150px;top:190px;width:230px;height:230px;border-radius:52px;z-index:5;box-shadow:0 0 0 3px rgba(255,255,255,.14)">', 5),
                            tx(t1, 140, 480, 900, 116, WHITE, mx=3),
                            el("voice", 1480, 380, .75, 4, 3), el("mayaprompt", 1450, 700, .7, -4, 4), burst(1450 + 330, 700 + 27, .74)]),
        # 6. The strip: four real pieces in a row under one line.
        "06-bande": (WHITE, [tx(t2, 124, 150, 1800, 96, align="center", mx=1),
                             el("card_lea", 420, 640, .3, -7, 3), el("time1", 800, 650, 1.05, 5, 4),
                             el("malik_sports", 1270, 650, .5, -4, 4), el("like", 1680, 650, 1.1, 0, 5)]),
        # 7. The ticket: Maya's card and her time pinned together, the hour as the headline.
        "07-ticket": (PAGE, [tx(f"{day},\n{hour}.", 140, 220, 900, 190, mx=2, lh=.9), tx(t1, 150, 640, 900, 72, MUTE, mx=2, lh=1.05),
                             el("card_maya", 1450, 500, .44, -6, 3), el("time1", 1720, 700, 1.15, 8, 5, trail=TR), wm(150, 820, 64)]),
        # 8. The figure: a giant 9:00 in graphite, the card and the time over it.
        "08-chiffre": (PAGE, [raw(f'<div class="h" style="position:absolute;left:150px;top:150px;font-size:500px;line-height:.82;letter-spacing:-.05em;color:#111214;z-index:0">{hour}</div>', 0),
                              el("card_lea", 1520, 500, .37, -6, 3), el("time1", 1750, 680, 1.1, 8, 5),
                              tx(t1, 150, 760, 1100, 84, MUTE, mx=1, z=6)]),
        # 9. In common: the Hyrox profile's sports block over a tonal 3x, the line on the left.
        "09-commun": (WHITE, [raw('<div class="h" style="position:absolute;left:1020px;top:140px;font-size:760px;line-height:.8;letter-spacing:-.05em;color:#E4E6E9;z-index:0">3×</div>', 0),
                              wm(150, 250, 100), tx(t2, 140, 420, 860, 116, mx=3),
                              el("malik_sports", 1480, 520, .75, -4, 4), el("mchip3", 1400, 880, .95, -3, 5)]),
        # 10. The start line: a white line across graphite, the time card sitting on it, the like.
        "10-depart": (GRAPHITE, [raw('<div style="position:absolute;left:0;top:760px;width:2048px;height:14px;background:#fff;z-index:1"></div>', 1),
                                 wm(150, 230, 110, WHITE), tx(t1, 140, 400, 1000, 124, WHITE, mx=3),
                                 el("time1", 1500, 560, 1.3, -6, 4, trail=TR, **LIT), el("like", 1820, 640, 1.15, 0, 5)]),
    }


CHECK = """<pre id="chk"></pre><script>
document.fonts.ready.then(()=>{
document.querySelectorAll('.fit').forEach(el=>{const max=+el.dataset.max;let fs=parseFloat(getComputedStyle(el).fontSize);
 const lh=()=>parseFloat(getComputedStyle(el).lineHeight)||fs;let g=0;
 while(g++<120&&(el.scrollWidth>el.clientWidth+1||el.offsetHeight>lh()*max+4)){fs-=3;el.style.fontSize=fs+'px';}});
const W=%d,H=%d,S=%d,bad=[];
function box(e){const r=document.createRange();r.selectNodeContents(e);const rs=[...r.getClientRects()];
 return {left:Math.min(...rs.map(x=>x.left)),top:Math.min(...rs.map(x=>x.top)),right:Math.max(...rs.map(x=>x.right)),bottom:Math.max(...rs.map(x=>x.bottom))};}
// Key text, wordmark and icon inside the safe zone; every piece of the app fully on the canvas.
document.querySelectorAll('.key').forEach(e=>{const r=box(e);if(r.left<S||r.top<S||r.right>W-S||r.bottom>H-S)bad.push('text outside the safe zone: '+e.textContent.slice(0,30));});
document.querySelectorAll('[data-safe]').forEach(e=>{const r=e.getBoundingClientRect();if(r.left<S-40||r.top<S||r.right>W-S||r.bottom>H-S)bad.push(e.dataset.safe+' outside the safe zone');});
document.querySelectorAll('img:not([data-safe])').forEach(e=>{const r=e.getBoundingClientRect();if(r.left<0||r.top<0||r.right>W||r.bottom>H)bad.push((e.src||'').split('/').pop()+' cut by the edge');});
document.getElementById('chk').textContent=JSON.stringify(bad);});</script>""" % (FW, FH, SAFE)


def page(lang, bg, items):
    body = ""
    for it in items:
        if it["k"] == "tx":
            h = C.render_item(dict(it), lang)
            body += h.replace('class="h fit"', 'class="h fit key"' if it.get("key") else 'class="h fit"')
        elif it["k"] == "el":
            body += C.render_item(dict(it), lang)
        else:
            body += it["html"]
    return (f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{C.CSS}'
            f'body{{width:{FW}px;height:{FH}px;background:{bg}}} .strip{{position:relative;width:{FW}px;height:{FH}px;overflow:hidden}} #chk{{display:none}}</style></head>'
            f'<body><div class="strip">{body}</div>{CHECK}</body></html>')


def build(work, out, name, lang):
    bg, items = variants(lang)[name]
    d = work / "html" / "feature"
    d.mkdir(parents=True, exist_ok=True)
    html = d / f"{name}-{lang}.html"
    html.write_text(page(lang, bg, items))
    dom = C.chrome([f"--window-size={FW},{FH}", "--force-device-scale-factor=1", "--dump-dom", html.as_uri()])
    bad = json.loads(re.search(r'<pre id="chk">(.*?)</pre>', dom, re.S).group(1).replace("&quot;", '"') or "[]")
    png = d / f"{name}-{lang}.png"
    C.chrome([f"--window-size={FW},{FH}", "--force-device-scale-factor=1", f"--screenshot={png}", html.as_uri()])
    dst = out / "google-play/feature-graphic" / C.LOCALE[lang]
    dst.mkdir(parents=True, exist_ok=True)
    # The chosen one is the store file; the others keep their names, to compare.
    Image.open(png).convert("RGB").resize((1024, 500), Image.LANCZOS).save(dst / ("feature-graphic.png" if name == CHOSEN else f"{name}.png"), optimize=True)
    return bad


if __name__ == "__main__":
    work, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    C.WORK, C.OUT, C.LIB = work, out, work / "lib"
    args = sys.argv[3:]
    names = [a for a in args if a in variants("en")] or ([CHOSEN] if CHOSEN else list(variants("en")))
    langs = [a for a in args if a in C.LOCALE] or list(C.LOCALE)
    ok = True
    for n in names:
        for l in langs:
            bad = build(work, out, n, l)
            print(n, l, "OK" if not bad else bad)
            ok &= not bad
    sys.exit(0 if ok else 1)
