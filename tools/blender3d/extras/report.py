#!/usr/bin/env python3
"""4 · 보고용 비교 자료 — `report_data.json` 하나에 숫자를 다 모으고, 결론 그림 한 장.

    python3 tools/blender3d/extras/report.py

모으는 것 다섯
  1. 두 길의 qc 12줄  (공식 = `build/b3d/qc_baseline_jokull.json` · 3D = `7_sheet/qc.json`)
  2. 두 길의 비용 실측 — 공식은 `docs/SPRITE.md` 의 값 + **`build/sprite/krea/` 를 세어
     실제로 몇 장을 버렸는가** + 파일 mtime 으로 잰 **실제 벽시계 시간**
  3. 두 길의 그림 잣대 — 채움비 · 밝기 중앙값 · 고유색 · 몸 높이 · 배율
  4. `anim.json` 두 개
  5. `side_by_side.png` — 공식 attack 12칸과 3D attack 6칸
"""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import mx    # noqa: E402
import spec  # noqa: E402

ROOT = spec.ROOT
UNIT = "jokull"
OFF_DIR = ROOT / "art/anim" / UNIT
B3D_DIR = spec.OUT / UNIT / "7_sheet"
KREA = ROOT / "build/sprite/krea"
WAN_FRAMES_PER_CLIP = 33            # docs/SPRITE.md 규격


# ---------------------------------------------------------------- qc 12줄
def qc12(path: Path) -> dict:
    """qc.json 을 12줄로 편다. 1~8 은 시트마다 있으므로 **제일 나쁜 시트**를 남긴다."""
    q = mx.load(path)
    rows: dict = {}
    for s in q["sheets"]:
        for c in s["checks"]:
            k = str(c["no"])
            cur = rows.get(k)
            if cur is None or (cur["ok"] and not c["ok"]):
                rows[k] = {"no": c["no"], "name": c["name"], "ok": c["ok"],
                           "value": c["value"], "limit": c["limit"], "sheet": s["name"]}
    for c in q.get("shared", []):
        rows[str(c["no"])] = {"no": c["no"], "name": c["name"], "ok": c["ok"],
                              "value": c["value"], "limit": c["limit"], "sheet": "(공통)"}
    return {"rows": [rows[str(i)] for i in range(1, 13) if str(i) in rows],
            "fail_n": q.get("fail_n"),
            "palette_n": q.get("palette_n"), "elem": q.get("elem"),
            "sheets": [{"name": s["name"], "frames": s["frames"], "loop": s["loop"]}
                       for s in q["sheets"]]}


# ---------------------------------------------------------------- 비용
def count_clips() -> dict:
    """★ 씨앗·세기 사냥으로 **몇 장을 더 구웠나**. 최종은 `clips/` 100장이다."""
    per = {}
    for d in sorted(KREA.glob("clips*")):
        if not d.is_dir():
            continue
        dirs = [x for x in d.iterdir() if x.is_dir()]
        pngs = sum(1 for _ in d.rglob("*.png"))
        ts = sorted(p.stat().st_mtime for p in d.rglob("*.png"))
        per[d.name] = {"clip_dirs": len(dirs), "frames": pngs,
                       "span_min": round((ts[-1] - ts[0]) / 60.0, 1) if len(ts) > 1 else 0.0,
                       "first": time.strftime("%m-%d %H:%M", time.localtime(ts[0])) if ts else "",
                       "last": time.strftime("%m-%d %H:%M", time.localtime(ts[-1])) if ts else ""}
    final = per.get("clips", {}).get("clip_dirs", 0)
    extra = sum(v["clip_dirs"] for k, v in per.items() if k != "clips")
    total = final + extra
    return {"per_dir": per, "final_clips": final, "discarded_clips": extra,
            "total_clips_baked": total,
            "waste_ratio": round(extra / max(1, final), 3),
            "wan_frames_rendered": total * WAN_FRAMES_PER_CLIP,
            "wan_frames_kept": final * WAN_FRAMES_PER_CLIP}


