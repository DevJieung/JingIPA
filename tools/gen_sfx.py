#!/usr/bin/env python3
"""효과음을 **코드로 합성**해서 art/sfx/*.wav 로 만든다.

    python3 tools/gen_sfx.py          # 전부 (1초쯤)
    python3 tools/gen_sfx.py --list
    python3 tools/gen_sfx.py --only shot_fire,leak

왜 합성인가: 이 저장소에는 외부 음원이 없다. 받아 오면 (1) 라이선스를 따라다녀야 하고
(2) 서른 개가 몇 메가라 APK 가 그만큼 커진다. 여기서 만드는 것은 전부 사인파·톱니·잡음에
포락선을 씌운 것이라 **한 파일이 5~20KB** 이고, 무엇보다 표를 고치면 소리가 같이 바뀐다.

★ 소리도 규칙을 말해야 한다. 이 게임의 규칙은 「속성이 상태이상을 정한다」이므로
  발사음도 **속성마다** 다르다 — 불은 거칠고, 얼음은 맑고, 전기는 지직거리고,
  물은 둥글고, 무상성은 마른 딱 소리다. 눈을 감고도 무엇이 나가는지 알 수 있어야 한다.
★ 크기(peak)를 0.5 언저리로 맞춘다. 전투에서는 여섯 영웅이 초당 열 발을 쏘므로,
  하나가 꽉 차 있으면 겹치는 순간 통째로 깨진다.
"""
from __future__ import annotations

import argparse
import os
import struct
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "sfx")
SR = 22050

rng = np.random.default_rng(20260828)


# --------------------------------------------------------------------------- #
# 재료
# --------------------------------------------------------------------------- #
def t(sec: float) -> np.ndarray:
	return np.arange(int(SR * sec), dtype=np.float64) / SR


def env(n: int, a: float, d: float, s: float = 0.0, r: float = 0.0) -> np.ndarray:
	"""어택-디케이-서스테인-릴리스. 값은 전부 **초 단위 비율이 아니라 초**다."""
	out = np.zeros(n)
	ai = max(1, int(a * SR))
	di = max(1, int(d * SR))
	ri = max(1, int(r * SR))
	si = max(0, n - ai - di - ri)
	i = 0
	out[i:i + ai] = np.linspace(0.0, 1.0, ai)
	i += ai
	out[i:i + di] = np.linspace(1.0, s if si or ri else 0.0, di)
	i += di
	if si:
		out[i:i + si] = s
		i += si
	if ri and i < n:
		out[i:] = np.linspace(out[i - 1] if i else 0.0, 0.0, n - i)
	return out[:n]


def expdec(n: int, k: float) -> np.ndarray:
	"""지수로 꺼지는 포락선. 타악기는 이쪽이 훨씬 자연스럽다."""
	return np.exp(-np.linspace(0.0, k, n))


def tone(sec: float, f0: float, f1: float | None = None, kind: str = "sin",
		 detune: float = 0.0) -> np.ndarray:
	x = t(sec)
	n = len(x)
	f = np.full(n, f0) if f1 is None else np.linspace(f0, f1, n)
	ph = 2.0 * np.pi * np.cumsum(f) / SR
	if kind == "saw":
		y = 2.0 * ((ph / (2.0 * np.pi)) % 1.0) - 1.0
	elif kind == "sq":
		y = np.sign(np.sin(ph))
	elif kind == "tri":
		y = 2.0 * np.abs(2.0 * ((ph / (2.0 * np.pi)) % 1.0) - 1.0) - 1.0
	else:
		y = np.sin(ph)
	if detune:
		y = 0.5 * y + 0.5 * np.sin(ph * (1.0 + detune))
	return y


def noise(sec: float) -> np.ndarray:
	return rng.uniform(-1.0, 1.0, int(SR * sec))


def lowpass(x: np.ndarray, cut: float) -> np.ndarray:
	"""한 극 저역통과. 잡음을 그대로 쓰면 전부 「치익」으로만 들린다."""
	a = np.exp(-2.0 * np.pi * cut / SR)
	y = np.empty_like(x)
	acc = 0.0
	for i in range(len(x)):
		acc = (1.0 - a) * x[i] + a * acc
		y[i] = acc
	return y


def highpass(x: np.ndarray, cut: float) -> np.ndarray:
	return x - lowpass(x, cut)


