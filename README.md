```text
────────────────────────  a90.com presents  ─────────────────────────

    _   __ ____      _____  ____   ______ ___     __ __  ______ ____
   / | / // __ \    / ___/ / __ \ / ____//   |   / //_/ / ____// __ \
  /  |/ // / / /    \__ \ / /_/ // __/  / /| |  / ,<   / __/  / /_/ /
 / /|  // /_/ /    ___/ // ____// /___ / ___ | / /| | / /___ / _, _/
/_/ |_/ \____/    /____//_/    /_____//_/  |_|/_/ |_|/_____//_/ |_|

─  haptic voice synthesis  ─────────────────────────────  trackpad  ─
```

**Mute your Mac. Your trackpad will still talk.**

There's no speaker in a MacBook trackpad, just a small haptic motor that taps the glass so you feel a click.
NO SPEAKER drives that motor up to 4,000 times a second, fast enough to make sound you can hear, and turns it
into a voice. It talks, sings, raps, and becomes an instrument under your finger.

One command. About a minute and a half. No speakers used.

<!-- demo video: drag an .mp4 here in GitHub's editor -->

## 01 / before you start

```text
[ mute your mac ]        it still talks; that's the point
[ put it on a table ]    on your lap it's much quieter
[ hands off the glass ]  until it asks you to touch it
```

**Space** skips a part. **q** or **Ctrl-C** goes to the end.

## 02 / run it

`[ one line ]`

```sh
curl -fsSL a90.com/nospeaker | sh
```

Downloads the latest release to `~/.local/bin/nospeaker` and starts the show. `a90.com/nospeaker` points
to [play.sh](play.sh) in this repo, so you can read what it runs first.

`[ download ]`

