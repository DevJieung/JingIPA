#!/usr/bin/env python3
"""캐릭터 몇 명만 **후보 여러 장**을 한 번에 뽑아 놓고 눈으로 고르게 한다.

    python3 tools/reroll_art.py ember_apprentice:4 frost_novice:4 tide_harpoon:0,1
    python3 tools/reroll_art.py --pick ember_apprentice=2      # 고른 것을 얹는다

★ 왜 따로 있는가 — `gen_art.py --force --try N` 은 **바로 덮어쓴다.** 마음에 안 들면
  또 덮어쓰는 수밖에 없고, 그때마다 모델을 3~4분씩 다시 올린다. 한 명을 고르는 데
  네 장이 필요한 것은 흔한 일이라(ART.md 1번: "고를 것이 없어 다시 뽑느니 아홉 장을
  뽑아라) 후보를 **한 번 올린 모델로 한꺼번에** 뽑아 두고 나중에 고른다.

★ 시드는 `gen_art.py` 와 **똑같이** 센다 — `_seed(id) + try*104729`. 그래서
  `try 0` 은 지금 게임에 들어 있는 그 그림이다. `holes` 만 켜서 다시 뽑고 싶을 때
  (활시위 안쪽·방패 안쪽의 흰 판때기) 그 한 장만 다시 만들면 된다.

★ 프롬프트도 `gen_art.jobs()` 가 만드는 것을 **그대로** 쓴다. 여기에 따로 적으면
  화풍 앵커가 두 벌이 되어, 여기서 뽑은 캐릭터만 나중에 따로 논다.

고르고 나면 `--pick` 이 세 가지를 한다:
  1. `art/units/<id>.png` 를 갈아 끼우고
  2. `build/<id>/` 의 리그를 지운다 (그림이 바뀌었으니 옛 좌표는 거짓말이다)
  3. 무엇을 다시 돌려야 하는지 적어 준다 (autorig → build_clips).
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_art as GA  # noqa: E402  — 화풍 앵커·후처리는 여기 한 곳에만 있다

CAND = os.path.join(ROOT, "build", "cand")


def unit_jobs(r: dict) -> dict:
	"""id → gen_art 가 만드는 그 캐릭터의 일감."""
	return {j["id"]: j for j in GA.jobs(r) if j["kind"] == "unit"}


def parse_spec(spec: str) -> tuple[str, list[int]]:
	"""`이름:x4` = 시드 1~4 · `이름:0,3` = 그 시드만 · `이름:0` = 그 한 장 · `이름` = 1~3.

	★ 숫자 하나는 **개수가 아니라 시드**다. 개수로 읽으면 `이름:0` 이 "0장"이 되어
	  아무 말 없이 건너뛴다 — 실제로 파도작살수 한 장이 그렇게 빠졌다.
	"""
	if ":" not in spec:
		return spec, [1, 2, 3]
	name, rest = spec.split(":", 1)
	rest = rest.strip()
	if rest.startswith("x"):
		return name, list(range(1, int(rest[1:]) + 1))
	return name, [int(v) for v in rest.split(",") if v.strip() != ""]


def pick(name: str, tag: str, jobs: dict) -> int:
	src = os.path.join(CAND, name, "%s.png" % tag)
	if not os.path.exists(src):
		print("  !! 후보가 없다: %s" % src)
		return 1
	dst = jobs[name]["path"] if "path" in jobs[name] else \
		os.path.join(ROOT, "art", "units", name + ".png")
	shutil.copy2(src, dst)
	# ★ 리그는 **그림에서 잰 좌표**다. 그림을 갈았으면 옛 좌표는 남의 몸을 가리킨다.
	rig = os.path.join(ROOT, "build", name, "rig.json")
	if os.path.exists(rig):
		os.remove(rig)
	print("  %s ← %s  (리그를 지웠다)" % (dst, tag))
	print("     이어서: python3 tools/anim/autorig.py %s"
		  " && python3 tools/anim/build_clips.py %s" % (name, name))
	return 0


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__,
								 formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("specs", nargs="*", help="이름[:시드수 또는 시드목록]")
	ap.add_argument("--pick", default="", help="이름=태그 (쉼표로 여러 명)")
	ap.add_argument("--holes", default="",
					help="이 이름들만 갇힌 배경을 지운다 (쉼표). 안 주면 roster.json 을 따른다")
	a = ap.parse_args()

	r = GA.load_roster()
	jobs = unit_jobs(r)

	if a.pick:
		bad = 0
		for one in a.pick.split(","):
			name, tag = one.split("=")
			if name.strip() not in jobs:
				print("  !! roster 에 없는 이름: %s" % name)
				bad += 1
				continue
			bad += pick(name.strip(), tag.strip(), jobs)
		return 1 if bad else 0

	force_holes = {s.strip() for s in a.holes.split(",") if s.strip()}
	todo = []
	for spec in a.specs:
		name, tries = parse_spec(spec)
		if name not in jobs:
			raise SystemExit("roster.json 에 %s 가 없다" % name)
		j = jobs[name]
		for k in tries:
			todo.append(dict(name=name, tag="t%d" % k, prompt=j["prompt"],
							 out_h=j["out_h"],
							 holes=j["holes"] or (name in force_holes),
							 seed=(j["seed"] + k * 104729) % 2000000))
	if not todo:
		raise SystemExit("뽑을 것이 없다")

	for j in todo:
		os.makedirs(os.path.join(CAND, j["name"]), exist_ok=True)

	# ★ Krea2 와 MiniMax H3 는 같은 순간에 못 뜬다 — 올리기 전에 문지기를 부른다 (tools/gpu_guard.py)
	import gpu_guard
	gpu_guard.claim("krea2")
	from krea2.pipelines.image import Krea2ImagePipeline

	print("[reroll] %d장 — 모델을 한 번만 올립니다" % len(todo), flush=True)
	t0 = time.time()
	pipe = Krea2ImagePipeline("turbo").load()
	print("[reroll] 모델 준비 완료 (%.0f초)" % (time.time() - t0), flush=True)

	for i, j in enumerate(todo, 1):
		t1 = time.time()
		img = pipe.generate(j["prompt"], width=1024, height=1024, seed=j["seed"])[0].image
		out = os.path.join(CAND, j["name"])
		img.save(os.path.join(out, "%s_raw.png" % j["tag"]))
		cut, kept, trapped = GA.cut_white(img, holes=j["holes"])
		px = GA.pixelize(cut, j["out_h"], GA.COLORS_UNIT)
		px.save(os.path.join(out, "%s.png" % j["tag"]), optimize=True)
		print("[reroll] (%d/%d) %-18s %s  %dx%d  남은넓이 %.0f%%  갇힌흰색 %.2f%%  %.0f초"
			  % (i, len(todo), j["name"], j["tag"], px.size[0], px.size[1],
				 kept * 100, trapped * 100, time.time() - t1), flush=True)

	print("[reroll] 완료 %.1f분 → %s" % ((time.time() - t0) / 60, CAND), flush=True)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