def mix(*parts: np.ndarray) -> np.ndarray:
	n = max(len(p) for p in parts)
	out = np.zeros(n)
	for p in parts:
		out[:len(p)] += p
	return out


def at(x: np.ndarray, delay: float, total: float) -> np.ndarray:
	"""x 를 delay 초 뒤에 놓은 total 초짜리 트랙."""
	out = np.zeros(int(SR * total))
	i = int(SR * delay)
	m = min(len(out) - i, len(x))
	if m > 0:
		out[i:i + m] = x[:m]
	return out


def norm(x: np.ndarray, peak: float = 0.5) -> np.ndarray:
	m = float(np.max(np.abs(x))) or 1.0
	return x * (peak / m)


def save(name: str, x: np.ndarray, peak: float = 0.5) -> int:
	x = norm(x, peak)
	# 끝을 3ms 로 재운다. 안 재우면 파형이 뚝 끊겨 「딱」 하는 잡음이 붙는다.
	k = min(len(x), int(SR * 0.003))
	if k > 1:
		x[-k:] *= np.linspace(1.0, 0.0, k)
	pcm = np.clip(x, -1.0, 1.0)
	data = (pcm * 32767.0).astype("<i2").tobytes()
	os.makedirs(OUT, exist_ok=True)
	p = os.path.join(OUT, name + ".wav")
	with wave.open(p, "wb") as f:
		f.setnchannels(1)
		f.setsampwidth(2)
		f.setframerate(SR)
		f.writeframes(data)
	return len(data) + 44


# --------------------------------------------------------------------------- #
# 소리 하나하나
#
# 이름은 core/sound.gd 의 Sfx.play("...") 와 **정확히 같아야 한다.**
# ★ 표를 두 곳에 두지 않으려고 여기 한 곳에서만 이름을 짓는다. ns_check 가
#   game/ 에서 부르는 이름이 실제로 있는 파일인지 검사한다.
# --------------------------------------------------------------------------- #
def s_shot_none():
	# 마른 딱 소리 — 활·총·표창. 잡음 짧게 + 낮은 몸통 하나.
	n = noise(0.06) * expdec(int(SR * 0.06), 26.0)
	b = tone(0.06, 320.0, 150.0) * expdec(int(SR * 0.06), 18.0)
	return mix(highpass(n, 900.0) * 0.7, b * 0.6)


def s_shot_fire():
	# 거친 숨 — 저역 잡음이 확 나갔다 꺼진다.
	n = lowpass(noise(0.20), 1400.0) * expdec(int(SR * 0.20), 9.0)
	b = tone(0.20, 180.0, 70.0, "saw") * expdec(int(SR * 0.20), 12.0)
	return mix(n * 0.9, b * 0.35)


def s_shot_ice():
	# 맑은 유리 — 높은 사인 둘이 살짝 어긋나 떨린다.
	a = tone(0.22, 1760.0, 1500.0) * expdec(int(SR * 0.22), 11.0)
	b = tone(0.22, 2640.0, 2300.0) * expdec(int(SR * 0.22), 15.0)
	c = highpass(noise(0.05), 4000.0) * expdec(int(SR * 0.05), 20.0)
	return mix(a * 0.7, b * 0.35, c * 0.3)


def s_shot_elec():
	# 지직 — 잡음을 사각파로 잘라 낸다. 매끈하면 광선과 구별이 안 된다.
	n = int(SR * 0.16)
	g = (np.sign(np.sin(np.linspace(0, 2 * np.pi * 70, n))) * 0.5 + 0.5)
	x = highpass(noise(0.16), 1500.0) * g * expdec(n, 10.0)
	b = tone(0.16, 900.0, 420.0, "sq") * expdec(n, 14.0)
	return mix(x * 0.9, b * 0.25)


def s_shot_water():
	# 둥근 물방울 — 아래로 떨어지는 사인.
	a = tone(0.18, 900.0, 380.0) * expdec(int(SR * 0.18), 12.0)
	b = lowpass(noise(0.08), 700.0) * expdec(int(SR * 0.08), 16.0)
	return mix(a * 0.8, b * 0.35)


def s_shot_beam():
	# 광선 — 위로 올라가 잠깐 버틴다.
	n = int(SR * 0.30)
	a = tone(0.30, 420.0, 1150.0, "saw") * env(n, 0.02, 0.06, 0.55, 0.16)
	b = tone(0.30, 840.0, 2300.0) * env(n, 0.02, 0.08, 0.30, 0.16)
	return mix(a * 0.5, b * 0.35)


