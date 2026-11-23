#!/usr/bin/env python3
"""Validate native GUI translations and maintainable SwiftUI module sizes."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = json.loads(
    (root / "MacApp/Resources/Localizable.xcstrings").read_text(encoding="utf-8")
)
assert catalog["sourceLanguage"] == "en", "English source locale changed"
assert catalog["strings"], "Localizable catalog is empty"
for key, content in catalog["strings"].items():
    for locale in ("en", "hu"):
        translation = content["localizations"].get(locale)
        assert translation is not None, (locale, key)
        assert translation["stringUnit"]["value"], (locale, key)
        assert translation["stringUnit"]["state"] == "translated", (locale, key)

sources = sorted((root / "MacApp/Sources").glob("*.swift"))
assert sources, "No native UI code found"
for source in sources:
    count = len(source.read_text(encoding="utf-8").splitlines())
    assert count <= 200, f"{source}: {count} lines, max 200"

print(f"PASS: {len(catalog['strings'])} localized keys, en/hu translations")
print(f"PASS: {len(sources)} SwiftUI source files, all at most 200 lines")
