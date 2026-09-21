#!/usr/bin/env python3
"""3 · 칸마다의 시간을 다시 살린다.

    python3 tools/blender3d/extras/timing.py

CLAUDE.md 18-4 는 '가장 짧은 칸이 놓는 칸이다 — 균등하게 나누면 언제 쐈는지가
안 읽힌다' 인데, 공식 파이프라인은 쉰 명이 **전부 83ms 등간격**이다. Wan 영상에서
잘라 낸 칸이라 어느 칸이 얼마나 걸렸는지를 알 길이 없어서 그렇게 됐다.
3D 는 칸마다 시간을 내가 정한다.

## 규격 하나만 어기지 않는다
`hit_ms == sum(ms[0:hit_frame])` — `pack.verify` 와 `core/anim.gd` 의
`Anim.hit_time()` 이 같은 산수를 쓰므로, 여기가 어긋나면 화면의 팔이 가장 앞으로
나가는 순간과 탄이 떠나는 순간이 갈린다.

## 두 벌을 굽는다
  even   83 x 6  (= 공식 규격 그대로)
  uneven 84 · 112 · 132 · **42(★놓는 칸)** · 54 · 74   — 총길이는 똑같이 498ms
둘 다 `qc.py` 12검사와 Godot 실기를 통과해야 한다.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import mx    # noqa: E402
import spec  # noqa: E402
import pack  # noqa: E402
import engine_check as EC  # noqa: E402

SRC = mx.OUT / "dirs8" / "clean"
META = mx.OUT / "dirs8" / "meta.json"
ROOT = mx.OUT / "timing"
UNIT = "jokull"
ELEM = "ice"
TIER_I = 1

#: ★ 불균등판. 총길이는 등간격판과 **똑같이** 498ms 다 — 그래야 나란히 놓고
#:   '같은 시간에 무엇을 보여 주는가'만 견줄 수 있다.
#:   0 준비 · 1·2 감음(2번이 제일 길다 = 힘을 모으는 자리) · ★3 타격(제일 짧다)
#:   · 4 흘림 · 5 되돌아옴
UNEVEN = [84, 112, 132, 42, 54, 74]
ROLE = ["준비", "감음", "감음 끝(정점)", "★ 타격", "흘림", "되돌아옴"]


def build(tag: str, ms: list[int] | None) -> dict:
    out = ROOT / tag
    if out.exists():
        shutil.rmtree(out)
    rep = pack.pack(UNIT, SRC, out, META, spec.GAME_DIR, TIER_I, ELEM, UNIT,
                    do_atlas=False, do_preview=False)
    aj = mx.load(out / "anim.json")
    if ms is not None:
        a = aj["clips"]["attack"]
        assert len(ms) == a["frames"], "칸 수가 안 맞는다"
        a["ms"] = list(ms)
        a["total_ms"] = sum(ms)
        aj["hit_ms"] = sum(ms[:a["hit_frame"]])
        mx.save(out / "anim.json", aj)
    return {"rep": rep, "anim": mx.load(out / "anim.json"), "dir": str(out)}


def contract(aj: dict) -> dict:
    """`pack.verify` 2번과 `core/anim.gd` 의 `Anim.hit_time()` 이 쓰는 산수 그대로."""
    a = aj["clips"]["attack"]
    want = sum(a["ms"][:a["hit_frame"]])
    wind = aj["hit_ms"] / 1000.0
    return {"hit_ms": aj["hit_ms"], "sum_ms_before_hit": want,
            "ok_hit_ms": aj["hit_ms"] == want,
            "wind_sec": round(wind, 3),
            "ok_wind_band": 0.05 <= wind <= 0.50,
            "total_ms": a["total_ms"], "ms": a["ms"],
            "shortest_is_hit": a["ms"].index(min(a["ms"])) == a["hit_frame"],
            "min_ms": min(a["ms"]), "max_ms": max(a["ms"]),
            "contrast": round(max(a["ms"]) / min(a["ms"]), 2)}


def run_qc(tag: str) -> dict:
    d = ROOT / tag
    outp = d / "qc.json"
    cmd = [sys.executable, str(HERE.parent / "qc.py"),
           "--sheets", ",".join(str(d / f"{UNIT}_{a}.png") for a in ("idle", "attack")),
           "--anim-json", str(d / "anim.json"),
           "--dirs", str(SRC / "idle"),
           "--out", str(outp)]
    r = subprocess.run(cmd, text=True, capture_output=True)
    if not outp.exists():
        return {"ok": False, "err": r.stderr[-800:]}
    q = mx.load(outp)
    return {"ok": q["fail_n"] == 0, "fail_n": q["fail_n"], "path": str(outp)}


def run_engine(tag: str) -> dict:
    """Godot 안에서 실제로 돌린다 — `engine_check.py` 와 같은 길이되 자리만 내 것."""
    import os
    d = ROOT / tag
    qcd = d / "engine"
    qcd.mkdir(parents=True, exist_ok=True)
    exe = EC.ensure_xvfb()
    env = dict(os.environ)
    env["DISPLAY"] = ":%d" % (EC.DISPLAY_NUM + 1)
    env["POCKER_NO_SAVE"] = "1"
    env["LD_LIBRARY_PATH"] = str(EC.XVFB_HOME / "usr/lib/aarch64-linux-gnu") + ":" + \
        env.get("LD_LIBRARY_PATH", "")
    xv = subprocess.Popen([str(exe), env["DISPLAY"], "-screen", "0", "1180x700x24",
                           "-nolisten", "tcp"], env=env,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.5)
        r = subprocess.run([str(EC.GODOT), "--path", str(spec.ROOT),
                            "--resolution", "1180x700",
                            "res://tools/blender3d/godot/b3d_shot.tscn", "--",
                            "--dir", str(d), "--out", str(qcd)],
                           env=env, text=True, capture_output=True, timeout=300)
    finally:
        xv.terminate()
    shots = sorted(qcd.glob("engine_*.png"))
    return {"ok": bool(shots) and r.returncode == 0, "shots": [s.name for s in shots],
            "rc": r.returncode, "out": str(qcd),
            "tail": r.stdout.strip().splitlines()[-3:] if r.stdout else []}


def survey_official() -> dict:
    """★ 공식 길의 쉰 명이 실제로 어떤 시간을 갖고 있는가 — 저장소를 세어 본다."""
    from collections import Counter
    ms_sig, hit_f, hit_ms, wind = Counter(), Counter(), Counter(), Counter()
    n = 0
    for p in sorted((spec.ROOT / "art/anim").glob("*/anim.json")):
        d = json.loads(p.read_text())
        n += 1
        for act, c in d["clips"].items():
            ms_sig["%s:%s" % (act, "/".join(str(v) for v in sorted(set(c["ms"]))))] += 1
        if "attack" in d["clips"]:
            hit_f[d["clips"]["attack"]["hit_frame"]] += 1
            hit_ms[d["hit_ms"]] += 1
    for m in re.finditer(r'"wind": ([0-9.]+)', (spec.ROOT / "core/roster.gd").read_text()):
        wind[m.group(1)] += 1
    return {"units": n, "ms_values": dict(ms_sig), "hit_frame": dict(hit_f),
            "hit_ms": dict(hit_ms), "roster_wind": dict(wind),
            "all_identical": len(hit_ms) == 1 and len(wind) == 1}


def main() -> int:
    data: dict = {"job": "timing", "variants": {}, "official_survey": survey_official()}
    for tag, ms in (("even", None), ("uneven", UNEVEN)):
        b = build(tag, ms)
        c = contract(b["anim"])
        q = run_qc(tag)
        e = run_engine(tag)
        data["variants"][tag] = {"contract": c, "qc": q, "engine": e,
                                 "dir": b["dir"]}
        print("%-7s ms=%s hit_ms=%d(%s) qc=%s engine=%s"
              % (tag, c["ms"], c["hit_ms"], "OK" if c["ok_hit_ms"] else "X",
                 "OK" if q["ok"] else "FAIL(%s)" % q.get("fail_n", q.get("err")),
                 "OK" if e["ok"] else "FAIL"))
    data["roles"] = ROLE
    mx.save(mx.OUT / "timing_data.json", data)
    draw(data)
    return 0


# ---------------------------------------------------------------- 그림
def draw(data: dict) -> Path:
    TL_W = 1420                      # 498ms 가 차지하는 가로
    LAB = 118
    W = LAB + TL_W + 40
    ROWH = 200
    SAMP = 26                        # 균등 시각 표본 수
    H = 96 + ROWH * 2 + 150 + 122
    img = Image.new("RGB", (W, H), mx.BG)
    dr = ImageDraw.Draw(img)
    f18, f13, f12, f11, f10 = mx.font(18), mx.font(13), mx.font(12), mx.font(11), mx.font(10)

    total = data["variants"]["even"]["contract"]["total_ms"]
    ppm = TL_W / float(total)
    dr.text((12, 10), "3 · 칸마다의 시간 — 등간격(공식 규격)과 불균등(3D 가 정한다)을 같은 총길이 %dms 로"
            % total, font=f18, fill=mx.HL)
    dr.text((12, 36),
            "띠의 가로가 곧 그 칸이 화면에 머무는 시간이다. 아래 눈금은 50ms. "
            "★ 는 놓는 칸(hit_frame %d) — 탄이 떠나는 순간이고, 'hit_ms = 그 앞 칸들의 합' 이 계약이다."
            % spec.ACTIONS["attack"]["hit"], font=f11, fill=mx.DIM)

    y = 74
    for tag, title in (("even", "등간격 — 83ms x 6 (공식 파이프라인 쉰 명이 전부 이것이다)"),
                       ("uneven", "불균등 — 감음을 길게 · 놓는 칸을 짧게 (3D 길만 할 수 있다)")):
        v = data["variants"][tag]
        c = v["contract"]
        d = Path(v["dir"])
        fr = mx.strip_frames(d / f"{UNIT}_attack.png", len(c["ms"]))
        hit = data["variants"][tag]["contract"]
        hf = spec.ACTIONS["attack"]["hit"]
        dr.text((12, y), title, font=f13, fill=mx.FG)
        dr.text((12, y + 20), "hit_ms %d · 대비 %.2f배 (제일 긴 칸 %d / 제일 짧은 칸 %d)"
                % (c["hit_ms"], c["contrast"], c["max_ms"], c["min_ms"]),
                font=f11, fill=mx.DIM)
        dr.text((12, y + 38), "qc 12검사 %s · Godot 실기 %s"
                % ("통과" if v["qc"]["ok"] else "실패", "통과" if v["engine"]["ok"] else "실패"),
                font=f11, fill=mx.OK if (v["qc"]["ok"] and v["engine"]["ok"]) else mx.NG)

        top = y + 56
        x = LAB
        for i, msv in enumerate(c["ms"]):
            w = msv * ppm
            is_hit = (i == hf)
            dr.rectangle([x, top, x + w - 2, top + 118],
                         fill=(58, 48, 26) if is_hit else (42, 42, 52),
                         outline=mx.HL if is_hit else (70, 70, 84))
            f = fr[i]
            img.paste(f, (int(x + w / 2 - 48), top + 12), f)
            dr.text((x + 4, top + 120), "%d  %dms" % (i, msv), font=f11,
                    fill=mx.HL if is_hit else mx.DIM)
            dr.text((x + 4, top + 134), ROLE[i], font=f10,
                    fill=mx.HL if is_hit else mx.DIM)
            x += w
        # 눈금
        gy = top + 152
        dr.line([(LAB, gy), (LAB + TL_W, gy)], fill=(90, 90, 108))
        for t in range(0, total + 1, 50):
            gx = LAB + t * ppm
            dr.line([(gx, gy - 4), (gx, gy + 4)], fill=(120, 120, 140))
            dr.text((gx - 8, gy + 6), str(t), font=f10, fill=mx.DIM)
        # 균등 시각 표본 — 눈이 실제로 보는 것
        sy = gy + 24
        dr.text((12, sy + 4), "%dms마다 본 것" % (total // SAMP), font=f10, fill=mx.DIM)
        acc = []
        s = 0
        for msv in c["ms"]:
            s += msv
            acc.append(s)
        for k in range(SAMP):
            t = (k + 0.5) * total / SAMP
            i = next((j for j, a in enumerate(acc) if t < a), len(acc) - 1)
            gx = LAB + k * (TL_W / SAMP)
            col = mx.HL if i == hf else (110, 130, 170)
            dr.rectangle([gx, sy, gx + TL_W / SAMP - 2, sy + 14], fill=col)
            dr.text((gx + 4, sy), str(i), font=f10, fill=(20, 20, 24))
        y += ROWH + 78

    def line(t, col=mx.FG, dy=20):
        nonlocal y
        dr.text((12, y), t, font=f12, fill=col)
        y += dy

    ce, cu = (data["variants"][k]["contract"] for k in ("even", "uneven"))
    line("★ 계약: hit_ms == sum(ms[0:hit_frame]) — 등간격 %d==%d · 불균등 %d==%d (둘 다 참)"
         % (ce["hit_ms"], ce["sum_ms_before_hit"], cu["hit_ms"], cu["sum_ms_before_hit"]),
         mx.OK)
    line("★ 놓는 칸이 제일 짧은가 (CLAUDE.md 18-4): 등간격 %s · 불균등 %s"
         % ("아니다 — 여섯 칸이 다 같다" if not ce["shortest_is_hit"] else "그렇다",
            "그렇다" if cu["shortest_is_hit"] else "아니다"),
         mx.FG)
    sv = data["official_survey"]
    line("★ 공식 길의 쉰 명은 %s — anim.json 의 ms 가 전부 83 하나뿐이고, hit_frame %s · hit_ms %s · "
         "roster 의 wind %s 초. 칸마다의 시간이라는 손잡이가 로스터 전체에서 값 하나로 굳어 있다."
         % ("전부 같다" if sv["all_identical"] else "제각각이다",
            "/".join(str(k) for k in sv["hit_frame"]),
            "/".join(str(k) for k in sv["hit_ms"]),
            "/".join(sv["roster_wind"])), mx.HL)
    line("★ 놓는 칸이 화면에 머무는 시간: 등간격 %dms · 불균등 %dms. 60fps 에서 %.1f프레임 -> %.1f프레임. "
         "3배속이면 %.1f프레임이라 한 프레임도 못 받는 순간이 생긴다 — 이것이 불균등의 대가다."
         % (ce["min_ms"], cu["min_ms"], ce["min_ms"] / 16.7, cu["min_ms"] / 16.7,
            cu["min_ms"] / 3 / 16.7), mx.DIM)
    out = mx.OUT / "timing.png"
    img.save(out)
    print(out, img.size)
    return out


if __name__ == "__main__":
    raise SystemExit(main())
