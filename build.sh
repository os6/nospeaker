#!/bin/sh
# Builds nospeaker as one program for Apple Silicon and Intel Macs.
#
#   ./build.sh            build ./nospeaker (signed for this Mac only)
#   ./build.sh release    also sign it with your Developer ID, have Apple notarize it, and make
#                         dist/nospeaker.zip, which runs on any Mac without security warnings
set -eu
umask 077
IFS=$(printf ' \t\nx')
IFS="${IFS%x}"

fail() {
    printf '\n  nospeaker: %s\n\n' "$1" >&2
    exit 1
}

mode="${1:-}"
if [ "$#" -gt 1 ] || { [ -n "$mode" ] && [ "$mode" != "release" ]; }; then
    fail "usage: ./build.sh [release]"
fi

cd -- "$(dirname -- "$0")"

[ "$(uname -s)" = "Darwin" ] || fail "this builds on macOS only (it drives a Mac's trackpad)."

# /usr/bin/swiftc exists even without developer tools (it only offers to install them), so ask xcode-select.
{ xcode-select -p >/dev/null 2>&1 && command -v swiftc >/dev/null 2>&1; } || fail "Swift isn't installed. Install Apple's Command Line Tools:

    xcode-select --install

  then run ./build.sh again."

# Swift 6.0 or newer (strict concurrency complete checking).
ver_line=$(swiftc --version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1.\2/p' | head -n 1)
major="${ver_line%%.*}"
minor="${ver_line#*.}"
case "$major" in ''|*[!0-9]*) major="" ;; esac
case "$minor" in ''|*[!0-9]*) minor="" ;; esac
if [ -z "$major" ] || [ -z "$minor" ] || [ "$major" -lt 6 ]; then
    fail "this needs Swift 6.0 or newer, and found ${major:-?}.${minor:-?}. Update Xcode or the Command Line Tools
  (Software Update, or: xcode-select --install)."
fi

if [ -L build ] || [ -L nospeaker ] || [ -L dist ] || [ -d nospeaker ]; then
    fail "refusing to write through symbolic links or overwrite a directory at ./nospeaker."
fi

mkdir -p -- build
set -- -O -swift-version 6 -strict-concurrency=complete
if [ -n "${SWIFT_MODULE_CACHE_PATH:-}" ]; then
    set -- "$@" -module-cache-path "$SWIFT_MODULE_CACHE_PATH"
fi

echo "building for Apple Silicon…"
swiftc "$@" -target arm64-apple-macos12 nospeaker.swift -o build/nospeaker-arm64 \
    || fail "the Apple Silicon build failed (errors above). Make sure Xcode or the Command Line Tools are up to date."
echo "building for Intel…"
swiftc "$@" -target x86_64-apple-macos13 nospeaker.swift -o build/nospeaker-x86_64 \
    || fail "the Intel build failed (errors above). Make sure Xcode or the Command Line Tools are up to date."

lipo -create build/nospeaker-arm64 build/nospeaker-x86_64 -output build/nospeaker
chmod 0755 build/nospeaker
codesign -s - -f build/nospeaker \
    || fail "local ad-hoc code signing failed."
codesign --verify --strict build/nospeaker \
    || fail "local code signature verification failed."
mv -f -- build/nospeaker nospeaker     # atomic rename, so a copy that's already running isn't disturbed
echo "built ./nospeaker ($(lipo -archs nospeaker)). Run it with: ./nospeaker"

[ "$mode" = "release" ] || exit 0

# Release: Developer ID signature (with the hardened runtime Apple requires), then notarization.
# Select unambiguous 40-hex SHA-1 certificate fingerprint (or explicit CODESIGN_IDENTITY).
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    case "$CODESIGN_IDENTITY" in
        *[!0-9A-Fa-f]*) fail "CODESIGN_IDENTITY must be a 40-character hex SHA-1 certificate hash." ;;
    esac
    [ "${#CODESIGN_IDENTITY}" -eq 40 ] \
        || fail "CODESIGN_IDENTITY must be a 40-character hex SHA-1 certificate hash."
    identity="$CODESIGN_IDENTITY"
else
    hashes=$(security find-identity -v -p codesigning \
        | awk '/"Developer ID Application:/ { print $2 }' \
        | sort -u)
    count=$(printf '%s\n' "$hashes" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        fail "no Developer ID Application certificate in your keychain. Add one in Xcode:
  Settings > Accounts > your team > Manage Certificates > + > Developer ID Application,
  then run ./build.sh release again."
    elif [ "$count" -gt 1 ]; then
        fail "multiple Developer ID Application certificates found in keychain; set CODESIGN_IDENTITY=<40-hex SHA-1>
  from 'security find-identity -v -p codesigning' and run ./build.sh release again."
    fi
    identity="$hashes"
fi

profile="${NOTARY_PROFILE:-nospeaker}"
case "$profile" in
    ''|*[!A-Za-z0-9._-]*|-*) fail "NOTARY_PROFILE must contain only letters, digits, '.', '_', or '-'." ;;
esac

xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 || fail "no saved notary sign-in called \"$profile\". Save one once (it asks for an app-specific password,
  made at account.apple.com > Sign-In and Security > App-Specific Passwords):

    xcrun notarytool store-credentials $profile --apple-id <your Apple ID> --team-id <your team ID>

  then run ./build.sh release again."

echo "signing with Developer ID ($identity)…"
codesign --force --options runtime --timestamp --sign "$identity" nospeaker
codesign --verify --strict nospeaker

# Stage archive inside build/ and promote to dist/nospeaker.zip strictly after notarization passes.
rm -f -- dist/nospeaker.zip dist/nospeaker.zip.sha256 build/nospeaker-staging.zip
ditto -c -k --norsrc --noextattr nospeaker build/nospeaker-staging.zip

echo "sending to Apple for notarization (usually a minute or two)…"
if ! xcrun notarytool submit build/nospeaker-staging.zip --keychain-profile "$profile" --wait; then
    rm -f -- build/nospeaker-staging.zip
    fail "notarization didn't pass. See why with: xcrun notarytool log <submission id> --keychain-profile $profile"
fi

if ! codesign --verify --strict -R="notarized" --check-notarization nospeaker; then
    rm -f -- build/nospeaker-staging.zip
    fail "Apple accepted it, but macOS can't confirm the notarization yet. Try again in a minute."
fi

mkdir -p -- dist
mv -f -- build/nospeaker-staging.zip dist/nospeaker.zip
shasum -a 256 dist/nospeaker.zip > dist/nospeaker.zip.sha256
chmod 0644 dist/nospeaker.zip dist/nospeaker.zip.sha256
echo "released: dist/nospeaker.zip (+ .sha256), signed and notarized. Attach them to the GitHub release."
