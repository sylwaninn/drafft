#!/usr/bin/env python3
"""Step 3: compose the store screenshots from the cut pieces: 5 screens x 7 languages x the store formats.

    python3 compose.py WORK OUT [lang ...] [iphone|play|ipad ...]

WORK/lib/<lang>/*.png (from extract.py) -> OUT/<store>/<device>/<locale>/01.png..05.png
The HTML of each strip stays in WORK/html/<format>/<lang>.html: open it in a browser to preview.
The captions (C), the hour (HOUR) and the layout (items) below are the validated set: edit them here.

Design width is 1320 for every format; the design height follows the format (iPhone 2868, Play 9:16 2347,
iPad 3:4 1760). Positions and sizes are mapped for each, the same checks run (nothing leaves the strip,
a seam shows at least MIN px each side, no heart on a seam), then Chrome renders at the store size."""
import base64, json, math, pathlib, re, subprocess, sys
from PIL import Image

REPO = pathlib.Path(__file__).resolve().parents[2]
ASSETS = REPO / "Drafft/Resources/Assets.xcassets"
FONTS = REPO / "Drafft/Resources/Fonts"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK = OUT = LIB = None  # set by main (or by feature.py, which imports this module)

PAGE, NIGHT, WHITE, GRAPHITE = "#EEEFF1", "#1C1E21", "#FFFFFF", "#111214"


def _b64(p):
    return base64.b64encode(pathlib.Path(p).read_bytes()).decode()


# The app's display face, embedded (Inter Display Black / ExtraBold), and the wordmark with its drafting trail.
CSS = f"""
@font-face {{ font-family: 'Inter Display'; font-weight: 900; src: url(data:font/ttf;base64,{_b64(FONTS / 'InterDisplay-Black.ttf')}) format('truetype'); }}
@font-face {{ font-family: 'Inter Display'; font-weight: 800; src: url(data:font/ttf;base64,{_b64(FONTS / 'InterDisplay-ExtraBold.ttf')}) format('truetype'); }}
:root {{ --ink: #0E0F0C; --display: 'Inter Display', -apple-system, sans-serif; }}
* {{ box-sizing: border-box; margin: 0; }}
.strip {{ position: relative; overflow: hidden; }}
.h {{ font-family: var(--display); font-weight: 900; color: var(--ink); text-wrap: balance; hyphens: none; }}
.wm {{ position: absolute; display: inline-block; font-family: var(--display); font-weight: 900; letter-spacing: -0.03em; line-height: 1; isolation: isolate; }}
.wm::before, .wm::after {{ content: 'drafft'; position: absolute; top: 0; left: 0; z-index: -1; }}
.wm::before {{ transform: translateX(-0.1em); opacity: .45; }}
.wm::after {{ transform: translateX(-0.2em); opacity: .2; }}
.wm > span {{ position: relative; z-index: 1; }}
"""


def frt(s):
    """French typography: a no-break space before ? ! : ;"""
    for c in "?!:;":
        s = s.replace(" " + c, "\u00a0" + c)
    return s
W, N, MIN = 1320, 5, 80
INK, MUTE, MUTE_N = "#0E0F0C", "#55595E", "#B8BCC2"
NB = " "
TR = (70, -34)
HEART = ("M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 "
         "19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z")

# Store locale folders (Play Console and App Store Connect use these codes).
LOCALE = {"en": "en-GB", "fr": "fr-FR", "es": "es-ES", "de": "de-DE", "it": "it-IT", "pt": "pt-PT", "nl": "nl-NL"}

