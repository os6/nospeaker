# Hungarian speech on the Force Touch trackpad

## What we verified

- macOS Tünde produces understandable Hungarian on the normal audio output.
- The trackpad signal is a severely reduced version of that speech: its
  voiced frames carry only F1 and F2 as pure tones, pulsed at detected F0.
- The earlier unvoiced-consonant fix cannot resolve the specific "Hogy vagy?"
  complaint: Hungarian gy (IPA /ɟ/) is a voiced palatal stop.
- English remains on the original signal path, including the macOS-selected
  default voice and its original pitch-detection bounds.
- There is no evidence yet that a new text-to-speech voice would improve the
  two-tone representation used by the trackpad.

## Experimental Hungarian encoder changes

- Hungarian amplitude envelope now uses an exponent of 0.95 instead of the
  original 0.45 compression exponent. This suppresses low-level closure
  periods relative to vowels and preserves the stop's amplitude contrast.
- Hungarian formant tracking now applies a 3-frame rather than 5-frame
  median filter, retaining more of the fast F1/F2 transitions around stops.
- Both parameters are restricted to Hungarian. English stays byte-for-byte
  identical in these branches.
- These are physics-informed candidate improvements, not independently
  validated human recognition gains. Evaluate through speaker preview.

## Offline listening and safety

Use this to render the same frequency, relative amplitude, duration, and
onset schedule as motor commands and listen through the Mac audio output:

    ./nospeaker --lang hu --preview "Hogy vagy?"

To save a WAV for repeatable analysis:

    ./nospeaker --lang hu --preview-wav test.wav "Hogy vagy?"

Neither the private MultitouchSupport framework nor the motor is opened by
the preview route.

**Important:** this is an electronic approximation, not a measured physical
trackpad transfer function. Glass resonance, actuator, driver behavior and
room acoustics differ. Do not interpret successful WAV playback as proof
that the motor output will be equally intelligible.

## Research-grounded next steps

1. **Voiced-stop cues:** investigate preserving closure timing, release bursts
   and vowel-to-consonant formant transitions, including the palatal gy.
2. **Spectral representation:** evaluate adaptive F1/F2/F3 selection and
   frequency-band peak prioritization, rather than adding unconditional
   tones that dilute the motor's limited acoustic output.
3. **Controlled evaluation:** compare the original encoder with each
   candidate using the speaker preview and blinded Hungarian word-pair
   listening tests; keep the English baseline unchanged.
4. **Learned encoder only after baseline:** if deterministic approaches fail,
   consider training a small *audio-to-haptic encoder* using labeled
   intelligibility measurements. Training a replacement TTS alone will not
   restore speech features discarded downstream.

These are research directions, not validated improvements on this motor.

## References

- LMU München, Hungarian palatal versus velar stop contrasts:
  https://www.phonetik.uni-muenchen.de/studium/skripten/languagedemos/Demos/hungarian.html
- Oxford Phonetics Laboratory, acoustic structure of consonants:
  https://www.phon.ox.ac.uk/jcoleman/consonant_acoustics.htm
- Formant frequency focusing for tactile speech (2024):
  https://pmc.ncbi.nlm.nih.gov/articles/PMC10901863/
- Spectral peak picking for tactile speech (2025):
  https://pmc.ncbi.nlm.nih.gov/articles/PMC12749695/
- Hungarian vowel length in fast speech (ISSP 2024):
  https://www.isca-archive.org/issp_2024/deme24_issp.html
- Apple AVAudioFile and AVAudioPCMBuffer documentation:
  https://developer.apple.com/documentation/avfaudio/avaudiofile
  https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer
