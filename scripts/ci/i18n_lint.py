#!/usr/bin/env python3
"""Translation checks for drafft's string catalogs, on every change.

Fails when a string people see is missing a language, isn't reviewed, loses or gains a placeholder,
capitalises the brand, or when the catalog no longer matches the code (stale keys, L("…") keys the
catalog doesn't have). Warns when a short English string grows much longer in another language.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOGS = [ROOT / "Drafft/Resources/Localizable.xcstrings", ROOT / "Drafft/Resources/InfoPlist.xcstrings"]
LANGUAGES = ["en", "fr", "es", "de", "it", "pt", "nl"]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(@|lld|ld|lu|d|u|f|\.\d+f|%)")
WORD = re.compile(r"[A-Za-zÀ-ÿ]{2,}")


def placeholders(text: str) -> list[str]:
    return sorted(m.group(1) for m in PLACEHOLDER.finditer(text) if m.group(1) != "%")


def leaves(unit_holder: dict, path: str = ""):
    """Every string unit of a localization, plural and device variations included."""
    if "stringUnit" in unit_holder:
        yield path, unit_holder["stringUnit"]
    for kind, cases in unit_holder.get("variations", {}).items():
        for case, sub in cases.items():
            yield from leaves(sub, f"{path}{kind}.{case} ")


def check_catalog(path: pathlib.Path, errors: list[str], warnings: list[str]) -> set[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    rel = path.relative_to(ROOT)
    source_language = data.get("sourceLanguage", "en")
    for key, entry in data["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        if entry.get("extractionState") == "stale":
            errors.append(f"{rel}: stale key (no longer in the code, delete it): {key!r}")
            continue
        # Keys without words (\"%@ %@\", \"2×\") need no translation.
        if not WORD.search(PLACEHOLDER.sub("", key)):
            continue
        locs = entry.get("localizations", {})
        source = locs.get(source_language, {}).get("stringUnit", {}).get("value", key)
        for lang in LANGUAGES:
            if lang == source_language and lang not in locs:
                continue
            if lang not in locs:
                errors.append(f"{rel}: missing {lang}: {key!r}")
                continue
            for variant, unit in leaves(locs[lang]):
                where = f"{rel}: {lang} {variant}{key!r}"
                value = unit.get("value", "")
                if unit.get("state") not in ("translated", None) and lang != source_language:
                    errors.append(f"{where}: state is {unit.get('state')!r}, review it")
                if not variant and placeholders(value) != placeholders(source):
                    errors.append(f"{where}: placeholders {placeholders(value)} != source {placeholders(source)}")
                if re.search(r"\b(Drafft|DRAFFT)\b", value):
                    errors.append(f"{where}: the brand is 'drafft', lowercase: {value!r}")
                if "·" in value:
                    errors.append(f"{where}: no '·' separators: {value!r}")
                if lang != source_language and len(source) <= 24 and len(value) > max(2.2 * len(source), len(source) + 16):
                    warnings.append(f"{where}: short English grew to {len(value)} chars: {value!r}")
    return set(data["strings"])


def code_keys() -> set[str]:
    """Literal keys passed to L(\"…\") in the code (interpolated ones are matched by Xcode's extraction)."""
    keys = set()
    for path in (ROOT / "Drafft").rglob("*.swift"):
        for m in re.finditer(r'\bL\("((?:[^"\\]|\\.)*)"\)', path.read_text(encoding="utf-8")):
            if "\\(" not in m.group(1):
                keys.add(m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8"))
    return keys


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    known = set()
    for catalog in CATALOGS:
        known |= check_catalog(catalog, errors, warnings)
    for key in sorted(code_keys() - known):
        errors.append(f"L({key!r}) isn't in Localizable.xcstrings: build once in Xcode, then translate it")
    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    print(f"i18n-lint: {len(errors)} error(s), {len(warnings)} warning(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