# Captions (WORDING.md: informal "you", "you two" plural where both people act; brand terms per §4).
C = {
    "en": dict(s1a="Saturday, {T}.", s1b="Your next session\nhas company.", s2a="Propose\na session.", s2b="Find the time\nthat suits you both.",
               s3a="A sport\nin" + NB + "common?", s3b="You see it straight away.", s4="Icebreakers\nmake the first" + NB + "move.",
               s5="Hear their" + NB + "voice.\nLike what speaks to" + NB + "you."),
    "fr": dict(s1a="Samedi, {T}.", s1b="Ta prochaine séance\na de la compagnie.", s2a="Propose\nune séance.",
               s2b="Trouvez ensemble le" + NB + "moment qui vous convient.", s3a="Un sport\nen" + NB + "commun" + NB + "?",
               s3b="Ça se voit tout de suite.", s4="L'icebreaker\nfait le premier" + NB + "pas.", s5="Écoute sa voix.\nLike ce qui te" + NB + "parle."),
    "es": dict(s1a="Sábado, {T}.", s1b="Tu próxima sesión\ntiene compañía.", s2a="Propón\nuna sesión.", s2b="Encontrad juntos el" + NB + "momento que os va bien.",
               s3a="¿Un deporte\nen" + NB + "común?", s3b="Se ve a primera vista.", s4="El icebreaker\nda el primer" + NB + "paso.",
               s5="Escucha su voz.\nDale like a lo que te" + NB + "llega."),
    "de": dict(s1a="Samstag, {T}.", s1b="Deine nächste Session\nhat Gesellschaft.", s2a="Schlag eine\nSession vor.", s2b="Findet gemeinsam den" + NB + "Moment, der euch passt.",
               s3a="Ein gemeinsamer\nSport?", s3b="Siehst du sofort.", s4="Der Icebreaker\nmacht den ersten" + NB + "Schritt.",
               s5="Hör dir die Stimme an.\nLike, was dich" + NB + "anspricht."),
    "it": dict(s1a="Sabato, {T}.", s1b="La tua prossima sessione\nè in compagnia.", s2a="Proponi\nuna sessione.", s2b="Trovate insieme il" + NB + "momento che fa per voi.",
               s3a="Uno sport\nin" + NB + "comune?", s3b="Si vede subito.", s4="L'icebreaker\nfa il primo" + NB + "passo.",
               s5="Ascolta la sua voce.\nMetti like a ciò che ti" + NB + "parla."),
    "pt": dict(s1a="Sábado, {T}.", s1b="A tua próxima sessão\ntem companhia.", s2a="Propõe\numa sessão.", s2b="Encontrem juntos o" + NB + "momento que vos dá jeito.",
               s3a="Um desporto\nem" + NB + "comum?", s3b="Vê-se logo.", s4="O icebreaker\ndá o primeiro" + NB + "passo.",
               s5="Ouve a sua voz.\nDá like ao que te diz" + NB + "algo."),
    "nl": dict(s1a="Zaterdag, {T}.", s1b="Je volgende sessie\nheeft gezelschap.", s2a="Stel een\nsessie voor.", s2b="Vind samen het moment" + NB + "dat jullie allebei past.",
               s3a="Een gedeelde\nsport?", s3b="Dat zie je meteen.", s4="De icebreaker\nzet de eerste" + NB + "stap.",
               s5="Luister naar de stem.\nLike wat je" + NB + "aanspreekt."),
}
# The hour as the app writes it in each language (it matches the time card underneath).
HOUR = {"en": "9:00", "fr": "9:00", "es": "9:00", "de": "9:00", "it": "9:00", "pt": "9:00", "nl": "9:00"}

FORMATS = {
    # name: design height, scale of pieces and type, outputs [(store folder, width, height)]
    "iphone": dict(Hd=2868, k=1.0, outs=[("app-store/iphone-6.9", 1320, 2868)]),
    "play": dict(Hd=2347, k=.84, outs=[("google-play/phone", 1080, 1920), ("google-play/tablet-7", 1080, 1920),
                                        ("google-play/tablet-10", 1620, 2880)]),
    "ipad": dict(Hd=1760, k=.64, outs=[("app-store/ipad-13", 2064, 2752)]),
}


def X(i, x):
    return i * W + x


class Map:
    def __init__(self, Hd, k):
        self.fy, self.k = Hd / 2868, k

    def y(self, v):
        return v * self.fy


