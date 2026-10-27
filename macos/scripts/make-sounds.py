#!/usr/bin/env python3
"""Synthesises the app's built-in sounds into macos/Resources/Sounds/ (run once; the WAVs are committed)."""
import math
import struct
import sys
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "Resources" / "Sounds"


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(abs(s) for s in samples) or 1.0
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * 0.85 * 32767)) for s in samples))


def buzzer(seconds=0.75):
    """Game-show 'wrong answer' buzz: two detuned sawtooths with a fast attack and release."""
    out = []
    n = int(RATE * seconds)
    for i in range(n):
        t = i / RATE
        saw = sum(((f * t) % 1.0) * 2 - 1 for f in (98.0, 100.5, 147.0))
        env = min(1.0, t / 0.01) * min(1.0, (seconds - t) / 0.04)
        out.append(math.tanh(saw * 1.6) * env)
    return out


def ding(seconds=1.4):
    """Bright 'correct answer' bell: a few inharmonic partials with exponential decay."""
    out = []
    n = int(RATE * seconds)
    partials = [(1318.5, 1.0, 3.0), (2637.0, 0.45, 4.5), (3640.0, 0.25, 6.0), (659.25, 0.3, 2.5)]
    for i in range(n):
        t = i / RATE
        s = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-d * t) for f, a, d in partials)
        out.append(s * min(1.0, t / 0.003))
    return out


if __name__ == "__main__":
    write("Buzzer", buzzer())
    write("Ding", ding())
    print(f"wrote {OUT}/Buzzer.wav and Ding.wav", file=sys.stderr)
