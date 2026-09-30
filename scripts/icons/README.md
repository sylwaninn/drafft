# App icons

Generates the icons of both apps from their SVG sources (rules: DESIGN.md, Icons).

- Solar linear/bold: `npm pack @iconify-json/solar` → `package/icons.json`
- Material Symbols Light (sports Solar lacks): `npm pack @iconify-json/material-symbols-light` → `msl/package/icons.json`
- Drawn in the Solar style: `custom/*.svg` (bodies, 24 grid, 1.5 stroke; `customs.py` writes them)

Setup, in a scratch folder next to copies of these files:

    python3 -m venv venv && ./venv/bin/pip install picosvg
    npm pack @iconify-json/solar && tar xzf iconify-json-solar-*.tgz
    mkdir msl && npm pack @iconify-json/material-symbols-light && tar xzf iconify-json-material-symbols-light-*.tgz -C msl

Targets: `name` (Solar linear), `b:name` (Solar bold, saved as `name-bold`), `m:name` (Material), `c:name` (custom).

    ./venv/bin/python build_icons.py out b:heart m:rowing c:padel                 # iOS: out/<name>.symbolset
    ./venv/bin/python build_icons.py android:andr b:heart m:rowing c:padel        # Android: andr/ic_<name>.xml

Copy the symbolsets into `Drafft/Resources/Assets.xcassets/Icons/`, the drawables into
`drafft-android/core/ui/src/main/res/drawable/`, and add each Android name to `Symbols.kt`.
Strokes are outlined and merged into one glyph; the symbol is scaled 5 units per px and centred
on the cap height, so it sits and sizes like an SF Symbol.