def doc_numbers() -> dict:
    """docs/SPRITE.md 에 적힌 값을 **글에서 그대로 긁어** 온다 (손으로 옮겨 적지 않는다)."""
    txt = (ROOT / "docs/SPRITE.md").read_text()
    out = {}
    m = re.search(r"클립 한 장 \|\s*\*\*(\d+)~(\d+)초\*\*", txt)
    if m:
        out["clip_sec"] = [int(m.group(1)), int(m.group(2))]
    m = re.search(r"run50\.sh` 하나가 원화부터 엔진 반입까지 돌린다\(약 (\d+)분\)", txt)
    if m:
        out["run50_min"] = int(m.group(1))
    m = re.search(r"\|\s*(\d+)\s*fps\s*\|", txt)
    if m:
        out["fps"] = int(m.group(1))
    return out


def cost_official() -> dict:
    c = count_clips()
    d = doc_numbers()
    clips = c["per_dir"].get("clips", {})
    span = clips.get("span_min", 0.0)
    n = max(1, c["final_clips"])
    return {
        "doc": d,
        "clips": c,
        "measured_wall": {
            "final_run_min": span,
            "final_run_sec_per_clip": round(span * 60.0 / n, 1),
            "final_run_sec_per_frame": round(span * 60.0 / (n * WAN_FRAMES_PER_CLIP), 3),
            "note": "build/sprite/krea/clips 의 파일 mtime 처음~끝. 100장을 굽는 데 걸린 벽시계",
        },
        "per_char": {
            "clips": 2,
            "frames_generated": 2 * WAN_FRAMES_PER_CLIP,
            "frames_used": 8 + 12,
            "frame_waste_ratio": round(1.0 - (8 + 12) / (2.0 * WAN_FRAMES_PER_CLIP), 3),
            "note": "한 캐릭터가 idle 8칸 + attack 12칸을 쓰는데 Wan 은 33칸짜리 클립 둘을 낸다",
        },
    }


def cost_3d() -> dict:
    rec = mx.load(mx.OUT / "recolor" / "report.json")
    given = {
        "tris": 1516, "bones": 18,
        "render_sec_per_frame": 0.0301, "pipeline_sec": 4.71,
        "note": "앞 단계(mk/run.sh)가 요쿨 하나를 0->7 단계로 돌린 실측",
    }
    d8 = mx.load(mx.OUT / "dirs_data.json")
    return {
        "given": given,
        "measured_here": {
            "recolor_5elem_total_sec": rec["total_sec"],
            "recolor_render_sec": rec["total_render_sec"],
            "recolor_renders": rec["renders_total"],
            "recolor_sec_per_render": round(rec["total_render_sec"] / rec["renders_total"], 4),
            "blender_boot_sec": rec["boot_sec"],
            "dirs8_out_frames": d8["summary"]["frames"],
            "note": "렌더 횟수에는 정렬 되돌이와 번호+깊이 패스가 다 들어 있다",
        },
        "modeling_hours": None,
        "solana_time_log": (mx.load(spec.OUT / "solana" / "time_log.json")
                            if (spec.OUT / "solana" / "time_log.json").exists() else None),
    }


# ---------------------------------------------------------------- 그림 잣대
def sheet_metrics(sheet: Path, n: int) -> dict:
    fr = mx.strip_frames(sheet, n)
    ms = [mx.measure(f) for f in fr]
    a = mx.agg(ms)
    a["fill_ratio_f0"] = ms[0]["fill_ratio"]
    a["v_median_f0"] = ms[0]["v_median"]
    a["sat_median_f0"] = mx.sat_median(fr[0])
    a["body_h_f0"] = ms[0]["body_h"]
    a["body_w_f0"] = ms[0]["body_w"]
    return a


def image_metrics() -> dict:
    off = mx.load(OFF_DIR / "anim.json")
    b3d = mx.load(B3D_DIR / "anim.json")
    out = {}
    for tag, d, aj in (("official", OFF_DIR, off), ("b3d", B3D_DIR, b3d)):
        per = {}
        for act, c in aj["clips"].items():
            f = d / f"{UNIT}_{act}.png"
            if f.exists():
                per[act] = sheet_metrics(f, c["frames"])
        out[tag] = {
            "clips": per,
            "scale": aj["scale"],
            "static": aj["static"],
            "anchor": aj["anchor"],
            "muzzle_at": aj["muzzle_at"],
            "hit_ms": aj["hit_ms"],
            "draw_h_px": round(aj["scale"] * aj["static"]["h"], 1),
        }
    return out


