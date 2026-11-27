#!/bin/sh
set -e

cd "$(dirname "$0")"

echo "=== Building NoSpeaker.app ==="

# Build Apple Silicon binary
mkdir -p build
echo "Compiling for Apple Silicon (arm64)..."
swiftc -O -target arm64-apple-macos14 -framework SwiftUI -framework AppKit NoSpeakerCore.swift NoSpeakerGUI.swift -o build/NoSpeaker-arm64

# Try Intel build
echo "Compiling for Intel (x86_64)..."
if swiftc -O -target x86_64-apple-macos14 -framework SwiftUI -framework AppKit NoSpeakerCore.swift NoSpeakerGUI.swift -o build/NoSpeaker-x86_64 2>/dev/null; then
    echo "Creating universal binary (arm64 + x86_64)..."
    lipo -create build/NoSpeaker-arm64 build/NoSpeaker-x86_64 -output build/NoSpeaker
else
    echo "Intel build skipped (using arm64 binary)..."
    cp -f build/NoSpeaker-arm64 build/NoSpeaker
fi

# Assemble .app bundle structure
APP_DIR="NoSpeaker.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp -f build/NoSpeaker "$APP_DIR/Contents/MacOS/NoSpeaker"
chmod +x "$APP_DIR/Contents/MacOS/NoSpeaker"

# Copy Icon
if [ -f "AppIcon.icns" ]; then
    cp -f "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NoSpeaker</string>
    <key>CFBundleIdentifier</key>
    <string>com.a90.nospeaker.gui</string>
    <key>CFBundleName</key>
    <string>NoSpeaker</string>
    <key>CFBundleDisplayName</key>
    <string>NoSpeaker</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Code sign with ad-hoc signature
echo "Code signing NoSpeaker.app..."
codesign --force --deep --sign - "$APP_DIR"

echo "=== Successfully built $APP_DIR ==="
echo "You can launch it with: open NoSpeaker.app"