def s_shot_zone():
	# 장판 — **땅에 내려앉는** 소리다. 아래로 떨어지는 울림에 한 번의 쿵.
	# ★ 옛 shot_aura 는 그냥 낮게 깔린 울림이었다. 지금 장판은 「지목한 자리에
	#   내려앉는다」이므로 소리도 내려앉아야 한다 — 주파수가 **떨어져야** 한다.
	n = int(SR * 0.38)
	a = tone(0.38, 210.0, 96.0) * env(n, 0.03, 0.12, 0.30, 0.20)
	b = tone(0.38, 318.0, 140.0, "tri") * env(n, 0.04, 0.14, 0.22, 0.18)
	c = lowpass(noise(0.10), 900.0) * expdec(int(SR * 0.10), 20.0)
	return mix(a * 0.7, b * 0.35, at(c * 0.5, 0.0, 0.38))


def s_ric():
	# 도탄 — **쇠가 튕기는** 짧고 높은 소리. 연쇄(chain)의 지직거림과 결이 반대여야
	# 한다: 연쇄는 번개고 도탄은 물건이다. 그래서 잡음이 아니라 **맑은 한 점**이다.
	n = int(SR * 0.11)
	a = tone(0.11, 1750.0, 2450.0) * expdec(n, 26.0)
	b = tone(0.11, 2600.0, 3400.0, "tri") * expdec(n, 34.0)
	return mix(a * 0.42, b * 0.22)


def s_hit():
	n = noise(0.05) * expdec(int(SR * 0.05), 30.0)
	b = tone(0.05, 260.0, 120.0) * expdec(int(SR * 0.05), 22.0)
	return mix(lowpass(n, 2600.0) * 0.6, b * 0.7)


def s_hit_weak():
	# 약점 — **두 배로 들어갔다**는 것이 소리로도 커야 한다. 위로 뛰는 3화음.
	p = []
	for i, f in enumerate((523.0, 784.0, 1046.0)):
		p.append(at(tone(0.13, f, f * 1.06) * expdec(int(SR * 0.13), 9.0), i * 0.028, 0.26))
	n = at(highpass(noise(0.07), 2000.0) * expdec(int(SR * 0.07), 16.0), 0.0, 0.26)
	return mix(*p, n * 0.4)


def s_hit_resist():
	# 저항 — 답답하게 막힌 소리. 저역만 남긴다.
	n = lowpass(noise(0.09), 500.0) * expdec(int(SR * 0.09), 16.0)
	b = tone(0.09, 150.0, 96.0) * expdec(int(SR * 0.09), 18.0)
	return mix(n * 0.7, b * 0.5)


def s_hit_immune():
	# 무효 — 쇠에 튕긴 소리. 아무 일도 안 일어났다는 뜻이 담겨야 한다.
	a = tone(0.16, 1400.0, 1360.0, "sq") * expdec(int(SR * 0.16), 20.0)
	b = tone(0.16, 2100.0, 2050.0) * expdec(int(SR * 0.16), 26.0)
	c = highpass(noise(0.04), 5000.0) * expdec(int(SR * 0.04), 24.0)
	return mix(a * 0.4, b * 0.3, c * 0.5)


def s_crit():
	p = []
	for i, f in enumerate((880.0, 1320.0, 1760.0, 2640.0)):
		p.append(at(tone(0.10, f) * expdec(int(SR * 0.10), 12.0), i * 0.02, 0.24))
	return mix(*p)


def s_splash():
	# 광역이 터진다 — 저역이 확 꺼지고 파편이 흩어진다.
	n = int(SR * 0.42)
	low = tone(0.42, 220.0, 45.0, "saw") * expdec(n, 7.0)
	body = lowpass(noise(0.42), 1100.0) * expdec(n, 6.0)
	deb = highpass(noise(0.42), 2600.0) * expdec(n, 3.5) * 0.5
	return mix(low * 0.8, body * 0.9, deb * 0.5)


def s_chain():
	p = []
	for i in range(3):
		f = 1200.0 * (1.0 + 0.35 * i)
		g = np.sign(np.sin(np.linspace(0, 2 * np.pi * 90, int(SR * 0.09)))) * 0.5 + 0.5
		p.append(at(highpass(noise(0.09), 1800.0) * g * expdec(int(SR * 0.09), 14.0)
					+ tone(0.09, f, f * 0.6, "sq") * expdec(int(SR * 0.09), 16.0) * 0.4,
					i * 0.05, 0.28))
	return mix(*p)


