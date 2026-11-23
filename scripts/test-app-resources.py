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

# Both controls must use actual Apple Glass APIs while retaining a
# macOS 13–25 fallback; otherwise a style regression can look correct on CI.
language_menu = (root / "MacApp/Sources/SpeechLanguageMenu.swift").read_text()
output_selector = (root / "MacApp/Sources/GlassOutputSelector.swift").read_text()
assert "if #available(macOS 26.0, *)" in language_menu
assert ".buttonStyle(.glass)" in language_menu
assert ".menuStyle(.button)" in language_menu
assert "if #available(macOS 26.0, *)" in output_selector
assert "GlassEffectContainer" in output_selector
assert ".glassEffect(" in output_selector
assert ".matchedGeometryEffect(" in output_selector
assert ".pickerStyle(.segmented)" in output_selector

print(f"PASS: {len(catalog['strings'])} localized keys, en/hu translations")
print(f"PASS: {len(sources)} SwiftUI source files, all at most 200 lines")
print("PASS: native Glass menus and output selector, older macOS fallbacks")
