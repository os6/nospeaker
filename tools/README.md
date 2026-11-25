# glassmap

nospeaker plays music on the trackpad's haptic motor. glassmap shows which notes your trackpad can actually play.

It plays every semitone from 98 Hz to 3,951 Hz, records each one with the Mac's own microphone, and draws a
chart. It takes under a minute.

```sh
swiftc -O tools/glassmap.swift -o tools/glassmap
tools/glassmap
```

Put the Mac on a table, keep your hands off the glass, and run it in a quiet room.

## What you get

While it plays, every note shows up as a line: a bar as long as the note is loud, shaded by how clean it is.

```
 note     Hz  loudness: █ clean  ▓ fair  ░ buzz                dB  clean
   E6   1319  ████████████████████████████               +27.5 dB    63%
   F6   1397  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                 +25.9 dB    52%
  F#6   1480  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░              +28.8 dB    33%
   G6   1568  ███████████████████████████████████        +35.2 dB    75%
  G#6   1661  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓          +33.2 dB    47%
   A6   1760  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓          +33.3 dB    50%
  A#6   1865  ███████████████████████████████████        +34.5 dB    89%
   B6   1976  ███████████████████████████                +27.2 dB    77%
   C7   2093  ░░░░░░░░░░░░░░░░░░░░░░░                    +22.8 dB     4%
  C#7   2217  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                    +22.8 dB    44%
```

Then the whole range as a chart, and what it found:

```
│                   ▓▓░                          █
│      ░▓▓░        ░▓▓░              ██ █        █▓▓█
│     ░░▓▓░░     ░░░▓▓░░             ████        █▓▓█
│   ░░░░▓▓░░     ░░░▓▓░░░      ▓▓█  ░████       ░█▓▓█
│█ ░░░░░▓▓░░░   ░░░░▓▓░░░░░░▓ ▓▓▓█▓ ░████▓ ▓▓██ ░█▓▓██  █░
│█▓░░░░░▓▓░░░ ░░░░░░▓▓░░░░░░▓░▓▓▓█▓▓░████▓░▓▓██▓░█▓▓██  █░
│█▓░░░░░▓▓░░░░░░░░░░▓▓░░░░░░▓░▓▓▓█▓▓░████▓░▓▓██▓░█▓▓██░▓█░
│█▓░░░░░▓▓░░░░░░░░░░▓▓░░░░░░▓░▓▓▓█▓▓░████▓░▓▓██▓░█▓▓██░▓█░
│█▓░░░░░▓▓░░░░░░░░░░▓▓░░░░░░▓░▓▓▓█▓▓░████▓░▓▓██▓░█▓▓██░▓█░
│█▓░░░░░▓▓░░░░░░░░░░▓▓░░░░░░▓░▓▓▓█▓▓░████▓░▓▓██▓░█▓▓██░▓█░▓░
│█▓░░░░░▓▓░░░░░░░░░░▓▓░░░░░░▓░▓▓▓█▓▓░████▓░▓▓██▓░█▓▓██░▓█░▓░█░
│█▓░░░░░▓▓░░░░░░░░░░▓▓░░░░░░▓░▓▓▓█▓▓░████▓░▓▓██▓░█▓▓██░▓█░▓░█░░▓░█
└─────────────────────────────────────────────────────────────────
      131         262         523         1047        2093    3951
                                                  └┘  └┘└┘└┘└┘└┘└┘

across: every semitone, in Hz · up: loudness over the room, +13 to +36 dB
█ clean   ▓ fair   ░ mostly buzz   └┘ one pitch

one pitch   G#6 = A6, C7 = C#7, D7 = D#7, E7 = F7, F#7 = G7, G#7 = A7, A#7 = B7
dead spots  none
```

- **Height:** how loud the note is over the room.
- **█ ▓ ░:** how much of that sound is the note: clean, fair, mostly buzz.
- **└┘ one pitch:** two neighbouring notes that come out at the same pitch.
- **Dead spots:** notes that barely sound.

<details>
<summary>Every note on this Mac (MacBookPro18,3)</summary>