def items(lang, M):
    c = {key: v.replace("{T}", HOUR[lang]) for key, v in C[lang].items()}
    k, Y = M.k, M.y
    L = LIB / lang

    def el(name, cx, cy, s=1.0, r=0.0, z=2, trail=None, tc=None, tk=1):
        return dict(k="el", name=name, cx=cx, cy=Y(cy), s=s * k, r=r, z=z, trail=(trail[0] * k, trail[1] * k) if trail else None, tc=tc, tk=tk)

    def tx(t, x, y, w, size, color=INK, align="left", mx=3, lh=.96, z=5, ls=-.024):
        return dict(k="tx", t=t, x=x, y=Y(y), w=w, size=size * k, color=color, align=align, mx=mx, lh=lh, z=z, ls=ls)

    def raw(html, z=1):
        return dict(k="raw", html=html, z=z)

    def wm(x, y, size, color):
        return raw(f'<div class="wm" style="position:absolute;left:{x}px;top:{Y(y):.0f}px;font-size:{size * k:.0f}px;color:{color};z-index:6"><span>drafft</span></div>', 6)

    def photo(name, cx, cy, w, h, r, z=1):
        p = next((ASSETS / f"{name}.imageset").glob("*.jpg")).as_uri()
        w, h = w * k, h * k
        return raw(f'<div data-chk="photo {name}" style="position:absolute;left:{cx - w / 2:.0f}px;top:{Y(cy) - h / 2:.0f}px;width:{w:.0f}px;height:{h:.0f}px;'
                   f'border-radius:{72 * k:.0f}px;background:url({p}) center/cover;transform:rotate({r}deg);z-index:{z};'
                   f'box-shadow:0 50px 90px -30px rgba(14,15,12,.45)"></div>', z)

    def burst(cx, cy):
        # The app's HeartBurst (7 hearts, like green and its tint), frozen mid-flight, scaled up; two fly further.
        out = ""
        for i in range(7):
            a = math.radians(i / 7 * 360 - 90)
            size = (10 + (i % 3) * 3) * 5.2 * k
            x, y = cx + math.cos(a) * 175 * k, cy + math.sin(a) * 175 * k
            col = "#9fe870" if i % 2 == 0 else "#CDFFAD"
            out += (f'<svg data-chk="heart" viewBox="0 0 24 24" style="position:absolute;left:{x - size / 2:.0f}px;top:{y - size / 2:.0f}px;width:{size:.0f}px;'
                    f'height:{size:.0f}px;z-index:8;transform:rotate({(i * 23) % 40 - 20}deg);filter:drop-shadow(0 10px 18px rgba(0,0,0,.35))">'
                    f'<path d="{HEART}" fill="{col}"/></svg>')
        for dx, dy, size, col, rot in ((-185, -317, 132, "#9fe870", -14), (75, -407, 92, "#CDFFAD", 12)):
            size *= k
            x, y = cx + dx * k, cy + dy * k
            out += (f'<svg data-chk="heart" viewBox="0 0 24 24" style="position:absolute;left:{x - size / 2:.0f}px;top:{y - size / 2:.0f}px;width:{size:.0f}px;'
                    f'height:{size:.0f}px;z-index:8;transform:rotate({rot}deg);filter:drop-shadow(0 12px 22px rgba(0,0,0,.4))"><path d="{HEART}" fill="{col}"/></svg>')
        return raw(out, 8)

    lit = dict(tc="brightness(0) invert(1)", tk=.5)
    return [
        # 1. Grey. The hour huge, real Discover cards, the like.
        tx(c["s1a"], X(0, 96), 190, 1128, 212, mx=2, lh=.9),
        tx(c["s1b"], X(0, 104), 618, 1128, 92, MUTE, mx=2, lh=1.05),
        el("card_thomas", X(0, 440), 1700, .55, -10, 2),
        el("card_maya", X(0, 640), 1640, .57, -2, 3),
        el("card_lea", X(0, 820), 1700, .61, 6, 4),
        el("like", X(0, 1010), 2420, 1.45, 0, 6),
        el("card_karim", X(1, 0), 1480, .5, 14, 1),
        # 2. Graphite. Three times tumbling down, the words at the bottom.
        el("time1", X(1, 560), 800, 1.45, -12, 4),
        el("time2", X(1, 860), 1190, 1.45, 4, 5),
        el("time3", X(1, 960), 1640, 1.4, 12, 6),
        tx(c["s2a"], X(1, 96), 2080, 1128, 180, WHITE, mx=2, lh=.92),
        tx(c["s2b"], X(1, 104), 2440, 1128, 84, MUTE_N, mx=2, lh=1.08),
        # 3. White. Headline set right, the figure behind, the tags.
        tx(c["s3a"], X(2, 96), 190, 1128, 156, align="right", mx=2),
        tx(c["s3b"], X(2, 96), 520, 1128, 84, MUTE, align="right", mx=1),
        tx("3×", X(2, 40), 1080, 3000, 1150, "#E4E6E9", mx=1, lh=.8, z=0, ls=-.05),
        el("malik_sports", X(2, 620), 1760, .88, -5, 4),
        el("mchip2", X(2, 330), 2360, 1.1, -5, 6),
        el("mchip3", X(2, 540), 2560, 1.05, -2, 6),
        el("mchip4", X(2, 1010), 2380, 1.05, 6, 5),
        photo("hero_2", X(3, 0), 1150, 600, 820, -5, 2),
        # 4. Grey. The icebreaker.
        tx(c["s4"], X(3, 96), 190, 1128, 164, mx=3, lh=.92),
        el("icebreaker", X(3, 730), 1640, .85, 5, 4),
        el("prompt", X(3, 580), 2420, .78, -5, 5),
        el("vitals", X(3, 1030), 2180, 1.15, 8, 6),
        # 5. Night. Hear the voice, like what speaks to you.
        tx(c["s5"], X(4, 96), 190, 1128, 180, WHITE, mx=3, lh=.92),
        el("voice", X(4, 660), 1210, 1.0, 4, 3),
        el("mayaprompt", X(4, 640), 1960, .95, -4, 4),
        burst(X(4, 640) + 445 * k, Y(1960) + 37 * k),
        wm(X(4, 104), 2640, 64, WHITE),
    ]


