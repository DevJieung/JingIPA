#!/usr/bin/env python3
"""개구리 용사 — 절차적 사운드 생성기.

외부 사운드 에셋 없이 게임에 필요한 효과음과 배경음을 전부 합성해서
assets/audio/ 아래에 .ogg 로 저장한다.

사용법:
    python3 tools/gen_audio.py            # 전체 재생성
    python3 tools/gen_audio.py correct    # 특정 항목만

의존성: numpy, ffmpeg(libvorbis)
"""

from __future__ import annotations

import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio")

# 아이용 게임이므로 전체적으로 부드럽고 톤이 높은, 귀에 자극적이지 않은 음색을 쓴다.
MASTER_PEAK = 0.72


# --------------------------------------------------------------------------- #
# 기본 도구
# --------------------------------------------------------------------------- #
def n_samples(dur: float) -> int:
    return max(1, int(round(dur * SR)))


def t_axis(dur: float) -> np.ndarray:
    return np.arange(n_samples(dur), dtype=np.float64) / SR


def midi(note: float) -> float:
    """MIDI 번호 -> 주파수. 69 = A4 = 440Hz."""
    return 440.0 * (2.0 ** ((note - 69.0) / 12.0))


# 계이름 헬퍼 (C4 = 60)
NOTE_BASE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def nn(name: str) -> float:
    """'C4', 'F#5', 'Eb3' -> MIDI 번호."""
    letter = name[0].upper()
    idx = 1
    acc = 0
    while idx < len(name) and name[idx] in "#b":
        acc += 1 if name[idx] == "#" else -1
        idx += 1
    octave = int(name[idx:])
    return NOTE_BASE[letter] + acc + (octave + 1) * 12


def phase_of(freq, n: int) -> np.ndarray:
    """스칼라 또는 배열 주파수로부터 누적 위상(라디안)을 만든다 (글라이드 지원)."""
    if np.isscalar(freq):
        f = np.full(n, float(freq))
    else:
        f = np.asarray(freq, dtype=np.float64)
        if f.shape[0] != n:
            f = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, f.shape[0]), f)
    return 2.0 * np.pi * np.cumsum(f) / SR


def osc(freq, dur: float, wave_type: str = "sine", duty: float = 0.5,
        phase0: float = 0.0) -> np.ndarray:
    n = n_samples(dur)
    ph = phase_of(freq, n) + phase0
    if wave_type == "sine":
        return np.sin(ph)
    if wave_type == "tri":
        # 삼각파: 부드러운 배음, 베이스에 적합
        return 2.0 / np.pi * np.arcsin(np.sin(ph))
    if wave_type == "saw":
        return 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    if wave_type == "square":
        return np.where((ph / (2 * np.pi)) % 1.0 < duty, 1.0, -1.0)
    if wave_type == "soft":
        # 사인 + 약한 3배음: 마림바/실로폰 느낌
        return 0.82 * np.sin(ph) + 0.14 * np.sin(3 * ph) + 0.04 * np.sin(5 * ph)
    if wave_type == "bell":
        return (0.6 * np.sin(ph) + 0.25 * np.sin(2.76 * ph)
                + 0.1 * np.sin(5.4 * ph) + 0.05 * np.sin(8.9 * ph))
    if wave_type == "noise":
        rng = np.random.default_rng(1234)
        return rng.uniform(-1.0, 1.0, n)
    raise ValueError(f"unknown wave: {wave_type}")


