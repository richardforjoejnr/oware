"""Lelu Ludo's sounds, made from nothing but arithmetic, so the app owns every second of
them (no samples, no libraries, no licences). Run from apps/lelu-ludo:

    python art/make_audio.py

Writes LeluLudo/Resources/Audio/*.m4a (AAC, mono, 44.1 kHz) via macOS `afconvert`. They are stand-ins
until recorded foley arrives (docs/AUDIO_SOURCES.md): a file of the same name
replaces one without any change to the app.

The instruments, roughly: a wooden xylophone with a buzzing gourd (after the gyil), an iron bell, a
seed shaker and a hand drum.
"""

import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy.signal import butter, sosfilt

SR = 44_100
OUT = os.path.join(os.path.dirname(__file__), "..", "LeluLudo", "Resources", "Audio")
rng = np.random.default_rng(1957)   # fixed: the same files every run


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def band(x, lo=None, hi=None, order=2):
    if lo and hi:
        sos = butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    elif lo:
        sos = butter(order, lo, btype="highpass", fs=SR, output="sos")
    else:
        sos = butter(order, hi, btype="lowpass", fs=SR, output="sos")
    return sosfilt(sos, x)


def mode(f, t, decay):
    """One decaying resonance."""
    return np.sin(2 * np.pi * f * t) * np.exp(-t * decay)


def place(track, sound, at):
    """Mixes `sound` into `track` from `at` seconds, cut at the end of the track."""
    i = int(at * SR)
    if i >= len(track):
        return
    n = min(len(sound), len(track) - i)
    track[i:i + n] += sound[:n]


# Instruments -------------------------------------------------------------------------------------

def gyil(f, vel=1.0, dur=1.6, buzz=1.0):
    """A wooden bar struck with a rubber mallet over a gourd: the bar's inharmonic modes, a soft
    knock, and the buzz of the gourd's membrane, strongest as the note starts."""
    t = t_axis(dur)
    body = (mode(f, t, 3.2 + f / 180) * 1.0
            + mode(f * 3.93, t, 12 + f / 60) * 0.32
            + mode(f * 9.1, t, 40) * 0.06
            + mode(f * 2.0, t, 8) * 0.10)            # the gourd adds an octave
    knock = band(rng.uniform(-1, 1, len(t)), hi=2_500) * np.exp(-t * 250) * 0.5
    x = body + knock
    # The membrane: a rattle that follows the note's loudness, high-passed so it reads as buzz.
    env = np.exp(-t * (6 + f / 120))
    rattle = np.sign(np.sin(2 * np.pi * f * t)) * env * (0.5 + 0.5 * rng.uniform(-1, 1, len(t)))
    x += band(rattle, lo=1_800, hi=6_000) * 0.07 * buzz
    return x * vel * 0.45


def bell(f, vel=1.0, dur=1.0):
    """Struck iron: inharmonic partials, the high ones dying first."""
    t = t_axis(dur)
    x = (mode(f, t, 7) + mode(f * 2.72, t, 11) * 0.45 + mode(f * 5.1, t, 18) * 0.2 + mode(f * 8.3, t, 30) * 0.08)
    x += band(rng.uniform(-1, 1, len(t)), lo=3_000) * np.exp(-t * 600) * 0.3
    return x * vel * 0.18


def shaker(vel=1.0, dur=0.09):
    """Seeds in a gourd: a short swish of high noise."""
    t = t_axis(dur)
    env = np.minimum(t / 0.006, 1) * np.exp(-t * 55)
    return band(rng.uniform(-1, 1, len(t)), lo=3_500, hi=10_000) * env * vel * 0.22


def drum(f=105, vel=1.0, dur=0.6, slap=0.0):
    """A hand drum: a pitch that drops as the skin settles, plus some slap."""
    t = t_axis(dur)
    pitch = f * (1 + 0.35 * np.exp(-t * 30))
    phase = 2 * np.pi * np.cumsum(pitch) / SR
    x = np.sin(phase) * np.exp(-t * 9) + np.sin(phase * 1.5) * np.exp(-t * 18) * 0.25
    x += band(rng.uniform(-1, 1, len(t)), lo=600, hi=5_000) * np.exp(-t * 90) * (0.15 + slap)
    return x * vel * 0.5


# The pentatonic scale the tunes use (G A B D E).
N = {"E3": 164.81, "G3": 196.00, "A3": 220.00, "B3": 246.94, "D4": 293.66, "E4": 329.63, "G4": 392.00,
     "A4": 440.00, "B4": 493.88, "D5": 587.33, "E5": 659.26, "G5": 783.99, "A5": 880.0}


# Sound effects -----------------------------------------------------------------------------------

def wood_tap(scale):
    """A wooden pawn set down on a wooden board."""
    t = t_axis(0.16)
    x = band(rng.uniform(-1, 1, len(t)), hi=6_000) * np.exp(-t * 420) * 0.8
    x += (mode(1_150 * scale, t, 60) * 0.45 + mode(1_780 * scale, t, 85) * 0.3
          + mode(2_950 * scale, t, 150) * 0.15 + mode(240 * scale, t, 35) * 0.35)
    return x


