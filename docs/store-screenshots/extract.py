#!/usr/bin/env python3
"""Step 2: cut the store pieces out of the Simulator captures, in every language, finding each piece by
its colours (longer German or Dutch text moves things; that doesn't matter).

    python3 extract.py WORK [lang ...]     WORK/shots/<lang>/<scene>.png -> WORK/lib/<lang>/<piece>.png

Each language also gets WORK/lib-<lang>.jpg, a contact sheet of its pieces to eyeball."""
import pathlib, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter



def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(np.int16)


def runs(flags, max_gap=0, min_len=1):
    """(start, end) of True runs, merging gaps up to max_gap."""
    out, start, last = [], None, None
    for i, f in enumerate(flags):
        if f:
            if start is None:
                start = i
            elif i - last - 1 > max_gap:
                out.append((start, last)); start = i
            last = i
    if start is not None:
        out.append((start, last))
    return [r for r in out if r[1] - r[0] + 1 >= min_len]


def lum(a):
    return a.mean(axis=2)


def is_grey(a):
    lo, hi = a.min(axis=2), a.max(axis=2)
    return (lo >= 226) & (hi <= 247) & (hi - lo <= 10)


def is_white(a):
    return a.min(axis=2) >= 250


X0, X1 = 30, 1290


def dark_block(a, y0, y1, first=False):
    dark = lum(a) < 80
    cov = dark[:, X0:X1].mean(axis=1)
    rs = [r for r in runs(cov > .5, max_gap=70, min_len=150) if r[0] >= y0 and r[1] <= y1]
    if not rs:
        raise ValueError(f"no dark block in {y0}-{y1}")
    ya, yb = rs[0] if first else max(rs, key=lambda r: r[1] - r[0])
    cols = dark[ya:yb].mean(axis=0) > .5
    xs = np.nonzero(cols)[0]
    return int(xs.min()), int(ya), int(xs.max()), int(yb)


def grey_block(a, y0, y1, first=False):
    g = is_grey(a)
    cov = g[:, X0:X1].mean(axis=1)
    rs = [r for r in runs(cov > .45, max_gap=160, min_len=150) if r[0] >= y0 and r[1] <= y1]
    if not rs:
        raise ValueError(f"no grey block in {y0}-{y1}")
    ya, yb = rs[0] if first else max(rs, key=lambda r: r[1] - r[0])
    cols = g[ya:yb].mean(axis=0) > .4
    xs = np.nonzero(cols)[0]
    return int(xs.min()), int(ya), int(xs.max()), int(yb)


def chips(a, y0, y1):
    """Grey pills on the white page between y0 and y1, in reading order."""
    g = is_grey(a)[y0:y1]
    rowhas = np.array([len(runs(r[X0:X1], max_gap=0, min_len=24)) > 0 for r in g])
    out = []
    for ra, rb in runs(rowhas, max_gap=12, min_len=60):
        if rb - ra > 200:  # a block, not a pill
            continue
        band = g[ra:rb + 1]
        cols = band.any(axis=0)
        for ca, cb in runs(cols, max_gap=3, min_len=90):
            out.append((int(ca), int(y0 + ra), int(cb), int(y0 + rb)))
    return out


