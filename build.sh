#!/bin/sh
# Builds nospeaker as one program for Apple Silicon and Intel Macs.
#
#   ./build.sh            build ./nospeaker (signed for this Mac only)
#   ./build.sh release    also sign it with your Developer ID, have Apple notarize it, and make
#                         dist/nospeaker.zip, which runs on any Mac without security warnings
set -e
mode="$1"
cd "$(dirname "$0")"

fail() {
    printf '\n  nospeaker: %s\n\n' "$1" >&2
    exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "this builds on macOS only (it drives a Mac's trackpad)."

# /usr/bin/swiftc exists even without developer tools (it only offers to install them), so ask xcode-select.
{ xcode-select -p >/dev/null 2>&1 && command -v swiftc >/dev/null 2>&1; } || fail "Swift isn't installed. Install Apple's Command Line Tools:

    xcode-select --install

  then run ./build.sh again."

# Swift 5.7 or newer (Xcode 14 or later).
version=$(swiftc --version 2>/dev/null | sed -n 's/.*Swift version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')
set -- $version
if [ -z "$1" ] || [ "$1" -lt 5 ] || { [ "$1" -eq 5 ] && [ "$2" -lt 7 ]; }; then
    fail "this needs Swift 5.7 or newer, and found ${1:-?}.${2:-?}. Update Xcode or the Command Line Tools
  (Software Update, or: xcode-select --install)."
fi

mkdir -p build
echo "building for Apple Silicon…"
swiftc -O -target arm64-apple-macos12 nospeaker.swift -o build/nospeaker-arm64 \
    || fail "the Apple Silicon build failed (errors above). Make sure Xcode or the Command Line Tools are up to date."
echo "building for Intel…"
swiftc -O -target x86_64-apple-macos13 nospeaker.swift -o build/nospeaker-x86_64 \
    || fail "the Intel build failed (errors above). Make sure Xcode or the Command Line Tools are up to date."

lipo -create build/nospeaker-arm64 build/nospeaker-x86_64 -output build/nospeaker
codesign -s - -f build/nospeaker 2>/dev/null
mv -f build/nospeaker nospeaker     # a rename, so a copy that's already running isn't disturbed
echo "built ./nospeaker ($(lipo -archs nospeaker)). Run it with: ./nospeaker"

# sparkle: the show's closing sound alone, a tiny program for "done" sounds (see sparkle.swift).
swiftc -O -target arm64-apple-macos12 sparkle.swift -o build/sparkle-arm64 \
    && swiftc -O -target x86_64-apple-macos13 sparkle.swift -o build/sparkle-x86_64 \
    && lipo -create build/sparkle-arm64 build/sparkle-x86_64 -output build/sparkle \
    && codesign -s - -f build/sparkle 2>/dev/null && mv -f build/sparkle sparkle \
    && echo "built ./sparkle too. Try: ./sparkle 50"

[ "$mode" = "release" ] || exit 0

# Release: Developer ID signature (with the hardened runtime Apple requires), then notarization.
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)
[ -n "$identity" ] || fail "no Developer ID Application certificate in your keychain. Add one in Xcode:
  Settings > Accounts > your team > Manage Certificates > + > Developer ID Application,
  then run ./build.sh release again."

profile="${NOTARY_PROFILE:-nospeaker}"
xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 || fail "no saved notary sign-in called \"$profile\". Save one once (it asks for an app-specific password,
  made at account.apple.com > Sign-In and Security > App-Specific Passwords):

    xcrun notarytool store-credentials $profile --apple-id <your Apple ID> --team-id <your team ID>

  then run ./build.sh release again."

echo "signing with $identity…"
codesign --force --options runtime --timestamp --sign "$identity" nospeaker
codesign --verify --strict nospeaker

mkdir -p dist
rm -f dist/nospeaker.zip
ditto -c -k --norsrc --noextattr nospeaker dist/nospeaker.zip    # the program alone, at the top of the zip

echo "sending to Apple for notarization (usually a minute or two)…"
xcrun notarytool submit dist/nospeaker.zip --keychain-profile "$profile" --wait \
    || fail "notarization didn't pass. See why with: xcrun notarytool log <submission id> --keychain-profile $profile"

codesign --verify --strict -R="notarized" --check-notarization nospeaker \
    || fail "Apple accepted it, but macOS can't confirm the notarization yet. Try again in a minute."
echo "released: dist/nospeaker.zip, signed and notarized. Attach it to the GitHub release."