def noise(dur: float, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return rng.uniform(-1.0, 1.0, n_samples(dur))


def adsr(dur: float, a: float = 0.005, d: float = 0.05, s: float = 0.7,
         r: float = 0.1) -> np.ndarray:
    n = n_samples(dur)
    na, nd, nr = n_samples(a), n_samples(d), n_samples(r)
    ns = max(0, n - na - nd - nr)
    if na + nd + nr > n:  # 너무 짧으면 비율로 축소
        scale = n / float(na + nd + nr)
        na, nd, nr = int(na * scale), int(nd * scale), int(nr * scale)
        ns = max(0, n - na - nd - nr)
    env = np.concatenate([
        np.linspace(0.0, 1.0, na, endpoint=False) if na else np.empty(0),
        np.linspace(1.0, s, nd, endpoint=False) if nd else np.empty(0),
        np.full(ns, s),
        np.linspace(s, 0.0, nr) if nr else np.empty(0),
    ])
    if env.shape[0] < n:
        env = np.pad(env, (0, n - env.shape[0]))
    return env[:n]


def perc_env(dur: float, attack: float = 0.002, curve: float = 4.0) -> np.ndarray:
    """타악기형 엔벨로프: 순간 어택 + 지수 감쇠."""
    n = n_samples(dur)
    na = min(n_samples(attack), n)
    env = np.empty(n)
    env[:na] = np.linspace(0.0, 1.0, na)
    tail = np.linspace(0.0, 1.0, n - na) if n > na else np.empty(0)
    if tail.size:
        env[na:] = np.exp(-curve * tail * 3.0)
    return env


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    """1차 IIR 로우패스 — 날카로움을 눌러 아이 귀에 편하게."""
    if cutoff >= SR / 2:
        return x
    alpha = math.exp(-2.0 * math.pi * cutoff / SR)
    out = np.empty_like(x)
    acc = 0.0
    for i in range(x.shape[0]):
        acc = (1.0 - alpha) * x[i] + alpha * acc
        out[i] = acc
    return out


def highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    return x - lowpass(x, cutoff)


def fast_lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    """FFT 기반 브릭월 로우패스 (긴 신호용, 위 IIR보다 훨씬 빠름)."""
    n = x.shape[0]
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    roll = 1.0 / (1.0 + (freqs / max(1.0, cutoff)) ** 4)
    return np.fft.irfft(spec * roll, n)


def place(base: np.ndarray, snippet: np.ndarray, at: float,
          gain: float = 1.0) -> np.ndarray:
    """base 위 at(초) 위치에 snippet 을 더한다. 길이가 모자라면 늘린다."""
    i = int(round(at * SR))
    end = i + snippet.shape[0]
    if end > base.shape[0]:
        base = np.pad(base, (0, end - base.shape[0]))
    base[i:end] += snippet * gain
    return base


def reverb(x: np.ndarray, wet: float = 0.22, decay: float = 0.32,
           spread: float = 1.0) -> np.ndarray:
    """가벼운 슈뢰더 리버브 — 공간감만 살짝."""
    delays = [int(SR * d * spread) for d in (0.0297, 0.0371, 0.0411, 0.0437)]
    out = np.zeros(x.shape[0] + max(delays) + int(SR * 0.4))
    dry = np.pad(x, (0, out.shape[0] - x.shape[0]))
    acc = np.zeros_like(out)
    for k, dl in enumerate(delays):
        buf = np.zeros_like(out)
        buf[dl:dl + x.shape[0]] = x
        g = decay * (0.92 ** k)
        # 반복 반사 3회
        for rep in range(1, 4):
            off = dl * rep
            if off + x.shape[0] < out.shape[0]:
                buf[off:off + x.shape[0]] += x * (g ** rep)
        acc += buf / len(delays)
    out = dry * (1.0 - wet) + acc * wet
    return out


def soft_clip(x: np.ndarray) -> np.ndarray:
    return np.tanh(x * 1.15) / math.tanh(1.15)


def normalize(x: np.ndarray, peak: float = MASTER_PEAK) -> np.ndarray:
    m = float(np.max(np.abs(x))) if x.size else 0.0
    if m < 1e-9:
        return x
    return x * (peak / m)


def fade(x: np.ndarray, fin: float = 0.004, fout: float = 0.02) -> np.ndarray:
    n = x.shape[0]
    ni, no = min(n_samples(fin), n), min(n_samples(fout), n)
    if ni:
        x[:ni] *= np.linspace(0.0, 1.0, ni)
    if no:
        x[-no:] *= np.linspace(1.0, 0.0, no)
    return x


# --------------------------------------------------------------------------- #
# 파일 출력
# --------------------------------------------------------------------------- #
def write_ogg(name: str, data: np.ndarray, quality: int = 4,
              stereo: bool = False) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    # Vorbis 는 손실 압축이라 디코딩 결과가 원본 피크를 넘길 수 있다(오버슛).
    # 길고 조밀한 배경음일수록 심해서, 여유를 크게 두지 않으면 기기에서 클리핑한다.
    # (측정: 0.83 로 넣은 BGM 이 1.20 으로 디코딩됨.)
    target = 0.52 if stereo else MASTER_PEAK
    data = soft_clip(normalize(np.asarray(data, dtype=np.float64), target))
    if stereo:
        if data.ndim == 1:
            data = np.stack([data, data], axis=1)
        channels = 2
        interleaved = data.reshape(-1)
    else:
        if data.ndim == 2:
            data = data.mean(axis=1)
        channels = 1
        interleaved = data

    pcm = np.clip(interleaved, -1.0, 1.0)
    pcm16 = (pcm * 32767.0).astype("<i2")

    with tempfile.TemporaryDirectory() as td:
        wav_path = os.path.join(td, "tmp.wav")
        with wave.open(wav_path, "wb") as wf:
            wf.setnchannels(channels)
            wf.setsampwidth(2)
            wf.setframerate(SR)
            wf.writeframes(pcm16.tobytes())
        ogg_path = os.path.join(OUT_DIR, f"{name}.ogg")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
             "-c:a", "libvorbis", "-q:a", str(quality), ogg_path],
            check=True,
        )
    size = os.path.getsize(os.path.join(OUT_DIR, f"{name}.ogg"))
    dur = data.shape[0] / SR if data.ndim == 1 else data.shape[0] / SR
    print(f"  {name + '.ogg':<22} {dur:5.2f}s  {size / 1024:7.1f} KB")


