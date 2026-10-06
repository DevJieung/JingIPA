#!/usr/bin/env python3
"""Deterministic original impact layers. No samples or external audio sources."""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[2]


def render(name: str, duration: float, bass: float, seed: int) -> None:
    rng = random.Random(seed)
    rate = 44100
    values = []
    phase = 0.0
    smooth_noise = 0.0
    for i in range(round(rate * duration)):
        t = i / rate
        phase += 2 * math.pi * (bass + 110 * math.exp(-t * 45)) / rate
        smooth_noise = smooth_noise * .55 + rng.uniform(-1, 1) * .45
        body = math.sin(phase) * math.exp(-t * 20) * .62
        crack = smooth_noise * math.exp(-t * 70) * .34
        sheen = math.sin(2 * math.pi * 1480 * t) * math.exp(-t * 35) * .10
        envelope = min(1, t / .0015) * min(1, (duration - t) / .015)
        values.append((body + crack + sheen) * envelope)
    peak = max(abs(v) for v in values)
    data = b"".join(struct.pack("<h", round(v / peak * 16500)) for v in values)
    target = ROOT / "art/sfx" / (name + ".wav")
    with wave.open(str(target), "wb") as out:
        out.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        out.writeframes(data)
    print(target.relative_to(ROOT))


if __name__ == "__main__":
    render("impact_weight", .22, 72, 611)
    render("impact_critical", .30, 51, 612)
