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

## 03 / play with it

```text
./nospeaker "hello there"            say anything
./nospeaker --voice Daniel "hello"   in another macOS voice
./nospeaker --sweep                  a rising tone, 100 Hz to 4 kHz

--dark                               white on black
--plain                              no visuals, plain text
```

`[ music ]`

```text
./nospeaker --song "billie eilish bad guy"   find a song, play its 30-second preview
./nospeaker --file ~/Music/song.mp3          play any audio file, whole
./nospeaker --sound jingle                   a tune: jingle, birthday, sing, sparkle,
                                             heartbeat, sweep

--country kz        which iTunes store to search (default us)
--octave 1          move the whole song up 1 or 2 octaves
--floor 400         lift notes below this many Hz up by octaves (default 400, 0 = off)
--volume 50         0 to 100, never past the motor's normal maximum
```

Songs come from Apple's public iTunes Search API, which only gives 30-second previews. Files can be mp3, m4a,
wav, aiff or flac; songs with DRM (Apple Music downloads) can't be read. Every 10 ms an FFT finds the song's two
strongest notes in the motor's range, and sudden low-end hits (kicks) become a short pitch-dive thump. Notes
under 400 Hz are quiet on the motor and blur together, so they're moved up by whole octaves: the same note,
higher, and the melody stays recognisable.

`[ web panel ]`

```sh
./nospeaker --web                    # opens http://127.0.0.1:4747 (--port 4848, --no-open)
```

One page for everything: search and play songs, drop in a file, type a line to say, play the show's sounds,
stop, volume and pitch. The **Instrument** tab plays until you stop it and draws your trackpad at its real
shape as a heatmap: where each finger is, and how hard (contact size) by colour. Only this Mac can open the
panel, and other websites can't drive the motor through it.

`[ sparkle ]`

```sh
./sparkle 50                         # the show's closing sparkle alone, at 50%
```

A tiny separate program (`sparkle.swift`, built by `./build.sh`) for "done" sounds. It exits with 1 when
there's no Force Touch trackpad, so it can fall back to a normal sound, e.g. as a Claude Code `Stop` hook:

```sh
sparkle 50 || afplay /System/Library/Sounds/Glass.aiff
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

**The code.** One Swift file, [nospeaker.swift](nospeaker.swift), with no dependencies.

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