# --------------------------------------------------------------------------- #
# 효과음
# --------------------------------------------------------------------------- #
def sfx_ui_tap() -> np.ndarray:
    """버튼 터치 — 짧고 동글동글한 팝."""
    d = 0.10
    f = np.linspace(880, 660, n_samples(d))
    body = osc(f, d, "soft") * perc_env(d, 0.001, 5.0)
    click = noise(0.012, 7) * perc_env(0.012, 0.0005, 9.0) * 0.18
    out = np.zeros(n_samples(d))
    out += body
    out = place(out, click, 0.0)
    return fade(out * 0.7)


def sfx_answer_pick() -> np.ndarray:
    """보기 선택 — 물방울 같은 상승 블립."""
    d = 0.16
    f = np.linspace(520, 1040, n_samples(d)) ** 1.0
    body = osc(f, d, "sine") * perc_env(d, 0.004, 3.2)
    sub = osc(np.linspace(260, 520, n_samples(d)), d, "sine") * perc_env(d, 0.004, 3.2) * 0.3
    return fade(body + sub)


def sfx_block_pop() -> np.ndarray:
    """블록 하나가 놓일 때 — 나무 마림바 톡. 게임에서 pitch_scale 로 음정을 올려 쓴다."""
    d = 0.22
    base = nn("C5")
    tone = (osc(midi(base), d, "soft") * perc_env(d, 0.001, 5.5)
            + osc(midi(base + 12), d, "sine") * perc_env(d, 0.001, 8.0) * 0.35
            + osc(midi(base + 19), d, "sine") * perc_env(d, 0.001, 11.0) * 0.15)
    knock = noise(0.008, 3) * perc_env(0.008, 0.0004, 10.0) * 0.25
    out = tone
    out = place(out, knock, 0.0)
    return fade(reverb(out, 0.12, 0.2)[:n_samples(d + 0.1)])


def sfx_block_snap() -> np.ndarray:
    """빼는 블록(붉은 블록)이 놓일 때 — "챡!" 하는 딱딱한 나무 딱지 소리.

    더하는 블록(block_pop)의 둥글둥글한 마림바 톡과 확실히 갈라야 한다.
    아이가 화면을 안 봐도 "이건 얹을 것이 아니라 덜어낼 것"이라고 귀로 알아챈다.
    어택을 거의 0에 가깝게, 감쇠도 훨씬 빠르게 잡되(그래서 '톡'이 아니라 '챡'),
    로우패스로 4.5kHz 위를 눌러 아이 귀에 따갑지 않게 한다.
    """
    d = 0.13
    base = nn("D5")
    # 짧고 단단한 몸통 — block_pop 보다 배음이 적고 훨씬 빨리 죽는다.
    body = (osc(midi(base), d, "soft") * perc_env(d, 0.0006, 13.0) * 0.60
            + osc(midi(base + 7), d, "sine") * perc_env(d, 0.0006, 17.0) * 0.20)
    # 딱! — 노이즈 클랙 두 겹을 4ms 어긋나게 겹쳐 '챡' 의 두께를 만든다.
    clack = noise(0.020, 21) * perc_env(0.020, 0.0002, 16.0) * 0.60
    clack2 = noise(0.013, 43) * perc_env(0.013, 0.0002, 24.0) * 0.34
    out = body
    out = place(out, clack, 0.0)
    out = place(out, clack2, 0.004)
    out = lowpass(out, 4500.0)
    return fade(out * 0.95)


