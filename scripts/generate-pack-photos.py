#!/usr/bin/env python3
"""Generate the athletes shown behind your card in the boost / super like / likes sheets.

Photorealistic, made once, bundled as assets (pack_woman_1..6, pack_man_1..6): see PackPhotos.swift.
Uses the OpenAI Images API. The key is read from OPENAI_API_KEY and never printed or stored.

    export OPENAI_API_KEY=...        # in your own terminal
    python3 scripts/generate-pack-photos.py            # all missing photos
    python3 scripts/generate-pack-photos.py man_3      # redo one
"""
import base64
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import urllib.request

ASSETS = pathlib.Path(__file__).resolve().parent.parent / "Drafft/Resources/Assets.xcassets"

STYLE = (
    "Photorealistic candid sports photograph, shot on a 85mm lens, natural light, shallow depth of "
    "field, real effort: sweat, focus, motion. One person, face clearly visible, framed from the "
    "waist or chest up, vertical composition with the subject centred. Plain unbranded sportswear, "
    "no logos, no text, no race numbers with readable digits, no watermark. Looks like a real "
    "photo, not an illustration."
)

SUBJECTS = {
    "woman_1": "East Asian woman in her late twenties pushing a heavy sled in an indoor HYROX-style race hall",
    "woman_2": "Black woman in her thirties with dark skin and braided hair, running a city marathon mid-stride",
    "woman_3": "South Asian woman with a strong, curvy build riding a road bike up a mountain pass, helmet on",
    "woman_4": "Latina woman in her twenties trail running on a rocky path at sunrise, hair tied back",
    "woman_5": "Middle Eastern woman wearing a sports hijab, pulling hard on a rowing machine in a bright gym",
    "woman_6": "Red-haired white woman around forty with freckles, running out of a lake in a triathlon wetsuit",
    "man_1": "Black man with a shaved head throwing a wall ball in an indoor HYROX-style race, gritted teeth",
    "man_2": "Lean East Asian man sprinting on an outdoor athletics track, evening light",
    "man_3": "Bearded white man with a stocky build riding a gravel bike on a dusty forest road",
    "man_4": "South Asian man in his thirties finishing a marathon, crowd blurred behind him",
    "man_5": "Latino man with tattoos on his forearms doing battle ropes in a warehouse gym",
    "man_6": "North African man with curly hair and a hydration vest, running a mountain trail race",
}


def generate(name: str, subject: str, key: str) -> None:
    body = json.dumps({
        "model": "gpt-image-1",
        "prompt": f"{subject}. {STYLE}",
        "size": "1024x1536",
        "quality": "high",
        "n": 1,
    }).encode()
    request = urllib.request.Request(
        "https://api.openai.com/v1/images/generations", data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=300) as response:
        image = base64.b64decode(json.load(response)["data"][0]["b64_json"])

    folder = ASSETS / f"pack_{name}.imageset"
    folder.mkdir(exist_ok=True)
    target = folder / f"pack_{name}.jpg"
    with tempfile.NamedTemporaryFile(suffix=".png") as raw:
        raw.write(image)
        raw.flush()
        # 3:4 cards of 84 pt at most: 600 px wide is plenty at 3x.
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "80", "-Z", "900",
                        raw.name, "--out", str(target)], check=True, capture_output=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"idiom": "universal", "filename": target.name}],
        "info": {"version": 1, "author": "xcode"},
    }, indent=2) + "\n")
    print(f"pack_{name}: done")


def main() -> None:
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        sys.exit("Set OPENAI_API_KEY in your terminal first.")
    wanted = sys.argv[1:] or [n for n in SUBJECTS if not (ASSETS / f"pack_{n}.imageset").exists()]
    for name in wanted:
        generate(name, SUBJECTS[name], key)


if __name__ == "__main__":
    main()
