#!/usr/bin/env python3
"""Step 3-5 — 클립의 **한 구간만** 다시 굽는다 (「다리 놓기」).

`wan_i2v.py`(Step 2)와 `sprite_post.py`(Step 3) 사이에 낀다. 하는 일은 하나다:
**좋은 칸 둘을 못 박고 그 사이만 새로 생성해서 클립에 끼워 넣는다.**
그러면 쉰 명을 다시 굽지 않고 **한 명의 한 구간**만 고칠 수 있다.

근거와 실측은 [`docs/PIXELLAB.md`](../../docs/PIXELLAB.md) 3-2 에 있다. 요점 둘:

  ★★ **양끝이 서로 달라야 뜻이 있다.** 같은 그림을 양쪽에 못 박으면 「가만히 있기」가
     그 조건을 만족하는 가장 짧은 답이라 **죽은 다리**가 나온다(실측: 진폭 1/15,
     스텝을 올려도 클립을 늘려도 안 살아난다). 그래서 이 도구는 **죽은 클립을
     고치지 못한다** — 그건 씨앗을 다시 굴릴 일이고, `scan` 이 그렇게 갈라 준다.
  ★★ **속도 LoRA 를 빼고 20스텝**이어야 한다. 4스텝 lightx2v 증류에서는 정답 재현
     이득이 **+3.5%**(잡음)인데 20스텝·무LoRA 에서 **+39.1%** 다. 값은 클립 한 장에
     21초 → 84초. `DEF_STEPS`·`DEF_SPLIT`·`DEF_SPEED_W` 가 그 값이다.

★ **고친 구간은 반드시 `repairs.json` 에 적는다.** `build/` 는 gitignore 라 클립이
  저장소에 안 남는다 — 안 적어 두면 다시 구울 때 그 캐릭터가 조용히 옛 결함으로
  되돌아간다 (`units.SEED` 와 `anim/rig_overrides.json` 이 같은 규칙이다).

돌리는 법:
    python3 tools/sprite/repair.py --scan                  # 무엇을 고쳐야 하나 (GPU 안 씀)
    gpujob run pd-repair python3 tools/sprite/repair.py --apply
    python3 tools/sprite/repair.py --apply --only conor_idle --span 5,9   # 손으로 한 구간
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

import pixels                      # noqa: E402
import sprite_post as SP           # noqa: E402
import units as U                  # noqa: E402
import wan_i2v as W                # noqa: E402
# ★ FLF 그래프는 `pixellab.graph` 한 곳에만 있다 — 베끼면 두 벌이 된다.
import pixellab as PL              # noqa: E402

OUT = os.path.join(ROOT, "build", "sprite")
TABLE = os.path.join(HERE, "repairs.json")

#: ★ 다리 놓기 전용 샘플러 값. 파이프라인 본 굽기(4스텝)와 **일부러 다르다**.
DEF_STEPS, DEF_SPLIT, DEF_SPEED_W = 20, 10, 0.0

#: 구간 길이는 `4k+1` 이어야 한다 — Wan 의 latent 는 네 칸을 한 칸으로 접으므로
#: (`((length-1)//4)+1`) 그 배수가 아니면 끝 칸이 정확히 안 걸린다.
def span_ok(a: int, b: int) -> bool:
    return b > a and (b - a) % 4 == 0


# --------------------------------------------------------------------------
# 재기 — 무엇이 고칠 거리인가
# --------------------------------------------------------------------------
#: 출고된 쉰 명의 idle 시트를 실제로 재서 정한 값들(docs/PIXELLAB.md 6-1).
#:   진폭 분포: 최소 0.0023 · 10% 0.0133 · 중앙 0.0445 · 최대 0.1421
#:   그래서 「죽음」은 하위 10% 언저리인 0.013 밑으로 잡는다.
DEAD_AMP = 0.013
#: 「튐」은 한 칸이 나머지 걸음의 몇 배인가. 3배를 넘으면 눈에 덜컥 걸린다.
JUMP_RATIO = 3.0
#: 튀는 칸이 이 값보다 작으면 그냥 둔다 — 죽은 클립에서는 **정상 걸음도** 중앙값의
#: 열 배가 되므로, 비율만 보면 죽은 것이 전부 「튐」으로 잡힌다.
JUMP_MIN = 0.030


def clip_dir(uid: str, anim: str, route: str, tag: str = "") -> str:
    return os.path.join(OUT, route, "clips" + tag, f"{uid}_{anim}")


def picked(frames: list[Image.Image], anim: str, family: str) -> list[int]:
    """`sprite_post` 가 **실제로 고를** 칸. 검사기와 굽는 쪽이 같은 자를 써야 한다."""
    return SP.pick(frames, pixels.FRAMES[anim], loop=anim in pixels.LOOPING,
                   family=family)


def classify(frames: list[Image.Image], anim: str, family: str) -> dict:
    """이 클립이 「죽음」인가 「튐」인가 「멀쩡」인가.

    ★ 재는 것은 원본 33칸이 아니라 **골라 뽑은 칸들**이다 — 게임이 보는 것이 그것이고,
      원본이 움직여도 고르고 나면 죽어 있을 수 있다(주크가 실제로 그렇다).
    """
    idx = picked(frames, anim, family)
    sel = [frames[i] for i in idx]
    amp = max(SP._diff(f, sel[0]) for f in sel)

    # ★★ **같은 칸이 잇달아 뽑힌 자리는 걸음에서 빼고 잰다.**
    #   두 가지를 갈라야 하기 때문이다:
    #     · 루프(idle)의 `[1,6,15,22,31,22,15,6]` 처럼 **거울로 되돌아오며** 같은 칸을
    #       다시 쓰는 것은 `_pingpong` 의 설계다. 결함이 아니다.
    #     · `[1,1,1,2,2,2,…]` 처럼 **잇달아** 같은 칸이 나오는 것은 고르기가 멎은 것이다.
    #   그냥 `len - len(set)` 로 세면 앞엣것까지 결함으로 잡혀 쉰 개 전부가 걸린다
    #   (실측: 그 자로는 idle 50개가 전부 「중복 3칸」으로 나왔다).
    #   그리고 멎은 자리의 걸음은 **0** 이라, 그것을 중앙값에 넣으면 중앙값이 끌려 내려가
    #   **멀쩡한 걸음이 「튐」으로 둔갑한다** — 다리를 놓을 까닭이 없는 곳에 놓게 된다.
    stall = sum(1 for i in range(len(idx) - 1) if idx[i] == idx[i + 1])
    st = [SP._diff(sel[i], sel[i + 1]) for i in range(len(sel) - 1)
          if idx[i] != idx[i + 1]]
    med = sorted(st)[len(st) // 2] if st else 0.0
    mx = max(st) if st else 0.0
    live = [i for i in range(len(idx) - 1) if idx[i] != idx[i + 1]]

    r = {"picked": idx, "amp": round(amp, 4), "med": round(med, 4),
         "max": round(mx, 4), "stall": stall, "kind": "ok", "why": ""}
    if amp < DEAD_AMP:
        r["kind"] = "dead"
        r["why"] = (f"진폭 {amp:.4f} < {DEAD_AMP} — 골라 뽑은 칸이 거의 안 움직인다. "
                    f"★다리로는 못 고친다(양끝이 같아진다). 씨앗을 다시 굴려라")
        return r
    if mx > JUMP_MIN and med > 0 and mx / med >= JUMP_RATIO:
        # 튀는 자리를 **원본 칸 번호**로 되돌려 준다 — 다리를 놓을 곳이 거기다.
        k = live[st.index(mx)]
        r["kind"] = "jump"
        r["at"] = [idx[k], idx[k + 1]]
        r["why"] = (f"고른 칸 {idx[k]}→{idx[k + 1]} 에서 걸음이 {mx / med:.1f}배 튄다 "
                    f"({mx:.4f} 대 {med:.4f})")
    if stall:
        # ☆ 이것은 **다리로 못 고친다.** 클립이 아니라 `sprite_post.pick` 이 멎은 것이라
        #   고칠 자리가 `impact_i` 다 — 여기서는 알려 주기만 한다.
        r["stall_note"] = f"고르기가 {stall}번 멎었다 (같은 칸이 잇달아 뽑힘)"
    return r


def suggest_span(idx_a: int, idx_b: int, n: int) -> tuple[int, int]:
    """튀는 자리를 감싸는 `4k+1` 구간. 양끝은 **성한 칸**이어야 하므로 한 칸씩 물린다.

    ★ **0번 칸은 못 박지 마라.** Wan I2V 의 0번은 넣어 준 입력 그대로이고 1번부터가
      모델이 다시 그린 것이라 그 사이에 결이 한 번 튄다(docs/SPRITE.md 1-6 ·
      `_pingpong` 이 `lo=1` 로 0번을 건너뛰는 것과 같은 까닭). 0번을 다리의 기둥으로
      쓰면 그 결 차이를 구간 안으로 끌고 들어온다.
    """
    a, b = max(1, idx_a - 1), min(n - 1, idx_b + 1)
    while not span_ok(a, b):
        if b < n - 1:
            b += 1
        elif a > 1:
            a -= 1
        else:
            break
    return a, b


# --------------------------------------------------------------------------
# 고치기 — 구간을 다시 구워 끼워 넣는다
# --------------------------------------------------------------------------
def bridge(uid: str, anim: str, a: int, b: int, *, route: str, tag: str,
           seed: int, size: int, steps: int, split: int, speed_w: float,
           view: str, keep: bool) -> dict:
    """클립의 `a`~`b` 칸을 다시 굽는다. **양끝 두 칸은 원본 그대로 남는다.**"""
    d = clip_dir(uid, anim, route, tag)
    fr = SP._load_dir(d)
    if not span_ok(a, b):
        raise SystemExit(f"{uid}_{anim}: 구간 {a}~{b} 은 4k+1 이 아니다")
    if b >= len(fr):
        raise SystemExit(f"{uid}_{anim}: 구간 끝 {b} 이 칸 수 {len(fr)} 를 넘는다")

    u = U.load([uid])[0]
    # ★ 못 박을 두 칸을 **캐릭터마다 다른 이름**으로 올린다. `W.upload` 는 basename 을
    #   그대로 쓰므로 `f_0005.png` 로 올리면 캐릭터끼리 서로의 입력을 덮어쓴다.
    tmp = os.path.join(OUT, route, "repair")
    os.makedirs(tmp, exist_ok=True)
    pa = os.path.join(tmp, f"br_{uid}_{anim}_a.png")
    pb = os.path.join(tmp, f"br_{uid}_{anim}_b.png")
    fr[a].save(pa)
    fr[b].save(pb)

    act = (U.ATTACK_ACTION if anim == "attack" else U.IDLE_ACTION)[u["family"]]
    pos = (f"{view} view pixel art sprite of a character, {act}, "
           f"solid magenta background, no camera movement, static camera, full body, "
           f"the character stays in the same place and keeps the same design")
    g = PL.graph(W.upload(pa), pos, seed=seed, length=b - a + 1, size=size,
                 loras=[("speed", speed_w)], steps=steps, split=split,
                 end_image=W.upload(pb))
    outs = W.run(g, f"{uid}_{anim} 다리 {a}~{b}")
    if len(outs) != b - a + 1:
        raise SystemExit(f"{uid}_{anim}: {b - a + 1}칸을 시켰는데 {len(outs)}칸이 왔다")

    before = classify(fr, anim, u["family"])
    if keep:
        bak = d + "_before"
        if not os.path.isdir(bak):
            shutil.copytree(d, bak)

    # ★ 양끝은 **안 덮는다.** 못 박은 칸이므로 원본과 같아야 하고, 그래야 이 구간
    #   바깥의 걸음이 한 톨도 안 달라진다.
    for i in range(1, b - a):
        shutil.copyfile(outs[i], os.path.join(d, "f_%04d.png" % (a + i)))
    after = classify(SP._load_dir(d), anim, u["family"])
    return {"span": [a, b], "before": before, "after": after}


# --------------------------------------------------------------------------
def load_table() -> dict:
    if not os.path.exists(TABLE):
        return {}
    return json.load(open(TABLE, encoding="utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", default="krea", choices=("sdxl", "krea"))
    ap.add_argument("--tag", default="")
    ap.add_argument("--scan", action="store_true", help="재기만 한다 (GPU 안 씀)")
    ap.add_argument("--apply", action="store_true", help="repairs.json 대로 고친다")
    ap.add_argument("--only", default="", help="`<id>_<anim>` 쉼표로")
    ap.add_argument("--span", default="", help="`a,b` — 손으로 구간을 줄 때")
    ap.add_argument("--seed", type=int, default=W.DEF_SEED)
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--steps", type=int, default=DEF_STEPS)
    ap.add_argument("--split", type=int, default=DEF_SPLIT)
    ap.add_argument("--speed-w", type=float, default=DEF_SPEED_W)
    ap.add_argument("--view", default="front")
    ap.add_argument("--keep", action="store_true", default=True,
                    help="고치기 전 클립을 `_before` 로 남긴다 (기본 켬)")
    a = ap.parse_args()

    base = os.path.join(OUT, a.route, "clips" + a.tag)
    if not os.path.isdir(base):
        raise SystemExit(f"클립이 없다: {base}")
    want = [s for s in a.only.split(",") if s]
    names = want or sorted(d for d in os.listdir(base)
                           if os.path.isdir(os.path.join(base, d)))

    if a.scan or not a.apply:
        us = {u["id"]: u for u in U.load(U.all_ids())}
        dead, jump, ok = [], [], 0
        for nm in names:
            uid, _, anim = nm.rpartition("_")
            if uid not in us:
                continue
            r = classify(SP._load_dir(os.path.join(base, nm)), anim, us[uid]["family"])
            if r["kind"] == "dead":
                dead.append((nm, r))
            elif r["kind"] == "jump":
                jump.append((nm, r))
            else:
                ok += 1
        print(f"클립 {len(names)}개 — 멀쩡 {ok} · 튐 {len(jump)} · 죽음 {len(dead)}\n")
        print("=== 튐 — ★다리로 고칠 수 있다 ===")
        for nm, r in sorted(jump, key=lambda x: -x[1]["max"] / max(x[1]["med"], 1e-9)):
            n = len(os.listdir(os.path.join(base, nm)))
            s = suggest_span(r["at"][0], r["at"][1], n)
            print(f"  {nm:<22} {r['why']}")
            print(f"  {'':<22} → 구간 {s[0]},{s[1]}")
        print("\n=== 죽음 — ☆다리로는 못 고친다 (씨앗을 다시 굴려라) ===")
        for nm, r in sorted(dead, key=lambda x: x[1]["amp"]):
            print(f"  {nm:<22} {r['why']}")
        return 0

    tbl = load_table()
    if a.span:
        if len(names) != 1:
            raise SystemExit("--span 은 --only 로 하나만 줄 때 쓴다")
        x, y = (int(v) for v in a.span.split(","))
        plan = {names[0]: {"span": [x, y], "why": "손으로 준 구간"}}
    else:
        plan = {k: v for k, v in tbl.items() if not want or k in want}
    if not plan:
        print(f"고칠 것이 없다 ({TABLE} 가 비었다). 먼저 --scan 을 봐라")
        return 0

    # ★ 없는 클립은 **건너뛴다.** 표에 적힌 캐릭터를 아직 안 구운 채로 run50 을 돌리면
    #   여기서 멈추는데, 그러면 뒤에 남은 단계가 통째로 안 돈다 — 「한 명이 실패해도
    #   나머지는 얹는다」(CLAUDE.md 18-1 · sprite_post 의 KeyedAway 와 같은 규칙).
    miss = [nm for nm in plan
            if not os.path.isdir(clip_dir(*nm.rpartition("_")[::2], a.route, a.tag))]
    for nm in miss:
        print(f"  {nm}: 클립이 없다 — 건너뜀")
        plan.pop(nm)
    if not plan:
        print("고칠 클립이 하나도 없다")
        return 0

    W.serve()
    done = {}
    for nm, spec in plan.items():
        uid, _, anim = nm.rpartition("_")
        x, y = spec["span"]
        r = bridge(uid, anim, x, y, route=a.route, tag=a.tag,
                   seed=spec.get("seed", a.seed), size=a.size, steps=a.steps,
                   split=a.split, speed_w=a.speed_w, view=a.view, keep=a.keep)
        b0, b1 = r["before"], r["after"]
        print(f"  {nm}: 튐 {b0['max'] / max(b0['med'], 1e-9):.1f}배 "
              f"→ {b1['max'] / max(b1['med'], 1e-9):.1f}배 · "
              f"진폭 {b0['amp']:.4f} → {b1['amp']:.4f}")
        done[nm] = r
    print(f"\n고친 것 {len(done)}개 — 이제 sprite_post 를 다시 돌려라")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
