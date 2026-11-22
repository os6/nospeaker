# Hungarian audio-to-haptic research

## Grounded diagnosis

The user's own listening tests established that Tünde's original output is
intelligible on normal speakers, but the prior nospeaker motor-command preview
rendered "Hogy vagy?" like "hogi vagi". The issue is therefore in the
audio-to-haptic encoding, not Tünde's Hungarian letter-to-sound rules.

Hungarian gy is a voiced palatal stop, IPA /ɟ/, rather than separate g and y.
As a stop, its closure, release and adjacent formant transitions are meaningful
perceptual cues. Hungarian orthography also has ty, ny, sz, zs, cs, dz and dzs.
The macOS TTS already performs the orthography-to-pronunciation conversion.

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
- The Hungarian actuator repetition rate remains capped at 250 Hz, the
  original English ceiling, instead of increasing load to chase high pitches.
- The separate Hungarian encoder avoids the earlier heuristic which enabled
  F2/F3 changes throughout an entire phrase merely because that phrase
  *contained* a palatal phoneme, without any phoneme-to-audio alignment.
- A small orthography-to-IPA inventory (optional --phonemes) documents
  Hungarian multigraphs. It is not used as a forced aligner or a replacement
  text-to-speech engine.

No new motor amplitudes are introduced. English continues to use its original
path. This design is informed by published tactile spectral-peak-picking
work, but has not been validated as equivalent to any specific study.

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