# ---------------------------------------------------------------- 본체
def main() -> int:
    u = spec.roster_unit(UNIT)
    data = {
        "unit": {k: u[k] for k in ("id", "en", "ko", "tier", "tier_i", "elem",
                                   "weapon", "bullet", "role", "profile", "sc",
                                   "color", "unit_h") if k in u},
        "qc": {
            "official": qc12(spec.OUT / "qc_baseline_jokull.json"),
            "b3d": qc12(B3D_DIR / "qc.json"),
        },
        "cost": {"official": cost_official(), "b3d": cost_3d()},
        "image": image_metrics(),
        "anim_json": {
            "official": mx.load(OFF_DIR / "anim.json"),
            "b3d": mx.load(B3D_DIR / "anim.json"),
        },
        "extras": {
            "recolor": mx.load(mx.OUT / "recolor_data.json"),
            "dirs": mx.load(mx.OUT / "dirs_data.json"),
            "timing": mx.load(mx.OUT / "timing_data.json"),
        },
    }
    # 두 길의 qc 를 나란히 세워 어긋난 줄만 뽑는다
    a = {r["no"]: r for r in data["qc"]["official"]["rows"]}
    b = {r["no"]: r for r in data["qc"]["b3d"]["rows"]}
    data["qc"]["diff"] = [
        {"no": i, "name": (a.get(i) or b.get(i))["name"],
         "official": a.get(i, {}).get("ok"), "b3d": b.get(i, {}).get("ok"),
         "official_value": a.get(i, {}).get("value"),
         "b3d_value": b.get(i, {}).get("value")}
        for i in range(1, 13) if a.get(i, {}).get("ok") != b.get(i, {}).get("ok")
    ]
    # ---- 두 길의 처리량을 **같은 자**로 (시트에 실린 프레임 한 장당 몇 초인가) ----
    co, cb = data["cost"]["official"], data["cost"]["b3d"]
    shipped_off = 50 * (8 + 12)                      # 쉰 명 x (idle 8 + attack 12)
    wan_min = sum(v["span_min"] for v in co["clips"]["per_dir"].values())
    d8 = data["extras"]["dirs"]
    b3d_shipped = sum(c["frames"] for c in data["anim_json"]["b3d"]["clips"].values())
    data["cost"]["compare"] = {
        "official": {
            "frames_rendered": co["clips"]["wan_frames_rendered"],
            "frames_shipped_50": shipped_off,
            "render_to_ship_ratio": round(co["clips"]["wan_frames_rendered"] / shipped_off, 2),
            "wan_wall_min_all_runs": round(wan_min, 1),
            "sec_per_shipped_frame": round(wan_min * 60.0 / shipped_off, 3),
            "note": "clips* 디렉터리 전부의 mtime 폭을 더한 값. 마스터 생성·후처리·사람이 고르는 시간은 안 들었다",
        },
        "b3d": {
            "renders_per_output_frame": round(429 / 96.0, 2),
            "sec_per_output_frame": round(11.84 / 96.0, 4),
            "frames_shipped_1": b3d_shipped,
            "pipeline_sec_per_char": cb["given"]["pipeline_sec"],
            "note": "렌더 한 장 0.0276초인데 출력 한 칸에 4.47장이 든다 — 발밑 픽셀 정렬 되돌이와 번호+깊이 패스",
        },
        "speedup_sec_per_shipped_frame": round(
            (wan_min * 60.0 / shipped_off) / (11.84 / 96.0), 1),
    }
    mx.save(mx.OUT / "report_data.json", data)
    side_by_side(data)
    print("report_data.json — qc 어긋난 줄 %d개 · 공식 실패 %d · 3D 실패 %d"
          % (len(data["qc"]["diff"]), data["qc"]["official"]["fail_n"],
             data["qc"]["b3d"]["fail_n"]))
    return 0


