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

**macOS Unicode voice fix:** Foundation's Process converts accented
command-line arguments to decomposed UTF-8. Passing the displayed name
"Tünde" directly to the macOS say command therefore silently selected the
default English voice on this Mac. NoSpeaker now resolves accented voice names
through Apple's AVSpeechSynthesisVoice identifiers (ASCII) before synthesis.
The original English default voice is unchanged, and the test suite checks
that gyár and giár no longer produce identical motor-preview WAVs.

Hungarian audio processing uses a **separate experimental spectral vocoder**
(20 ms analysis windows, 5 ms analysis hops). It selects up to two dominant
audio spectrum components in each window, tracks pitch independently and
preserves rapid amplitude changes. Tünde produces the original Hungarian
speech; the vocoder turns that audio into motor commands. The original English
LPC/formant pipeline is left unchanged.

The optional Hungarian phoneme inventory identifies gy (/ɟ/), ty (/c/),
sz (/s/), cs (/t͡ʃ/), dzs (/d͡ʒ/) and long digraph spellings for inspection.
This spelling-to-IPA inventory is **not** a complete G2P system and does not
replace Tünde's pronunciation or time-align phonemes to the waveform:

```sh
./nospeaker --lang hu --phonemes "Hogy vagy?"
# Hungarian phoneme inventory (approximate IPA): /hoɟ vɒɟ/
```

Intelligibility is limited by the physical trackpad and the maximum of two
simultaneous tones. This encoding is experimental until listeners validate it.

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