def sfx_count_tick() -> np.ndarray:
    """세기 애니메이션의 똑딱."""
    d = 0.07
    tone = osc(midi(nn("E6")), d, "sine") * perc_env(d, 0.001, 8.0)
    return fade(tone * 0.55)


def sfx_merge() -> np.ndarray:
    """두 블록 무리가 합쳐질 때 — 위로 쓸어올리는 휘익."""
    d = 0.38
    n = n_samples(d)
    sweep = fast_lowpass(noise(d, 11), 2500) * 3.0
    env = np.sin(np.linspace(0, math.pi, n)) ** 1.6
    f = np.linspace(300, 1500, n)
    tone = osc(f, d, "sine") * env * 0.5
    return fade(sweep * env * 0.45 + tone)


def sfx_ten_bundle() -> np.ndarray:
    """블록 10개가 '십 막대'로 묶일 때 — 반짝 상승 아르페지오."""
    notes = [nn("C5"), nn("E5"), nn("G5"), nn("C6"), nn("E6")]
    out = np.zeros(n_samples(0.62))
    for i, m in enumerate(notes):
        seg = osc(midi(m), 0.30, "bell") * perc_env(0.30, 0.002, 5.0)
        out = place(out, seg, i * 0.055, 0.62 ** 0.0 * (0.9 - i * 0.06))
    shimmer = fast_lowpass(noise(0.4, 21), 9000) * np.exp(-np.linspace(0, 6, n_samples(0.4))) * 0.12
    out = place(out, shimmer, 0.03)
    return fade(reverb(out, 0.3, 0.35)[:n_samples(0.9)])


def sfx_correct() -> np.ndarray:
    """정답 — 밝은 장3화음 상승 + 반짝임."""
    seq = [(nn("C5"), 0.00), (nn("E5"), 0.075), (nn("G5"), 0.15), (nn("C6"), 0.225)]
    out = np.zeros(n_samples(1.0))
    for m, t in seq:
        seg = (osc(midi(m), 0.45, "soft") * adsr(0.45, 0.004, 0.10, 0.45, 0.30)
               + osc(midi(m + 12), 0.45, "sine") * adsr(0.45, 0.004, 0.08, 0.25, 0.30) * 0.3)
        out = place(out, seg, t, 0.85)
    sparkle = np.zeros(n_samples(1.0))
    for i, m in enumerate([nn("G6"), nn("C7"), nn("E7")]):
        s = osc(midi(m), 0.25, "sine") * perc_env(0.25, 0.001, 7.0) * 0.18
        sparkle = place(sparkle, s, 0.30 + i * 0.045)
    out += sparkle
    return fade(reverb(out, 0.26, 0.35)[:n_samples(1.25)])


def sfx_wrong() -> np.ndarray:
    """오답 — 혼내지 않는 부드러운 2음 하강. 저음/거친 배음 배제."""
    out = np.zeros(n_samples(0.75))
    for i, m in enumerate([nn("A4"), nn("F4")]):
        seg = osc(midi(m), 0.34, "soft") * adsr(0.34, 0.012, 0.10, 0.5, 0.20)
        out = place(out, seg, i * 0.16, 0.55)
    out = fast_lowpass(out, 2600)
    return fade(reverb(out, 0.2, 0.28)[:n_samples(0.95)])


def sfx_tongue() -> np.ndarray:
    """개구리 혀 발사 — 채찍처럼 쭉."""
    d = 0.30
    n = n_samples(d)
    f = np.concatenate([
        np.linspace(1800, 420, int(n * 0.55)),
        np.linspace(420, 260, n - int(n * 0.55)),
    ])
    body = osc(f, d, "sine") * perc_env(d, 0.002, 3.0)
    air = fast_lowpass(noise(d, 5), 4000) * perc_env(d, 0.001, 4.0) * 0.4
    return fade(body * 0.7 + air)


def sfx_snake_hit() -> np.ndarray:
    """뱀 명중 — 퍽 + 살짝 삑."""
    d = 0.28
    thud = osc(np.linspace(220, 70, n_samples(d)), d, "sine") * perc_env(d, 0.001, 5.5)
    crack = fast_lowpass(noise(0.09, 13), 5200) * perc_env(0.09, 0.0006, 7.0) * 0.5
    squeak = osc(np.linspace(1300, 900, n_samples(0.12)), 0.12, "square", 0.25) * perc_env(0.12, 0.002, 6.0) * 0.16
    out = thud
    out = place(out, crack, 0.0)
    out = place(out, squeak, 0.02)
    return fade(out)


