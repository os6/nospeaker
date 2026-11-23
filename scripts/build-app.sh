#!/bin/sh
# Build the macOS SwiftUI app with the original CLI motor embedded.
set -eu
cd "$(dirname "$0")/.."

./build.sh
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --spec project.yml >/dev/null
fi
if [ ! -d NoSpeaker.xcodeproj ]; then
    echo "Missing NoSpeaker.xcodeproj (install XcodeGen to regenerate it)." >&2
    exit 1
fi

xcodebuild -project NoSpeaker.xcodeproj -scheme NoSpeaker \
    -configuration Release -derivedDataPath build/MacApp \
    -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO \
    build > build/macapp-build.log 2>&1 || {
        grep -A5 'error:' build/macapp-build.log >&2 || true
        tail -22 build/macapp-build.log >&2
        exit 1
    }

app="build/MacApp/Build/Products/Release/NoSpeaker.app"
test -x "$app/Contents/Resources/nospeaker"
codesign --force --sign - "$app/Contents/Resources/nospeaker"
codesign --force --deep --sign - "$app"
codesign --verify --strict --deep "$app"
echo "Built: $app"
