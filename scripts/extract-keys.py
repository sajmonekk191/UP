#!/usr/bin/env python3
"""Lists tr() strings and item advice missing from Translations/keys.json."""
import json, re, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
keys = json.loads((root / "Translations/keys.json").read_text())
found = []
for path in sorted((root / "Sources/UP").rglob("*.swift")):
    if "Translations" in path.parts:
        continue
    text = path.read_text()
    found += re.findall(r'\btr\(\s*"((?:[^"\\]|\\.)*)"', text)
    if "static let counterItems" in text:
        block = text[text.index("static let counterItems"):]
        block = block[:block.index("\n    ]")]
        found += re.findall(r'\d+:\s*"((?:[^"\\]|\\.)*)"', block)
missing = [k for k in dict.fromkeys(found) if k not in keys]
print(json.dumps(missing, ensure_ascii=False, indent=1))
