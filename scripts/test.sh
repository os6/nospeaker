#!/bin/sh
# Runs source-level checks and non-haptic CLI validation.
set -eu
cd "$(dirname "$0")/.."

binary=$(mktemp -t nospeaker-language-tests)
trap 'rm -f "$binary"' EXIT

swiftc Sources/NoSpeaker/Speech/SpeechLanguage.swift Tests/Language/main.swift -o "$binary"
"$binary"

./nospeaker --help | grep -q 'speak English (default)'
./nospeaker --help | grep -q -- '--lang hu'
set +e
./nospeaker --lang invalid >/dev/null 2>&1
invalid_language_status=$?
./nospeaker --voice nospeaker_nonexistent_test_voice >/dev/null 2>&1
invalid_voice_status=$?
set -e
if [ "$invalid_language_status" -ne 64 ] || [ "$invalid_voice_status" -ne 64 ]; then
    echo 'FAIL: invalid language or voice did not return exit code 64' >&2
    exit 1
fi
echo 'PASS: CLI help and unsupported-option handling (without actuating the motor)'

oversized=$(find Sources/NoSpeaker -name '*.swift' -print |
    while IFS= read -r file; do
        lines=$(wc -l < "$file" | tr -d ' ')
        [ "$lines" -le 200 ] || printf '%s: %s lines\n' "$file" "$lines"
    done)
if [ -n "$oversized" ]; then
    printf 'FAIL: source files exceeding 200 lines:\n%s\n' "$oversized" >&2
    exit 1
fi
echo 'PASS: all Swift source files are at most 200 lines'
