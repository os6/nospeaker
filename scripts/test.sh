#!/bin/sh
# Runs source-level checks and non-haptic CLI validation.
set -eu
cd "$(dirname "$0")/.."

binary=$(mktemp -t nospeaker-language-tests)
trap 'rm -f "$binary"' EXIT

swiftc Sources/NoSpeaker/Speech/SpeechLanguage.swift Tests/Language/main.swift -o "$binary"
"$binary"

swiftc Sources/NoSpeaker/Core/SpeechActuationLimits.swift \
    Tests/SpeechActuationLimits/main.swift -o "$binary"
"$binary"

swiftc Sources/NoSpeaker/Speech/SpeechVoiceResolution.swift \
    Tests/SpeechVoiceResolution/main.swift -o "$binary"
"$binary"

swiftc Sources/NoSpeaker/Speech/HungarianPhonology.swift Tests/Phonology/main.swift -o "$binary"
"$binary"

swiftc Sources/NoSpeaker/Core/SpeechActuationLimits.swift \
    Sources/NoSpeaker/Speech/LinearPrediction.swift \
    Sources/NoSpeaker/Speech/SpeechAnalysis.swift \
    Tests/SpeechAnalysis/main.swift -o "$binary"
"$binary"

swiftc Sources/NoSpeaker/Speech/SpeechLanguage.swift \
    Sources/NoSpeaker/Speech/SpeechEncodingProfile.swift \
    Sources/NoSpeaker/Core/SpeechActuationLimits.swift \
    Sources/NoSpeaker/Speech/LinearPrediction.swift \
    Sources/NoSpeaker/Speech/SpeechAnalysis.swift \
    Sources/NoSpeaker/Audio/SpeechActuations.swift \
    Tests/SpeechActuations/main.swift -o "$binary"
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

# The preview branch generates WAV files without opening the trackpad motor.
preview_directory=$(mktemp -d -t nospeaker-preview-tests)
trap 'rm -f "$binary"; rm -rf "$preview_directory"' EXIT
./nospeaker --lang hu --preview-wav "$preview_directory/hungarian.wav" "Hogy vagy?" >/dev/null
./nospeaker --preview-wav "$preview_directory/english.wav" "How are you?" >/dev/null
test -s "$preview_directory/hungarian.wav"
test -s "$preview_directory/english.wav"

# The Tünde source must distinguish Hungarian gy /ɟ/ from written gi.
# Preview consonants contain random noise-like carriers, so comparing
# their WAV bytes would not be a valid phoneme regression by itself.
# The voice resolver unit test above checks the application selects
# this exact ASCII identifier, which avoids the Unicode fallback.
if /usr/bin/say -v '?' | grep -q '^Tünde '; then
    /usr/bin/say -v com.apple.voice.compact.hu-HU.Mariska \
        -o "$preview_directory/gyar.wav" --file-format=WAVE \
        --data-format=LEF32@16000 "gyár"
    /usr/bin/say -v com.apple.voice.compact.hu-HU.Mariska \
        -o "$preview_directory/giar.wav" --file-format=WAVE \
        --data-format=LEF32@16000 "giár"
    if cmp -s "$preview_directory/gyar.wav" "$preview_directory/giar.wav"; then
        echo 'FAIL: Tünde source collapsed Hungarian gy into g+i' >&2
        exit 1
    fi
    echo 'PASS: ASCII Tünde voice source preserves Hungarian gy versus g+i'
fi

afinfo "$preview_directory/hungarian.wav" | grep -q '16000 Hz'
afinfo "$preview_directory/english.wav" | grep -q '16000 Hz'
echo 'PASS: English and Hungarian speaker WAVs rendered without motor activation'


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
