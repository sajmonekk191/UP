#!/usr/bin/env python3
"""Validates Translations/<lang>.json and writes Sources/UP/Translations/L10n+<lang>.swift."""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
spec = re.compile(r'%(?:\.\d+)?[@dfs%]')
keys = json.loads((root / "Translations/keys.json").read_text())
ok = True

def swift(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'

for path in sorted((root / "Translations").glob("*.json")):
    lang = path.stem
    if lang == "keys":
        continue
    table = json.loads(path.read_text())
    missing = [k for k in keys if k not in table]
    bad = [k for k in keys if k in table and spec.findall(k) != spec.findall(table[k])]
    if missing or bad:
        ok = False
        print(f"{lang}: {len(missing)} missing, {len(bad)} format mismatches", *bad[:5], sep="\n  ")
    lines = [f"    {swift(k)}: {swift(table[k])}," for k in keys if k in table and k not in bad]
    out = f"extension Localizer {{\n    static let {lang}: [String: String] = [\n" + "\n".join(lines) + "\n    ]\n}\n"
    (root / f"Sources/UP/Translations/L10n+{lang}.swift").write_text(out)
    print(f"{lang}: {len(lines)} strings")

sys.exit(0 if ok else 1)
