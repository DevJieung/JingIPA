#!/usr/bin/env python3
"""PixelLab 플로우를 **이 장비의 모델로** 옮긴 시범 (한 명만).

PixelLab 이 클라우드에서 파는 것은 여섯 단계다. 그중 **Step 1 · 5 · 6** 은 이 저장소가
이미 한다(`make_ref` → `wan_i2v` → `sprite_post`, docs/SPRITE.md). 안 하는 것이 셋이고,
이 파일은 그중 **둘**을 로컬 모델로 지어 한 명에게 돌려 본 것이다:

  Step 2 **Rotate**  — 정면 한 장에서 나머지 방향을 만든다
      → 로컬: **Wan 2.2 I2V 로 「제자리에서 한 바퀴 도는」 클립**을 뽑고 거기서
        방향 칸을 고른다. PixelLab 은 방향마다 한 장씩 따로 뽑지만, 비디오 모델은
        **회전을 시간으로 푼다** — 그래서 방향 사이가 저절로 이어진다.

  Step 4 **Freeze N → Generate M** — 좋은 칸을 못 박고 나머지만 새로 만든다
      → 로컬: **`WanFirstLastFrameToVideo`**. 첫 칸과 끝 칸을 **둘 다** 마스터로
        못 박으면(= PixelLab 의 「Freeze 2 → Generate 1」) 가운데만 생성되고,
        **끝이 처음으로 되돌아오므로 루프가 산수로 닫힌다.**
        ☆ 이 노드가 Wan 2.2 두 전문가 그래프에서 도는가가 이 시범의 진짜 물음이었다.
          노드 몸통을 읽어 보면 `concat_latent_image` 와 `concat_mask` 를 조건에
          얹을 뿐이라(= `WanImageToVideo` 와 **같은 자리**) 모델을 안 가린다.
          실제로 돌려서 확인했다.

  Step 3 **Skeleton** — 캐릭터에서 스켈레톤을 자동 추정해 템플릿 동작을 얹는다
      → 로컬에 있는 가장 가까운 것이 **DWPose**(COCO-wholebody, yolox_l + dw-ll_ucoco)다.
        그런데 그것은 **사진 속 사람**으로 학습된 것이라 4등신 96px 도트에 붙는지가
        물음이다. **주장하지 않고 재 봤다** — `--mode pose` 가 그 실험이다.
        결과는 `docs/PIXELLAB.md` 에 있다.

★★ **이 파일은 굽는 규격을 하나도 새로 짓지 않는다.** 크로마키·팔레트·공통 크롭·
  테두리·시트 패킹은 전부 `pixels` 와 `sprite_post` 것을 **그대로 부른다.** 규격이
  두 벌이 되는 순간 「시범으로 만든 것」과 「게임에 들어가는 것」이 조용히 갈린다
  (CLAUDE.md 4-1-1 이 자세 표에서, docs/SPRITE.md 1-10 이 크롭 상자에서 배운 것).

돌리는 법:
    gpujob run pd-pixellab python3 tools/sprite/pixellab.py --only estoque --all
    python3 tools/sprite/pixellab.py --only estoque --mode freeze      # 하나만
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

import pixels                      # noqa: E402  — 규격은 여기 한 곳
import sprite_post as SP           # noqa: E402  — 고르기·굽기·검사
import units as U                  # noqa: E402
import wan_i2v as W                # noqa: E402  — ComfyUI 몰이는 저기 것을 그대로

OUT = os.path.join(ROOT, "build", "sprite")

#: 방향 몇 개를 뽑을까. PixelLab 은 4방향 또는 8방향이다.
DIRS8 = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]

#: ★ 회전 클립의 프롬프트. `wan_i2v.NEG` 의 「배경이 바뀌면 안 된다」는 그대로 쓰되,
#:   거기 있는 `camera pan` 금지는 여기서도 맞다 — **카메라가 아니라 캐릭터가** 돈다.
#:   카메라가 돌면 크로마 배경까지 같이 흘러서 공통 크롭이 뜻을 잃는다.
ROT_POS = ("{view} view pixel art sprite of a character, "
           "the character turns around in place, rotating a full 360 degrees, "
           "showing front then side then back then side then front again, "
           "feet planted on the same spot, "
           "solid magenta background, no camera movement, static camera, full body, "
           "the character keeps the exact same design and colors while turning")

#: ★ 「제자리에서 돈다」를 안 적으면 Wan 이 **걸어서** 돈다 — 발이 움직이면 공통 크롭
#:   안에서 캐릭터가 좌우로 흘러 방향 칸끼리 키가 안 맞는다.


# --------------------------------------------------------------------------
# 그래프 — `wan_i2v.graph` 와 **같은 뼈대**에 조건 노드만 갈아 끼운다
# --------------------------------------------------------------------------
def graph(image: str, pos: str, *, seed: int, length: int, size: int,
          loras: list[tuple[str, float]], steps: int, split: int,
          end_image: str | None = None) -> dict:
    """Wan 2.2 I2V 두 전문가 그래프.

    `end_image` 를 주면 조건 노드가 **`WanFirstLastFrameToVideo`** 로 바뀐다 —
    그것이 PixelLab 의 「Freeze」다. 안 주면 `wan_i2v.graph` 와 **한 글자도 다르지
    않은** 그래프가 된다(그래야 비교 팔이 정직하다).

    ★ 로더·샘플러·LoRA 사슬을 베끼지 않고 `wan_i2v.graph` 를 **불러서 고친다.**
      베끼면 저쪽에서 스텝이나 스케줄러를 바꾼 날 둘이 조용히 갈린다.
    """
    g = W.graph(image, pos, seed=seed, length=length, size=size,
                loras=loras, steps=steps, split=split)
    if end_image is None:
        return g

    # ★★ Freeze — 첫 칸과 끝 칸을 둘 다 못 박는다.
    #   노드 몸통(comfy_extras/nodes_wan.py)이 하는 일은 이것뿐이다:
    #     image[:1] = start · mask[:, :, :1+3] = 0
    #     image[-1:] = end   · mask[:, :, -1:]  = 0
    #     positive/negative 에 concat_latent_image · concat_mask 를 얹는다
    #   `WanImageToVideo` 와 **같은 자리에 같은 종류**를 얹으므로 모델을 안 가린다 —
    #   Wan 2.1 FLF2V 전용 체크포인트가 따로 필요하지 않다.
    g["17"] = {"class_type": "LoadImage", "inputs": {"image": end_image}}
    g["12"] = {"class_type": "WanFirstLastFrameToVideo",
               "inputs": {"positive": ["9", 0], "negative": ["10", 0], "vae": ["4", 0],
                          "start_image": ["11", 0], "end_image": ["17", 0],
                          "width": size, "height": size,
                          "length": length, "batch_size": 1}}
    return g


# --------------------------------------------------------------------------
# 잣대 — 「됐다」를 눈이 아니라 숫자로 말한다
# --------------------------------------------------------------------------
def seam(fr: list[Image.Image]) -> float:
    """루프 이음매 — 끝 칸과 첫 칸이 얼마나 다른가 (0 이면 완벽히 닫힌다).

    ★ `sprite_post._diff` 를 그대로 쓴다. 이 값이 곧 공식 `qc()` 의 「루프 이음매」
      항목이 재는 것이라, 새 자를 지으면 통과 기준이 두 벌이 된다.
    """
    return SP._diff(fr[-1], fr[0])


def drift(fr: list[Image.Image]) -> list[float]:
    """칸마다 0번 칸에서 얼마나 멀어졌나 — 회전에서 **정체성이 새는가**를 잰다.

    ★ 회전은 **당연히** 그림이 달라지므로 이 값 자체는 크다. 볼 것은 값이 아니라
      **모양**이다: 한 바퀴를 제대로 돌면 가운데(뒷모습)에서 제일 크고 끝에서 다시
      작아지는 **산 모양**이 나온다. 단조증가면 그것은 회전이 아니라 **표류**다.
    """
    return [SP._diff(f, fr[0]) for f in fr]


def ink(im: Image.Image) -> float:
    """알파가 찬 넓이 비율. 회전 중에 캐릭터가 녹아 없어지는가를 본다."""
    a = im.split()[-1]
    return sum(1 for p in a.getdata() if p > 128) / float(im.width * im.height)


def palette_hist(im: Image.Image, colors: list[str]) -> list[float]:
    """팔레트 열다섯 칸이 각각 몇 할인가. 색이 통째로 도는 것을 잡는다."""
    want = [pixels.hex2rgb(c) for c in colors]
    n = [0] * len(want)
    tot = 0
    for px in im.convert("RGBA").getdata():
        if px[3] < 128:
            continue
        tot += 1
        best, bd = 0, 1 << 30
        for i, w in enumerate(want):
            d = (px[0] - w[0]) ** 2 + (px[1] - w[1]) ** 2 + (px[2] - w[2]) ** 2
            if d < bd:
                best, bd = i, d
        n[best] += 1
    return [c / tot for c in n] if tot else [0.0] * len(want)


def hist_dist(a: list[float], b: list[float]) -> float:
    """두 히스토그램의 거리 (0~1). 0.5 를 넘으면 옷 색이 통째로 바뀐 것이다."""
    return 0.5 * sum(abs(x - y) for x, y in zip(a, b))


# --------------------------------------------------------------------------
# 한 모드 돌리기
# --------------------------------------------------------------------------
def clip(u: dict, *, mode: str, route: str, tag: str, seed: int,
         length: int, size: int, steps: int, split: int, view: str,
         speed_w: float, force: bool) -> str:
    """Wan 을 돌려 프레임 PNG 를 받는다. 이미 있으면 건너뛴다."""
    dst = os.path.join(OUT, route, "pixellab", "clips" + tag, f"{u['id']}_{mode}")
    if os.path.isdir(dst) and os.listdir(dst) and not force:
        print(f"  {u['id']}_{mode}: 있음 — 건너뜀")
        return dst

    src = os.path.join(OUT, route, "wan_in", f"{u['id']}.png")
    if not os.path.exists(src):
        raise SystemExit(f"Wan 입력이 없다: {src} (먼저 make_ref → refine)")
    name = W.upload(src)

    loras = [("speed", speed_w)]
    end = None
    if mode == "rotate":
        pos = ROT_POS.format(view=view)
        # ★ 픽셀 LoRA 를 **안 얹는다.** `pix_attack` 은 「melee attack」으로 학습돼
        #   있어서(units.PIX_W 머리말) 돌라고 시키면 도는 대신 **칼을 휘두른다.**
    elif mode in ("freeze", "loose"):
        act = U.IDLE_ACTION[u["family"]]
        pos = (f"{view} view pixel art sprite of a character, {act}, "
               f"solid magenta background, no camera movement, static camera, full body, "
               f"the character stays in the same place and keeps the same design")
        if mode == "freeze":
            end = name        # ★ 첫 칸과 **같은 그림**을 끝에도 못 박는다 = 루프
    else:
        raise SystemExit(f"모르는 모드: {mode}")

    g = graph(name, pos, seed=seed, length=length, size=size, loras=loras,
              steps=steps, split=split, end_image=end)
    outs = W.run(g, f"{u['id']}_{mode} (seed {seed})")
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(dst):
        os.remove(os.path.join(dst, f))
    for i, f in enumerate(outs):
        shutil.copyfile(f, os.path.join(dst, "f_%04d.png" % i))
    return dst


# --------------------------------------------------------------------------
# Step 4 를 **PixelLab 이 실제로 쓰는 꼴로** 재는 실험 — 「다리 놓기」
#
# 위의 `freeze` 는 첫 칸과 끝 칸에 **같은 그림**을 못 박는다(= 루프 만들기).
# 그런데 PixelLab 의 「Freeze 2 → Generate 1」은 그 쓰임이 아니다 — **서로 다른**
# 두 칸을 못 박고 **사이를 채우는** 것이다("가이드 프레임이 2장이 되어 결과가 더
# 안정적", "시퀀스 확장이나 마지막 프레임 개선에 사용").
#
# ★★ 그 쓰임은 **정답을 알고** 잴 수 있다. 대조군(`loose`) 클립의 0번과 끝 칸을
#   양쪽에 못 박고 사이를 새로 생성한 뒤, 그 클립의 **실제 가운데 칸들**과 견주면
#   된다. 채워 넣은 것이 정답에 가까우면 이 기능은 진짜로 도는 것이다.
# ★ 견줄 바닥선(baseline)이 있어야 뜻이 산다 — 「0번을 그냥 붙들고 있기」다.
#   그보다 못하면 이 기능은 아무것도 안 한 것과 같다.
# --------------------------------------------------------------------------
def bridge_probe(u: dict, *, route: str, tag: str, seed: int, size: int,
                 steps: int, split: int, view: str, speed_w: float,
                 force: bool) -> dict:
    src_dir = os.path.join(OUT, route, "pixellab", "clips" + tag, f"{u['id']}_loose")
    if not os.path.isdir(src_dir):
        return {"error": f"대조군 클립이 없다: {src_dir} (먼저 --mode loose)"}
    truth = SP._load_dir(src_dir)
    n = len(truth)

    dst = os.path.join(OUT, route, "pixellab", "clips" + tag, f"{u['id']}_bridge")
    if not (os.path.isdir(dst) and os.listdir(dst)) or force:
        # ★ 이름을 캐릭터마다 다르게 준다. `W.upload` 는 basename 을 그대로 쓰므로
        #   `f_0000.png` 로 올리면 캐릭터끼리 서로의 입력을 덮어쓴다.
        a = os.path.join(OUT, route, "pixellab", f"br_a_{u['id']}.png")
        b = os.path.join(OUT, route, "pixellab", f"br_b_{u['id']}.png")
        truth[0].save(a)
        truth[-1].save(b)
        act = U.IDLE_ACTION[u["family"]]
        pos = (f"{view} view pixel art sprite of a character, {act}, "
               f"solid magenta background, no camera movement, static camera, full body, "
               f"the character stays in the same place and keeps the same design")
        g = graph(W.upload(a), pos, seed=seed, length=n, size=size,
                  loras=[("speed", speed_w)], steps=steps, split=split,
                  end_image=W.upload(b))
        outs = W.run(g, f"{u['id']}_bridge (칸 {n})")
        os.makedirs(dst, exist_ok=True)
        for f in os.listdir(dst):
            os.remove(os.path.join(dst, f))
        for i, f in enumerate(outs):
            shutil.copyfile(f, os.path.join(dst, "f_%04d.png" % i))
    got = SP._load_dir(dst)

    if len(got) != n:
        return {"error": f"칸 수가 다르다: {len(got)} vs {n}"}
    # ★ 양 끝은 못 박은 칸이라 당연히 같다 — **가운데만** 잰다.
    mid = range(1, n - 1)
    err = [SP._diff(got[i], truth[i]) for i in mid]
    hold = [SP._diff(truth[0], truth[i]) for i in mid]       # 바닥선: 0번을 붙들기
    return {
        "n": n,
        "bridge_err": round(sum(err) / len(err), 4),
        "hold_err": round(sum(hold) / len(hold), 4),
        "gain": round((sum(hold) - sum(err)) / sum(hold), 3) if sum(hold) else 0,
        "worst": round(max(err), 4),
        "per_frame": [round(x, 4) for x in err],
    }


# --------------------------------------------------------------------------
# Step 3 — 스켈레톤이 **붙는가**를 잰다 (주장하지 않고)
# --------------------------------------------------------------------------
#: DWPose 는 사진 속 사람으로 학습됐다. 이 게임의 캐릭터는 **4등신 96px 도트**에
#: 얼굴이 눈 두 점뿐이다(sprite_design.md §1·§5). 붙을 이유가 없어 보이지만,
#: **안 붙는다고 적기 전에 재는 것**이 이 저장소의 규칙이다 (CLAUDE.md 4-4 가
#: 「감으로 고치지 마라」로 적은 것과 같다).
POSE_SRC = {
    "raw":    ("raw",     "원화 1024 — 사람 비율에 가장 가깝다"),
    "master": ("master",  "마스터 96 — 게임이 실제로 쓰는 그림"),
    "wan_in": ("wan_in",  "Wan 입력 512 — 마스터를 키운 것"),
}


def pose_graph(image: str, res: int) -> dict:
    """DWPose 한 장. **Wan 모델을 하나도 안 읽는다** — 28GB 로더가 없다."""
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": image}},
        "2": {"class_type": "DWPreprocessor",
              "inputs": {"image": ["1", 0], "detect_hand": "enable",
                         "detect_body": "enable", "detect_face": "enable",
                         "resolution": res,
                         "bbox_detector": "yolox_l.torchscript.pt",
                         "pose_estimator": "dw-ll_ucoco_384_bs5.torchscript.pt",
                         "scale_stick_for_xinsr_cn": "disable"}},
        "3": {"class_type": "SaveImage",
              "inputs": {"images": ["2", 0],
                         "filename_prefix": "pocker_pose/" + image[:-4]}},
        "4": {"class_type": "SavePoseKpsAsJsonFile",
              "inputs": {"pose_kps": ["2", 1],
                         "filename_prefix": "pocker_pose/kps_" + image[:-4]}},
    }


def pose_probe(u: dict, route: str, res: int, control: list[str] | None = None) -> dict:
    """세 그림에 스켈레톤을 붙여 보고 **관절이 몇 개 잡혔나**를 돌려준다.

    ★★ **대조군을 반드시 같이 돌려라**(`control`). 셋 다 0 이 나왔을 때 그것이
      「DWPose 가 도트 그림에 안 붙는다」인지 「내 probe 가 고장 났다」인지를
      가르는 것은 **사람 사진 한 장**뿐이다. 대조군에서도 0 이면 결론이 뒤집힌다 —
      모델이 아니라 배관이 틀린 것이다.
    """
    srcs = [(k, os.path.join(OUT, route, sub, f"{u['id']}.png"), why)
            for k, (sub, why) in POSE_SRC.items()]
    for p in (control or []):
        srcs.append(("control:" + os.path.basename(p), p,
                     "★대조군 — 진짜 사진. 여기서도 0 이면 probe 가 고장 난 것이다"))

    out: dict = {}
    for key, src, why in srcs:
        if not os.path.exists(src):
            out[key] = {"why": why, "error": "그림이 없다"}
            continue
        # ★ 원화는 RGBA 라 알파가 있다. DWPose 는 RGB 를 보므로 **흰 바탕에 얹어**
        #   넣는다 — 투명을 검정으로 읽으면 실루엣이 통째로 어둠에 묻힌다.
        im = Image.open(src).convert("RGBA")
        flat = Image.new("RGB", im.size, (255, 255, 255))
        flat.paste(im, (0, 0), im)
        safe = key.replace(":", "_").replace(".", "_")
        tmp = os.path.join(OUT, route, "pixellab", f"pose_{safe}_{u['id']}.png")
        os.makedirs(os.path.dirname(tmp), exist_ok=True)
        flat.save(tmp)
        name = W.upload(tmp)
        outs = W.run(pose_graph(name, res), f"{u['id']} pose/{key}")
        # ★ 잡힌 것이 없으면 DWPose 는 **새까만 그림**을 돌려준다. 그것이 답이다.
        pose = Image.open(outs[0]).convert("RGB") if outs else None
        lit = 0.0
        if pose is not None:
            lit = sum(1 for p in pose.getdata() if max(p) > 24) / float(pose.width * pose.height)
        kps = _read_kps(u["id"], safe)
        out[key] = {"why": why, "src": src, "pose_png": outs[0] if outs else "",
                    "lit": round(lit, 5),
                    "people": kps.get("people", -1),
                    "joints": kps.get("joints", -1),
                    "found": lit > 0.0005}
    return out


def _read_kps(uid: str, key: str) -> dict:
    """`SavePoseKpsAsJsonFile` 이 떨군 파일에서 사람 수와 관절 수를 센다."""
    d = os.path.join(W.COMFY, "output", "pocker_pose")
    if not os.path.isdir(d):
        return {}
    cand = sorted(f for f in os.listdir(d)
                  if f.startswith(f"kps_pose_{key}_{uid}") and f.endswith(".json"))
    if not cand:
        return {}
    try:
        j = json.load(open(os.path.join(d, cand[-1]), encoding="utf-8"))
    except Exception:
        return {}
    frames = j if isinstance(j, list) else [j]
    ppl = frames[0].get("people", []) if frames else []
    # ★ 신뢰도 0 인 자리는 「못 찾았다」다. 그것을 세면 언제나 열여덟이 나온다.
    n = 0
    for p in ppl:
        v = p.get("pose_keypoints_2d") or []
        n += sum(1 for i in range(2, len(v), 3) if v[i] > 0.3)
    return {"people": len(ppl), "joints": n}


def bake_sheet(frames_dir: str, u: dict, *, n: int, loop: bool,
               uniform: bool) -> tuple[Image.Image, dict]:
    """프레임 → 96 시트. **굽는 일은 `sprite_post` 것을 그대로 쓴다.**

    ★ 회전만 고르는 자가 다르다. `sprite_post.pick` 은 「임팩트」와 「루프 이음매」를
      찾는 자라 회전에는 뜻이 없다 — 한 바퀴에서 방향을 뽑는 일은 **균등 분할**이
      정답이고, 그것이 PixelLab 의 4방향/8방향과 같은 뜻이다.
    """
    raw = SP._load_dir(frames_dir)
    keyed = [pixels.dekey_hard(pixels.dekey(im.copy())) for im in raw]
    gone = max(pixels.keyed_ratio(a, b) for a, b in zip(raw, keyed))
    if gone > 0.985:
        raise SystemExit(f"{frames_dir}: 크로마키가 {gone:.1%} 를 지웠다")

    if uniform:
        # ★ 한 바퀴에서 방향 n개 — **마지막 칸은 뺀다.** 360도는 0도와 같은 그림이라
        #   넣으면 같은 방향이 두 번 선다.
        idx = [round(i * (len(keyed) - 1) / float(n)) for i in range(n)]
    else:
        idx = SP.pick(keyed, n, loop=loop, family=u["family"])
    sel = [keyed[i] for i in idx]
    box = pixels.union_bbox(sel)
    return SP.render(sel, idx, box, size=u["size"], elem=u["elem"],
                     loop=loop, n_src=len(keyed))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", default="krea", choices=("sdxl", "krea"))
    ap.add_argument("--only", default="estoque", help="시범은 한 명이 기본")
    ap.add_argument("--mode", default="", help="rotate · freeze · loose · pose · bridge")
    ap.add_argument("--all", action="store_true", help="셋 다 (loose 는 freeze 의 대조군)")
    ap.add_argument("--pose-res", type=int, default=512)
    ap.add_argument("--pose-control", default="", help="대조군 사진 (쉼표로 여럿)")
    ap.add_argument("--dirs", type=int, default=8, help="회전에서 뽑을 방향 수")
    ap.add_argument("--length", type=int, default=33)
    ap.add_argument("--rot-length", type=int, default=49,
                    help="회전은 길게 — 33칸이면 한 바퀴에 방향 여덟이 안 들어간다")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--steps", type=int, default=4)
    ap.add_argument("--split", type=int, default=2)
    ap.add_argument("--seed", type=int, default=W.DEF_SEED)
    ap.add_argument("--view", default="front")
    ap.add_argument("--speed-w", type=float, default=1.0)
    ap.add_argument("--tag", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-gpu", action="store_true",
                    help="이미 받아 둔 프레임으로 굽기·재기만 한다")
    a = ap.parse_args()

    modes = ["rotate", "freeze", "loose"] if a.all else \
        [s for s in a.mode.split(",") if s] or ["freeze"]
    us = U.load([s for s in a.only.split(",") if s])
    os.makedirs(OUT, exist_ok=True)
    if not a.no_gpu:
        W.serve()

    sheets_dir = os.path.join(OUT, a.route, "pixellab", "sheets" + a.tag)
    os.makedirs(sheets_dir, exist_ok=True)
    # ★ 앞서 돌린 모드의 결과를 **덮지 않는다.** 모드마다 따로 돌리는 길이 있으므로
    #   (GPU 를 한 번에 다 안 쓰려고 그렇게 한다) 매번 새로 쓰면 앞의 것이 사라진다.
    rp = os.path.join(sheets_dir, "pixellab_report.json")
    report: dict = {}
    if os.path.exists(rp):
        try:
            report = json.load(open(rp, encoding="utf-8"))
        except Exception:
            report = {}

    for u in us:
        report.setdefault(u["id"], {"elem": u["elem"], "family": u["family"],
                                    "tier": u["tier"], "modes": {}})
        for mode in modes:
            # ★ 「다리 놓기」도 시트가 안 나온다 — 정답과 견주는 실험이다.
            if mode == "bridge":
                r = bridge_probe(u, route=a.route, tag=a.tag, seed=a.seed,
                                 size=a.size, steps=a.steps, split=a.split,
                                 view=a.view, speed_w=a.speed_w, force=a.force)
                report[u["id"]]["modes"]["bridge"] = r
                if "error" in r:
                    print(f"  {u['id']} bridge: {r['error']}")
                else:
                    print(f"  {u['id']} bridge: 채운 오차 {r['bridge_err']:.4f} · "
                          f"바닥선(0번 붙들기) {r['hold_err']:.4f} · "
                          f"이득 {r['gain']:+.1%}")
                continue

            # ★ Step 3 은 시트가 안 나온다 — 「붙는가」만 재는 실험이다.
            if mode == "pose":
                r = pose_probe(u, a.route, a.pose_res,
                               [x for x in a.pose_control.split(",") if x])
                report[u["id"]]["modes"]["pose"] = r
                for k, v in r.items():
                    print(f"  {u['id']} pose/{k}: "
                          + (v["error"] if "error" in v else
                             f"{'찾음' if v['found'] else '★못 찾음'} · "
                             f"사람 {v['people']} · 관절 {v['joints']} · "
                             f"그린 넓이 {v['lit']:.5f}"))
                continue

            length = a.rot_length if mode == "rotate" else a.length
            if a.no_gpu:
                d = os.path.join(OUT, a.route, "pixellab", "clips" + a.tag,
                                 f"{u['id']}_{mode}")
                if not os.path.isdir(d):
                    print(f"  {u['id']}_{mode}: 프레임이 없다 — 건너뜀")
                    continue
            else:
                d = clip(u, mode=mode, route=a.route, tag=a.tag, seed=a.seed,
                         length=length, size=a.size, steps=a.steps, split=a.split,
                         view=a.view, speed_w=a.speed_w, force=a.force)

            n = a.dirs if mode == "rotate" else pixels.FRAMES["idle"]
            loop = mode != "rotate"
            sheet, meta = bake_sheet(d, u, n=n, loop=loop,
                                     uniform=(mode == "rotate"))
            p = os.path.join(sheets_dir, pixels.sheet_name(u["id"], mode, u["size"], n))
            sheet.save(p)

            fr = [sheet.crop((i * u["size"], 0, (i + 1) * u["size"], u["size"]))
                  for i in range(n)]
            pal = pixels.palette_for(u["elem"])
            h0 = palette_hist(fr[0], pal)
            m = {
                "frames_src": meta["src_frames"],
                "picked": meta["picked"],
                "n": n,
                "sheet": os.path.basename(p),
                "seam": round(seam(fr), 4),
                "drift": [round(x, 4) for x in drift(fr)],
                "ink": [round(ink(f), 4) for f in fr],
                "hist_dist": [round(hist_dist(palette_hist(f, pal), h0), 4) for f in fr],
                "qc": SP.qc(sheet, u["size"], n, u["elem"], loop),
            }
            report[u["id"]]["modes"][mode] = m
            print(f"  {u['id']}_{mode}: 이음매 {m['seam']:.3f} · "
                  f"넓이 {min(m['ink']):.3f}~{max(m['ink']):.3f} · "
                  f"지적 {len(m['qc'])}건")
            for b in m["qc"]:
                print(f"     !! {b}")

    json.dump(report, open(rp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"\n표 → {rp}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
