#!/usr/bin/env python3
"""Lists tr() strings and item advice missing from Translations/keys.json; --prune drops keys the code no longer uses."""
import json, re, sys, pathlib

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
used = set(found)
missing = [k for k in dict.fromkeys(found) if k not in keys]
print(json.dumps(missing, ensure_ascii=False, indent=1))

if "--prune" in sys.argv:
    unused = [k for k in keys if k not in used]
    kept = [k for k in keys if k in used]
    (root / "Translations/keys.json").write_text(json.dumps(kept, ensure_ascii=False, indent=0))
    for path in sorted((root / "Translations").glob("*.json")):
        if path.stem == "keys":
            continue
        table = json.loads(path.read_text())
        path.write_text(json.dumps({k: v for k, v in table.items() if k in used}, ensure_ascii=False, indent=1, sort_keys=True))
    print(f"pruned {len(unused)} unused keys")
