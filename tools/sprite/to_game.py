#!/usr/bin/env python3
"""Step 4 — 구운 시트를 **게임이 읽는 자리**로 옮긴다.

  build/sprite/<route>/sheets/unit_<id>_<anim>_96x96_<n>.png
      ↓
  art/anim/<id>/<id>_idle.png · <id>_attack.png · anim.json

★★ **왜 옛 길(`tools/anim/`)의 파일 꼴을 그대로 쓰는가.**
  `core/anim.gd` 가 읽는 꼴이 그것이다. 새 꼴을 하나 더 만들면 형식이 둘이 되고,
  둘 중 하나만 고치는 날 조용히 어긋난다 (`Anim._meta` 머리말이 못 박은 것).
  시트는 이미 **가로로 이어 붙인 스트립**이라 `Anim.clip()` 이 그대로 읽는다 —
  옮길 것은 사실 곁딸린 숫자 넷뿐이다: 기준점 · 배율 · 총구 · 놓는 칸.

이 도구가 재는 넷:

  **기준점**(anchor)  가로는 **발**의 가운데, 세로는 발밑.
      ☆ 칸 가운데(48)를 쓰면 안 된다. 공통 크롭 상자는 채찍 호와 치켜든 팔까지
        아우르므로 그 가운데는 **몸의 가운데가 아니다** — 채찍잡이는 통째로
        한쪽으로 밀려 서고, 발밑 그림자와 등급 고리가 발이 아닌 곳에 그려진다.

  **배율**(scale)     시트는 등급과 상관없이 언제나 96x96 인데, 게임의 그림 높이는
      등급마다 다르다(96~141px). 그대로 그리면 로열이 하이카드와 같은 키가 된다.
      ☆ 자는 **정지 그림과 같은 것**이어야 한다 — 정지 그림은 몸을 바짝 자른
        상자의 높이가 곧 `unit_h(등급)` 이다. 그래서 아이들 0번 칸의 몸 높이를
        재서 `unit_h / 그 높이` 를 배율로 준다. 그러면 편성 판(정지 그림)과
        전투 화면(클립)에서 같은 사람이 같은 키로 선다.

  **총구**(muzzle_at) 놓는 칸에서, 몸통 위쪽 절반의 **제일 앞선 점**.
      ☆ 광역(raise)만 다르다 — 탄이 안 나가고 두 팔을 들 뿐이라, 손 높이
        (몸 높이의 0.62 지점)를 준다. **가로는 거리로 재고 하한을 못 박는다**
        (RAISE_MIN_X_OF_H) — 뜻 없는 1px 이 그림을 뒤집기 때문이다.
      ☆ 스프라이트는 **오른쪽을 본다**(지침 §0-2 · Wan 프롬프트). 그래서 가로는
        늘 양수이고, `Balance.art_aim()` 이 그 부호를 보고 좌우를 정한다 —
        음수면 화면이 그림을 뒤집는다. 뒤집을 그림이 없으므로 양수여야 맞다.
        ★ 그래서 `one()` 이 마지막에 **부호를 한 번 더 확인한다**. 여기서 새는
          날 그 캐릭터만 조용히 거꾸로 서고, 화면 말고는 아무 데도 안 적힌다.

  **놓는 칸**(hit_ms) `sprite_post.pick()` 이 임팩트를 **5번 자리**에 맞춰 놓았으므로
      5 x (1000/12) = **417ms** 다.
      ☆★ **다시 재지 않고 그 자리를 믿는다.** 처음에는 시트에서 다시 쟀는데, 그 자는
        「0번에서 가장 먼 칸」이라 뒤쪽 칸이 뽑히기 쉽다 — 실측으로 림네가 9번(750ms)이
        나왔고 `ns_check` 의 「뻗는 시간은 0.05~0.50초」에 걸렸다. `pick` 이 놓은
        자리가 곧 정답인데 그것을 버리고 다시 잰 것이 잘못이었다.
      ☆ 대신 **어긋나면 알려 준다** — 다시 잰 값이 두 칸 넘게 떨어져 있으면 그 클립은
        `pick` 이 겨눈 자리에 임팩트가 안 온 것이라 눈으로 봐야 한다.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))

import gen_art          # noqa: E402  — unit_h(등급) 를 여기서만 정의한다
import pixels           # noqa: E402
import sprite_post      # noqa: E402
import units as U       # noqa: E402

OUT = os.path.join(ROOT, "build", "sprite")
DST = os.path.join(ROOT, "art", "anim")

#: 손 높이 — 몸 높이의 위에서부터 이만큼. 광역(raise)의 총구가 여기 선다.
HAND_OF_H = 0.62

#: ★★ 광역(raise)의 총구 **가로 하한** — 몸 높이의 이만큼. 반드시 양수다.
#:
#: 광역은 탄이 캐릭터에서 안 나가므로(장판은 저 멀리 깔린다) 이 값의 **부호에는
#: 뜻이 없다.** 그런데 부호가 **그림의 방향**을 정한다 — `Balance.art_aim()` 이
#: `muz[0] < 0` 이면 그 캐릭터를 통째로 좌우 반전해서 그린다(CLAUDE.md 18-11).
#: 뜻 없는 1px 이 그림을 뒤집는 셈이다.
#:
#: 실측으로 그 일이 났다: 브라사의 몸통 가운데가 발 가운데보다 **1px 왼쪽**이라
#: `muzzle_at.x = -1` 이 나왔고, 게임이 브라사만 좌우로 뒤집어 그리고 있었다.
#: 비다르는 `+1` 로 아슬아슬하게 살아 있었다 — 클립을 다시 구우면 언제든 넘어간다.
#:
#: 그래서 가로는 **거리(절댓값)로 재고 하한을 못 박는다.** 하한을 0.05h 로 잡은 것은
#: `ns_check._check_muzzle` 이 **다른 무기 마흔 명에게** 요구하는 하한과 같은 값이라
#: 그것이다 — 장판은 그 검사에서 면제지만, 면제라고 안 지킬 까닭은 없다.
RAISE_MIN_X_OF_H = 0.05

#: 놓는 칸의 자리. `sprite_post.pick(hit_at=5)` 과 **같은 값**이어야 한다 —
#: 둘이 갈리면 화면이 그리는 칸과 탄이 떠나는 순간이 어긋난다.
HIT_AT = 5


def frames_of(sheet: Image.Image, size: int) -> list[Image.Image]:
	n = sheet.width // size
	return [sheet.crop((i * size, 0, (i + 1) * size, size)) for i in range(n)]


class EmptyFrame(Exception):
	"""칸이 비었다. 그 한 명만 건너뛰라는 뜻이다 — 멈추면 나머지가 통째로 안 얹힌다."""


def bbox(im: Image.Image) -> tuple[int, int, int, int]:
	b = im.getbbox()
	if b is None:
		raise EmptyFrame("빈 칸이다 — 크로마키가 캐릭터를 먹었다")
	return b


def foot_x(im: Image.Image) -> float:
	"""**발**의 가로 가운데. 아래쪽 한 자락만 보고 잰다.

	★ 칸 전체의 가운데를 쓰면 채찍 호·치켜든 팔이 딸려 들어와 몸이 한쪽으로
	  밀린다. 발은 언제나 몸 바로 밑에 있으므로 아래 자락이 제일 정직하다.
	"""
	x0, y0, x1, y1 = bbox(im)
	h = y1 - y0
	band = max(2, int(h * 0.14))          # 아래 14% = 발과 밑단
	px = im.load()
	xs = [x for y in range(y1 - band, y1) for x in range(x0, x1) if px[x, y][3] > 0]
	return (sum(xs) / len(xs)) if xs else (x0 + x1) * 0.5


def muzzle(im: Image.Image, family: str, ax: float, ay: float) -> tuple[int, int]:
	"""놓는 칸에서 잰 총구. 기준점(발밑 가운데)에서의 상대 좌표 · 위가 음수."""
	x0, y0, x1, y1 = bbox(im)
	h = y1 - y0
	if family == "raise":
		# 광역은 손이 머리 옆에 있고 탄이 안 나간다. 손 높이 가운데를 준다.
		# ★ 가로는 **거리**로 재고 하한을 못 박는다 — 부호가 그림을 뒤집기 때문이다
		#   (위 RAISE_MIN_X_OF_H 머리말). 몸통이 발보다 왼쪽에 있는 칸 하나 때문에
		#   그 캐릭터가 통째로 뒤집혀 서는 일이 실제로 있었다(브라사).
		lean = abs((x0 + x1) * 0.5 - ax)
		mx = max(int(round(lean)), max(2, int(round(h * RAISE_MIN_X_OF_H))))
		return mx, int(round(y0 + h * (1.0 - HAND_OF_H) - ay))
	px = im.load()
	# 몸통 **위쪽 65%** 안에서 제일 오른쪽 점. 아래를 같이 보면 앞으로 내디딘
	# 발이 팔보다 앞서서, 총구가 신발 끝에 붙는다.
	top = y0
	bot = y0 + int(h * 0.65)
	best = None
	for y in range(top, bot):
		for x in range(x1 - 1, x0 - 1, -1):
			if px[x, y][3] > 0:
				if best is None or x > best[0]:
					best = (x, y)
				break
	if best is None:
		best = (x1 - 1, y0 + h // 3)
	return int(round(best[0] - ax)), int(round(best[1] - ay))


def one(u: dict, route: str, tag: str, tier_i: int) -> dict | None:
	src = os.path.join(OUT, route, "sheets" + tag)
	size = u["size"]
	got: dict[str, tuple[Image.Image, list[Image.Image]]] = {}
	for anim in U.ANIMS:
		p = os.path.join(src, pixels.sheet_name(u["id"], anim, size, pixels.FRAMES[anim]))
		if not os.path.exists(p):
			return None
		sh = Image.open(p).convert("RGBA")
		got[anim] = (sh, frames_of(sh, size))
	idle0 = got["idle"][1][0]
	x0, y0, x1, y1 = bbox(idle0)
	body_h = y1 - y0
	ax = foot_x(idle0)
	ay = float(y1)                                  # 발밑
	# ★ 정지 그림과 같은 자. 아래 머리말 「배율」.
	scale = gen_art.unit_h(tier_i) / float(body_h)

	# 놓는 칸 — `sprite_post.pick` 이 5번 자리에 맞춰 뒀다(위 머리말).
	hit = HIT_AT
	seen = sprite_post.impact_i(got["attack"][1], u["family"])
	if abs(seen - hit) > 2:
		print("    ! %s: 임팩트가 %d칸에 보인다 (겨눈 자리 %d) — 눈으로 봐라"
			  % (u["id"], seen, hit))
	mx, my = muzzle(got["attack"][1][hit], u["family"], ax, ay)
	# ★ 부호 확인. 음수면 `Balance.art_aim()` 이 그 캐릭터를 **통째로 좌우 반전**해서
	#   그린다 — 그림은 오른쪽을 보고 뽑혔는데 화면에서만 왼쪽을 보게 된다.
	#   (CLAUDE.md 18-11 은 「왼쪽을 겨누고 뽑힌 그림」에만 그 길을 열어 뒀다)
	if mx <= 0:
		print("    !! %s: 총구 가로가 %+d 다 — 게임이 그림을 뒤집는다. 눈으로 봐라"
			  % (u["id"], mx))

	d = os.path.join(DST, u["id"])
	os.makedirs(d, exist_ok=True)
	for anim, (sh, _fr) in got.items():
		sh.save(os.path.join(d, f"{u['id']}_{anim}.png"))
	# ★★ **칸마다의 시간과 놓는 시각은 같은 산수에서 나와야 한다.**
	#   1000/12 는 83.33ms 인데 칸 시간은 정수로 적으므로 83 이다. 놓는 시각을
	#   `round(5 x 83.33)` = **417** 로 적으면 `Anim.hit_time` 이 세는 값
	#   (83 x 5 = **415**)과 2ms 어긋나고, `ns_check` 가 그 둘을 나란히 놓고 잡는다.
	#   그러니 **칸 시간을 먼저 정하고 그것을 더해서** 놓는 시각을 낸다.
	step = int(round(1000.0 / pixels.FPS))
	meta = {
		"name": u["id"], "ko": u["ko"], "elem": u["elem"],
		"source": "tools/sprite (Wan 2.2 I2V)",
		"cell": {"w": size, "h": size},
		"static": {"w": x1 - x0, "h": body_h,
				   "note": "아이들 0번 칸의 몸 상자. 배율과 총구를 재는 자다"},
		"anchor": {"x": round(ax, 1), "y": round(ay, 1),
				   "note": "가로 = 발의 가운데 · 세로 = 발밑 (Art.draw_at 과 같은 규칙)"},
		"scale": round(scale, 4),
		"muzzle_at": {"x": mx, "y": my,
					  "note": "기준점에서 잰 상대 좌표. 탄이 여기서 나간다"},
		"hit_ms": step * hit,
		"face": 1,
		"family": u["family"],
		"clips": {
			anim: {
				"frames": len(fr),
				"ms": [step] * len(fr),
				"total_ms": step * len(fr),
				"loop": anim in pixels.LOOPING,
				**({"hit_frame": hit} if anim == "attack" else {}),
			}
			for anim, (_sh, fr) in got.items()
		},
	}
	json.dump(meta, open(os.path.join(d, "anim.json"), "w", encoding="utf-8"),
			  ensure_ascii=False, indent=1)
	return meta


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--route", default="krea")
	ap.add_argument("--tag", default="")
	ap.add_argument("--only", default="")
	ap.add_argument("--clean", action="store_true",
					help="로스터에 없는 옛 캐릭터의 art/anim/<id>/ 를 지운다")
	a = ap.parse_args()

	ids = [s for s in a.only.split(",") if s] or U.PILOT
	tier_of = {}
	data = json.load(open(U.ROSTER, encoding="utf-8"))
	for ti, t in enumerate(data["tiers"]):
		for x in t["units"]:
			tier_of[x["id"]] = ti

	done, miss = [], []
	for u in U.load(ids):
		try:
			m = one(u, a.route, a.tag, tier_of[u["id"]])
		except EmptyFrame as e:
			print("!! %s: %s — 건너뜀" % (u["id"], e))
			miss.append(u["id"])
			continue
		if m is None:
			miss.append(u["id"])
			continue
		done.append(u["id"])
		print("  %-12s 몸 %3dpx → 배율 %.2f · 총구 (%+d,%+d) · 놓는 칸 %d (%dms)"
			  % (u["id"], m["static"]["h"], m["scale"],
				 m["muzzle_at"]["x"], m["muzzle_at"]["y"],
				 m["clips"]["attack"]["hit_frame"], m["hit_ms"]))

	if a.clean:
		keep = set(tier_of)
		for name in sorted(os.listdir(DST)):
			if name not in keep and os.path.isdir(os.path.join(DST, name)):
				shutil.rmtree(os.path.join(DST, name))
				print("  지움:", name)

	print("\n반입 %d명 · 시트 없음 %d명%s" % (len(done), len(miss),
											 (" — " + ", ".join(miss[:8])) if miss else ""))
	print("★ 이 뒤에 반드시: godot --headless --path . --import  그리고  tools/gen_roster.py")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
