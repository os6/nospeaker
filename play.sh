#!/bin/sh
# Downloads the latest nospeaker release, verifies its Apple Developer ID
# signature and notarization, and plays it.
#
# It installs one file, ~/.local/bin/nospeaker. Delete that file to uninstall.
# Optional environment variables for supply-chain pinning:
#   NOSPEAKER_VERSION         release tag (e.g. v1.0)
#   NOSPEAKER_SHA256          expected 64-hex SHA-256 of nospeaker.zip
#   NOSPEAKER_REQUIRE_SHA256  set to 1 to require SHA-256 verification
#   NOSPEAKER_TEAM_ID         expected 10-character Apple Developer Team ID
set -eu
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
IFS=$(printf ' \t\nx')
IFS="${IFS%x}"

fail() {
    printf '\n  nospeaker: %s\n\n' "$1" >&2
    exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "this runs on macOS only (it plays through a Mac's trackpad)."

[ -n "${HOME:-}" ] || fail "HOME is not set."
case "$HOME" in
    /*) ;;
    *) fail "HOME must be an absolute path." ;;
esac
[ -d "$HOME" ] && [ ! -L "$HOME" ] || fail "HOME is not a regular directory."

if [ -n "${NOSPEAKER_VERSION:-}" ]; then
    case "$NOSPEAKER_VERSION" in
        *[!A-Za-z0-9._-]*|-*) fail "invalid NOSPEAKER_VERSION format." ;;
    esac
    url="https://github.com/os6/nospeaker/releases/download/${NOSPEAKER_VERSION}/nospeaker.zip"
else
    url="https://github.com/os6/nospeaker/releases/latest/download/nospeaker.zip"
fi

tmp=$(mktemp -d /tmp/nospeaker.XXXXXXXX) \
    || fail "couldn't create a private temporary directory."
[ -n "$tmp" ] && [ -d "$tmp" ] && [ ! -L "$tmp" ] \
    || fail "temporary path is not a regular directory."
chmod 0700 -- "$tmp"
trap 'rm -rf -- "$tmp"' EXIT INT TERM HUP

echo "downloading nospeaker…"
curl --proto '=https' --tlsv1.2 --max-redirs 5 -fsSL --connect-timeout 10 --max-time 60 --max-filesize 20971520 \
    -- "$url" -o "$tmp/nospeaker.zip" \
    || fail "the download failed. Check your connection, or get it from github.com/os6/nospeaker/releases"

# Verify SHA-256 digest when pinned via NOSPEAKER_SHA256 or published alongside the release.
expected_sha=""
if [ -n "${NOSPEAKER_SHA256:-}" ]; then
    expected_sha=$(printf '%s' "$NOSPEAKER_SHA256" | tr 'A-F' 'a-f')
elif curl --proto '=https' --tlsv1.2 --max-redirs 5 -fsSL --connect-timeout 10 --max-time 30 --max-filesize 4096 \
    -- "${url}.sha256" -o "$tmp/nospeaker.zip.sha256" 2>/dev/null; then
    expected_sha=$(awk 'NR==1 {print $1}' "$tmp/nospeaker.zip.sha256" | tr 'A-F' 'a-f')
    [ -n "$expected_sha" ] \
        || fail "downloaded nospeaker.zip.sha256 is empty or malformed; refusing to install."
fi

if [ "${NOSPEAKER_REQUIRE_SHA256:-0}" = "1" ] && [ -z "$expected_sha" ]; then
    fail "SHA-256 verification required (NOSPEAKER_REQUIRE_SHA256=1), but no digest was provided."
fi

if [ -n "$expected_sha" ]; then
    case "$expected_sha" in
        *[!0-9a-f]*) fail "expected SHA-256 digest contains invalid characters." ;;
    esac
    [ "${#expected_sha}" -eq 64 ] || fail "expected SHA-256 digest must be 64 hex characters."
    actual_sha=$(shasum -a 256 -- "$tmp/nospeaker.zip" | awk '{print tolower($1)}')
    [ "$actual_sha" = "$expected_sha" ] \
        || fail "SHA-256 checksum mismatch for nospeaker.zip; refusing to install."
fi

# Inspect archive entries before extraction to prevent path traversal, multi-file injection, or symlinks.
entries=$(cd -- "$tmp" && zipinfo -1 -- nospeaker.zip 2>/dev/null) \
    || fail "the downloaded archive is unreadable or corrupt."
[ "$entries" = "nospeaker" ] \
    || fail "refusing archive with unexpected file entries."
entry_meta=$(cd -- "$tmp" && zipinfo -l -- nospeaker.zip 2>/dev/null | sed -n '3p')
case "$entry_meta" in
    -*) ;;
    *) fail "refusing archive containing non-regular file entry." ;;
esac

mkdir -m 0700 -- "$tmp/extract"
ditto -x -k -- "$tmp/nospeaker.zip" "$tmp/extract" \
    || fail "couldn't unpack nospeaker.zip."
bin="$tmp/extract/nospeaker"
[ -f "$bin" ] && [ ! -L "$bin" ] \
    || fail "unpacked binary is missing or is a symbolic link."

# Stamp quarantine metadata and enforce Developer ID + Apple notarization + Gatekeeper checks before install.
qhex=$(printf '%08x' "$(date +%s)")
xattr -w com.apple.quarantine "0083;${qhex};curl;" "$bin" 2>/dev/null || true

req='anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and notarized'
if [ -n "${NOSPEAKER_TEAM_ID:-}" ]; then
    case "$NOSPEAKER_TEAM_ID" in
        *[!A-Z0-9]*|'') fail "NOSPEAKER_TEAM_ID must contain only uppercase ASCII letters and digits." ;;
    esac
    [ "${#NOSPEAKER_TEAM_ID}" -eq 10 ] || fail "NOSPEAKER_TEAM_ID must be a 10-character Apple Team ID."
    req="${req} and certificate leaf[subject.OU] = \"${NOSPEAKER_TEAM_ID}\""
fi

codesign --verify --deep --strict --check-notarization -R="$req" -- "$bin" \
    || fail "Developer ID signature or Apple notarization check failed; refusing to install."
spctl --assess --type execute --context context:primary-signature -- "$bin" >/dev/null 2>&1 \
    || fail "macOS Gatekeeper rejected the downloaded binary; refusing to install."

local_dir="$HOME/.local"
dest="$local_dir/bin"
if [ -L "$local_dir" ] || [ -L "$dest" ]; then
    fail "refusing to install through a symbolic link in ~/.local/bin."
fi
mkdir -p -- "$dest"
[ -d "$dest" ] && [ ! -L "$dest" ] || fail "~/.local/bin is not a regular directory."
if [ -L "$dest/nospeaker" ] || [ -d "$dest/nospeaker" ]; then
    fail "refusing to overwrite symbolic link or directory at ~/.local/bin/nospeaker."
fi

staged="$dest/.nospeaker.tmp.$$"
rm -f -- "$staged"
install -m 0755 -- "$bin" "$staged"
mv -f -- "$staged" "$dest/nospeaker"

rm -rf -- "$tmp"
trap - EXIT INT TERM HUP
echo "installed ~/.local/bin/nospeaker"

# Piped into sh, stdin is the script itself, so rebind /dev/tty only when stdin is not already a TTY.
if [ -t 0 ]; then
    exec "$dest/nospeaker" "$@"
elif [ -r /dev/tty ] && { true </dev/tty; } 2>/dev/null; then
    exec "$dest/nospeaker" "$@" </dev/tty
else
    exec "$dest/nospeaker" "$@" </dev/null
fi
