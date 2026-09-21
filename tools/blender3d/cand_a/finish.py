#!/usr/bin/env python3
"""후보 A · 6단계 + 시트 + 잣대 — 렌더 낱장을 게임이 먹을 수 있는 꼴로 굳힌다.

    python3 tools/blender3d/cand_a/finish.py build/b3d/cand_a

★ 후처리는 **`post.clean_one()` 하나만** 부른다. 그 속은 공식 파이프라인의
  `tools/sprite/pixels.py`(quantize · add_outline · binarize_alpha)라, 두 길의 차이가
  「후처리 코드가 달라서」가 아니라 **원본 프레임의 차이**로만 남는다.
"""
import sys, json, shutil
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent.parent / "sprite"))
import spec      # noqa: E402
import post      # noqa: E402  ← 6단계. 고치지 않는다
import pixels    # noqa: E402  ← 공식 규격. 읽기만 한다
import measure   # noqa: E402

UNIT = "jokull"
ELEM = "ice"


def clean_all(root: Path, palette):
    src, dst = root / "5_frames", root / "6_clean"
    if dst.exists():
        shutil.rmtree(dst)
    n = 0
    for f in sorted(src.rglob("*.png")):
        o = dst / f.relative_to(src)
        o.parent.mkdir(parents=True, exist_ok=True)
        post.clean_one(f, palette, outline=True).save(o)
        n += 1
    return n


def pack(root: Path, act: str, name: str):
    d = root / "6_clean" / act / spec.GAME_DIR
    ims = [Image.open(p).convert("RGBA") for p in sorted(d.glob("*.png"))]
    sheet = pixels.pack_sheet(ims, spec.CELL[0])
    out = root / f"{UNIT}_{act}.png"
    sheet.save(out)
    return out, sheet.size, len(ims)


def anchor_scale(root: Path):
    """엔진 계약 — 기준점 · 배율 · 총구. 전부 **실제 픽셀에서** 잰다."""
    idle0 = Image.open(root / "6_clean/idle" / spec.GAME_DIR / "0001.png").convert("RGBA")
    st = measure.frame_stats(idle0)
    x0, y0, x1, y1 = st["bbox"]
    px = idle0.load()
    # 발 가로 가운데 = 맨 아랫 **여섯 줄**의 알파 무게중심.
    # ★ 세 줄만 보면 안 된다 — 내림각 20도라 카메라에 가까운 앞발이 뒷발보다
    #   3px 아래에 찍혀서, 세 줄 안에는 **한 발밖에 안 들어온다**(실측 anchor.x 가
    #   50 이 아니라 43 으로 나왔다). 여섯 줄이면 두 발이 다 든다.
    xs = [x for y in range(y1 - 6, y1) for x in range(96) if px[x, y][3]]
    ax = round(sum(xs) / max(1, len(xs)), 1)
    body_h = y1 - y0
    scale = round(spec.unit_h(1) / body_h, 4)

    hit = spec.ACTIONS["attack"]["hit"]
    him = Image.open(root / "6_clean/attack" / spec.GAME_DIR
                     / f"{hit + 1:04d}.png").convert("RGBA")
    hp = him.load()
    # 총구 = 놓는 칸에서 **가장 앞(+x)으로 나간 점** = 칼끝. 검사는 x>0 만 본다.
    best = None
    for y in range(96):
        for x in range(95, -1, -1):
            if hp[x, y][3]:
                if best is None or x > best[0]:
                    best = (x, y)
                break
    mz = {"x": int(best[0] - ax), "y": int(best[1] - y1)}
    return {"anchor": {"x": ax, "y": float(y1)}, "body_h": body_h, "body_w": x1 - x0,
            "scale": scale, "muzzle_at": mz, "hit_frame": hit,
            "hit_ms": int(round(1000.0 * hit / spec.FPS))}


def loop_seam(root: Path, act="idle"):
    """루프 이음매 — 마지막 칸과 첫 칸이 **다르되 튀지 않는가**.
    다르지 않으면 한 칸이 낭비이고, 너무 다르면 이어질 때 툭 끊긴다."""
    d = root / "6_clean" / act / spec.GAME_DIR
    ps = sorted(d.glob("*.png"))
    a = Image.open(ps[0]).convert("RGBA")
    b = Image.open(ps[-1]).convert("RGBA")
    pa, pb = a.load(), b.load()
    diff = sum(1 for y in range(96) for x in range(96) if pa[x, y] != pb[x, y])
    mid = Image.open(ps[len(ps) // 2]).convert("RGBA").load()
    far = sum(1 for y in range(96) for x in range(96) if pa[x, y] != mid[x, y])
    return {"last_vs_first_px": diff, "mid_vs_first_px": far}


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/b3d/cand_a")
    pal = spec.palette_for(ELEM)
    n = clean_all(root, pal)
    sheets = {}
    for act in ("idle", "attack"):
        p, size, k = pack(root, act, UNIT)
        sheets[act] = {"path": str(p), "size": list(size), "frames": k,
                       "width_mod_frames": size[0] % k}
    m = measure.run(str(root / "6_clean"), pal)
    a = anchor_scale(root)
    rep = {"unit": UNIT, "elem": ELEM, "cleaned": n, "sheets": sheets,
           "contract": a, "loop": loop_seam(root), "measure": m}
    (root / "cand_a_report.json").write_text(
        json.dumps(rep, ensure_ascii=False, indent=1))
    print("FINISH_JSON " + json.dumps({"cleaned": n, "contract": a,
                                       "loop": rep["loop"],
                                       "sheets": {k: v["size"] for k, v in sheets.items()}},
                                      ensure_ascii=False))


main()