def s_die():
	n = int(SR * 0.26)
	a = lowpass(noise(0.26), 1500.0) * expdec(n, 9.0)
	b = tone(0.26, 300.0, 90.0, "tri") * expdec(n, 10.0)
	return mix(a * 0.7, b * 0.6)


def s_die_big():
	n = int(SR * 0.9)
	a = lowpass(noise(0.9), 700.0) * expdec(n, 3.4)
	b = tone(0.9, 160.0, 32.0, "saw") * expdec(n, 3.0)
	c = highpass(noise(0.5), 2200.0) * expdec(int(SR * 0.5), 4.0)
	return mix(a * 0.9, b * 0.9, c * 0.35)


def s_leak():
	# 크리스탈이 깨진다 — 이 게임에서 제일 아픈 소리. 유리가 깨지고 아래로 떨어진다.
	n = int(SR * 0.7)
	glass = highpass(noise(0.7), 3000.0) * expdec(n, 5.0)
	fall = tone(0.7, 900.0, 120.0, "tri") * expdec(n, 4.0)
	thud = tone(0.7, 90.0, 40.0) * expdec(n, 6.0)
	return mix(glass * 0.8, fall * 0.5, thud * 0.7)


def s_block():
	a = tone(0.22, 620.0, 900.0) * expdec(int(SR * 0.22), 9.0)
	b = tone(0.22, 1240.0, 1800.0) * expdec(int(SR * 0.22), 12.0)
	return mix(a * 0.6, b * 0.3)


def s_stun():
	n = int(SR * 0.30)
	g = np.sign(np.sin(np.linspace(0, 2 * np.pi * 42, n))) * 0.5 + 0.5
	return highpass(noise(0.30), 1200.0) * g * expdec(n, 7.0)


def s_frost():
	a = tone(0.35, 2200.0, 1400.0) * expdec(int(SR * 0.35), 8.0)
	b = highpass(noise(0.35), 4500.0) * expdec(int(SR * 0.35), 7.0)
	return mix(a * 0.5, b * 0.5)


def s_wave():
	# 탄이 시작된다 — 낮은 북 하나에 뿔피리.
	n = int(SR * 0.8)
	drum = tone(0.8, 120.0, 55.0) * expdec(n, 8.0)
	horn = at(mix(tone(0.55, 330.0, 330.0, "saw"), tone(0.55, 440.0, 440.0, "saw") * 0.6)
			  * env(int(SR * 0.55), 0.05, 0.10, 0.55, 0.24), 0.12, 0.8)
	return mix(drum * 0.9, horn * 0.5)


def s_boss():
	# 보스 등장 — 낮게 으르렁대다 위로 한 번 치솟는다.
	n = int(SR * 1.5)
	growl = tone(1.5, 70.0, 52.0, "saw", detune=0.012) * env(n, 0.20, 0.30, 0.6, 0.6)
	rumble = lowpass(noise(1.5), 260.0) * env(n, 0.25, 0.35, 0.55, 0.6)
	stab = at(tone(0.5, 200.0, 620.0, "sq") * expdec(int(SR * 0.5), 6.0), 0.85, 1.5)
	return mix(growl * 0.8, rumble * 0.7, stab * 0.35)


def s_victory():
	p = []
	for i, f in enumerate((523.0, 659.0, 784.0, 1046.0)):
		p.append(at(mix(tone(0.55, f), tone(0.55, f * 2.0) * 0.4)
					* env(int(SR * 0.55), 0.01, 0.12, 0.5, 0.3), i * 0.11, 1.2))
	return mix(*p)


def s_defeat():
	p = []
	for i, f in enumerate((392.0, 330.0, 262.0, 196.0)):
		p.append(at(mix(tone(0.7, f, f * 0.985, "tri"), tone(0.7, f * 0.5) * 0.5)
					* env(int(SR * 0.7), 0.02, 0.18, 0.4, 0.4), i * 0.17, 1.5))
	return mix(*p)


def s_button():
	return tone(0.05, 700.0, 520.0, "sq") * expdec(int(SR * 0.05), 20.0) * 0.8