def sfx_snake_die() -> np.ndarray:
    """뱀 처치 — 바람 빠지는 하강 + 뽕."""
    d = 0.55
    f = np.linspace(900, 180, n_samples(d))
    body = osc(f, d, "square", 0.35) * perc_env(d, 0.004, 2.6) * 0.35
    hiss = fast_lowpass(noise(d, 17), 3200) * perc_env(d, 0.002, 3.0) * 0.3
    pop = osc(np.linspace(500, 900, n_samples(0.10)), 0.10, "sine") * perc_env(0.10, 0.001, 6.0) * 0.45
    out = fast_lowpass(body + hiss, 3800)
    out = place(out, pop, 0.42)
    return fade(reverb(out, 0.2, 0.3)[:n_samples(0.8)])


def sfx_frog_hurt() -> np.ndarray:
    """개구리 피격 — 짧고 귀여운 '으윽'."""
    d = 0.26
    f = np.linspace(600, 300, n_samples(d))
    body = osc(f, d, "tri") * adsr(d, 0.006, 0.08, 0.4, 0.14)
    return fade(fast_lowpass(body, 2200) * 0.75)


def sfx_heart_lost() -> np.ndarray:
    d = 0.5
    out = np.zeros(n_samples(d))
    for i, m in enumerate([nn("E5"), nn("C5")]):
        seg = osc(midi(m), 0.3, "bell") * perc_env(0.3, 0.002, 4.0)
        out = place(out, seg, i * 0.11, 0.5)
    return fade(reverb(out, 0.25, 0.3)[:n_samples(0.7)])


def sfx_jump() -> np.ndarray:
    """개구리 점프 — 보잉."""
    d = 0.22
    f = np.concatenate([np.linspace(300, 780, n_samples(0.10)),
                        np.linspace(780, 520, n_samples(d) - n_samples(0.10))])
    body = osc(f, d, "tri") * perc_env(d, 0.003, 3.5)
    return fade(body * 0.6)


def _fanfare(notes, note_dur=0.16, gain=0.8, tail=0.6) -> np.ndarray:
    total = notes[-1][1] + note_dur + tail
    out = np.zeros(n_samples(total))
    seg_dur = note_dur + 0.25
    for m, t in notes:
        lead = osc(midi(m), seg_dur, "soft") * adsr(seg_dur, 0.005, 0.09, 0.4, 0.22)
        harm = osc(midi(m + 12), seg_dur, "sine") * adsr(seg_dur, 0.005, 0.07, 0.22, 0.22) * 0.28
        bass = osc(midi(m - 24), seg_dur, "tri") * adsr(seg_dur, 0.006, 0.10, 0.35, 0.18) * 0.35
        out = place(out, lead + harm + bass, t, gain)
    return out


def sfx_stage_clear() -> np.ndarray:
    """스테이지 클리어 — 짧은 팡파르."""
    notes = [(nn("C5"), 0.00), (nn("E5"), 0.13), (nn("G5"), 0.26),
             (nn("C6"), 0.39), (nn("G5"), 0.56), (nn("C6"), 0.68)]
    out = _fanfare(notes, 0.16, 0.7)
    return fade(reverb(out, 0.3, 0.4)[:n_samples(1.8)])


def sfx_world_clear() -> np.ndarray:
    """월드(보스) 클리어 — 더 크고 긴 팡파르."""
    notes = [(nn("G4"), 0.00), (nn("C5"), 0.12), (nn("E5"), 0.24), (nn("G5"), 0.36),
             (nn("C6"), 0.50), (nn("B5"), 0.72), (nn("C6"), 0.84), (nn("E6"), 1.02),
             (nn("G6"), 1.20)]
    out = _fanfare(notes, 0.18, 0.62)
    roll = fast_lowpass(noise(0.5, 31), 1200) * np.linspace(0, 1, n_samples(0.5)) ** 2 * 0.25
    out = place(out, roll, 0.0)
    return fade(reverb(out, 0.34, 0.45)[:n_samples(2.8)])