```
 note     Hz  loudness: █ clean  ▓ fair  ░ buzz                dB  clean
   G2     98  ███████████████████████████                +26.9 dB    67%
  G#2    104  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                 +25.9 dB    45%
   A2    110  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░               +28.1 dB     8%
  A#2    117  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░             +30.0 dB    10%
   B2    123  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░            +30.7 dB     7%
   C3    131  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           +31.7 dB     5%
  C#3    139  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░         +33.6 dB     3%
   D3    147  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓         +33.6 dB    54%
  D#3    156  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓         +33.5 dB    49%
   E3    165  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░          +33.3 dB    22%
   F3    175  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░            +31.0 dB    16%
  F#3    185  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░               +28.0 dB     6%
   G3    196  ░░░░░░░░░░░░░░░░░░░░░░░░                   +23.9 dB     8%
  G#3    208  ░░░░░░░░░░░░░░░░░░░░░░░░░                  +25.4 dB    22%
   A3    220  ░░░░░░░░░░░░░░░░░░░░░░░░░░                 +26.4 dB    19%
  A#3    233  ░░░░░░░░░░░░░░░░░░░░░░░░░░░                +27.1 dB     9%
   B3    247  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░            +31.2 dB     2%
   C4    262  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░          +32.6 dB     4%
  C#4    277  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░        +34.5 dB     8%
   D4    294  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓        +35.4 dB    50%
  D#4    311  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓       +35.7 dB    41%
   E4    330  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░        +34.7 dB    24%
   F4    349  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           +32.4 dB    12%
  F#4    370  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░              +29.4 dB     8%
   G4    392  ░░░░░░░░░░░░░░░░░░░░░░░░░░░                +27.0 dB    22%
  G#4    415  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░               +27.9 dB    35%
   A4    440  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░               +27.9 dB    19%
  A#4    466  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓               +27.6 dB    52%
   B4    494  ░░░░░░░░░░░░░░░░░░░░░░░░░░░                +26.5 dB    23%
   C5    523  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓               +28.0 dB    50%
  C#5    554  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓             +29.7 dB    56%
   D5    587  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓             +29.8 dB    57%
  D#5    622  ██████████████████████████████             +30.4 dB    61%
   E5    659  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓               +27.8 dB    54%
   F5    698  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                 +26.4 dB    37%
  F#5    740  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░              +29.2 dB    31%
   G5    784  █████████████████████████████████          +33.0 dB    78%
  G#5    831  ██████████████████████████████████         +33.7 dB    80%
   A5    880  ████████████████████████████████           +32.4 dB    60%
  A#5    932  █████████████████████████████████          +33.3 dB    82%
   B5    988  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓               +27.8 dB    57%
   C6   1047  ░░░░░░░░░░░░░░░░░░░░░░░░░                  +24.8 dB    24%
  C#6   1109  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                +27.2 dB    57%
   D6   1175  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓              +28.6 dB    57%
  D#6   1245  █████████████████████████████              +28.7 dB    66%
   E6   1319  ████████████████████████████               +27.5 dB    63%
   F6   1397  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                 +25.9 dB    52%
  F#6   1480  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░              +28.8 dB    33%
   G6   1568  ███████████████████████████████████        +35.2 dB    75%
  G#6   1661  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓          +33.2 dB    47%
   A6   1760  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓          +33.3 dB    50%
  A#6   1865  ███████████████████████████████████        +34.5 dB    89%
   B6   1976  ███████████████████████████                +27.2 dB    77%
   C7   2093  ░░░░░░░░░░░░░░░░░░░░░░░                    +22.8 dB     4%
  C#7   2217  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                    +22.8 dB    44%
   D7   2349  ████████████████████████████               +27.5 dB    81%
  D#7   2489  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░               +27.5 dB    18%
   E7   2637  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                          +17.1 dB    53%
   F7   2794  ░░░░░░░░░░░░░░░░░                          +17.0 dB     1%
  F#7   2960  ████████████████                           +16.5 dB    70%
   G7   3136  ░░░░░░░░░░░░░░░░                           +16.1 dB     4%
  G#7   3322  ░░░░░░░░░░░░░░                             +14.3 dB    24%
   A7   3520  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓                             +14.3 dB    44%
  A#7   3729  ░░░░░░░░░░░░░░                             +14.3 dB     3%
   B7   3951  ██████████████                             +13.8 dB    65%
```

