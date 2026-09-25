#!/usr/bin/env python3
"""Design rules drafft's code must keep (DESIGN.md, PRODUCT.md), checked on every change.

A line may opt out of one rule with a reason, on that line or the line above:
    // design-lint: allow <rule> - <why>

Exit 1 on any violation. No dependency beyond Python 3.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = ROOT / "Drafft"
# Tokens and primitives are where raw values are allowed to live.
DESIGN_SYSTEM = SOURCES / "DesignSystem"

RULES = {
    "middle-dot": (
        re.compile(r"·"),
        "No '·' separators: use layout (spacing, stacks) or words.",
    ),
    "gradient": (
        re.compile(r"\b(Linear|Radial|Angular|Elliptical|Mesh)Gradient\b"),
        "Solid fills only. Gradients are for photo scrims and blur masks: annotate them.",
    ),
    "truncation": (
        re.compile(r"\.truncationMode\(|\+\s*\"(…|\.\.\.)\""),
        "No '…' on UI copy: wrap, reflow (AdaptiveRow/ViewThatFits), then scale.",
    ),
    "brand-case": (
        re.compile(r"\"[^\"\n]*\b(Drafft|DRAFFT)\b[^\"\n]*\""),
        "The brand is 'drafft', lowercase, in every string people see.",
    ),
    "raw-color": (
        re.compile(r"\b(Color|UIColor)\((red|white|hue|displayP3Red):|Color\(hex|#colorLiteral"),
        "Colors come from DS.Palette, not raw values.",
    ),
    "debug-output": (
        re.compile(r"(?<![\w.])(print|debugPrint|dump|NSLog)\("),
        "No console output in shipped code: use Logger if it must stay.",
    ),
    "secret": (
        re.compile(r"sb_secret_[A-Za-z0-9]|service_role\s*=|-----BEGIN [A-Z ]*PRIVATE KEY"),
        "Never a secret in the app: only public (publishable) keys.",
    ),
}
# Rules that don't apply inside the design system itself.
DESIGN_SYSTEM_EXEMPT = {"gradient", "raw-color"}

ALLOW = re.compile(r"design-lint:\s*allow\s+([\w-]+)")
SHEET = re.compile(r"\.sheet\(")


def code_part(line: str) -> str:
    """The line without its // comment (string contents containing // are rare enough here)."""
    stripped = line.lstrip()
    if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
        return ""
    return re.sub(r"(?<!:)//.*$", "", line)


def allowed(lines: list[str], i: int, rule: str) -> bool:
    for j in (i, i - 1):
        if j >= 0:
            m = ALLOW.search(lines[j])
            if m and m.group(1) == rule:
                return True
    return False


def sheet_body(lines: list[str], start: int) -> str:
    """The text of a `.sheet(...) { ... }` presentation, braces balanced from its line."""
    depth, seen, out = 0, False, []
    for line in lines[start:start + 60]:
        out.append(line)
        for ch in line:
            if ch == "{":
                depth, seen = depth + 1, True
            elif ch == "}":
                depth -= 1
        if seen and depth <= 0:
            break
    return "\n".join(out)


def main() -> int:
    problems: list[str] = []
    for path in sorted(SOURCES.rglob("*.swift")):
        rel = path.relative_to(ROOT)
        in_ds = DESIGN_SYSTEM in path.parents
        lines = path.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            code = code_part(line)
            if not code:
                continue
            for rule, (pattern, why) in RULES.items():
                if in_ds and rule in DESIGN_SYSTEM_EXEMPT:
                    continue
                if pattern.search(code) and not allowed(lines, i, rule):
                    problems.append(f"{rel}:{i + 1}: [{rule}] {why}\n    {line.strip()}")
            # Every sheet sits on its own surface, never the page colour.
            if SHEET.search(code) and not allowed(lines, i, "sheet-surface"):
                body = sheet_body(lines, i)
                if ".sheetSurface()" not in body and "presentationBackground" not in body:
                    problems.append(
                        f"{rel}:{i + 1}: [sheet-surface] Sheets never share the page colour: "
                        f"add .sheetSurface() to the presented view.\n    {line.strip()}"
                    )

    # Strings people see that live outside Swift: the app's display name and permission prompts.
    for i, line in enumerate((ROOT / "project.yml").read_text(encoding="utf-8").splitlines()):
        if re.search(r"(Description|DisplayName)\s*:", line) and re.search(r"\b(Drafft|DRAFFT)\b", line):
            problems.append(f"project.yml:{i + 1}: [brand-case] The brand is 'drafft', lowercase.\n    {line.strip()}")

    for p in problems:
        print(p)
    print(f"design-lint: {len(problems)} problem(s)." if problems else "design-lint: clean.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