def sfx_game_over() -> np.ndarray:
    """하트 소진 — 실패가 아니라 '다시 해보자' 느낌의 부드러운 하강."""
    notes = [(nn("G5"), 0.0), (nn("E5"), 0.18), (nn("C5"), 0.36), (nn("G4"), 0.56)]
    out = np.zeros(n_samples(1.6))
    for m, t in notes:
        seg = osc(midi(m), 0.45, "soft") * adsr(0.45, 0.01, 0.12, 0.4, 0.28)
        out = place(out, seg, t, 0.6)
    return fade(reverb(fast_lowpass(out, 3000), 0.28, 0.35)[:n_samples(2.0)])


def sfx_star() -> np.ndarray:
    """결과 화면 별 하나가 채워질 때."""
    d = 0.55
    out = np.zeros(n_samples(d))
    for i, m in enumerate([nn("C6"), nn("G6")]):
        seg = osc(midi(m), 0.35, "bell") * perc_env(0.35, 0.002, 5.0)
        out = place(out, seg, i * 0.06, 0.7 - i * 0.2)
    return fade(reverb(out, 0.3, 0.35)[:n_samples(0.8)])


def sfx_unlock() -> np.ndarray:
    """새 월드 해금."""
    d = 1.0
    out = np.zeros(n_samples(d))
    for i, m in enumerate([nn("D5"), nn("F#5"), nn("A5"), nn("D6")]):
        seg = osc(midi(m), 0.5, "bell") * perc_env(0.5, 0.003, 3.6)
        out = place(out, seg, i * 0.09, 0.6)
    return fade(reverb(out, 0.34, 0.4)[:n_samples(1.5)])


# --------------------------------------------------------------------------- #
# 배경음악
# --------------------------------------------------------------------------- #
def _seq_track(events, wave_type, dur_scale=1.0, gain=1.0, duty=0.5,
               total=None, attack=0.006, release=0.12, sustain=0.6,
               vibrato=0.0) -> np.ndarray:
    """events: [(midi_or_None, start_sec, len_sec), ...]"""
    end = max(e[1] + e[2] for e in events) + release + 0.2
    out = np.zeros(n_samples(total if total else end))
    for m, st, ln in events:
        if m is None:
            continue
        ln = ln * dur_scale
        n = n_samples(ln)
        f = midi(m)
        if vibrato > 0.0:
            lfo = np.sin(2 * np.pi * 5.2 * (np.arange(n) / SR)) * vibrato
            freq = f * (2.0 ** (lfo / 12.0))
        else:
            freq = f
        seg = osc(freq, ln, wave_type, duty) * adsr(ln, attack, 0.06, sustain, release)
        out = place(out, seg, st, gain)
    return out


def _drum_track(pattern, total, kick_gain=0.5, hat_gain=0.16, snare_gain=0.3):
    out = np.zeros(n_samples(total))
    for kind, t in pattern:
        if kind == "k":
            d = 0.16
            seg = osc(np.linspace(150, 45, n_samples(d)), d, "sine") * perc_env(d, 0.001, 5.0)
            out = place(out, seg, t, kick_gain)
        elif kind == "h":
            d = 0.05
            seg = highpass(noise(d, int(t * 1000) % 997), 6000) * perc_env(d, 0.0005, 9.0)
            out = place(out, seg, t, hat_gain)
        elif kind == "s":
            d = 0.13
            body = fast_lowpass(noise(d, int(t * 977) % 991), 4200) * perc_env(d, 0.001, 5.0)
            tone = osc(np.linspace(320, 200, n_samples(d)), d, "tri") * perc_env(d, 0.001, 6.0) * 0.3
            out = place(out, body + tone, t, snare_gain)
    return out


