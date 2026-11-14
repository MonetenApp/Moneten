#!/usr/bin/env python3
"""Writes the three sounds of the notification about new transactions into App/Resources/Sounds.

positive: two rising notes, for a positive sum of the new transactions.
negative: two falling notes, for a negative sum.
neutral: one note, for a sum of zero or sums in several currencies with opposite signs.
"""
import math
import pathlib
import struct
import wave

RATE = 44_100
NOTE = 0.16
TAIL = 0.5
OUT = pathlib.Path(__file__).resolve().parent.parent / "App" / "Resources" / "Sounds"


def bell(frequency, start, length, samples):
    for i in range(int(length * RATE)):
        t = i / RATE
        envelope = math.exp(-7 * t) * min(1, t / 0.004)
        value = math.sin(2 * math.pi * frequency * t) + 0.25 * math.sin(2 * math.pi * 2 * frequency * t)
        samples[int(start * RATE) + i] += 0.3 * envelope * value


def write(name, frequencies):
    samples = [0.0] * int((NOTE * (len(frequencies) - 1) + TAIL) * RATE)
    for index, frequency in enumerate(frequencies):
        bell(frequency, index * NOTE, TAIL, samples)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32_767)) for s in samples))


OUT.mkdir(parents=True, exist_ok=True)
write("positive", [987.77, 1318.51])
write("negative", [1318.51, 987.77])
write("neutral", [1174.66])
