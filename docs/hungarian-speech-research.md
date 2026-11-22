# Hungarian audio-to-haptic research

## Confirmed root cause: incorrect voice selection

The user's listening tests found Tünde's natural Hungarian clear on speakers,
but the trackpad and its speaker preview produced "hogi vagi".

The decisive regression check synthesized the words gyár and giár:
- Direct macOS say with the NFC name Tünde generated *different* source audio.
- The Swift Process version generated *identical* audio for both phrases.
- A raw argv byte inspection proved that Foundation's Process converted
  the Unicode voice name to decomposed UTF-8 (NFD): u + combining diaeresis.
- The macOS say command silently fell back to the default voice with that
  decomposed name instead of selecting Hungarian Tünde.
- The AVSpeechSynthesisVoice identifier
  com.apple.voice.compact.hu-HU.Mariska is pure ASCII and selects the same
  Tünde source audio as the correctly composed name.
- After switching to the voice identifier, the Hungarian preview preserves
  the gyár/giár difference; a regression test now enforces this.

This voice-selection failure was the primary reason the earlier changes
could not repair the perceived Hungarian pronunciation. The separate
Hungarian spectral codec remains an experiment; further perceptual improvement
must be evaluated independently, *after* confirming the correct source voice.

Official documentation: Apple Foundation Process.arguments describes that
arguments are passed via fileSystemRepresentation, which explains the observed
Unicode normalization behavior:
https://developer.apple.com/documentation/foundation/process/arguments

## Implementation: an independent Hungarian vocoder

- English keeps its original LPC vowel-formant encoder, frame length, pitch
  bounds, default voice, and original consonant processing.
- Hungarian invokes its own spectrum and pitch analyzers after the
  Tünde macOS speech audio has been synthesized.
- 20 ms audio windows sampled every 5 ms provide more frequent measurements
  than the original 25 ms / 10 ms English windows.
- The Hungarian spectral encoder searches for dominant local spectral peaks
  in the 300–3900 Hz range, selecting at most two non-adjacent components
  and preserving local relative amplitude and low-energy pauses.
- Upper-frequency peaks are emphasized for unvoiced consonants and fast
  onsets; voiced vowel stretches prefer one low and one high spectral peak.
- English and Hungarian now share the same global speech-pulse bounds,
  70–250 Hz, in SpeechActuationLimits. Unvoiced pulses retain their
  original 4 ms duration (250 per second). This limit is separate from the
  much higher carrier/spectral frequencies also used by original English.
- The separate Hungarian encoder avoids the earlier heuristic which enabled
  F2/F3 changes throughout an entire phrase merely because that phrase
  *contained* a palatal phoneme, without any phoneme-to-audio alignment.
- A small orthography-to-IPA inventory (optional --phonemes) documents
  Hungarian multigraphs. It is not used as a forced aligner or a replacement
  text-to-speech engine.

No new motor amplitudes are introduced. English continues to use its original
path. This design is informed by published tactile spectral-peak-picking
work, but has not been validated as equivalent to any specific study.

## Experimental refinement (November 22, 2026)

Spectral-peak frequencies now use three-point log-power interpolation rather than being restricted to 100 Hz bins. A 575 Hz synthetic tone is recovered within 20 Hz in an automated test. Human listening must establish whether this improves actual speech intelligibility; the motor limits remain unchanged.

## Testing without motor actuation

    ./nospeaker --lang hu --preview "Hogy vagy?"
    ./nospeaker --lang en --preview "How are you?"
    ./nospeaker --lang hu --preview-wav hungarian.wav "Hogy vagy?"
    ./nospeaker --lang hu --phonemes "Hogy vagy?"
    ./scripts/test.sh

The --preview route creates the electronic waveform approximating the
frequencies, durations and levels of the motor's sine-tone instructions.
It does **not** activate the trackpad. It is not a measured mechanical model
of the motor, glass, case, driver or acoustic room response.

## Evidence and limits

- The original and new Hungarian previews differ numerically, and the new
  encoder has 5 ms frame timing, unlike the 10 ms English path.
- Unit tests check 2-peak bounds, pitch extraction, handling silence and
  the motor-safe amplitude/frequency limits.
- The new candidate is *not yet proven* to make Hungarian speech more
  intelligible. A human listening assessment of the updated preview is
  required before attributing an improvement.
- If the phoneme contrast remains unintelligible, merely changing the TTS
  voice will not restore the discarded acoustic content. More faithful
  actuation scheduling, motor frequency-response measurement and a labeled
  audio-to-haptic evaluation corpus would be needed before training a model.

## Research sources

- Olaszy and Abari, Hungarian speech-acoustics mini dictionary:
  https://www.magyarbeszed.hu/en/mb-lws/dictionary/
- Geng and Mooshammer, Hungarian palatal stop phonetics:
  https://zaspil.leibniz-zas.de/article/view/250