def bgm_battle() -> np.ndarray:
    """전투(문제풀이) BGM — 밝은 다장조, 120BPM, 8마디 루프."""
    bpm = 116.0
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * 8

    # I - V - vi - IV  x2  (C - G - Am - F)
    chords = [
        (nn("C4"), [0, 4, 7]), (nn("G3"), [0, 4, 7]),
        (nn("A3"), [0, 3, 7]), (nn("F3"), [0, 4, 7]),
        (nn("C4"), [0, 4, 7]), (nn("G3"), [0, 4, 7]),
        (nn("A3"), [0, 3, 7]), (nn("F3"), [0, 4, 7]),
    ]

    # 리드 멜로디 (8분음표 기반, 개구리가 폴짝거리는 느낌)
    lead_pat = [
        # 마디별 (스케일 도수, 시작 박, 길이 박)
        [(0, 0.0, 0.5), (2, 0.5, 0.5), (4, 1.0, 1.0), (2, 2.0, 0.5), (4, 2.5, 0.5), (7, 3.0, 1.0)],
        [(7, 0.0, 0.5), (4, 0.5, 0.5), (2, 1.0, 1.0), (4, 2.0, 1.5), (None, 3.5, 0.5)],
        [(5, 0.0, 0.5), (7, 0.5, 0.5), (9, 1.0, 1.0), (7, 2.0, 0.5), (5, 2.5, 0.5), (4, 3.0, 1.0)],
        [(2, 0.0, 0.75), (4, 0.75, 0.25), (5, 1.0, 1.0), (4, 2.0, 0.5), (2, 2.5, 0.5), (0, 3.0, 1.0)],
        [(0, 0.0, 0.5), (4, 0.5, 0.5), (7, 1.0, 0.5), (9, 1.5, 0.5), (11, 2.0, 1.0), (9, 3.0, 1.0)],
        [(7, 0.0, 0.5), (9, 0.5, 0.5), (11, 1.0, 1.0), (12, 2.0, 2.0)],
        [(9, 0.0, 0.5), (7, 0.5, 0.5), (5, 1.0, 0.5), (4, 1.5, 0.5), (5, 2.0, 1.0), (7, 3.0, 1.0)],
        [(4, 0.0, 0.5), (2, 0.5, 0.5), (0, 1.0, 1.5), (None, 2.5, 0.5), (0, 3.0, 1.0)],
    ]
    major = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21]
    lead_events = []
    for bi, barpat in enumerate(lead_pat):
        for deg, st, ln in barpat:
            if deg is None:
                continue
            m = nn("C5") + major[deg]
            lead_events.append((m, bi * bar + st * beat, ln * beat * 0.92))

    bass_events = []
    chord_events = []
    for bi, (root, ivs) in enumerate(chords):
        t0 = bi * bar
        # 베이스: 루트 - 5도 - 루트 - 옥타브
        for k, off in enumerate([0, 7, 0, 12]):
            bass_events.append((root - 12 + off, t0 + k * beat, beat * 0.85))
        # 코드: 오프비트 스탭
        for k in range(4):
            for iv in ivs:
                chord_events.append((root + 12 + iv, t0 + k * beat + beat * 0.5, beat * 0.34))

    lead = _seq_track(lead_events, "square", gain=0.30, duty=0.34, total=total,
                      attack=0.006, release=0.09, sustain=0.65, vibrato=0.12)
    bass = _seq_track(bass_events, "tri", gain=0.42, total=total,
                      attack=0.004, release=0.06, sustain=0.7)
    pad = _seq_track(chord_events, "square", gain=0.085, duty=0.22, total=total,
                     attack=0.004, release=0.05, sustain=0.5)

    drums = []
    for bi in range(8):
        t0 = bi * bar
        drums += [("k", t0), ("k", t0 + beat * 2.5), ("s", t0 + beat), ("s", t0 + beat * 3)]
        for k in range(8):
            drums.append(("h", t0 + k * beat * 0.5))
    drum = _drum_track(drums, total, 0.42, 0.10, 0.20)

    mix = lead + bass + pad + drum
    mix = mix[:n_samples(total)]
    # 스테레오: 리드 살짝 오른쪽, 패드 왼쪽
    left = (lead[:n_samples(total)] * 0.85 + bass[:n_samples(total)]
            + pad[:n_samples(total)] * 1.15 + drum[:n_samples(total)])
    right = (lead[:n_samples(total)] * 1.15 + bass[:n_samples(total)]
             + pad[:n_samples(total)] * 0.85 + drum[:n_samples(total)])
    st = np.stack([left, right], axis=1)
    st = st / max(1e-9, float(np.max(np.abs(st)))) * 0.78
    return st


