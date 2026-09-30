import json, re, os, sys, shutil
from picosvg.svg import SVG
import pathops
sol=json.load(open('package/icons.json'))['icons']; ms=json.load(open('msl/package/icons.json'))['icons']
mapping=[l.split() for l in open('mapping.txt') if l.strip()] if os.path.exists('mapping.txt') else []
ANDROID=sys.argv[1].startswith('android:'); OUT=sys.argv[1].split(':')[-1]
targets=sorted({b for a,b in mapping} | set(sys.argv[2:]))
def body_of(t):
    if t.startswith('m:'): return ms[t[2:]]['body']
    if t.startswith('c:'): return open(f'custom/{t[2:]}.svg').read()
    if t.startswith('b:'): return sol[t[2:]+'-bold']['body']
    return sol[t+'-linear']['body']
def name_of(t): return t[2:]+'-bold' if t.startswith('b:') else t.split(':')[-1]
SCALE=5.0; CAPMID=35.25; PAD=2.0
def symbol_svg(d_list, minx, maxx):
    w=(maxx-minx)*SCALE+2*PAD
    left=1391.0
    paths=''.join(f'<path d="{d}"/>' for d in d_list)
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <g id="Notes">
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1933)">Template v.3.0</text>
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
 </g>
 <g id="Guides">
  <line id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="696" y2="696"/>
  <line id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="625.541" y2="625.541"/>
  <line id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1126" y2="1126"/>
  <line id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
  <line id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1556" y2="1556"/>
  <line id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
  <line id="left-margin-Regular-M" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{left}" x2="{left}" y1="1030.79" y2="1150.12"/>
  <line id="right-margin-Regular-M" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{left+w:.3f}" x2="{left+w:.3f}" y1="1030.79" y2="1150.12"/>
 </g>
 <g id="Symbols">
  <g id="Regular-M" transform="matrix(1 0 0 1 {left} 1126)">
   {paths}
  </g>
 </g>
</svg>
'''
os.makedirs(OUT, exist_ok=True)
if not ANDROID: json.dump({"info":{"author":"xcode","version":1},"properties":{"provides-namespace":False}}, open(f'{OUT}/Contents.json','w'), indent=2)
for t in targets:
    body=body_of(t).replace('currentColor','#000000')
    svg=SVG.fromstring(f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">{body}</svg>')
    pico=svg.topicosvg(allow_text=False)
    # union everything into one filled outline (single-colour template glyph)
    shapes=[s for s in pico.shapes()]
    # rebuild with pathops union
    acc=None
    for s in shapes:
        pth=pathops.Path(fillType=pathops.FillType.WINDING)
        from picosvg.svg_pathops import skia_path
        pth=skia_path(s.as_cmd_seq(), s.fill_rule)
        acc=pth if acc is None else pathops.op(acc, pth, pathops.PathOp.UNION)
    acc.simplify()
    b=acc.bounds
    minx,miny,maxx,maxy=b
    from picosvg.svg_pathops import svg_commands
    from picosvg.svg_types import SVGPath
    from picosvg.svg_transform import Affine2D
    sp=SVGPath.from_commands(svg_commands(acc)).apply_transform(Affine2D(SCALE,0,0,SCALE,PAD-minx*SCALE,-12*SCALE-CAPMID))
    d=sp.round_floats(3).d
    n=name_of(t)
    if ANDROID:
        dd=SVGPath.from_commands(svg_commands(acc)).round_floats(3).d
        open(f'{OUT}/ic_{n.replace("-","_")}.xml','w').write(f'''<?xml version="1.0" encoding="utf-8"?>
<!-- {n}: generated from the Solar / Material Symbols source, see Symbols.kt -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FF000000"
        android:pathData="{dd}" />
</vector>
''')
        continue
    ds=f'{OUT}/{n}.symbolset'; os.makedirs(ds, exist_ok=True)
    open(f'{ds}/{n}.svg','w').write(symbol_svg([d],minx,maxx))
    json.dump({"info":{"author":"xcode","version":1},"symbols":[{"filename":f"{n}.svg","idiom":"universal"}]}, open(f'{ds}/Contents.json','w'), indent=2)
print(len(targets),'symbols')