- Improved tactile speech perception with formant focusing (2024):
  https://pubmed.ncbi.nlm.nih.gov/38418558/
- Improved tactile phoneme discrimination with envelope expansion (2024):
  https://pmc.ncbi.nlm.nih.gov/articles/PMC11217272/
- Spectral peak picking improves tactile speech perception (2025):
  https://pubmed.ncbi.nlm.nih.gov/41286404/


## Shared pulse limits and ringing suppression

Speech pulse scheduling now uses one shared SpeechActuationLimits policy
across English and Hungarian: 70–250 Hz. Unvoiced pulses retain the original
4 ms duration. This is the **pulse repetition limit**, not a 250 Hz cap on
the spectral carrier frequencies, which the original English engine also
uses above 250 Hz.

The Hungarian-only ToneStabilizer smooths high-frequency peaks tracked across
nearby voiced frames, attenuates isolated high-frequency jumps, and reduces
overly strong high components during stable vowels. It leaves unvoiced
consonant releases unchanged. Since the motor normalizes simultaneous tone
weights, isolated single-tone whistles reduce output level explicitly.
Synthetic tests verify the changes while speaker WAVs confirm bounded output.
Improved intelligibility and absence of ringing still require listening tests.


## Follow-up: suppressing residual high-frequency ringing

A real long-text sample showed numerous large (>850 Hz) upper spectral-peak
jumps between adjacent voiced frames. The previous stabilizer attenuated
only isolated peaks. The updated Hungarian-only filter applies continuity
weights to upper peaks: 0.18 for untracked peaks and 0.50 when only one
neighbour matches. Coherent peaks are smoothed over adjacent 5 ms frames.
Normalization-aware attenuation also reduces absolute frame level, so two
simultaneous high peaks cannot defeat the filter through amplitude
renormalization. Unvoiced consonant releases are explicitly untouched.

Identical 9.003-second, speaker-only test phrase:
- Before: high-pass >3000 Hz RMS 0.01197, total RMS 0.05823,
  peak absolute amplitude 0.2183.
- After: high-pass >3000 Hz RMS 0.00861, total RMS 0.05671,
  peak absolute amplitude 0.2089.

This supports a reduction in high-frequency signal energy, not an objective
measurement of human intelligibility. Keep subjective listening feedback
separate from the numerical signal checks. The English path is unchanged
and the shared 70–250 Hz speech-pulse limits are preserved.

## Targeted removal of high-frequency frame outliers

Long Hungarian utterances still contained narrow 5 ms spectral peaks that
jumped away from the upper tone in both adjacent voiced frames. A full
bandwidth reduction would also remove consonant cues. The updated stabilizer
instead reconnects a missing upper spectral trajectory only if the preceding
and following voiced frames agree (within 280 Hz) and the center is more
than 500 Hz away. Consonant onset and offset frames are not bridged.

The diagnostic on the same 16.258-second Hungarian phrase found 19 such
upper-frequency outliers before this change and 1 afterward. The maximum
voiced repetition frequency remained 250 Hz. Waveform duration remained
16.258 seconds and peak output level 0.219.

This result is a deterministic signal-quality improvement, not proof of
human speech intelligibility or trackpad acoustic fidelity. The real
trackpad was not actuated during this test.

References:
- McAulay and Quatieri (1986), sinusoidal speech modeling and temporal
  tracking: https://www.ll.mit.edu/r-d/publications/speech-analysissynthesis-based-sinusoidal-representation
- Spectral modeling synthesis, peak tracking and noise model:
  https://dsprelated.com/freebooks/sasp/Spectral_Modeling_Synthesis.html

## Isolated A/B after Hungarian listening feedback (2026-11-22)

The user reported *two different artifacts*: sharp crackling/contact-like
distortion was reduced in the combined phase-and-fricative experiment, but
musical ringing became much worse. Reverting both was too broad.

For the controlled follow-up, we reintroduced **only**
HungarianPulsePhaseAlignment (integer carrier cycles per existing pulse).
We intentionally excluded randomized/rapid fricative carrier jitter, which
could create new whistles. This keeps the global 70–250 Hz pulse-rate
limits and the unmodified English encoder.

The short and long speaker-preview WAVs for the phase-only variant match
the earlier, independently generated phase-only test files byte-for-byte.
The phase-only method prevents modelled nonzero end-of-command discontinuities
but changes carrier frequencies by up to half the pulse rate. Listening is
needed to distinguish relief of clicks from any residual musical artifacts.

References:
- SOF Project tone engine: sine start/stop clicks and anti-click ramps
  https://thesofproject.github.io/latest/developer_guides/firmware/tone.html
- Apple Accelerate: windowing reduces signal discontinuity artifacts
  https://developer.apple.com/documentation/accelerate/reducing-spectral-leakage-with-windowing