# ---------------------------------------------------------------- 결론 그림
def side_by_side(data: dict) -> Path:
    Z = 3
    off = data["anim_json"]["official"]
    b3d = data["anim_json"]["b3d"]
    n_off = off["clips"]["attack"]["frames"]
    n_b3d = b3d["clips"]["attack"]["frames"]
    CW = 96 * Z + 6
    LAB = 150
    W = LAB + CW * max(n_off, n_b3d) + 24
    ROWH = 96 * Z + 60
    GAME_Z = 2.1
    GROUND_H = int(96 * 1.30 * GAME_Z) + 96
    H = 86 + ROWH * 2 + GROUND_H + 450
    img = Image.new("RGB", (W, H), mx.BG)
    dr = ImageDraw.Draw(img)
    f20, f14, f12, f11, f10 = mx.font(20), mx.font(14), mx.font(12), mx.font(11), mx.font(10)

    dr.text((12, 10), "요쿨 attack — 공식 길(Wan 2.2 I2V) 12칸  vs  3D 길(Blender 툰) 6칸 · 3배 확대",
            font=f20, fill=mx.HL)
    c = data["cost"]
    dr.text((12, 40),
            "공식: 클립 한 장 %d~%d초(docs) · 실측 벽시계 %.1f분에 100장 = 장당 %.1f초 · "
            "씨앗/세기 사냥으로 %d장을 더 구웠다(최종 %d장 대비 %.0f%%) · Wan 이 실제로 렌더한 프레임 %d장"
            % (c["official"]["doc"].get("clip_sec", [21, 27])[0],
               c["official"]["doc"].get("clip_sec", [21, 27])[1],
               c["official"]["measured_wall"]["final_run_min"],
               c["official"]["measured_wall"]["final_run_sec_per_clip"],
               c["official"]["clips"]["discarded_clips"],
               c["official"]["clips"]["final_clips"],
               c["official"]["clips"]["waste_ratio"] * 100,
               c["official"]["clips"]["wan_frames_rendered"]),
            font=f11, fill=mx.DIM)
    dr.text((12, 58),
            "3D: 96칸 한 장 %.4f초 · 0->7단계 통째로 %.2f초 · 삼각형 %d · 뼈 %d · "
            "버린 장이 없다(씨앗이 없으니 사냥할 것도 없다)"
            % (c["b3d"]["given"]["render_sec_per_frame"], c["b3d"]["given"]["pipeline_sec"],
               c["b3d"]["given"]["tris"], c["b3d"]["given"]["bones"]),
            font=f11, fill=mx.DIM)

    y = 86
    rows = [("공식 (Wan 2.2 I2V)", OFF_DIR / f"{UNIT}_attack.png", n_off, off),
            ("3D (Blender 로우폴리 툰)", B3D_DIR / f"{UNIT}_attack.png", n_b3d, b3d)]
    for title, path, n, aj in rows:
        hit = aj["clips"]["attack"]["hit_frame"]
        dr.text((12, y + 6), title, font=f14, fill=mx.FG)
        dr.text((12, y + 28), "%d칸 · hit %d · hit_ms %d" % (n, hit, aj["hit_ms"]),
                font=f11, fill=mx.DIM)
        dr.text((12, y + 46), "몸 %dx%d · 배율 %.4f" %
                (aj["static"]["w"], aj["static"]["h"], aj["scale"]), font=f11, fill=mx.DIM)
        dr.text((12, y + 64), "그리는 키 %.0fpx" % (aj["scale"] * aj["static"]["h"]),
                font=f11, fill=mx.DIM)
        fr = mx.strip_frames(path, n)
        for i, f in enumerate(fr):
            x = LAB + i * CW
            if i == hit:
                dr.rectangle([x - 3, y - 3, x + 96 * Z + 2, y + 96 * Z + 2],
                             outline=mx.HL, width=2)
            z = mx.nn(f, Z)
            img.paste(z, (x, y), z)
            dr.text((x + 2, y + 96 * Z + 6), "%s%d" % ("★" if i == hit else "", i),
                    font=f11, fill=mx.HL if i == hit else mx.DIM)
        y += ROWH

    # ---- 게임이 그리는 키로 겹쳐 놓기 ----
    dr.text((12, y + 4), "게임이 실제로 그리는 키로 (배율을 곱해 바닥선을 맞췄다 — 둘 다 몸높이 %dpx)"
            % data["unit"]["unit_h"], font=f14, fill=mx.HL)
    gy = y + GROUND_H - 40
    dr.line([(6, gy), (W - 6, gy)], fill=mx.LINE)
    x = 24
    for title, path, n, aj in rows:
        m = aj["scale"] * GAME_Z
        fr = mx.strip_frames(path, n)
        pitch = int(96 * m * 0.80)
        for i, f in enumerate(fr):
            z = mx.nn(f, m)
            ax, ay = aj["anchor"]["x"] * m, aj["anchor"]["y"] * m
            img.paste(z, (int(x + i * pitch - ax + pitch * 0.5), int(gy - ay)), z)
        dr.text((x + 4, gy + 6), title, font=f12, fill=mx.FG)
        x += pitch * n + 130
    y = gy + 30

    # ---- 표 ----
    y += 24
    dr.text((12, y), "qc 12검사 — 두 길 나란히", font=f14, fill=mx.HL)
    y += 22
    xs = [12, 60, 300, 430, 560, 700, 840]
    for xx, t in zip(xs, ["no", "검사", "공식", "값", "3D", "값", "누가 이겼나"]):
        dr.text((xx, y), t, font=f11, fill=mx.DIM)
    y += 18
    a = {r["no"]: r for r in data["qc"]["official"]["rows"]}
    b = {r["no"]: r for r in data["qc"]["b3d"]["rows"]}
    for i in range(1, 13):
        ra, rb = a.get(i), b.get(i)
        if not ra and not rb:
            continue
        nm = (ra or rb)["name"]
        va = "-" if not ra else str(ra["value"])[:22]
        vb = "-" if not rb else str(rb["value"])[:22]
        oa = None if not ra else ra["ok"]
        ob = None if not rb else rb["ok"]
        win = "같다" if oa == ob else ("3D" if ob else "공식")
        for xx, t, col in ((xs[0], str(i), mx.DIM), (xs[1], nm, mx.FG),
                           (xs[2], "통과" if oa else "실패" if oa is not None else "-",
                            mx.OK if oa else mx.NG if oa is not None else mx.DIM),
                           (xs[3], va, mx.DIM),
                           (xs[4], "통과" if ob else "실패" if ob is not None else "-",
                            mx.OK if ob else mx.NG if ob is not None else mx.DIM),
                           (xs[5], vb, mx.DIM),
                           (xs[6], win, mx.HL if win != "같다" else mx.DIM)):
            dr.text((xx, y), t, font=f11, fill=col)
        y += 19

    # ---- 그림 잣대 ----
    y += 14
    dr.text((12, y), "그림 잣대 (attack 시트)", font=f14, fill=mx.HL)
    y += 22
    im = data["image"]
    keys = [("채움비", "fill_ratio"), ("밝기 중앙값", "v_median"),
            ("고유색(최대)", "colors_max"), ("몸 높이", "body_h"), ("발밑", "bottom")]
    xs2 = [12, 200, 420, 640]
    for xx, t in zip(xs2, ["잣대", "공식", "3D", ""]):
        dr.text((xx, y), t, font=f11, fill=mx.DIM)
    y += 18
    for lbl, k in keys:
        va = im["official"]["clips"]["attack"][k]
        vb = im["b3d"]["clips"]["attack"][k]
        dr.text((xs2[0], y), lbl, font=f11, fill=mx.FG)
        dr.text((xs2[1], y), str(va), font=f11, fill=mx.DIM)
        dr.text((xs2[2], y), str(vb), font=f11, fill=mx.DIM)
        y += 19
    dr.text((xs2[0], y), "배율(scale)", font=f11, fill=mx.FG)
    dr.text((xs2[1], y), "%.4f" % im["official"]["scale"], font=f11, fill=mx.DIM)
    dr.text((xs2[2], y), "%.4f" % im["b3d"]["scale"], font=f11, fill=mx.DIM)

    out = mx.OUT / "side_by_side.png"
    img.save(out)
    print(out, img.size)
    return out


if __name__ == "__main__":
    raise SystemExit(main())