def time_cards(a, y0, y1):
    """Three white cards side by side on the grey 'When' block."""
    w, g = is_white(a), is_grey(a)
    hits = []
    for y in range(y0, y1):
        wr = runs(w[y], max_gap=0, min_len=280)
        ok = [(s, e) for s, e in wr if e - s < 460 and s > 5 and e < 1314 and g[y, s - 4] and g[y, e + 4]]
        hits.append(len(ok) == 3)
    band = max(runs(hits, max_gap=90, min_len=60), key=lambda r: r[1] - r[0])
    ya, yb = y0 + band[0], y0 + band[1]
    # The card rows where all three are plain white across: pick the x runs there.
    rows = [y for y in range(ya, yb + 1) if hits[y - y0]]
    segs = [(s, e) for s, e in runs(w[rows[len(rows) // 2]], max_gap=0, min_len=280) if e - s < 460 and s > 5]
    # Grow the band to the cards' real top and bottom (the white continues above and below the hit rows).
    cx = (segs[0][0] + segs[0][1]) // 2
    while ya > 0 and w[ya - 1, cx]: ya -= 1
    while yb < w.shape[0] - 1 and (w[yb + 1, cx] or not g[yb + 1, cx]): yb += 1
    yb = min(yb, ya + 420)
    return [(int(s), int(ya), int(e), int(yb)) for s, e in segs]


def cut(a, box, pad=18, tol=7):
    """The piece in box, its background (the border colour) flooded out, soft decontaminated edges."""
    x0, y0, x1, y1 = box
    x0, y0, x1, y1 = max(0, x0 - pad), max(0, y0 - pad), min(a.shape[1], x1 + pad + 1), min(a.shape[0], y1 + pad + 1)
    r = a[y0:y1, x0:x1]
    h, w, _ = r.shape
    bg = np.median(np.concatenate([r[0], r[-1], r[:, 0], r[:, -1]]), axis=0)
    dist = np.abs(r - bg).max(axis=2)
    m = Image.fromarray(((dist <= tol) * 255).astype(np.uint8)).copy()
    px = m.load()
    for x in range(w):
        for y in (0, h - 1):
            if px[x, y] == 255: ImageDraw.floodfill(m, (x, y), 128)
    for y in range(h):
        for x in (0, w - 1):
            if px[x, y] == 255: ImageDraw.floodfill(m, (x, y), 128)
    outside = np.asarray(m) == 128
    alpha = np.where(outside, 0.0, 1.0)
    ring = (np.asarray(Image.fromarray((outside * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0) & ~outside
    alpha = np.where(ring, np.clip((dist - tol) / 70.0, 0, 1), alpha)
    alpha = np.where(outside & (dist > 2), np.clip(dist / 70.0, 0, .35), alpha)
    af = alpha[..., None]
    rgb = np.where(af > .02, (r - bg * (1 - af)) / np.maximum(af, .02), 0)
    out = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)).copy()
    bb = Image.fromarray((alpha > .4).astype(np.uint8) * 255).getbbox()
    return out.crop((max(0, bb[0] - 8), max(0, bb[1] - 8), min(w, bb[2] + 8), min(h, bb[3] + 8)))


def card(a):
    """A Discover card alone on the deck: strong difference to the page, cut with its 70 px corners."""
    bg = a[340, 5]
    d = np.abs(a - bg).max(axis=2)
    ys = np.nonzero(d[330:2300, 660] > 40)[0] + 330
    xs = np.nonzero(d[1200] > 40)[0]
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    S, rad = 4, 70
    m = Image.new("L", ((x1 - x0) * S, (y1 - y0) * S), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, (x1 - x0) * S - 1, (y1 - y0) * S - 1], radius=rad * S, fill=255)
    out = Image.fromarray(a[y0:y1, x0:x1].astype(np.uint8)).convert("RGBA")
    out.putalpha(m.resize(out.size, Image.LANCZOS))
    return out


def like_button(a):
    x0, y0, x1, y1 = 640, 2310, 940, 2610
    r = a[y0:y1, x0:x1]
    bg = np.median(np.concatenate([r[0], r[-1], r[:, 0], r[:, -1]]), axis=0)
    ys, xs = np.nonzero(np.abs(r - bg).max(axis=2) > 14)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    rad = min(xs.max() - xs.min(), ys.max() - ys.min()) / 2 + 1
    S = 4
    m = Image.new("L", ((x1 - x0) * S, (y1 - y0) * S), 0)
    ImageDraw.Draw(m).ellipse([(cx - rad) * S, (cy - rad) * S, (cx + rad) * S, (cy + rad) * S], fill=255)
    out = Image.fromarray(r.astype(np.uint8)).convert("RGBA")
    out.putalpha(m.resize(out.size, Image.LANCZOS))
    return out.crop((int(cx - rad - 2), int(cy - rad - 2), int(cx + rad + 3), int(cy + rad + 3)))


def extract(lang, src, dst):
    S = lambda n: load(src / f"{n}.png")
    dst.mkdir(parents=True, exist_ok=True)
    save = lambda im, n: im.save(dst / f"{n}.png", optimize=True)
    for p in ("lea", "maya", "thomas", "karim"):
        save(card(S(f"solo-{p}")), f"card_{p}")
    save(like_button(S("discover")), "like")
    a = S("propose")
    for i, box in enumerate(time_cards(a, 700, 2400), 1):
        save(cut(a, box, pad=14, tol=6), f"time{i}")
    a = S("malik")
    sp = dark_block(a, 800, 2560)
    save(cut(a, sp, tol=8), "malik_sports")
    cs = chips(a, max(0, sp[1] - 480), sp[1] - 10)
    for i, box in enumerate(cs[1:], 2):  # the first tag ("Early bird") stays out
        save(cut(a, box, pad=10, tol=8), f"mchip{i}")
    a = S("icebreaker")
    save(cut(a, dark_block(a, 800, 2300), tol=8), "icebreaker")
    a = S("profile")
    pr = grey_block(a, 700, 2000)
    save(cut(a, pr, tol=6), "prompt")
    ch = chips(a, max(0, pr[1] - 300), pr[1] - 10)
    save(cut(a, ch[-1], pad=10, tol=8), "vitals")
    a = S("mayav")
    vo = dark_block(a, 600, 1900, first=True)
    save(cut(a, vo, tol=8), "voice")
    save(cut(a, grey_block(a, vo[3] + 20, vo[3] + 900, first=True), tol=6), "mayaprompt")
    return len(cs)


def sheet(lang, dst, out):
    names = ["card_lea", "card_maya", "card_thomas", "card_karim", "like", "time1", "time2", "time3", "malik_sports",
             "mchip2", "mchip3", "mchip4", "icebreaker", "prompt", "vitals", "voice", "mayaprompt"]
    cw, chh = 300, 420
    im = Image.new("RGB", (cw * 9, chh * 2), (205, 90, 90))
    d = ImageDraw.Draw(im)
    for i, n in enumerate(names):
        p = dst / f"{n}.png"
        x, y = (i % 9) * cw + 8, (i // 9) * chh + 8
        if not p.exists():
            d.text((x, y), f"MISSING {n}", fill=(255, 255, 255)); continue
        t = Image.open(p); w0, h0 = t.size; t.thumbnail((cw - 16, chh - 40))
        im.paste(t, (x, y), t); d.text((x, y + chh - 30), f"{n} {w0}x{h0}", fill=(255, 255, 255))
    im.save(out, quality=82)


if __name__ == "__main__":
    work = pathlib.Path(sys.argv[1])
    langs = sys.argv[2:] or ["en", "fr", "es", "de", "it", "pt", "nl"]
    for l in langs:
        n = extract(l, work / "shots" / l, work / "lib" / l)
        sheet(l, work / "lib" / l, work / f"lib-{l}.jpg")
        print(l, "ok,", n, "lifestyle tags on the Hyrox profile (the first one is left out)")