BGS = [PAGE, GRAPHITE, WHITE, PAGE, NIGHT]
HEARTS = {"like"}


def render_item(it, lang):
    if it["k"] == "raw":
        return it["html"]
    if it["k"] == "tx":
        t = frt(it["t"]) if lang == "fr" else it["t"]
        t = " ".join(f'<span style="white-space:nowrap">{w}</span>' if "-" in w else w for w in t.split(" ")).replace("\n", "<br>")
        return (f'<div style="position:absolute;left:{it["x"]}px;top:{it["y"]:.0f}px;width:{it["w"]}px;z-index:{it["z"]};text-align:{it["align"]}">'
                f'<div class="h fit" data-max="{it["mx"]}" style="font-size:{it["size"]:.0f}px;color:{it["color"]};line-height:{it["lh"]};'
                f'letter-spacing:{it["ls"]}em">{t}</div></div>')
    src = LIB / lang / f"{it['name']}.png"
    w0, h0 = Image.open(src).size
    w, h = w0 * it["s"], h0 * it["s"]
    left, top = it["cx"] - w / 2, it["cy"] - h / 2
    uri = src.as_uri()
    out = ""
    if it["trail"]:
        dx, dy = it["trail"]
        for n, op in ((2, .2), (1, .45)):
            out += (f'<img src="{uri}" style="position:absolute;left:{left - dx * n:.0f}px;top:{top - dy * n:.0f}px;width:{w:.0f}px;height:{h:.0f}px;z-index:{it["z"]};'
                    f'transform:rotate({it["r"]}deg);filter:{it["tc"] or "brightness(0)"};opacity:{op * it["tk"]}">')
    out += (f'<img src="{uri}" style="position:absolute;left:{left:.0f}px;top:{top:.0f}px;width:{w:.0f}px;height:{h:.0f}px;z-index:{it["z"]};'
            f'transform:rotate({it["r"]}deg);filter:drop-shadow(0 34px 44px rgba(14,15,12,.26)) drop-shadow(0 6px 10px rgba(14,15,12,.10))">')
    return out