def s_buy():
	p = [at(tone(0.09, f) * expdec(int(SR * 0.09), 13.0), i * 0.05, 0.24)
		 for i, f in enumerate((880.0, 1320.0))]
	coin = at(highpass(noise(0.10), 3500.0) * expdec(int(SR * 0.10), 12.0), 0.0, 0.24)
	return mix(*p, coin * 0.4)


def s_deal():
	# 카드가 놓이는 소리 — 짧은 종이 마찰.
	return highpass(noise(0.08), 2200.0) * expdec(int(SR * 0.08), 22.0)


def s_flip():
	a = highpass(noise(0.11), 1800.0) * expdec(int(SR * 0.11), 16.0)
	b = tone(0.11, 520.0, 900.0) * expdec(int(SR * 0.11), 18.0)
	return mix(a * 0.7, b * 0.3)


def s_theme():
	# 테마 판이 뜬다 — 아래에서 위로 쓸어 올린다.
	n = int(SR * 0.9)
	sweep = highpass(noise(0.9), 500.0) * env(n, 0.35, 0.05, 0.2, 0.5)
	up = tone(0.9, 180.0, 720.0, "tri") * env(n, 0.30, 0.10, 0.35, 0.4)
	return mix(sweep * 0.45, up * 0.6)


def _reveal(fs, sec, peak_extra=1.0):
	p = []
	for i, f in enumerate(fs):
		p.append(at(mix(tone(sec, f), tone(sec, f * 2.0) * 0.35)
					* env(int(SR * sec), 0.008, 0.10, 0.45, sec * 0.4), i * (sec * 0.30),
					sec + sec * 0.30 * len(fs)))
	return mix(*p) * peak_extra


def s_reveal0():
	return _reveal((392.0,), 0.30)


def s_reveal1():
	return _reveal((392.0, 494.0), 0.30)


def s_reveal2():
	return _reveal((392.0, 494.0, 587.0), 0.30)


def s_reveal3():
	return _reveal((523.0, 659.0, 784.0), 0.32)


def s_reveal4():
	return _reveal((523.0, 659.0, 784.0, 880.0), 0.34)


def s_reveal5():
	return _reveal((587.0, 740.0, 880.0, 1109.0), 0.34)


def s_reveal6():
	# 풀하우스부터는 **화려해진다** — 아래에 낮은 북을 깐다.
	body = _reveal((523.0, 659.0, 784.0, 1046.0), 0.36)
	drum = at(tone(0.6, 110.0, 46.0) * expdec(int(SR * 0.6), 7.0), 0.0, len(body) / SR)
	return mix(body, drum * 0.7)


def s_reveal7():
	body = _reveal((587.0, 740.0, 880.0, 1175.0, 1480.0), 0.34)
	drum = at(tone(0.7, 120.0, 44.0) * expdec(int(SR * 0.7), 6.0), 0.0, len(body) / SR)
	return mix(body, drum * 0.8)


def s_reveal8():
	body = _reveal((659.0, 831.0, 988.0, 1319.0, 1661.0), 0.34)
	drum = at(tone(0.8, 130.0, 42.0) * expdec(int(SR * 0.8), 5.0), 0.0, len(body) / SR)
	shine = at(highpass(noise(0.9), 4000.0) * expdec(int(SR * 0.9), 4.0),
			   0.1, len(body) / SR)
	return mix(body, drum * 0.8, shine * 0.35)


def s_reveal9():
	# 로열 — 게임 전체에서 가장 드문 순간. 아낌없이 준다.
	body = _reveal((784.0, 988.0, 1175.0, 1568.0, 1976.0, 2349.0), 0.36)
	drum = at(tone(1.1, 140.0, 40.0) * expdec(int(SR * 1.1), 4.0), 0.0, len(body) / SR)
	bell = at(mix(tone(1.4, 2093.0), tone(1.4, 3136.0) * 0.5)
			  * expdec(int(SR * 1.4), 4.0), 0.25, len(body) / SR)
	shine = at(highpass(noise(1.4), 3500.0) * expdec(int(SR * 1.4), 3.0),
			   0.05, len(body) / SR)
	return mix(body, drum * 0.9, bell * 0.5, shine * 0.4)


def s_stack():
	# 겹쳤다 — 같은 음이 네 번 빠르게 겹쳐 쌓인다. 「x4」의 소리다.
	p = [at(tone(0.18, 660.0 * (1.0 + 0.12 * i)) * expdec(int(SR * 0.18), 10.0),
			i * 0.045, 0.4) for i in range(4)]
	return mix(*p)


