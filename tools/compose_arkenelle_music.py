#!/usr/bin/env python3
"""Original Arkenelle area/combat loops. No third-party samples or MIDI.

Writes looping Ogg Vorbis into assets/audio/music/, overwriting the old
placeholder rips so map paths stay valid. Run:

    python tools/compose_arkenelle_music.py
"""
from __future__ import annotations

import math
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio" / "music"
SR = 44100


def midi_hz(n: float) -> float:
    return 440.0 * (2.0 ** ((n - 69.0) / 12.0))


def env_adsr(n: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    e = np.ones(n, dtype=np.float32) * s
    na, nd, nr = int(a * n), int(d * n), int(r * n)
    na, nd, nr = max(na, 1), max(nd, 1), max(nr, 1)
    if na + nd + nr >= n:
        na = max(1, n // 8)
        nd = max(1, n // 8)
        nr = max(1, n // 6)
    e[:na] = np.linspace(0.0, 1.0, na, dtype=np.float32)
    e[na : na + nd] = np.linspace(1.0, s, nd, dtype=np.float32)
    e[-nr:] = np.linspace(s, 0.0, nr, dtype=np.float32)
    return e


def osc(kind: str, freq: float, n: int) -> np.ndarray:
    """Band-limited-ish tones. No naive square/saw (those rattle/alias)."""
    t = np.arange(n, dtype=np.float64) / SR
    ph = 2.0 * math.pi * float(freq) * t
    s1 = np.sin(ph)
    if kind == "sine":
        return s1.astype(np.float32)
    if kind == "tri":
        x = s1 - np.sin(3.0 * ph) / 9.0 + np.sin(5.0 * ph) / 25.0
        return (x * (8.0 / math.pi**2)).astype(np.float32)
    if kind == "square":
        x = s1 + np.sin(3.0 * ph) / 3.0 + np.sin(5.0 * ph) / 5.0
        return (x * (4.0 / math.pi) * 0.42).astype(np.float32)
    if kind == "pulse":
        x = s1 + 0.35 * np.sin(2.0 * ph) + 0.12 * np.sin(3.0 * ph)
        return (x * 0.72).astype(np.float32)
    if kind == "saw":
        x = s1
        for h in range(2, 8):
            x = x + np.sin(h * ph) / h
        return (x * 0.32).astype(np.float32)
    return s1.astype(np.float32)


def tone(kind: str, midi: float, dur: float, vol: float, a=0.02, d=0.12, s=0.55, r=0.18) -> np.ndarray:
    n = max(int(dur * SR), 8)
    wave = osc(kind, midi_hz(midi), n) * env_adsr(n, a, d, s, r) * vol
    # quiet overtone so leads aren't a dead square
    if kind in ("square", "pulse", "saw"):
        wave += osc("sine", midi_hz(midi) * 2.0, n) * env_adsr(n, a, d, s * 0.4, r) * vol * 0.12
    return wave.astype(np.float32)


def noise_hit(dur: float, vol: float) -> np.ndarray:
    n = max(int(dur * SR), 8)
    rng = np.random.default_rng(7)
    x = rng.uniform(-1.0, 1.0, n).astype(np.float32)
    return x * env_adsr(n, 0.002, 0.08, 0.05, 0.7) * vol


def kick(dur: float, vol: float) -> np.ndarray:
    n = max(int(dur * SR), 8)
    t = np.arange(n, dtype=np.float32) / SR
    freq = np.linspace(90.0, 55.0, n)
    ph = np.cumsum(2.0 * math.pi * freq / SR)
    return (np.sin(ph) * env_adsr(n, 0.001, 0.12, 0.15, 0.55) * vol).astype(np.float32)


def mix_at(buf: np.ndarray, src: np.ndarray, start: int) -> None:
    if start >= buf.size:
        return
    end = min(buf.size, start + src.size)
    buf[start:end] += src[: end - start]


def merge_runs(values: list, step_dur: float) -> list[tuple]:
    """Hold identical neighbors as one long note so retriggers don't beat."""
    runs: list[tuple] = []
    i = 0
    n = len(values)
    while i < n:
        j = i + 1
        while j < n and values[j] == values[i]:
            j += 1
        runs.append((values[i], i * step_dur, (j - i) * step_dur))
        i = j
    return runs


def lowpass_fft(x: np.ndarray, cutoff: float) -> np.ndarray:
    spec = np.fft.rfft(x.astype(np.float64))
    freqs = np.fft.rfftfreq(x.size, 1.0 / SR)
    spec *= np.exp(-0.5 * (freqs / max(cutoff, 1.0)) ** 6)
    return np.fft.irfft(spec, n=x.size).astype(np.float32)


def reverb(x: np.ndarray, wet: float = 0.35) -> np.ndarray:
    y = x.astype(np.float64)
    out = y.copy()
    for delay_s, g in ((0.029, 0.40), (0.037, 0.33), (0.053, 0.26), (0.079, 0.20)):
        d = int(delay_s * SR)
        if d < y.size:
            out[d:] += y[:-d] * g
    return ((1.0 - wet) * y + wet * out).astype(np.float32)


def normalize(buf: np.ndarray, peak: float = 0.86) -> np.ndarray:
    m = float(np.max(np.abs(buf)))
    if m < 1e-6:
        return buf
    return (buf * (peak / m)).astype(np.float32)


def write_wav(path: Path, buf: np.ndarray) -> None:
    pcm = np.clip(buf, -1.0, 1.0)
    pcm_i = (pcm * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm_i.tobytes())


def find_ffmpeg() -> str | None:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return None


def encode_ogg(wav_path: Path, ogg_path: Path, ffmpeg: str) -> None:
    subprocess.check_call(
        [
            ffmpeg,
            "-y",
            "-i",
            str(wav_path),
            "-c:a",
            "libvorbis",
            "-q:a",
            "5",
            str(ogg_path),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def beat_len(bpm: float) -> float:
    return 60.0 / bpm


def compose_loop(
    *,
    bpm: float,
    bars: int,
    bass_notes: list[int],
    chords: list[list[int]],
    melody: list[tuple[int, float]],
    lead: str = "pulse",
    bass_kind: str = "sine",
    drums: bool = False,
    hats: bool = False,
    combat: bool = False,
    pad: bool = True,
    cinematic: bool = False,
    cutoff: float | None = None,
    wet: float = 0.0,
) -> np.ndarray:
    # Hats/kicks against low sines are what read as a rattle. Pads and folk
    # loops stay drumless; fire is the same with a slightly brighter cutoff.
    if cinematic:
        drums = False
        hats = False
        if cutoff is None:
            cutoff = 2600.0
        if wet <= 0.0:
            wet = 0.40
    elif cutoff is None:
        cutoff = 3600.0
    if wet <= 0.0:
        wet = 0.22 if not cinematic else wet
    beat = beat_len(bpm)
    bar = beat * 4.0
    total = bar * bars
    n = int(round(total * SR))
    buf = np.zeros(n, dtype=np.float32)
    steps = len(bass_notes)
    step_dur = total / steps
    bass_vol = 0.13 if cinematic else 0.15
    pad_vol = 0.10 if cinematic else 0.08
    mel_vol = 0.065 if cinematic else 0.11
    # Fractions of note length. Cinematic notes are long, so keep these small
    # or the first several seconds are only a fade-in.
    ba, bd, bs, br = (0.07, 0.12, 0.88, 0.14) if cinematic else (0.05, 0.12, 0.78, 0.16)
    pa, pd, ps, pr = (0.10, 0.16, 0.84, 0.16) if cinematic else (0.10, 0.20, 0.72, 0.22)
    ma, md, ms, mr = (0.12, 0.18, 0.62, 0.22) if cinematic else (0.06, 0.14, 0.58, 0.24)

    for note, t0s, dur in merge_runs(bass_notes, step_dur):
        mix_at(
            buf,
            tone(bass_kind, max(int(note), 36), dur * 0.998, bass_vol, a=ba, d=bd, s=bs, r=br),
            int(t0s * SR),
        )
    if pad:
        chord_seq = [tuple(chords[i % len(chords)]) for i in range(steps)]
        for ch, t0s, dur in merge_runs(chord_seq, step_dur):
            for cn in ch:
                mix_at(buf, tone("sine", cn, dur * 0.998, pad_vol, a=pa, d=pd, s=ps, r=pr), int(t0s * SR))
                if cinematic:
                    mix_at(
                        buf,
                        tone("sine", cn + 12, dur * 0.998, pad_vol * 0.18, a=pa, d=pd, s=ps, r=pr),
                        int(t0s * SR),
                    )

    t_mel = 0.0
    for midi, beats in melody:
        dur = beats * beat
        if midi is not None and int(midi) > 0:
            mix_at(
                buf,
                tone(lead, midi, dur * 0.94, mel_vol, a=ma, d=md, s=ms, r=mr),
                int(t_mel * SR),
            )
        t_mel += dur

    if drums:
        t = 0.0
        step = 0
        while t < total - 0.01:
            st = int(t * SR)
            if step % 4 == 0:
                mix_at(buf, kick(0.28, 0.18), st)
            if hats and step % 2 == 0:
                mix_at(buf, noise_hit(0.08, 0.018), st)
            t += beat
            step += 1

    if cutoff:
        buf = lowpass_fft(buf, cutoff)
    if wet > 0.0:
        buf = reverb(buf, wet)
    return normalize(buf, peak=0.76 if cinematic else 0.86)


# Filenames stay stable so maps keep working. Mood is per-zone, not the old label.
TRACKS = {
    # Hub / home — bright G major, flute-ish.
    "village": dict(
        bpm=90,
        bars=16,
        bass_notes=[43, 43, 43, 43, 50, 50, 50, 50, 48, 48, 48, 48, 43, 43, 43, 43],
        chords=[[67, 71, 74]] * 4 + [[66, 69, 74]] * 4 + [[67, 72, 76]] * 4 + [[67, 71, 74]] * 4,
        melody=[
            (74, 4), (76, 2), (79, 2), (76, 4), (74, 4),
            (71, 4), (72, 2), (74, 2), (76, 8),
            (67, 4), (69, 4), (71, 4), (72, 4),
            (74, 8), (71, 4), (67, 4),
        ],
        lead="tri",
        drums=False,
    ),
    # Overworld travel.
    "adventure": dict(
        bpm=94,
        bars=16,
        bass_notes=[45, 45, 45, 45, 50, 50, 50, 50, 48, 48, 48, 48, 43, 43, 43, 43],
        chords=[[69, 73, 76]] * 4 + [[69, 74, 78]] * 4 + [[67, 72, 76]] * 4 + [[67, 71, 74]] * 4,
        melody=[
            (69, 4), (71, 2), (74, 2), (76, 8),
            (74, 4), (73, 4), (69, 8),
            (71, 4), (74, 4), (76, 4), (78, 4),
            (76, 8), (74, 4), (69, 4),
        ],
        lead="tri",
        drums=False,
    ),
    # Sewers / drowned water.
    "alone": dict(
        bpm=68,
        bars=16,
        bass_notes=[45, 45, 45, 45, 48, 48, 48, 48, 50, 50, 50, 50, 43, 43, 43, 43],
        chords=[[60, 64, 67]] * 4 + [[60, 65, 69]] * 4 + [[62, 65, 69]] * 4 + [[59, 62, 67]] * 4,
        melody=[
            (72, 8), (67, 8),
            (65, 8), (64, 8),
            (60, 8), (62, 8),
            (64, 8), (60, 8),
        ],
        lead="sine",
        drums=False,
        cinematic=True,
        cutoff=2400.0,
    ),
    # Goblin woodlands — playful Mixolydian.
    "lost_woods": dict(
        bpm=86,
        bars=16,
        bass_notes=[43, 43, 43, 43, 45, 45, 45, 45, 47, 47, 47, 47, 43, 43, 40, 40],
        chords=[[67, 71, 74]] * 4 + [[69, 72, 76]] * 4 + [[66, 71, 74]] * 4 + [[67, 71, 74], [67, 71, 74], [64, 67, 71], [64, 67, 71]],
        melody=[
            (74, 2), (71, 2), (67, 4), (69, 4), (71, 4),
            (74, 4), (76, 2), (74, 2), (71, 8),
            (69, 4), (67, 4), (64, 8),
            (67, 8), (62, 8),
        ],
        lead="tri",
        drums=False,
    ),
    # Fungus cave — odd, damp, not a woodland copy.
    "fungus": dict(
        bpm=74,
        bars=16,
        bass_notes=[39, 39, 39, 39, 42, 42, 42, 42, 44, 44, 44, 44, 37, 37, 37, 37],
        chords=[[58, 63, 66]] * 4 + [[61, 66, 70]] * 4 + [[63, 66, 70]] * 4 + [[58, 61, 66]] * 4,
        melody=[
            (66, 8), (63, 8),
            (61, 6), (58, 2), (63, 8),
            (66, 4), (70, 4), (66, 8),
            (63, 8), (58, 8),
        ],
        lead="sine",
        drums=False,
        cinematic=True,
        cutoff=2500.0,
    ),
    # Indoor shops / guild halls.
    "shop": dict(
        bpm=84,
        bars=16,
        bass_notes=[41, 41, 41, 41, 45, 45, 45, 45, 48, 48, 48, 48, 41, 41, 41, 41],
        chords=[[65, 69, 72]] * 4 + [[64, 69, 72]] * 4 + [[67, 72, 76]] * 4 + [[65, 69, 72]] * 4,
        melody=[
            (72, 4), (74, 4), (69, 8),
            (67, 4), (65, 4), (64, 8),
            (65, 4), (67, 4), (69, 8),
            (72, 8), (65, 8),
        ],
        lead="tri",
        drums=False,
    ),
    # Hub square, still major / happy.
    "market": dict(
        bpm=98,
        bars=16,
        bass_notes=[48, 48, 48, 48, 45, 45, 45, 45, 43, 43, 43, 43, 48, 48, 48, 48],
        chords=[[67, 72, 76]] * 4 + [[64, 69, 72]] * 4 + [[67, 71, 74]] * 4 + [[67, 72, 76]] * 4,
        melody=[
            (72, 2), (74, 2), (76, 4), (74, 4), (72, 4),
            (69, 4), (67, 4), (65, 8),
            (67, 4), (69, 2), (72, 2), (74, 8),
            (72, 8), (67, 8),
        ],
        lead="tri",
        drums=False,
    ),
    # Deep forest (not goblin woods).
    "angevin": dict(
        bpm=78,
        bars=16,
        bass_notes=[45, 45, 45, 45, 48, 48, 48, 48, 50, 50, 50, 50, 43, 43, 43, 43],
        chords=[[64, 69, 72]] * 4 + [[67, 72, 76]] * 4 + [[69, 73, 76]] * 4 + [[64, 67, 71]] * 4,
        melody=[
            (69, 8), (67, 8),
            (64, 8), (65, 8),
            (67, 4), (69, 4), (72, 8),
            (69, 8), (64, 8),
        ],
        lead="sine",
        drums=False,
    ),
    # Desert day.
    "al_kharid": dict(
        bpm=88,
        bars=16,
        bass_notes=[45, 45, 45, 45, 48, 48, 48, 48, 50, 50, 50, 50, 43, 43, 43, 43],
        chords=[[69, 72, 76]] * 4 + [[67, 72, 76]] * 4 + [[69, 74, 77]] * 4 + [[64, 69, 72]] * 4,
        melody=[
            (74, 4), (72, 4), (69, 8),
            (67, 4), (69, 4), (72, 8),
            (74, 6), (72, 2), (69, 8),
            (65, 8), (69, 8),
        ],
        lead="tri",
        drums=False,
    ),
    # Desert overworld — D dorian, warm sand (original, not a catalog copy).
    "arabian": dict(
        bpm=90,
        bars=16,
        bass_notes=[38, 38, 38, 38, 41, 41, 41, 41, 43, 43, 43, 43, 36, 36, 36, 36],
        chords=[[62, 65, 69]] * 4 + [[64, 69, 72]] * 4 + [[65, 69, 74]] * 4 + [[60, 65, 69]] * 4,
        melody=[
            (69, 6), (65, 2), (62, 8),
            (64, 4), (65, 4), (69, 8),
            (72, 4), (69, 4), (65, 8),
            (62, 8), (57, 8),
        ],
        lead="tri",
        drums=False,
    ),
    # Desert night / tombs color.
    "arabian_2": dict(
        bpm=72,
        bars=16,
        bass_notes=[38, 38, 38, 38, 36, 36, 36, 36, 41, 41, 41, 41, 38, 38, 38, 38],
        chords=[[62, 65, 68]] * 4 + [[60, 65, 68]] * 4 + [[64, 68, 71]] * 4 + [[62, 65, 69]] * 4,
        melody=[
            (68, 8), (65, 8),
            (61, 8), (65, 8),
            (68, 4), (70, 4), (68, 8),
            (65, 8), (62, 8),
        ],
        lead="sine",
        drums=False,
        cinematic=True,
        cutoff=2500.0,
    ),
    # Dungeon.
    "shadow_temple": dict(
        bpm=58,
        bars=16,
        bass_notes=[38, 38, 38, 38, 41, 41, 41, 41, 36, 36, 36, 36, 38, 38, 38, 38],
        chords=[[53, 56, 60]] * 4 + [[55, 58, 62]] * 4 + [[52, 56, 59]] * 4 + [[53, 56, 60]] * 4,
        melody=[
            (60, 8), (56, 8),
            (58, 8), (53, 8),
            (55, 8), (56, 8),
            (53, 8), (48, 8),
        ],
        lead="sine",
        drums=False,
        cinematic=True,
    ),
    # Mining cave.
    "army_of_darkness": dict(
        bpm=58,
        bars=16,
        bass_notes=[38, 38, 38, 38, 36, 36, 36, 36, 41, 41, 41, 41, 38, 38, 38, 38],
        chords=[[50, 53, 57]] * 4 + [[50, 53, 58]] * 4 + [[53, 57, 60]] * 4 + [[52, 55, 60]] * 4,
        melody=[
            (62, 8), (65, 8),
            (69, 6), (65, 2), (-1, 8),
            (67, 4), (65, 4), (62, 8),
            (60, 4), (57, 4), (62, 8),
        ],
        lead="sine",
        drums=False,
        cinematic=True,
    ),
    # Fire Forge — D phrygian, embers, no percussion.
    "attack_2": dict(
        bpm=70,
        bars=16,
        bass_notes=[38, 38, 38, 38, 41, 41, 41, 41, 36, 36, 36, 36, 38, 38, 38, 38],
        chords=[[53, 57, 60]] * 4 + [[53, 56, 60]] * 4 + [[52, 55, 60]] * 4 + [[50, 53, 57]] * 4,
        melody=[
            (57, 8), (60, 8),
            (62, 6), (60, 2), (57, 8),
            (53, 8), (56, 8),
            (57, 8), (50, 8),
        ],
        lead="sine",
        drums=False,
        cutoff=3200.0,
        wet=0.30,
    ),
    # Bellows Gallery — hotter relative of the forge.
    "attack_3": dict(
        bpm=74,
        bars=16,
        bass_notes=[40, 40, 40, 40, 43, 43, 43, 43, 38, 38, 38, 38, 40, 40, 40, 40],
        chords=[[55, 59, 62]] * 4 + [[55, 58, 62]] * 4 + [[53, 57, 62]] * 4 + [[52, 55, 59]] * 4,
        melody=[
            (59, 8), (62, 8),
            (64, 6), (62, 2), (59, 8),
            (55, 8), (58, 8),
            (59, 8), (52, 8),
        ],
        lead="sine",
        drums=False,
        cutoff=3300.0,
        wet=0.28,
    ),
    # The Hollow — low, slow, mechanical quiet.
    "middle_boss": dict(
        bpm=54,
        bars=16,
        bass_notes=[36, 36, 36, 36, 39, 39, 39, 39, 38, 38, 38, 38, 36, 36, 36, 36],
        chords=[[48, 51, 55]] * 4 + [[48, 51, 56]] * 4 + [[47, 50, 55]] * 4 + [[46, 50, 53]] * 4,
        melody=[
            (55, 8), (51, 8),
            (48, 8), (-1, 8),
            (51, 8), (55, 8),
            (48, 8), (43, 8),
        ],
        lead="sine",
        drums=False,
        cinematic=True,
    ),
    # Menu / arrival fanfare, still gentle.
    "arrival": dict(
        bpm=88,
        bars=16,
        bass_notes=[48, 48, 48, 48, 52, 52, 52, 52, 50, 50, 50, 50, 48, 48, 48, 48],
        chords=[[67, 72, 76]] * 4 + [[71, 74, 79]] * 4 + [[69, 72, 76]] * 4 + [[67, 71, 74]] * 4,
        melody=[
            (67, 4), (71, 4), (74, 8),
            (72, 4), (71, 4), (67, 8),
            (64, 4), (67, 4), (72, 8),
            (67, 8), (60, 8),
        ],
        lead="tri",
        drums=False,
    ),
}

def compose_boss_clear() -> np.ndarray:
    """Short non-looping sting."""
    bpm = 120
    beat = beat_len(bpm)
    notes = [
        (60, 0.5, 0.18),
        (64, 0.5, 0.18),
        (67, 0.5, 0.2),
        (72, 1.0, 0.22),
        (67, 0.5, 0.16),
        (72, 0.5, 0.18),
        (76, 0.5, 0.2),
        (79, 2.5, 0.24),
    ]
    n = int((8.0) * SR)
    buf = np.zeros(n, dtype=np.float32)
    t = 0.4
    for midi, beats, vol in notes:
        dur = beats * beat
        mix_at(buf, tone("tri", midi, dur, vol, a=0.005, d=0.08, s=0.6, r=0.35), int(t * SR))
        mix_at(buf, tone("sine", midi - 12, dur, vol * 0.45, a=0.01, d=0.1, s=0.55, r=0.4), int(t * SR))
        t += dur
    mix_at(buf, kick(0.25, 0.2), int(0.4 * SR))
    return normalize(buf)


def main() -> int:
    ffmpeg = find_ffmpeg()
    if ffmpeg is None:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "imageio-ffmpeg", "-q"])
        ffmpeg = find_ffmpeg()
    if ffmpeg is None:
        print("Need ffmpeg (or pip install imageio-ffmpeg)", file=sys.stderr)
        return 1

    wanted = set(sys.argv[1:]) if len(sys.argv) > 1 else None
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix="arkenelle-music-"))
    try:
        jobs = list(TRACKS.items()) + [("boss_clear", None)]
        for name, spec in jobs:
            if wanted is not None and name not in wanted:
                continue
            if spec is None:
                buf = compose_boss_clear()
            else:
                buf = compose_loop(**spec)
            wav = tmp / f"{name}.wav"
            ogg = OUT / f"{name}.ogg"
            write_wav(wav, buf)
            encode_ogg(wav, ogg, ffmpeg)
            print(f"wrote {ogg.relative_to(ROOT)} ({ogg.stat().st_size} bytes, {buf.size / SR:.1f}s)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    readme = OUT / "ORIGIN.txt"
    readme.write_text(
        "Arkenelle original soundtrack.\n"
        "Synthesized in-repo by tools/compose_arkenelle_music.py.\n"
        "No third-party samples, MIDI packs, Epidemic Sound, or catalog tracks.\n"
        "Each filename is a zone mood (hub, woodland, desert, forge, cave, ...).\n"
        "Loops are drumless cinematic/folk pads so they do not rattle in-game.\n"
        "Arkenelle / RealmCraft may use these commercially.\n",
        encoding="utf-8",
    )
    print("wrote", readme.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
