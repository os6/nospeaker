#!/usr/bin/env python3
"""Integration tests for GUI playback protocol. Speaker only; no motor access."""
import signal
import subprocess
from pathlib import Path

BINARY = str((Path(__file__).resolve().parent.parent / "nospeaker").resolve())


def run_preview(language, text):
    process = subprocess.run(
        [BINARY, "--lang", language, "--stdin", "--word-events", "--preview"],
        input=text, text=True, encoding="utf-8", capture_output=True,
        timeout=35, check=True,
    )
    records = [line.split("\t") for line in process.stdout.splitlines()
               if line.startswith("NSP\t")]
    assert records[0][1] == "START", records
    assert records[-1][1] == "END", records
    assert float(records[0][2]) > 0, records[0]
    words = [record for record in records if record[1] == "WORD"]
    assert len(words) >= 4, words
    utf16 = text.encode("utf-16-le")
    prev = -1
    fragments = []
    for record in words:
        start, count = int(record[2]), int(record[3])
        assert 0 <= start < start + count <= len(utf16) // 2
        assert start >= prev
        fragments.append(utf16[start * 2:(start + count) * 2].decode("utf-16-le"))
        prev = start
    assert len(fragments) == len(words)
    assert any("gyönyörű" in word.lower() for word in fragments) if language == "hu" else True
    ticks = [float(record[2]) for record in records if record[1] == "TIME"]
    assert ticks and ticks == sorted(ticks) and ticks[-1] <= float(records[0][2])
    print("PASS:", language, "timed words", len(words), "duration", records[0][2])


run_preview("hu", "Szia! Gyönyörű idő van, és újra itt vagyunk.")
run_preview("en", "Hello there! This trackpad can speak English clearly today.")

process = subprocess.Popen(
    [BINARY, "--lang", "hu", "--stdin", "--word-events", "--preview"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    text=True, encoding="utf-8", bufsize=1,
)
assert process.stdin and process.stdout
process.stdin.write(
    "Szia! Egy hosszabb szöveget mondunk el, mert a leállítást "
    "még a beszéd vége előtt szeretnénk ellenőrizni. " * 2
)
process.stdin.close()
started = False
for line in process.stdout:
    if line.startswith("NSP\tSTART\t"):
        started = True
        break
assert started, "No playback START event"
process.send_signal(signal.SIGTERM)
remaining = process.stdout.read()
process.wait(timeout=15)
assert "NSP\tEND\n" not in remaining, "Stop was ignored"
assert "NSP\tSTOPPED\n" in remaining, (process.returncode, remaining)
print("PASS: stop interrupts speaker playback and ends the word event stream")

invalid = subprocess.run(
    [BINARY, "--lang", "hu", "--stdin", "--word-events", "--preview"],
    input="  ", text=True, capture_output=True, timeout=10,
)
assert invalid.returncode == 64, invalid.returncode
print("PASS: blank text is rejected without motor activation")
