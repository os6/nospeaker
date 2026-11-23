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

# Use the same native control families as macOS Calendar and the toolbar.
# Keep one selected bezel, not a custom stacked Glass capsule.
language_menu = (root / "MacApp/Sources/SpeechLanguageMenu.swift").read_text()
output_selector = (root / "MacApp/Sources/NativeOutputSelector.swift").read_text()
delegate = (root / "MacApp/Sources/NoSpeakerAppDelegate.swift").read_text()
play_button = (root / "MacApp/Sources/AdaptivePlaybackButton.swift").read_text()
elastic_feedback = (root / "MacApp/Sources/ElasticGlassFeedback.swift").read_text()

assert "NSSegmentedControl(" in output_selector
assert ".segmentStyle = .automatic" in output_selector
assert "control.selectedSegmentBezelColor" in output_selector
assert "NSGlassEffectView" not in output_selector
assert "DragGesture" not in output_selector
assert "Menu {" in language_menu
assert ".menuStyle(.button)" in language_menu
assert ".buttonStyle(.glass)" in language_menu
assert "glassEffect(" not in language_menu
assert ".modifier(ElasticGlassFeedback(isEnabled: isEnabled))" in play_button
assert ".highPriorityGesture(" in elastic_feedback
assert ".accessibilityReduceMotion" in elastic_feedback
assert "applicationShouldTerminateAfterLastWindowClosed" in delegate
assert "playback?.stop()" in delegate

print(f"PASS: {len(catalog['strings'])} localized keys, en/hu translations")
print(f"PASS: {len(sources)} SwiftUI source files, all at most 200 lines")
print("PASS: native macOS segmented control and menu, close-to-quit")