def bgm_menu() -> np.ndarray:
    """메뉴/월드맵 BGM — 느긋하고 포근한 4마디 루프."""
    bpm = 84.0
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * 8

    # C - Am - F - G  x2
    chords = [(nn("C4"), [0, 4, 7]), (nn("A3"), [0, 3, 7]),
              (nn("F3"), [0, 4, 7]), (nn("G3"), [0, 4, 7])] * 2

    major = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16]
    lead_pat = [
        [(4, 0.0, 1.0), (2, 1.0, 1.0), (0, 2.0, 1.5), (2, 3.5, 0.5)],
        [(4, 0.0, 1.5), (5, 1.5, 0.5), (4, 2.0, 2.0)],
        [(2, 0.0, 1.0), (4, 1.0, 1.0), (5, 2.0, 2.0)],
        [(7, 0.0, 1.0), (5, 1.0, 1.0), (4, 2.0, 1.0), (2, 3.0, 1.0)],
        [(0, 0.0, 1.0), (4, 1.0, 1.0), (7, 2.0, 2.0)],
        [(9, 0.0, 1.5), (7, 1.5, 0.5), (5, 2.0, 2.0)],
        [(4, 0.0, 1.0), (5, 1.0, 1.0), (7, 2.0, 2.0)],
        [(4, 0.0, 1.0), (2, 1.0, 1.0), (0, 2.0, 2.0)],
    ]
    lead_events = []
    for bi, barpat in enumerate(lead_pat):
        for deg, st_, ln in barpat:
            lead_events.append((nn("C5") + major[deg], bi * bar + st_ * beat, ln * beat * 0.95))

    arp_events = []
    bass_events = []
    for bi, (root, ivs) in enumerate(chords):
        t0 = bi * bar
        bass_events.append((root - 12, t0, beat * 1.8))
        bass_events.append((root - 12 + 7, t0 + beat * 2, beat * 1.8))
        seq = [ivs[0], ivs[1], ivs[2], ivs[1]] * 2
        for k, iv in enumerate(seq):
            arp_events.append((root + 12 + iv, t0 + k * beat * 0.5, beat * 0.45))

    lead = _seq_track(lead_events, "soft", gain=0.32, total=total,
                      attack=0.03, release=0.25, sustain=0.6, vibrato=0.08)
    arp = _seq_track(arp_events, "sine", gain=0.16, total=total,
                     attack=0.006, release=0.14, sustain=0.5)
    bass = _seq_track(bass_events, "tri", gain=0.30, total=total,
                      attack=0.01, release=0.2, sustain=0.6)

    left = lead[:n_samples(total)] * 0.9 + arp[:n_samples(total)] * 1.2 + bass[:n_samples(total)]
    right = lead[:n_samples(total)] * 1.1 + arp[:n_samples(total)] * 0.8 + bass[:n_samples(total)]
    st = np.stack([left, right], axis=1)
    st = st / max(1e-9, float(np.max(np.abs(st)))) * 0.7
    return st


# --------------------------------------------------------------------------- #
BUILDERS = {
    "ui_tap": (sfx_ui_tap, 3, False),
    "answer_pick": (sfx_answer_pick, 3, False),
    "block_pop": (sfx_block_pop, 4, False),
    "block_snap": (sfx_block_snap, 4, False),
    "count_tick": (sfx_count_tick, 3, False),
    "merge": (sfx_merge, 4, False),
    "ten_bundle": (sfx_ten_bundle, 4, False),
    "correct": (sfx_correct, 5, False),
    "wrong": (sfx_wrong, 4, False),
    "tongue": (sfx_tongue, 4, False),
    "snake_hit": (sfx_snake_hit, 4, False),
    "snake_die": (sfx_snake_die, 4, False),
    "frog_hurt": (sfx_frog_hurt, 4, False),
    "heart_lost": (sfx_heart_lost, 4, False),
    "jump": (sfx_jump, 3, False),
    "star": (sfx_star, 4, False),
    "stage_clear": (sfx_stage_clear, 5, False),
    "world_clear": (sfx_world_clear, 5, False),
    "game_over": (sfx_game_over, 4, False),
    "unlock": (sfx_unlock, 4, False),
    "bgm_battle": (bgm_battle, 5, True),
    "bgm_menu": (bgm_menu, 5, True),
}


def main() -> int:
    if shutil.which("ffmpeg") is None:
        print("ffmpeg 가 필요합니다: sudo apt install ffmpeg", file=sys.stderr)
        return 1
    wanted = sys.argv[1:] or list(BUILDERS)
    unknown = [w for w in wanted if w not in BUILDERS]
    if unknown:
        print(f"알 수 없는 항목: {unknown}\n가능: {list(BUILDERS)}", file=sys.stderr)
        return 1
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"-> {OUT_DIR}")
    for name in wanted:
        fn, q, stereo = BUILDERS[name]
        write_ogg(name, fn(), q, stereo)
    total = sum(os.path.getsize(os.path.join(OUT_DIR, f))
                for f in os.listdir(OUT_DIR) if f.endswith(".ogg"))
    print(f"총 {total / 1024:.1f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