</details>

Add `--from C6 --to E7` to measure only part of the range, or `--external` for a Magic Trackpad.

## Sound signature

Every run also saves the trackpad's **sound signature**: the same results as a small JSON file, one note per
line, named after the Mac and the time, like `glassmap-MacBookPro18-3-20261125-1330.json`.
This Mac's is in [signatures/](signatures/).

```json
{
  "glassmap": 1,
  "mac": "MacBookPro18,3",
  "macos": "27.2.1",
  "mic": "MacBook Pro Microphone",
  "trackpad": "built-in",
  "date": "2026-11-25",
  "one_pitch": [["G#6", "A6"], ["C7", "C#7"], ["D7", "D#7"], ["E7", "F7"], ["F#7", "G7"], ["G#7", "A7"], ["A#7", "B7"]],
  "dead_spots": [],
  "notes": [
    {"note": "G2", "hz": 98.0, "db_over_room": 26.9, "clean": 0.67},
    ...
    {"note": "B7", "hz": 3951.1, "db_over_room": 13.8, "clean": 0.65, "same_pitch_as": ["A#7"]}
  ]
}
```

`db_over_room` is how loud the note is over the quiet room. `clean` is how much of that sound is the note,
from 0 to 1. Once there are signatures from enough Macs, nospeaker could use them to fit its tunes and its
voice to each trackpad.

## What we found

Measured on a 14" MacBook Pro (M1 Pro, 2021), macOS 27.2.1. Eight full runs over two days gave the same result
every time.

**The top octave has 7 notes, not 12.** Above about 1.6 kHz the motor doesn't play every frequency you ask
for. It plays a few fixed steps:

```
asked   1950  2000  2025  2050  2070 │ 2093  2110  2130  2182 Hz
heard   1971  1971  1971  1971  1971 │ 2184  2184  2184  2184 Hz
```

So neighbouring notes merge. **C7 can't be played in tune:** the nearest steps are a semitone below it and
three quarters of a semitone above. Changing the frequency only picks which step you land on.

The steps sit close to 24000/n Hz (24000/11 = 2,182, /8 = 3,000, /6 = 4,000). The jump between the two steps
above falls right where rounding to that grid predicts (2,087 Hz). So the driver is probably timing the motor
in whole ticks of 1/24,000 s. If that's right, every Mac has the same gaps. One Mac can't settle that. More
runs can.

**What it means for a tune:** keep the melody below about 1.6 kHz, or use only notes that fall on a step.
`sing()` ends on C7; on this Mac that note comes out near C#7.

**Also:** below about 300 Hz the laptop mic hears the glass ringing at 280–350 Hz more than the note itself,
so the low end of the chart is all `.`. Longer pieces didn't change that.

## How it measures

- 2 s of the quiet room, then each semitone for 0.6 s, played the way `sing()` holds a note: back-to-back
  pieces of whole cycles, about 45 ms each, at the motor's normal maximum. Never louder.
- The mic records the whole run. Each note is cut out by the mic's own clock, and the quiet room is
  subtracted from it.
- **One pitch:** a laptop mic can't tune a note to the cent, but it can tell when two notes sound the same.
  glassmap compares each note's spectrum with the next note's, from 1 kHz up. Real pairs match 96–100%; every
  other pair matched at most 31%.
- **Dead spot:** a note at least 10 dB quieter than the notes on either side.

One Swift file, no dependencies. It drives the motor through MultitouchSupport with the same calls nospeaker
makes, and doesn't need the network.

## Share yours

Run it twice and open an issue titled `glassmap: <your Mac>`. Paste the output and attach both signature
files. The first line of the output already has the model, the macOS version and the mic. Or add a signature
to [signatures/](signatures/) in a pull request.

Most useful: a different chip (Intel, M2–M5), a Magic Trackpad (`--external`), or a different macOS. If your
pairs differ from the seven above, that's the interesting part.

---

glassmap is by [Alex Samson](https://saalse.com), MIT License. The motor code is adapted from nospeaker by
Cody Collier.
