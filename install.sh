#!/bin/sh
set -e
cd "$(dirname "$0")"

echo "=== Installing NoSpeaker ==="

# Build CLI if needed
if [ ! -f "nospeaker" ]; then
    echo "Building nospeaker CLI..."
    ./build.sh
fi

# Build App if needed
if [ ! -d "NoSpeaker.app" ]; then
    echo "Building NoSpeaker.app..."
    ./build-app.sh
fi

# 1. Install CLI to ~/.local/bin
DEST="$HOME/.local/bin"
mkdir -p "$DEST"
cp -f nospeaker "$DEST/nospeaker"
chmod +x "$DEST/nospeaker"
echo "✓ Installed CLI: $DEST/nospeaker"

# 2. Install App to ~/Applications
APP_DEST="$HOME/Applications"
mkdir -p "$APP_DEST"
rm -rf "$APP_DEST/NoSpeaker.app"
cp -R NoSpeaker.app "$APP_DEST/NoSpeaker.app"
echo "✓ Installed GUI App: $APP_DEST/NoSpeaker.app"

# Check PATH
if ! echo "$PATH" | grep -q "$DEST"; then
    echo ""
    echo "Tip: $DEST is not currently in your PATH."
    echo "Add this line to your ~/.zshrc to run 'nospeaker' from any terminal:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "=== All Set! ==="
echo "  • Open GUI:  open ~/Applications/NoSpeaker.app  (or ./launch-gui.sh)"
echo "  • Run CLI:   nospeaker --help"
