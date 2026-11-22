# Contributing

Keep pull requests focused on one behavior. State what changed, why it changed,
and how you verified it. Avoid unrelated cosmetic changes in feature PRs.

## Source layout

- Sources/NoSpeaker/main.swift: command-line arguments and executable entry point
- Speech/: language selection, macOS speech rendering and signal analysis
- Haptics/: trackpad actuator and touch input
- Audio/: tones, melody, rhythm and audio output state
- Interface/: terminal input, UI state, rendering and screen views
- Show/: sequencing the interactive demonstration
- Core/: shared run-loop state and timing

Keep files focused and typically below 200 lines. Split by responsibility
rather than adding arbitrary extra layers solely to meet a line limit.

## Naming and behavior

Follow the Swift API Design Guidelines at:
https://www.swift.org/documentation/api-design-guidelines/

Prefer names that describe intent at the call site. Conventional audio and
signal-processing terminology (F0, F1, F2, Hz) is acceptable where standard.
Do not duplicate language-dependent strings outside SpeechLanguage.swift.

English must remain the default and use the original system voice, with Hungarian
opt-in through --lang hu using Tünde.
Do not change the trackpad actuation limits or increase motor output in a
localization PR.

## Verification

Run ./build.sh and ./scripts/test.sh before submitting.
Use --preview or --preview-wav to compare motor-command audio on speakers,
without actuating hardware. A speaker preview does not model the real motor
and should not be described as acoustically identical to the trackpad.
Only after validating preview recordings should a brief manual trackpad
listening check be considered; never automate repeated hardware actuation.