def s_gain():
	# 새 영웅이 왔다.
	p = [at(tone(0.16, f) * expdec(int(SR * 0.16), 9.0), i * 0.055, 0.36)
		 for i, f in enumerate((523.0, 784.0))]
	return mix(*p)


SOUNDS = {
	"shot_none": s_shot_none, "shot_fire": s_shot_fire, "shot_ice": s_shot_ice,
	"shot_elec": s_shot_elec, "shot_water": s_shot_water,
	"shot_beam": s_shot_beam, "shot_zone": s_shot_zone, "ric": s_ric,
	"hit": s_hit, "hit_weak": s_hit_weak, "hit_resist": s_hit_resist,
	"hit_immune": s_hit_immune, "crit": s_crit,
	"splash": s_splash, "chain": s_chain,
	"die": s_die, "die_big": s_die_big, "leak": s_leak, "block": s_block,
	"stun": s_stun, "frost": s_frost,
	"wave": s_wave, "boss": s_boss, "victory": s_victory, "defeat": s_defeat,
	"button": s_button, "buy": s_buy, "deal": s_deal, "flip": s_flip,
	"theme": s_theme, "stack": s_stack, "gain": s_gain,
	"reveal0": s_reveal0, "reveal1": s_reveal1, "reveal2": s_reveal2,
	"reveal3": s_reveal3, "reveal4": s_reveal4, "reveal5": s_reveal5,
	"reveal6": s_reveal6, "reveal7": s_reveal7, "reveal8": s_reveal8,
	"reveal9": s_reveal9,
}

# 소리마다 크기를 조금씩 다르게. 발사음은 초당 열 번씩 나므로 작게, 크리스탈이
# 깨지는 소리는 그 판에서 제일 아픈 순간이라 크게.
PEAK = {
	"shot_none": 0.26, "shot_fire": 0.26, "shot_ice": 0.26, "shot_elec": 0.26,
	"shot_water": 0.26, "shot_beam": 0.30, "shot_zone": 0.26, "ric": 0.30,
	"hit": 0.22, "hit_resist": 0.20, "hit_weak": 0.40, "hit_immune": 0.30,
	"crit": 0.38, "splash": 0.42, "chain": 0.32,
	"die": 0.26, "die_big": 0.62, "leak": 0.72, "block": 0.40,
	"stun": 0.30, "frost": 0.28,
	"wave": 0.55, "boss": 0.70, "victory": 0.62, "defeat": 0.58,
	"button": 0.32, "buy": 0.40, "deal": 0.24, "flip": 0.30,
	"theme": 0.45, "stack": 0.48, "gain": 0.44,
}


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--list", action="store_true")
	ap.add_argument("--check", action="store_true", help="파일을 고치지 않고 효과음 확인")
	ap.add_argument("--only", default="")
	ap.add_argument("--legacy-synth", action="store_true", help="이전 합성음을 명시적으로 다시 생성")
	a = ap.parse_args()
	if os.path.exists(os.path.join(ROOT, "art", "audio-manifest.json")) and not a.legacy_synth:
		if a.check:
			import subprocess
			import sys
			return subprocess.call([sys.executable, os.path.join(ROOT, "tools", "audio", "check_audio.py")])
		if not a.list:
			print("출고 음원은 ElevenLabs로 교체되었습니다. tools/audio/generate_elevenlabs.py --install을 사용하세요.")
			return 1
	if a.list:
		for k in sorted(SOUNDS):
			print(k)
		return 0
	want = [w for w in a.only.split(",") if w] or sorted(SOUNDS)
	if a.check:
		try:
			for name in want:
				with wave.open(os.path.join(OUT, name + ".wav"), "rb") as wav:
					if wav.getnframes() <= 0 or wav.getframerate() != SR or wav.getnchannels() != 1:
						raise ValueError("잘못된 효과음: " + name)
		except (OSError, wave.Error, ValueError) as exc:
			print(exc)
			return 1
		print("효과음 %d개 정상 (파일 수정 없음)" % len(want))
		return 0
	total = 0
	for k in want:
		if k not in SOUNDS:
			print("그런 소리는 없습니다: %s" % k)
			return 1
		total += save(k, SOUNDS[k](), PEAK.get(k, 0.5))
	print("소리 %d개를 만들었습니다 (%s, 합계 %.0fKB)" % (len(want), OUT, total / 1024.0))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