Grab `nospeaker.zip` from the [latest release](https://github.com/os6/nospeaker/releases/latest),
unzip it and run `./nospeaker` in Terminal. Signed with a Developer ID and notarized by Apple.

`[ from source ]`

Needs Xcode or the Command Line Tools (`xcode-select --install`). Builds one program for Apple Silicon
and Intel Macs.

```sh
git clone https://github.com/os6/nospeaker
cd nospeaker
./build.sh
./nospeaker
```

## Native macOS app

NoSpeaker includes a SwiftUI macOS app with a text editor, Hungarian/English
speech selection, trackpad/speaker output selection, play/stop controls and
highlighted words during playback. The existing NoSpeaker audio engine is reused
without changes to its speech coding. Word highlighting uses the macOS voice
synthesizer's word events aligned with the motor's playback timeline.

Build and open it from the repository (Xcode required; XcodeGen optional when
the checked-in Xcode project is present):

~~~sh
./scripts/build-app.sh
open build/MacApp/Build/Products/Release/NoSpeaker.app
~~~

The local build uses an ad-hoc signature, not Developer ID notarization.
macOS 13 or newer is supported. The trackpad/speaker selector is the
native AppKit NSSegmentedControl, the same control family used by Calendar.
AppKit owns its interaction, geometry, and OS-specific animations; there is
no custom Glass capsule, nested Glass material or simulated enlargement.
The speech-language selector is a native SwiftUI Menu using the same Glass
button style as the toolbar on supported macOS versions. Older versions
retain the system's native bordered menu style.

The Play/Stop buttons have bounded, reversible drag feedback that does not
trigger playback. Reduce Motion is respected. Closing the last window quits
the app and ends any running child audio process.

The upper-right menus select **display language** (System, Magyar, English)
and **appearance** (System, Light, Dark). Both preferences persist and default
to System. Display language is separate from speech language. To add another
display language, add an InterfaceLanguage case and the matching translations
in MacApp/Resources/Localizable.xcstrings.

The System appearance resolves the macOS effective appearance explicitly
and observes system appearance changes. This avoids the stale theme that
can result from applying preferredColorScheme(nil) after a Light override.
Native controls use the existing orange accent and respect macOS accessibility
preferences, including Reduce Motion.

For regression testing without the haptic motor:

~~~sh
./scripts/test.sh
python3 scripts/test-word-events.py
~~~

## Language / Nyelv

English remains the default (using the original macOS default voice). Hungarian
is optional (Tünde) using the
macOS built-in voices; download Tünde in macOS voice settings if it is missing.

```sh
./nospeaker "hello there"          # English (default)
./nospeaker --lang hu "Szia!"      # Hungarian
./nospeaker --lang en "Hello!"     # English (explicit)
./nospeaker --lang hu             # complete Hungarian demo
```

`--voice <name>` still overrides the system voice for either language. The
interactive text entry accepts Hungarian accented characters, including ő and ű.

**macOS Unicode voice fix:** Foundation's Process passes accented voice
names to say using decomposed Unicode; the displayed name Tünde silently
selected the default English voice on this Mac. NoSpeaker now resolves it
through its ASCII Apple voice identifier. Both languages now use the
**same tested LPC/formant encoder**, retaining Tünde's Hungarian
pronunciation. Hungarian uses a slightly lower upper-formant gain and a less
compressed RMS envelope so weak speech frames do not trigger excessive
electronic pulses. English keeps the original analysis and volume profile.
All acoustic settings are centralized in SpeechEncodingProfile.swift.
The shared speech pulse-rate limit is unchanged at 70–250 Hz.

The Hungarian codec also reduces the level of voiced pulses only when
their two sine carriers would otherwise end at a large nonzero value in
the motor-command simulation. The maximum per-pulse reduction is 35%.
This leaves carrier frequencies, phonetic transitions, pitch, the pulse
schedule and unvoiced consonants unchanged. English receives no such
correction. The correction mitigates modeled waveform clicks; real
trackpad acoustics require separate listening or microphone validation.

The experimental Hungarian spectral vocoder and its filters were removed
after quantitative listening and speech-recognition comparisons showed
poorer intelligibility. See docs/hungarian-speech-research.md.

The optional Hungarian phoneme inventory identifies gy (/ɟ/), ty (/c/),
sz (/s/), cs (/t͡ʃ/), dzs (/d͡ʒ/) and long digraph spellings for inspection.
This spelling-to-IPA inventory is **not** a complete G2P system and does not
replace Tünde's pronunciation or time-align phonemes to the waveform:

```sh
./nospeaker --lang hu --phonemes "Hogy vagy?"
# Hungarian phoneme inventory (approximate IPA): /hoɟ vɒɟ/
```

Intelligibility is limited by the physical trackpad and sine-wave speech
representation: voiced speech is reduced to two formant tones and unvoiced
speech to short high-tone bursts. This cannot preserve every component of a
natural human voice; some metallic coloration may remain. Motor playback
must be evaluated by listening, not assumed clean from synthetic tests.

Speech pulse rate is controlled by one global shared safety policy:
`SpeechActuationLimits` (70–250 Hz) for English and Hungarian.
The 250 Hz upper bound controls the repetition rate of voiced pulses, not
the acoustic frequencies of the sine-tone components (which can exceed
250 Hz in the original English algorithm). The English acoustic processing
and its existing motor tone frequencies remain unchanged.

## Test without actuating the trackpad

The program can render its haptic sine-tone commands to a regular speaker as
an **approximation**. This previews the frequencies, timing and relative
amplitudes sent to the motor, but does **not** reproduce the physical
trackpad's mechanical response. The preview mode does not open or activate
the trackpad motor.

```sh
./nospeaker --lang hu --preview "Hogy vagy?"
./nospeaker --lang en --preview "How are you?"
./nospeaker --lang hu --preview-wav hungarian.wav "Hogy vagy?"
```

Playback is capped at 20 seconds of synthesized speech per preview, with a
conservative waveform level. WAV export supports repeatable offline testing.

An optional offline evaluator uses an installed Hungarian Whisper model
to compare the reconstructed motor-preview speech against Tünde's original:

    python3 scripts/evaluate-hungarian-speech.py --runs 3
    python3 scripts/evaluate-hungarian-speech.py --sample sibilants --runs 3
    python3 scripts/evaluate-hungarian-speech.py --sample palatal --runs 3

This requires whisper.cpp, its Hungarian model, and ffmpeg already installed.
It never activates the trackpad or uploads any audio. ASR word and character
errors are only proxies for intelligibility, not listening test results.


## 03 / play with it

```text
./nospeaker "hello there"            say anything
./nospeaker --voice Daniel "hello"   in another macOS voice
./nospeaker --sweep                  a rising tone, 100 Hz to 4 kHz

--dark                               white on black
--plain                              no visuals, plain text
```

## 04 / needs

A Force Touch trackpad (built into MacBooks from 2015 on, or a Magic Trackpad 2 or newer), and macOS 12 or
later on Apple Silicon, or macOS 13 or later on Intel. Without a Force Touch trackpad, it says so and exits.

```text
tested on

MacBook Pro (Mac17,10)   M5 Max   macOS 27.2.1   everything works
```

Not tested yet: Intel Macs, a Magic Trackpad, and older versions of macOS. MultitouchSupport is private, so
older systems may lack the functions it uses, and loudness differs between trackpads. If you try it on another
Mac, open an issue with your model, your macOS version and how it sounded.

## 05 / how it works

```text
say ──▶ formants ──▶ two tones ──▶ motor ──▶ glass
        per 10 ms    F1 + F2       haptics   sound
```

**Why you can hear it.** The trackpad has no speaker, but the motor moves the glass. Driven back and forth
hundreds or thousands of times a second, the glass vibrates fast enough to make sound you can hear. It's quiet
because the motor is built for short taps, not for sound.

**The motor.** `MultitouchSupport` is the private framework macOS uses for the trackpad. Its function
`MTActuationCreateFromDictionary` takes a description of a vibration, a list of sine tones with a frequency,
a strength and a length each, and `MTActuationActuate` plays it on the motor. Apple's public haptics API only
offers three fixed taps.

**The range.** Measured with the MacBook's own microphone, every semitone from 98 Hz to 3,951 Hz: how loud it
is over a quiet room, and how much of the sound is the note itself.

```text
│                                      ###
│                          #+#     +++#####        #
│                         +#+#+   .+++#####       .#
│              .       ++++#+#+   .+++#####    # #.# #
│   ++        +. . #..+++++#+#++++.+++#####+ #####.###          .#
│   +++#.     +...+#..+++++#+#++++.+++#####+ #####.####+        .#
│  ++++#...   +...+#..+++++#+#++++.+++#####+.#####.####+        .#
│ .++++#...++++...+#..+++++#+#++++.+++#####+.#####.####+  +#    .#
│..++++#...++++...+#..+++++#+#++++.+++#####+.#####.####+#.+#  .#.#
│..++++#...++++...+#..+++++#+#++++.+++#####+.#####.####+#.+#+..#.#
└─────────────────────────────────────────────────────────────────
      131         262         523         1047        2093    3951
   public notes stop at 600 Hz ─┘

across: every semitone, in Hz · up: loudness, +16 to +34 dB
# clean note   + fair   . mostly buzz
```

It's loud from about 100 Hz to 4 kHz, with a few dead spots where the glass resonates. Its loudest, cleanest
notes are around 1 kHz, which covers the most important part of a voice.

**The voice.** macOS's own voice speaks the line into memory. Every 10 ms, linear prediction finds the voice's
two strongest resonances (formants), its loudness and its pitch. The motor plays those two resonances as tones,
restarted on every beat of the pitch, so they buzz like a voice instead of whistling. Hiss sounds (s, f, t)
become quick bursts of high tones. Two resonances beat three: in a blind test they were clearer, and louder,
because the motor's strength is split fewer ways.

It sounds robotic, and it's much easier to follow when you can read along, which is why the show types every
line as it speaks.

**The code.** The dependency-free Swift sources are organized under
[Sources/NoSpeaker](Sources/NoSpeaker) by responsibility: Audio, Core,
Haptics, Interface, Show, and Speech. build.sh compiles them into one executable.

## 06 / caveats

- **Is it safe?** It never drives the motor past its normal maximum strength. Going past it is possible and
  louder, but the driver starts to stall, so nospeaker doesn't.
- MultitouchSupport is private and undocumented, so a macOS update could break this.

The MultitouchSupport function names were learned from the open-source Tactile project. Everything else was
measured on a MacBook.

```text
──────────────────────  thanks for listening  ───────────────────────
```

Made by [Cody Collier](https://x.com/codycollier) · [a90.com](https://a90.com) · [MIT license](LICENSE)
