#!/usr/bin/env python3
"""Measure speech information kept by the motor-command preview (no motor access)."""
import argparse
import array
import math
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TEST_TEXT = (
    "Szia! Örülök, hogy újra itt vagy. Ma egy hosszabb magyar szöveget "
    "próbálunk ki. Gyönyörű idő van odakint, a gyerekek játszanak a kertben, "
    "és a szél finoman mozgatja a fákat. Figyeld meg, mennyire érthetők "
    "a különböző magyar hangok!"
)
TEST_SAMPLES = {
    "continuous": TEST_TEXT,
    "sibilants": (
        "Szia! Szép szél fúj a kertben. Sárga zsákot hoztam, "
        "és csengő szól az ajtó mellett. A gyerekek csendesen beszélgetnek."
    ),
    "palatal": (
        "Gyere ide! Hogy vagy? Gyönyörű gyümölcsöket hoztam. "
        "Egy gyerek gyalog jár, a tyúk pedig a tyúkólban alszik."
    ),
}

HUNGARIAN_VOICE = "com.apple.voice.compact.hu-HU.Mariska"


def normalized_words(text):
    return re.sub(r"[^\w\s]", "", text.casefold()).split()


def edit_distance(reference, hypothesis):
    old = list(range(len(hypothesis) + 1))
    for index, source in enumerate(reference, 1):
        new = [index] + [0] * len(hypothesis)
        for position, target in enumerate(hypothesis, 1):
            new[position] = min(
                old[position] + 1,
                new[position - 1] + 1,
                old[position - 1] + (source != target),
            )
        old = new
    return old[-1]


def transcribe(source, output, whisper, model):
    wav16 = output.with_suffix(".pcm16.wav")
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i",
         str(source), "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
         str(wav16)],
        check=True,
    )
    subprocess.run(
        [str(whisper), "-m", str(model), "-l", "hu", "-np", "-nt", "-f",
         str(wav16), "-otxt", "-of", str(output)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    return output.with_suffix(".txt").read_text(encoding="utf-8").strip()


def signal_metrics(path):
    """Analyze the actual speaker-preview waveform, not a motor recording."""
    def decoded(filter_spec=None):
        command = ["ffmpeg", "-v", "error", "-i", str(path)]
        if filter_spec:
            command += ["-af", filter_spec]
        data = subprocess.check_output(command + ["-f", "f32le", "-"])
        samples = array.array("f")
        samples.frombytes(data)
        if sys.byteorder != "little":
            samples.byteswap()
        return samples

    normal = decoded()
    high = decoded("highpass=f=3000")
    if not normal:
        raise RuntimeError("No audio samples in motor preview")

    def rms(samples):
        return math.sqrt(sum(float(x) ** 2 for x in samples) / len(samples))

    return {
        "duration_seconds": round(len(normal) / 16000, 3),
        "rms": round(rms(normal), 6),
        "highpass_3000_rms": round(rms(high), 6),
        "large_sample_jumps_over_0_09": sum(
            abs(a - b) > 0.09 for a, b in zip(normal, normal[1:])
        ),
        "severe_sample_jumps_over_0_13": sum(
            abs(a - b) > 0.13 for a, b in zip(normal, normal[1:])
        ),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", choices=TEST_SAMPLES, default="continuous")
    parser.add_argument("--text", help="Override the fixed test corpus")
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--binary", default="./nospeaker")
    parser.add_argument("--whisper", default=os.environ.get(
        "WHISPER_CLI", str(Path.home() /
                           ".cache/sayit-build/whisper.cpp/build/bin/whisper-cli")
    ))
    parser.add_argument("--model", default=os.environ.get(
        "WHISPER_MODEL", str(Path.home() / ".cache/voicelab/models/"
                             "ggml-hu-whisper-large-v3-turbo-finetuned-q8_0.bin")
    ))
    parser.add_argument("--output", type=Path,
                        help="Retain WAV and transcript files in this directory")
    args = parser.parse_args()
    text = args.text or TEST_SAMPLES[args.sample]

    if not 1 <= args.runs <= 10:
        parser.error("--runs must be between 1 and 10")
    whisper, model = Path(args.whisper).expanduser(), Path(args.model).expanduser()
    if not whisper.is_file() or not model.is_file():
        parser.error("Installed whisper.cpp and a Hungarian model are required")
    if shutil.which("ffmpeg") is None or shutil.which("say") is None:
        parser.error("macOS say and ffmpeg must be installed")

    temporary = tempfile.TemporaryDirectory(prefix="nospeaker-hu-eval-")
    work = args.output or Path(temporary.name)
    work.mkdir(parents=True, exist_ok=True)
    source_wav = work / "source.wav"
    subprocess.run(
        ["say", "-v", HUNGARIAN_VOICE, "-o", str(source_wav),
         "--file-format=WAVE", "--data-format=LEF32@16000", text],
        check=True,
    )
    reference = transcribe(source_wav, work / "reference", whisper, model)
    reference_words = normalized_words(reference)
    if not reference_words:
        raise RuntimeError("The ASR reference text is empty")

    runs = []
    for index in range(args.runs):
        output_wav = work / f"motor-preview-{index + 1}.wav"
        subprocess.run(
            [str(Path(args.binary).resolve()), "--lang", "hu",
             "--preview-wav", str(output_wav), text],
            stdout=subprocess.DEVNULL,
            check=True,
        )
        recognition = transcribe(
            output_wav, work / f"preview-{index + 1}", whisper, model
        )
        hypothesis = normalized_words(recognition)
        word_error = edit_distance(reference_words, hypothesis) / len(reference_words)
        reference_chars = "".join(reference_words)
        character_error = edit_distance(
            reference_chars, "".join(hypothesis)
        ) / len(reference_chars)
        runs.append({
            "wer": round(word_error, 4),
            "cer": round(character_error, 4),
            "recognized": recognition,
            "signal": signal_metrics(output_wav),
        })

    report = {
        "sample": args.sample if args.text is None else "custom",
        "text": text,
        "reference_asr": reference,
        "runs": runs,
        "mean_wer": round(sum(run["wer"] for run in runs) / len(runs), 4),
        "mean_cer": round(sum(run["cer"] for run in runs) / len(runs), 4),
        "note": "ASR is a proxy; it does not measure physical trackpad sound.",
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.output:
        (work / "report.json").write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
