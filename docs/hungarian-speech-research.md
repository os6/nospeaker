# Hungarian speech research and verification

## Confirmed source-voice failure

The original "hogi vagi" pronunciation was caused by macOS say silently
falling back to its default English voice. Swift Process.arguments passes
Unicode voice names in decomposed form on this Mac; the displayed name
Tünde did not select the installed voice. SpeechVoiceResolution.swift
resolves it to the ASCII identifier com.apple.voice.compact.hu-HU.Mariska.
The source audio now distinguishes gyár and giár correctly. Optional
--phonemes is a Hungarian spelling inventory, not a synthesizer.

## What the trackpad motor can represent

The original nospeaker reduces 25-ms speech windows at 10-ms intervals
to two LPC formant tones for voiced speech and short high-tone bursts
for unvoiced consonants. Its haptic backend receives sine tones, not
the original audio PCM. Sine-wave speech cannot exactly reconstruct
a natural human voice with two formants alone.

The single shared SpeechActuationLimits bounds pulse repetition to
70–250 Hz and unvoiced bursts to 4 ms. Carrier frequencies may reach
several kilohertz; this is separate from the 250 Hz repetition bound.

English uses its original LPC formant analysis and 1.8 upper-formant
gain. Hungarian uses the same LPC analyzer, the Tünde voice and 1.3
upper-formant gain. The original English path was not changed.

The speaker-only preview simulates the commands the motor receives,
but not the physical frequency response or resonance of its glass.

## Controlled comparative tests on 22 November 2026

The same 16-second Hungarian passage was rendered from the correctly
selected Tünde voice, transformed into the motor preview, and transcribed
using an installed fine-tuned Hungarian Whisper large-v3-turbo model.
Reference source Tünde speech was correctly transcribed. The following
are individual runs, not averages, against its normalized text:

| Encoder experiment | Word error | Character error |
| --- | ---: | ---: |
| Old independent spectral-peak encoder | 48.6% | 31.2% |
| Independent LPC envelope experiment | 48.6% | 34.9% |
| Mixed LPC vowels plus spectral consonants | 54.1% | 22.6% |
| Shared LPC with carrier phase rounding | 64.9% | 37.1% |
| Original English LPC and correct Tünde | 43.2% | 16.7% |
| Shared LPC, original upper-formant gain | 35.1% | 12.9% |
| Shared LPC, Hungarian gain 1.3 | 35.1% | 12.9% |
| Shared LPC, Hungarian gain 1.0 | 40.5% | 12.9% |
| Shared LPC, Hungarian gain 1.3 with third formant | 37.8% | 16.1% |

The first shared LPC run at gain 1.3 also produced about 11% less
above-3-kHz RMS than gain 1.8 (0.01269 versus 0.01424), with the same
WER and CER in that comparison.

The unvoiced carrier bursts are randomized in the original nospeaker,
so repeated WAV generations and ASR errors differ slightly. A further
rerun with the evaluator returned 37.8% WER and 14.0% CER at gain 1.3.
These figures are *not* human comprehension test results.

The prior frequency-peak tracker, its increasingly aggressive filters,
and the Hungarian-only phase-rounding and frequency-jitter experiments
were removed. They increased audible electronic ringing and/or measured
transcription errors. The shared tested LPC pipeline is simpler and
produced the strongest recognition results.

## Targeted noise investigation (23 November 2026)

The user confirmed that the shared LPC/Tünde model made the physical trackpad
speech more intelligible but still had electronic chirping and rattling.
The original LPC level mapping is pow(relative RMS, 0.45), which strongly
amplifies quiet frames. The original consonant model also emits three random
2700–4300 Hz sine tones every 4 ms; a two-formant, tone-only motor signal
cannot exactly reproduce natural fricatives or the human voice.

Experiments isolated upper-carrier bandwidth from envelope compression.
**The 3900 Hz cap was rejected:** it removed Hungarian sibilant cues,
raising the sibilant corpus WER from 44.7% to 55.3% in two ASR runs.

Instead, Hungarian alone now uses pow(relative RMS, 0.58). This slightly
reduces the original compression and the amplification of weak, noisy
speech frames. It does not change the frame timing, F0, formants, 4-ms
unvoiced bursts or global 70–250 Hz pulse limit. The original 2700–4300 Hz
consonant range and English mode are preserved. These values are centrally
defined in SpeechEncodingProfile.

Two-run ASR results for the *unchanged consonant range*:

| Sample | Baseline WER | Revised WER | Baseline CER | Revised CER |
| --- | ---: | ---: | ---: | ---: |
| Sibilants | 44.7% | 42.1% | 18.4% | 17.4% |
| Hungarian palatals | 44.1% | 41.2% | 29.7% | 26.2% |

Five-run long-passage averages:

| | Baseline | Revised |
| --- | ---: | ---: |
| WER | 36.2% | 36.8% |
| CER | 13.4% | 12.9% |

ASR results are stochastic and subjective listener intelligibility has
not been established. The revised 16.248-second speaker preview reduced
the number of adjacent 16-kHz samples with a normalized amplitude
difference above 0.09 from roughly 1,778 to 1,190 (about 33%), and its
above-3-kHz RMS from about 0.0127 to about 0.01135 (about 10%).
The sample-jump threshold is a diagnostic heuristic, not a direct count
of audible clicks or a physical motor measurement.

Further noise removal is limited by the private motor API's sine-tone-only
actuation and the trackpad's unmeasured mechanical resonance. A controlled
microphone recording of the *actual trackpad* and blinded listening are
needed before claiming elimination of feedback or metallic timbre.
The speaker preview is useful for detecting digital artifacts but does
not calibrate the mechanical output.

## Reproducible, motor-free evaluation

    ./build.sh
    ./scripts/test.sh
    python3 scripts/evaluate-hungarian-speech.py --runs 3
    python3 scripts/evaluate-hungarian-speech.py --sample sibilants --runs 3
    python3 scripts/evaluate-hungarian-speech.py --sample palatal --runs 3

Besides WER and CER, the evaluator now records total signal RMS, highpass
energy above 3 kHz and large adjacent-sample jumps in each generated WAV.
The selected baseline and the new configuration can be compared using
the same fixed corpus without modifying production code.

The evaluator requires a locally installed whisper.cpp executable, a
Hungarian Whisper model and ffmpeg. It generates clean Tünde reference
audio and speaker-preview motor commands, transcribes both, then prints
normalized word and character error rates. It does not activate haptics
or use the internet. The model can make transcription errors, so repeated
trials and actual blind human listening are still necessary.

## Research references

- Sine-wave vowel and formant perception:
  https://pmc.ncbi.nlm.nih.gov/articles/PMC3135151/
- Sine/noise vocoder envelope bandwidth and intelligibility:
  https://pmc.ncbi.nlm.nih.gov/articles/PMC2730710/
- Review of speech-signal coding, source-filter models:
  https://doi.org/10.1186/s13636-023-00274-x
- WORLD high-fidelity spectral envelope and aperiodicity:
  https://github.com/mmorise/World
- Audio-to-tactile speech research:
  https://pmc.ncbi.nlm.nih.gov/articles/PMC10432540/
- Original nospeaker motor protocol and limitations:
  https://github.com/os6/nospeaker
- Apple process arguments:
  https://developer.apple.com/documentation/foundation/process/arguments