def die_throw(seed):
    """A die thrown onto wood: bounces getting quicker and softer, then a short roll."""
    r = np.random.default_rng(seed)
    out = np.zeros(int(0.75 * SR))
    at, gap, vel = 0.0, 0.12 + r.uniform(-0.015, 0.015), 1.0
    while vel > 0.12 and at < 0.6:
        t = t_axis(0.12)
        s = r.uniform(0.92, 1.1)
        click = band(r.uniform(-1, 1, len(t)), lo=1_200, hi=7_000) * np.exp(-t * 650)
        click += (mode(2_100 * s, t, 160) * 0.35 + mode(3_300 * s, t, 220) * 0.2 + mode(520 * s, t, 55) * 0.3)
        place(out, click * vel, at)
        at += gap
        gap *= r.uniform(0.62, 0.78)
        vel *= r.uniform(0.62, 0.75)
    # The last of the roll: a soft grind of edges on wood.
    t = t_axis(0.2)
    grind = band(r.uniform(-1, 1, len(t)), lo=1_500, hi=5_000) * np.sin(np.pi * t / 0.2) * 0.06
    place(out, grind, at)
    return out


def knock(seed):
    """A pawn knocked off its square: a hard hit, then it clatters away."""
    r = np.random.default_rng(seed)
    out = np.zeros(int(0.6 * SR))
    t = t_axis(0.5)
    hit = band(r.uniform(-1, 1, len(t)), hi=4_000) * np.exp(-t * 300) * 1.0
    hit += mode(300, t, 22) * 0.7 + mode(520, t, 30) * 0.45 + mode(880, t, 45) * 0.25
    place(out, hit, 0)
    for k, at in enumerate([0.13, 0.21, 0.27]):
        place(out, wood_tap(r.uniform(1.2, 1.5)) * (0.5 - 0.13 * k), at + r.uniform(-0.01, 0.01))
    return out


def home():
    """A token home: three rising notes and a bell."""
    out = np.zeros(int(1.3 * SR))
    for k, n in enumerate(["G4", "B4", "D5"]):
        place(out, gyil(N[n], 0.8 + 0.1 * k, dur=1.1), 0.085 * k)
    place(out, bell(N["G5"] * 1.5, 0.7), 0.17)
    return out


def three_sixes():
    """Three sixes, and the turn is lost: two drum hits and a falling pair."""
    out = np.zeros(int(1.0 * SR))
    place(out, drum(95, 0.9), 0)
    place(out, drum(95, 0.7), 0.14)
    place(out, gyil(N["D4"], 0.7), 0.3)
    place(out, gyil(N["A3"], 0.7), 0.48)
    return out


def win():
    """You won: a run up the scale, a chord, the bell and the shaker."""
    out = np.zeros(int(2.6 * SR))
    for k, n in enumerate(["G4", "A4", "B4", "D5", "E5", "G5"]):
        place(out, gyil(N[n], 0.6 + 0.06 * k, dur=1.0), 0.075 * k)
    for n in ["G4", "D5", "G5"]:
        place(out, gyil(N[n], 0.8, dur=2.0), 0.55)
    place(out, drum(110, 0.8), 0.55)
    for k in range(10):
        place(out, shaker(0.9 if k % 3 == 0 else 0.5), 0.55 + 0.1 * k)
    for k, at in enumerate([0.55, 0.85, 1.05]):
        place(out, bell(1_180 if k else 880, 0.8), at)
    return out


def lose():
    """You lost: a gentle fall, no jeering."""
    out = np.zeros(int(2.0 * SR))
    for at, n in [(0.0, "D4"), (0.22, "B3"), (0.44, "A3"), (0.78, "G3")]:
        place(out, gyil(N[n], 0.75, dur=1.3, buzz=0.6), at)
    return out


# Output ------------------------------------------------------------------------------------------

def normalise(x, peak_db):
    x = x - np.mean(x)
    fade = int(0.004 * SR)   # no click at either end
    if len(x) > 2 * fade:
        x[:fade] *= np.linspace(0, 1, fade) if np.abs(x[0]) > 1e-3 else 1
        x[-fade:] *= np.linspace(1, 0, fade)
    return x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)


def write(name, x, peak_db=-1.0):
    x = normalise(x, peak_db)
    pcm = (np.clip(x, -1, 1) * 32_767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        dest = os.path.join(OUT, name + ".m4a")
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "80000", wav, dest],
                       check=True)
    print(f"{name}.m4a  {len(x) / SR:.2f}s  {os.path.getsize(dest) // 1024} KB")


def main():
    os.makedirs(OUT, exist_ok=True)
    for k, s in enumerate([0.94, 1.0, 1.05, 1.11]):
        write(f"sfx-step-{k + 1}", wood_tap(s), peak_db=-4)
    for k in range(3):
        write(f"sfx-roll-{k + 1}", die_throw(10 + k), peak_db=-2)
    for k in range(2):
        write(f"sfx-kick-{k + 1}", knock(20 + k), peak_db=-1)
    write("sfx-home-1", home(), peak_db=-2)
    write("sfx-threeSixes-1", three_sixes(), peak_db=-2)
    write("sfx-win-1", win(), peak_db=-1)
    write("sfx-lose-1", lose(), peak_db=-3)


if __name__ == "__main__":
    sys.exit(main())