def page(lang, its, Hd):
    body = "".join(f'<div style="position:absolute;left:{i * W}px;top:0;width:{W}px;height:{Hd}px;background:{bg};z-index:0"></div>'
                   for i, bg in enumerate(BGS))
    body += "".join(render_item(it, lang) for it in its)
    check = """<pre id="chk"></pre><script>
document.fonts.ready.then(()=>{
document.querySelectorAll('.fit').forEach(el=>{const max=+el.dataset.max;let fs=parseFloat(getComputedStyle(el).fontSize);
 const lh=()=>parseFloat(getComputedStyle(el).lineHeight)||fs;let g=0;
 while(g++<120&&(el.scrollWidth>el.clientWidth+1||el.offsetHeight>lh()*max+4)){fs-=3;el.style.fontSize=fs+'px';}});
(function(){const W=%d,H=%d,N=%d,MIN=%d,bad=[];const seams=[...Array(N-1)].map((_,i)=>(i+1)*W);
function test(r,name){if(r.width<2||r.height<2)return;
 if(r.left<-2||r.right>W*N+2||r.top<-2||r.bottom>H+2)bad.push(name+' leaves the strip '+[r.left,r.top,r.right,r.bottom].map(Math.round));
 seams.forEach(s=>{if(r.left<s-2&&r.right>s+2){const a=s-r.left,b=r.right-s;if(Math.min(a,b)<MIN)bad.push(name+' only '+Math.round(Math.min(a,b))+'px across seam '+s);
   if(/like|heart/.test(name))bad.push(name+' on seam '+s);}});}
document.querySelectorAll('img,[data-chk]').forEach(e=>test(e.getBoundingClientRect(),e.dataset.chk||(e.src||'').split('/').pop()));
document.querySelectorAll('.h').forEach(e=>{const r=document.createRange();r.selectNodeContents(e);const rs=[...r.getClientRects()];if(!rs.length)return;
 const u={left:Math.min(...rs.map(x=>x.left)),top:Math.min(...rs.map(x=>x.top)),right:Math.max(...rs.map(x=>x.right)),bottom:Math.max(...rs.map(x=>x.bottom))};
 u.width=u.right-u.left;u.height=u.bottom-u.top;test(u,'text "'+e.textContent.slice(0,24)+'"');});
document.getElementById('chk').textContent=JSON.stringify(bad);})();});</script>""" % (W, Hd, N, MIN)
    return (f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{CSS}'
            f'body{{width:{W * N}px;height:{Hd}px}} .strip{{width:{W * N}px;height:{Hd}px}} #chk{{display:none}}</style></head>'
            f'<body><div class="strip">{body}</div>{check}</body></html>')


def chrome(args):
    return subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                           "--virtual-time-budget=5000", *args], check=True, capture_output=True, text=True).stdout


def build(lang, fmt):
    F = FORMATS[fmt]
    Hd, k = F["Hd"], F["k"]
    its = items(lang, Map(Hd, k))
    work = WORK / "html" / fmt
    work.mkdir(parents=True, exist_ok=True)
    html = work / f"{lang}.html"
    html.write_text(page(lang, its, Hd))
    dom = chrome([f"--window-size={W * N},{Hd}", "--force-device-scale-factor=1", "--dump-dom", html.as_uri()])
    bad = json.loads(re.search(r'<pre id="chk">(.*?)</pre>', dom, re.S).group(1).replace("&quot;", '"') or "[]")
    big = max(o[1] for o in F["outs"])
    dsf = big / W
    png = work / f"{lang}.png"
    chrome([f"--window-size={W * N},{Hd}", f"--force-device-scale-factor={dsf}", f"--screenshot={png}", html.as_uri()])
    im = Image.open(png).convert("RGB")
    sw = im.width / N
    for folder, tw, th in F["outs"]:
        d = OUT / folder / LOCALE[lang]
        d.mkdir(parents=True, exist_ok=True)
        for i in range(N):
            sl = im.crop((round(i * sw), 0, round((i + 1) * sw), im.height)).resize((tw, th), Image.LANCZOS)
            sl.save(d / f"{i + 1:02d}.png", optimize=True)
    return bad


if __name__ == "__main__":
    WORK, OUT = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    LIB = WORK / "lib"
    args = sys.argv[3:]
    langs = [a for a in args if a in C] or list(C)
    fmts = [a for a in args if a in FORMATS] or list(FORMATS)
    ok = True
    for fmt in fmts:
        for lang in langs:
            bad = build(lang, fmt)
            print(fmt, lang, "OK" if not bad else bad)
            ok &= not bad
    sys.exit(0 if ok else 1)
