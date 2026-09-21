#!/usr/bin/env python3
"""출고된 스프라이트 시트를 잰다 — `art/anim/<id>/` 에 **실제로 들어 있는** 것.

★★ **왜 이 도구가 따로 있어야 하는가.**
  `sprite_post.qc()` 는 시트를 **굽는 순간**에만 돈다. 그리고 그 지적은
  **아무것도 막지 않는다** — 화면에 `!!` 한 줄을 찍고 시트는 그대로 저장된다.
  실제로 그렇게 나갔다: 쉰 명을 구울 때

      !! unit_sigrid_attack_96x96_12.png — 발 높이가 5px 흔들림

  이 찍혔는데, 그 지적을 아무도 안 보고 `to_game.py` 가 그대로 `art/anim/sigrid/` 로
  옮겼고, 지금 게임에서 시그리드는 **공격할 때마다 5px 가라앉는다.**
  그러니 이 도구의 요점은 「새 검사를 발명하는 것」이 아니라
  **「출고된 것을 다시 재고, 지적이 나오면 빌드를 세우는 것」**이다.
  `tools/verify.sh` 4-1 단계가 이것을 부르고, 하나라도 실패하면 갈무리가 멈춘다.

재는 것:

  1. **공식 검사 여덟 가지** — `sprite_post.qc()` 를 **그대로 부른다.**
     (색 수 · 팔레트 이탈 · 반투명 · 마젠타 · 발 높이 · 빈 칸 · 검은 테두리 · 루프 이음매)
     ★ 베끼지 마라. 잣대가 두 곳에 있으면 언젠가 갈리고, 갈린 뒤에는 어느 쪽이
       맞는지 아무도 모른다. 여기서는 **부르기만** 한다.

  2. **클립 사이 발 높이** (공식 qc 가 못 보는 자리)
     `qc()` 는 한 시트 **안**에서만 잰다. idle 의 발과 attack 의 발이 어긋나면
     공격할 때 영웅이 가라앉는데 그것은 통과한다. 공식 길은 클립마다 프레임을
     따로 고르고(`sprite_post.select`), 같은 상자로 자르기는 해도 **그 상자 안에서
     캐릭터가 어디에 서 있는지**는 클립마다 다르다 — Wan 이 걸음을 조금 옮겨
     놓으면 그대로 남는다.

  3. **`muzzle_at.x` 의 부호** (공식 qc 가 아예 안 보는 자리)
     `Balance.art_aim()` 이 `muz[0] < 0` 이면 그 캐릭터 그림을 **통째로 좌우 반전**
     해서 그린다(CLAUDE.md 18-11). `qc()` 는 시트만 보고 `anim.json` 을 안 봐서
     이 자리가 통째로 비어 있다. 스프라이트는 오른쪽을 보고 구워지므로
     (`to_game.py` 머리말) 총구 가로는 **양수여야** 맞다.

  4. **anim.json 과 시트가 서로 맞는가** — 어긋나면 게임이 **조용히** 정지 그림
     한 장으로 되돌아간다(`Anim.clip()` 이 빈 딕셔너리를 준다). 오류도 로그도 없다.

  5. **경고 하나** — 칸 테두리에 닿은 픽셀 수. **실패로 안 친다.** 아래 머리말.

    python3 tools/sprite/qc_game.py
    python3 tools/sprite/qc_game.py --only jokull,brasa
    python3 tools/sprite/qc_game.py --json build/qc_game.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import pixels                                    # noqa: E402
import sprite_post                               # noqa: E402

DST = os.path.join(ROOT, "art", "anim")

#: 클립 **사이**의 발 높이 흔들림 한도(px). 공식 `qc()` 의 시트 안 한도(2px)와
#: 같은 값이다 — 다른 값을 주면 「한 시트 안에서는 되는데 사이에서는 안 되는」
#: 어중간한 자가 하나 더 생긴다.
FOOT_SPREAD = 2

#: 총구 가로의 하한(px). 0 근처도 나쁘다 — 시트를 다시 구울 때 부호가 뒤집힌다.
MUZZLE_MIN_X = 2

# Native pipelines ship binary alpha and a shared actor palette. The new
# roster preserves generated anatomy while aligning each pose's foot origin.
NATIVE_PIXEL_SOURCES = {"last_refuge_v3_pixel_h3", "imagegen_element_aoe_v1", "imagegen_roster_v1"}


# --------------------------------------------------------------------------
# 시트 읽기
# --------------------------------------------------------------------------
def frames_of(sheet: Image.Image, cell: int) -> list[Image.Image]:
    n = sheet.width // cell
    return [sheet.crop((i * cell, 0, (i + 1) * cell, cell)) for i in range(n)]


def feet_of(frames: list[Image.Image]) -> list[int]:
    """칸마다 알파가 있는 **맨 아랫줄**. 발이 서 있는 자리다."""
    out = []
    for f in frames:
        b = f.getbbox()
        out.append(b[3] if b else 0)
    return out


def edge_touch(frames: list[Image.Image]) -> dict:
    """칸 **테두리**에 닿은 알파 픽셀 수. 발밑(y=H-1)은 닿아야 정상이라 뺀다."""
    e = {"top": 0, "left": 0, "right": 0}
    for f in frames:
        w, h = f.size
        px = f.load()
        e["top"] += sum(1 for x in range(w) if px[x, 0][3])
        e["left"] += sum(1 for y in range(h) if px[0, y][3])
        e["right"] += sum(1 for y in range(h) if px[w - 1, y][3])
    e["total"] = e["top"] + e["left"] + e["right"]
    return e


# --------------------------------------------------------------------------
# anim.json ↔ 시트 대조
# --------------------------------------------------------------------------
def check_meta(meta: dict, sheets: dict[str, Image.Image],
               names: dict[str, str]) -> list[str]:
    """`anim.json` 이 시트와 어긋나지 않는가.

    ★ 어긋나면 게임이 **조용히** 정지 그림으로 되돌아간다. `Anim.clip()` 은
      텍스처가 없거나 `clips` 에 그 이름이 없으면 **빈 딕셔너리**를 주고,
      화면은 그것을 「클립이 아직 없는 캐릭터」로 읽어 정지 그림 한 장을 그린다
      (CLAUDE.md 18-1). 오류도 경고도 안 뜬다 — 여기서 안 재면 아무도 못 잡는다.
    """
    bad: list[str] = []
    cell = meta.get("cell", {})
    cw, ch = int(cell.get("w", 0)), int(cell.get("h", 0))
    if cw <= 0 or ch <= 0:
        bad.append("anim.json 에 cell 이 없다")
        return bad

    for anim, sh in sheets.items():
        c = meta.get("clips", {}).get(anim)
        if c is None:
            bad.append(f"{anim}: 시트는 있는데 anim.json 의 clips 에 없다")
            continue
        clip_cell = c.get("cell", cell)
        cw, ch = int(clip_cell.get("w", 0)), int(clip_cell.get("h", 0))
        if cw <= 0 or ch <= 0:
            bad.append(f"{anim}: invalid clip cell")
            continue
        # ── 칸 크기. 세로가 곧 칸 높이다.
        if sh.height != ch:
            bad.append(f"{anim}: cell.h={ch} 인데 그림 높이는 {sh.height}")
        if sh.width % cw:
            bad.append(f"{anim}: 그림 폭 {sh.width} 이 cell.w={cw} 로 안 나뉜다")
        # ── 칸 수. `Anim.clip()` 은 칸 크기를 **그림 폭 ÷ frames** 로 잰다.
        #    frames 가 틀리면 칸을 엉뚱한 자리에서 자른다 — 그림이 반씩 겹쳐 나온다.
        want = sh.width // max(1, cw)
        if int(c.get("frames", -1)) != want:
            bad.append(f"{anim}: frames={c.get('frames')} 인데 그림은 {want}칸")
        ms = c.get("ms", [])
        if len(ms) != int(c.get("frames", -1)):
            bad.append(f"{anim}: ms 가 {len(ms)}개인데 frames={c.get('frames')}")
        if abs(float(c.get("total_ms", -1)) - sum(ms)) > 0.001:
            bad.append(f"{anim}: total_ms={c.get('total_ms')} 인데 ms 의 합은 {sum(ms)}")
        # ── PNG 이름. `Anim.clip()` 이 `<name>_<anim>.png` 로 찾는다.
        want_name = f"{meta.get('name', '')}_{anim}.png"
        if names[anim] != want_name:
            bad.append(f"{anim}: 파일은 {names[anim]} 인데 name 으로는 {want_name} 을 찾는다")

    # ── 놓는 시각. `Anim.hit_time()` 이 ms 를 hit_frame 개 더해서 낸다.
    #    `anim.json` 의 hit_ms 와 그 합이 다르면 총구 불꽃과 탄이 갈린다
    #    (`ns_check._check_muzzle` 이 그 둘을 나란히 놓고 잡는다).
    atk = meta.get("clips", {}).get("attack")
    if atk is not None:
        hf = int(atk.get("hit_frame", -1))
        ms = atk.get("ms", [])
        if hf < 0:
            bad.append("attack 에 hit_frame 이 없다")
        elif hf >= len(ms):
            bad.append(f"hit_frame={hf} 이 칸 수({len(ms)})보다 크다")
        else:
            want = sum(ms[:hf])
            if abs(float(meta.get("hit_ms", -1)) - want) > 0.001:
                bad.append(f"hit_ms={meta.get('hit_ms')} 인데 ms[:{hf}] 의 합은 {want}")
    return bad


# --------------------------------------------------------------------------
# 한 캐릭터
# --------------------------------------------------------------------------
def check_h3(meta: dict, sheets: dict, directory: str, names: dict) -> list[str]:
    bad = []
    colors = set()
    patches = []
    aligned_anatomy = meta.get("source") == "imagegen_roster_v1"
    box = None if aligned_anatomy else tuple(meta["foot_pin_box"])
    for name, sheet in sheets.items():
        info = meta["clips"][name]
        size = info["cell"]["w"]

        if sheet.getbbox() is None:
            bad.append(f"{name}: empty clip")
        with open(os.path.join(directory, names[name]), "rb") as f:
            if hashlib.sha256(f.read()).hexdigest() != info["sha256"]:
                bad.append(f"{name}: approved sheet hash mismatch")
        for frame in frames_of(sheet, size):
            alpha = set(frame.getchannel("A").getdata())
            if not alpha <= {0, 255}:
                bad.append(f"{name}: non-binary transparency")
            bounds = frame.getbbox()
            # Area FX deliberately fade to an empty last frame.
            if bounds is None and name in ("idle", "attack", "shot"):
                bad.append(f"{name}: empty frame")
            elif bounds and (bounds[0] <= 0 or bounds[1] <= 0 or bounds[2] >= size or bounds[3] >= size):
                bad.append(f"{name}: silhouette touches canvas edge")
            if name in ("idle", "attack"):
                colors.update(p[:3] for p in frame.getdata() if p[3])
                if box is not None:
                    patches.append(frame.crop(box).tobytes())
    if len(colors) > int(meta["palette_colors"]):
        bad.append(f"actor palette: {len(colors)} colors exceeds approved limit")
    if not aligned_anatomy and (not patches or any(p != patches[0] for p in patches)):
        bad.append("idle/attack feet differ from the pinned reference")
    if not {"idle", "attack"} <= sheets.keys():
        bad.append("missing idle or attack clip")
    if meta.get("readability"):
        path = os.path.join(ROOT, "art", "portraits", meta.get("portrait_id", meta["name"]) + ".png")
        if not os.path.exists(path):
            bad.append("missing dedicated UI portrait")
        else:
            with Image.open(path) as im:
                if im.mode != "RGBA" or im.getchannel("A").getextrema() != (0, 255):
                    bad.append("portrait must have actual transparent and opaque pixels")
                box = im.getbbox()
                if box is None or min(box[0], box[1], im.width - box[2], im.height - box[3]) < 2:
                    bad.append("portrait has no transparent padding")
            if not os.path.exists(path + ".import"):
                bad.append("portrait not imported by Godot")
    return list(dict.fromkeys(bad))


def one(uid: str, allow_left: set[str]) -> dict:
    d = os.path.join(DST, uid)
    rep: dict = {"unit": uid, "fail": [], "warn": [], "num": {}}

    jp = os.path.join(d, "anim.json")
    if not os.path.exists(jp):
        rep["fail"].append("anim.json 이 없다")
        return rep
    meta = json.load(open(jp, encoding="utf-8"))
    elem = meta.get("elem", "")
    cell = int(meta.get("cell", {}).get("w", 96))

    # ── 시트 읽기. 파일 이름은 `<name>_<anim>.png` 여야 한다.
    sheets: dict[str, Image.Image] = {}
    names: dict[str, str] = {}
    for anim in sorted(meta.get("clips", {})):
        fn = f"{meta.get('name', uid)}_{anim}.png"
        p = os.path.join(d, fn)
        if not os.path.exists(p):
            # 이름이 어긋났을 수도 있으니 `_<anim>.png` 로 끝나는 것을 한 번 더 찾는다
            cand = [f for f in sorted(os.listdir(d)) if f.endswith(f"_{anim}.png")]
            if not cand:
                rep["fail"].append(f"{anim}: 시트가 없다 ({fn})")
                continue
            fn = cand[0]
            p = os.path.join(d, fn)
        sheets[anim] = Image.open(p).convert("RGBA")
        names[anim] = fn
        # ★ `.import` 가 없으면 Godot 이 그 텍스처를 **못 읽는다** — 내보낸 APK 안에서는
        #   더 그렇다. 파일은 멀쩡히 있는데 게임만 정지 그림으로 되돌아간다.
        if not os.path.exists(p + ".import"):
            rep["fail"].append(f"{anim}: {fn}.import 이 없다 — godot --import 를 돌려라")
    if not sheets:
        rep["fail"].append("시트가 하나도 없다")
        return rep

    # ── anim.json ↔ 시트
    rep["fail"] += check_meta(meta, sheets, names)

    # H3 uses a per-character palette (64 original / 96 refined), 256px cells and
    # a fixed foot patch. The old Wan 20-color palette/outline rules don't apply.
    if meta.get("source") in NATIVE_PIXEL_SOURCES:
        rep["fail"] += check_h3(meta, sheets, d, names)
        sheets = {name: sh for name, sh in sheets.items() if name in ("idle", "attack")}

    # ── 1. 공식 검사 여덟 가지. **부르기만 한다** (머리말 1번).
    if meta.get("source") in NATIVE_PIXEL_SOURCES:
        pass
    elif elem not in pixels.PALETTE:
        rep["fail"].append(f"모르는 속성 '{elem}' — 팔레트를 못 고른다")
    else:
        for anim, sh in sheets.items():
            n = sh.width // cell
            loop = anim in pixels.LOOPING
            for b in sprite_post.qc(sh, cell, n, elem, loop):
                rep["fail"].append(f"[공식] {names[anim]}: {b}")

    # ── 2. 클립 사이 발 높이 (머리말 2번)
    per = {}
    for anim, sh in sheets.items():
        frames = frames_of(sh, cell)
        if meta.get("source") in NATIVE_PIXEL_SOURCES and meta.get("source") != "imagegen_roster_v1":
            # A swinging hose/blade can extend below the feet. Measure the
            # approved foot patch, whose complete pixels are checked above.
            box = tuple(meta["foot_pin_box"])
            ft = [y + box[1] for y in feet_of([f.crop(box) for f in frames])]
        else:
            ft = feet_of(frames)
        per[anim] = (min(ft), max(ft))
    lo = min(v[0] for v in per.values())
    hi = max(v[1] for v in per.values())
    spread = hi - lo
    rep["num"]["foot"] = spread
    rep["num"]["foot_per"] = {k: list(v) for k, v in per.items()}
    if spread > FOOT_SPREAD:
        rep["fail"].append(
            "[클립 사이] 발 높이가 %dpx 흔들림 (한도 %dpx · %s) — 공격할 때 영웅이 가라앉는다"
            % (spread, FOOT_SPREAD,
               " · ".join(f"{k} {v[0]}~{v[1]}" for k, v in sorted(per.items()))))

    # ── 3. 총구 가로 (머리말 3번)
    mx = meta.get("muzzle_at", {}).get("x")
    rep["num"]["muz_x"] = mx
    if mx is None:
        rep["fail"].append("[총구] anim.json 에 muzzle_at.x 가 없다")
    elif uid in allow_left:
        rep["warn"].append(f"[총구] x={mx:+d} — 왼쪽을 겨눈 그림으로 **예외 등록**돼 있다")
    elif mx < 0:
        rep["fail"].append(
            "[총구] x=%+d 이 음수다 — Balance.art_aim() 이 이 캐릭터 그림을 "
            "**통째로 좌우 반전**해서 그린다 (CLAUDE.md 18-11)" % mx)
    elif mx < MUZZLE_MIN_X:
        rep["fail"].append(
            "[총구] x=%+d 이 0 근처다 (한도 >= +%d) — 다시 구우면 부호가 뒤집힌다"
            % (mx, MUZZLE_MIN_X))

    # ── 5. 경고: 칸 테두리에 닿은 픽셀 (머리말 5번 · 아래 ★★)
    #
    # ★★ **이것은 「잘림」이 아니다. 실패로 치지 마라.**
    #   `sprite_post.render` 는 프레임을 **공통 bbox 로 바짝 자른 뒤** 정사각 캔버스에
    #   채워 넣고 96 으로 줄인다 — 즉 **잘려 나가는 픽셀이 없다.** 바짝 자르니
    #   실루엣이 칸 테두리에 닿는 것이 오히려 **정상**이다 (쉰 명이 전부 그렇다).
    #   3D 길처럼 카메라로 담는 방식이었다면 이것이 곧 「카메라가 모자라다」였겠지만,
    #   공식 길에서는 방식 그 자체다.
    #
    # ★ 남는 진짜 문제는 하나뿐이다: `add_outline` 은 칸 **밖으로는 못 그리므로**
    #   닿은 자리에는 1도트 검은 테두리가 빠진다. 그런데 그것은 이미 공식 검사 7번
    #   (검은 테두리 비율)이 재고 있고 쉰 명이 통과한다 — 실측 최소 0.938 · 중앙
    #   1.000 이고 한도가 0.60 이라, 닿은 자리에서 잃는 몫은 그 여유 안에 있다.
    #   그러니 여기서는 **숫자만** 남긴다 — 이 값이 갑자기 몇 배로 뛰면 크롭이나
    #   해상도가 바뀐 것이므로 눈으로 볼 신호가 된다.
    et = {"top": 0, "left": 0, "right": 0, "total": 0}
    for anim, sh in sheets.items():
        e = edge_touch(frames_of(sh, cell))
        for k in et:
            et[k] += e[k]
    rep["num"]["edge"] = et
    return rep


# --------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="쉼표로 나눈 id 몇 명만")
    ap.add_argument("--json", default="", help="결과를 이 파일에 JSON 으로")
    ap.add_argument("--allow-left", default="",
                    help="총구가 음수여도 봐 주는 id (일부러 왼쪽을 겨눈 그림 · "
                         "CLAUDE.md 18-11). 지금은 비어 있다")
    a = ap.parse_args()

    if not os.path.isdir(DST):
        print("!! art/anim/ 이 없다")
        return 1
    ids = [s for s in a.only.split(",") if s]
    if not ids:
        ids = sorted(n for n in os.listdir(DST)
                     if os.path.isfile(os.path.join(DST, n, "anim.json")))
    allow_left = {s for s in a.allow_left.split(",") if s}

    print("== 출고된 스프라이트 시트 (art/anim/) — %d명 ==" % len(ids))
    print("   공식 8종은 sprite_post.qc() 를 그대로 부른다. "
          "그 위에 클립 사이 발 높이와 총구 부호를 더 잰다.\n")

    reps = []
    nbad = 0
    for uid in ids:
        r = one(uid, allow_left)
        reps.append(r)
        num = r["num"]
        per = num.get("foot_per", {})
        line = "발 %s px" % num.get("foot", "?")
        if per:
            line += "(" + " · ".join("%s %d~%d" % (k, v[0], v[1])
                                     for k, v in sorted(per.items())) + ")"
        if num.get("muz_x") is not None:
            line += " · 총구x %+d" % num["muz_x"]
        if num.get("edge"):
            line += " · 테두리닿음 %dpx" % num["edge"]["total"]
        mark = "!!" if r["fail"] else "OK"
        if r["fail"]:
            nbad += 1
        print(" %s %-12s %s" % (mark, uid, line))
        for b in r["fail"]:
            print("      - %s" % b)
        for w in r["warn"]:
            print("      ~ %s" % w)

    # ── 어디쯤인가를 한눈에 (실패만 찍으면 「지금 어디쯤인가」를 알 수 없다)
    foots = [r["num"].get("foot", 0) for r in reps if "foot" in r["num"]]
    muzs = [r["num"]["muz_x"] for r in reps if r["num"].get("muz_x") is not None]
    edges = [r["num"]["edge"]["total"] for r in reps if r["num"].get("edge")]
    print()
    if foots:
        print("   발 높이(클립 사이): 최대 %dpx · 2px 넘는 캐릭터 %d명"
              % (max(foots), sum(1 for v in foots if v > FOOT_SPREAD)))
    if muzs:
        print("   총구 가로: %+d ~ %+d · +%d 미만 %d명"
              % (min(muzs), max(muzs), MUZZLE_MIN_X,
                 sum(1 for v in muzs if v < MUZZLE_MIN_X)))
    if edges:
        edges.sort()
        print("   테두리 닿음(경고만): 중앙 %dpx · %d~%dpx — 바짝 잘라 담는 방식이라 정상"
              % (edges[len(edges) // 2], edges[0], edges[-1]))

    if a.json:
        os.makedirs(os.path.dirname(os.path.abspath(a.json)), exist_ok=True)
        json.dump(reps, open(a.json, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
        print("   → %s" % a.json)

    print("\n%d명 중 %d명에 지적 사항" % (len(reps), nbad))
    if nbad:
        print("판정: 실패 — " + ", ".join(r["unit"] for r in reps if r["fail"]))
        return 1
    print("판정: 정상")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
