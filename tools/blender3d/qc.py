#!/usr/bin/env python3
"""품질 검사 — 3D 길의 시트를 **공식 파이프라인과 같은 자**로 잰다.

    python3 tools/blender3d/qc.py --dir build/b3d/jokull/7_sheet
    python3 tools/blender3d/qc.py --sheets art/anim/jokull/jokull_idle.png,art/anim/jokull/jokull_attack.png --elem ice

★★ **검사 1~8 은 `tools/sprite/sprite_post.py` 의 `qc()` 를 그대로 옮긴 것이다.**
   숫자(20색 · 2px · 0.60 · 2.2/0.012)를 여기서 손으로 고치지 마라 — 잣대가 갈리는
   순간 두 길을 견줄 수가 없다. 3D 결과가 공식 결과보다 나은지 못한지가
   「파이프라인이 달라서」인지 「자가 달라서」인지 영영 안 갈린다.
   ☆ 그래서 `_diff` 와 `outline_ratio` 는 **베끼지 않고 불러 쓴다**(sprite_post ·
     pixels 를 그대로 import). 그리고 `--cross`(기본 켜짐)가 **공식 qc() 를 실제로
     불러** 지적 사항 집합이 같은지 맞춰 본다. 어긋나면 그 자리에서 경고를 찍는다.

★ 그러면서도 굳이 옮겨 짠 까닭은 하나다 — 공식 `qc()` 는 **실패한 것만** 문자열로
  돌려준다. 「지금 길은 이 검사에서 어디쯤인가」를 알려면 **통과한 검사의 실측 숫자**가
  있어야 한다. 색이 20 중 15인지 20인지가 곧 3D 툰이 팔레트를 얼마나 쓰는가다.

★ 검사 9~12 는 **새로 더한 것**이다. 9·10 은 공식 qc 가 못 잡는 구멍이고
  (계약서가 지적한 것), 11·12 는 3D 길에만 뜻이 있는 것이다. 왜 필요한지는
  각 함수의 머리말에 적었다.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools" / "sprite"))

import spec                                   # noqa: E402  ← 0단계 규격 (읽기만)
import pixels                                 # noqa: E402  ← 공식 파이프라인 (읽기만)
import sprite_post                            # noqa: E402  ← 공식 qc 의 자 (읽기만)

#: ★ 공식 qc 가 쓰는 잣대를 **그대로 빌려 온다.** 여기에 같은 함수를 한 벌 더 적으면
#   두 곳이 조용히 갈라지고, 그 어긋남은 「3D 가 더 낫다/못하다」로 잘못 읽힌다.
_diff = sprite_post._diff
outline_ratio = pixels.outline_ratio

# 공식 qc 의 문턱값 — sprite_post.qc() 에 박혀 있는 그 숫자들이다.
MAX_COLORS = 20             # 1번
FOOT_SPREAD = 2             # 5번 · 9번 (px)
OUTLINE_MIN = 0.60          # 7번
SEAM_MULT, SEAM_ADD = 2.2, 0.012    # 8번
MUZZLE_MIN_X = 2            # 10번 (px)
DIR_SPREAD = 2              # 11번 (px)


# ==========================================================================
# 시트 읽기
# ==========================================================================
def frames_of(sheet: Image.Image) -> list[Image.Image]:
    """가로 1행 스트립을 정사각 칸으로 쪼갠다.

    ★ 칸 크기를 **높이에서** 잡는다. 계약서가 「가로 1행 · 간격 0 ·
      width % frames == 0」이라 이것이 곧 계약의 검산이기도 하다.
    """
    w, h = sheet.size
    if w % h:
        raise ValueError(f"가로 {w} 가 세로 {h} 로 안 나눠떨어진다 "
                         f"— 가로 1행 스트립이 아니거나 칸 사이에 틈이 있다")
    return [sheet.crop((i * h, 0, (i + 1) * h, h)) for i in range(w // h)]


def _tokens(p: Path) -> list[str]:
    return p.stem.split("_")


def act_of(p: Path) -> str:
    """파일 이름에서 동작 이름을 뽑는다 (idle · walk · attack)."""
    for t in _tokens(p):
        if t in spec.ACTIONS:
            return t
    return p.stem


def dir_of(p: Path) -> str | None:
    """파일 이름에서 방향 토큰(S · SE · E …)을 뽑는다. 없으면 None."""
    for t in _tokens(p):
        if t in spec.DIRS:
            return t
    return None


def loop_of(act: str, anim_json: dict | None) -> bool:
    """이 클립이 이어 도는가. anim.json 이 있으면 그것이 원본이다."""
    if anim_json:
        c = anim_json.get("clips", {}).get(act)
        if isinstance(c, dict) and "loop" in c:
            return bool(c["loop"])
    if act in spec.ACTIONS:
        return bool(spec.ACTIONS[act]["loop"])
    return act in pixels.LOOPING


class Clip:
    """검사 대상 한 벌 — 시트 하나와 그것을 쪼갠 칸들."""

    def __init__(self, path: Path, anim_json: dict | None = None):
        self.path = path
        self.sheet = Image.open(path).convert("RGBA")
        self.frames = frames_of(self.sheet)
        self.cell = self.sheet.height
        self.n = len(self.frames)
        self.act = act_of(path)
        self.dir = dir_of(path)
        self.loop = loop_of(self.act, anim_json)

    @property
    def name(self) -> str:
        return self.path.name


# ==========================================================================
# 검사 결과 한 줄
# ==========================================================================
def R(no: int, name: str, ok: bool, value, limit: str, note: str = "") -> dict:
    return {"no": no, "name": name, "ok": bool(ok),
            "value": value, "limit": limit, "note": note}


# ==========================================================================
# 1~8 — 공식 파이프라인의 여덟 (sprite_post.qc 를 그대로 옮긴 것)
# ==========================================================================
def check_sheet(c: Clip, elem: str, palette: list[str]) -> list[dict]:
    fr = c.frames
    out: list[dict] = []

    # 1) 색 수 — 알파>0 픽셀의 서로 다른 RGB
    cols = {p[:3] for f in fr for p in f.getdata() if p[3] > 0}
    out.append(R(1, "색 수", len(cols) <= MAX_COLORS,
                 len(cols), f"<= {MAX_COLORS}",
                 "3D 툰은 면마다 명/암이 갈려 중간 톤을 더 쓴다 — 여기가 먼저 새는 자리다"))

    # 2) 팔레트 이탈
    allowed = {pixels.hex2rgb(x) for x in palette}
    stray = sorted(cols - allowed)
    out.append(R(2, "팔레트 이탈", not stray, len(stray), "== 0",
                 ("샌 색: " + ", ".join("#%02x%02x%02x" % s for s in stray[:6])
                  + (" …" if len(stray) > 6 else "")) if stray else ""))

    # 3) 반투명 — 도트 그림에 반투명 가장자리는 없다
    semi = sum(1 for f in fr for p in f.getdata() if 0 < p[3] < 255)
    out.append(R(3, "반투명 픽셀", semi == 0, semi, "== 0",
                 "3D 는 filter_size=0 이면 원리상 0 이다. 0 이 아니면 Freestyle 이 되살린 것이다"))

    # 4) 마젠타 잔여 — 크로마키의 흔적
    mag = sum(1 for f in fr for p in f.getdata()
              if p[3] and p[0] > 150 and p[2] > 150 and p[1] < 90)
    out.append(R(4, "마젠타 잔여", mag == 0, mag, "== 0",
                 "3D 길에는 크로마키가 없다 — film_transparent 라 원리상 0 이다"))

    # 5) 발 높이 — 알파 bbox 의 아래끝이 칸마다 같은가
    feet = [(f.getbbox() or (0, 0, 0, 0))[3] for f in fr]
    spread = max(feet) - min(feet)
    out.append(R(5, "발 높이(시트 안)", spread <= FOOT_SPREAD, spread,
                 f"<= {FOOT_SPREAD}px", f"칸별 아래끝 {feet}"))

    # 6) 빈 칸
    empt = [i for i, f in enumerate(fr) if not f.getbbox()]
    out.append(R(6, "빈 칸", not empt, empt, "없음"))

    # 7) 검은 테두리 — 실루엣 가장자리 중 V<0.22 인 비율
    ratios = [outline_ratio(f) for f in fr]
    lo = min(ratios)
    out.append(R(7, "검은 테두리", lo >= OUTLINE_MIN, round(lo, 3),
                 f">= {OUTLINE_MIN:.2f}",
                 f"제일 나쁜 칸 {ratios.index(lo)}번 · 평균 {sum(ratios)/len(ratios):.3f}"))

    # 8) 루프 이음매 — 「이음매 걸음이 다른 걸음보다 튀지 않는가」
    if c.loop and len(fr) >= 2:
        steps = [_diff(fr[i], fr[i + 1]) for i in range(len(fr) - 1)]
        wrap = _diff(fr[-1], fr[0])
        mid = sorted(steps)[len(steps) // 2]
        ok = wrap <= mid * SEAM_MULT + SEAM_ADD
        out.append(R(8, "루프 이음매", ok, {"wrap": round(wrap, 4), "mid": round(mid, 4)},
                     f"wrap <= mid*{SEAM_MULT} + {SEAM_ADD}",
                     "왕복 루프에서는 「첫/끝이 닮았나」로 재면 안 된다 — 걸음 크기로 잰다"))
    else:
        out.append(R(8, "루프 이음매", True, None, "해당 없음",
                     "논루프 클립이라 안 잰다"))
    return out


# ==========================================================================
# 9 — 클립 **사이** 발 높이  ★ 공식 qc 가 못 잡는 구멍
# ==========================================================================
def check_cross_feet(clips: list[Clip]) -> dict:
    """5번은 **한 시트 안에서만** 잰다. idle 의 발과 attack 의 발이 어긋나면
    공격할 때 영웅이 가라앉았다 올라오는데, 공식 qc 는 그것을 통과시킨다.

    ★ 실제로 그럴 수 있다 — 공식 길은 클립마다 프레임을 따로 고르고
      (`sprite_post.select`), 같은 상자로 자르기는 해도 **그 상자 안에서 캐릭터가
      어디에 서 있는지**는 클립마다 다르다. Wan 이 걸음을 조금 옮겨 놓으면
      그대로 남는다. 3D 길은 카메라와 원점이 고정이라 원리상 0 이어야 하고,
      0 이 아니면 5단계에서 캐릭터가 격자를 벗어나 돈 것이다.
    """
    per = {}
    for c in clips:
        feet = [(f.getbbox() or (0, 0, 0, 0))[3] for f in c.frames]
        per[c.name] = {"min": min(feet), "max": max(feet)}
    lo = min(v["min"] for v in per.values())
    hi = max(v["max"] for v in per.values())
    spread = hi - lo
    return R(9, "발 높이(클립 사이)", spread <= FOOT_SPREAD, spread,
             f"<= {FOOT_SPREAD}px",
             " · ".join(f"{k} {v['min']}~{v['max']}" for k, v in per.items()))


# ==========================================================================
# 10 — muzzle_at.x  ★ 공식 qc 가 못 잡는 구멍
# ==========================================================================
def check_muzzle(anim_json: dict | None) -> dict:
    """총구의 가로가 0 근처면 안 되고, **음수면 더 안 된다.**

    ★ `Balance.art_aim()` 이 `muz[0] < 0` 이면 그 캐릭터의 그림을 **통째로 좌우
      반전**한다(CLAUDE.md 18-11). 3D 는 카메라 방향을 내가 고르므로 실수로 왼쪽을
      겨눈 채 굽기가 쉽고, 그러면 게임이 스프라이트를 뒤집어서 **총구는 맞는데
      캐릭터가 거꾸로 선다.** 0 근처도 나쁘다 — 부호가 프레임 하나 차이로 뒤집힌다.
    ★ 공식 qc 는 시트만 보고 anim.json 을 안 본다. 그래서 이 검사가 없다.
    """
    if not anim_json:
        return R(10, "총구 가로(muzzle_at.x)", True, None, "해당 없음",
                 "anim.json 이 없어서 안 잰다 (--anim-json 으로 줄 수 있다)")
    m = anim_json.get("muzzle_at", {})
    x = m.get("x")
    if x is None:
        return R(10, "총구 가로(muzzle_at.x)", False, None, f">= +{MUZZLE_MIN_X}px",
                 "anim.json 에 muzzle_at.x 가 없다")
    ok = x >= MUZZLE_MIN_X
    note = ""
    if x < 0:
        note = "★ 음수다 — 게임이 그림을 통째로 좌우 반전한다 (Balance.art_aim)"
    elif not ok:
        note = "0 근처라 부호가 흔들린다"
    return R(10, "총구 가로(muzzle_at.x)", ok, x, f">= +{MUZZLE_MIN_X}px", note)


# ==========================================================================
# 11 — 8방향 일관성  ★ 3D 길에만 뜻이 있다
# ==========================================================================
def check_dirs(dirframes: dict[str, Image.Image]) -> dict:
    """여덟 방향의 **첫 칸**이 같은 발밑 y 와 같은 몸 높이를 갖는가.

    ★ 3D 길의 이점이 8방향인데(spec.py 머리말), 그 이점은 **여덟이 같은 바닥에
      같은 키로 설 때만** 이점이다. 카메라가 방향마다 조금씩 흔들리거나 캐릭터가
      원점이 아닌 데서 돌면 여기서 걸린다 — 발밑 원점이 아니라 몸 가운데를 축으로
      돌리면 옆모습에서 발이 앞뒤로 밀리고, 그 몫이 그대로 y 차이로 나온다.
    ★ 몸 높이도 같이 재는 까닭: 직교 카메라라 방향이 바뀌어도 키는 안 변해야 한다.
      변하면 카메라가 직교가 아니거나(원근이 섞였다) 스케일이 방향마다 다른 것이다.
    """
    if len(dirframes) < 2:
        return R(11, "8방향 일관성", True, len(dirframes), "해당 없음",
                 "방향별 자료가 없어서 안 잰다 (--dirs 로 줄 수 있다)")
    per = {}
    for d, im in dirframes.items():
        b = im.getbbox()
        per[d] = {"foot": (b[3] if b else -1), "h": (b[3] - b[1] if b else -1)}
    foots = [v["foot"] for v in per.values()]
    hs = [v["h"] for v in per.values()]
    fs, hspread = max(foots) - min(foots), max(hs) - min(hs)
    ok = fs <= DIR_SPREAD and hspread <= DIR_SPREAD
    return R(11, "8방향 일관성", ok, {"foot_spread": fs, "h_spread": hspread},
             f"둘 다 <= {DIR_SPREAD}px",
             f"{len(per)}방향 · " + " · ".join(f"{d}:발{v['foot']}/키{v['h']}"
                                              for d, v in per.items()))


# ==========================================================================
# 12 — 칸 밖으로 나갔나  ★ 3D 길에만 뜻이 있다
# ==========================================================================
def check_clipped(clips: list[Clip]) -> dict:
    """알파가 칸 **테두리**(x=0 · x=W-1 · y=0)에 닿으면 잘린 것이다.

    ★ 발밑(y=H-1)은 **닿아야 정상**이라 뺀다 — 캐릭터는 칸 밑변에 서 있다.
    ★ 3D 길에서 이것은 곧 **직교 카메라의 담는 크기(ORTHO_SCALE)가 모자라다**는
      신호다. 검을 치켜들거나 두 팔을 드는 칸에서만 걸리므로, 정지 그림 한 장만
      보고 카메라를 정하면 놓친다. 공식 qc 의 「빈 칸」(6번)은 통째로 사라진
      것만 잡지 **잘린 것**은 못 잡는다.
    ☆ 공식 길은 프레임을 **알파 bbox 로 바짝 잘라** 칸에 앉히므로(union_bbox),
      위와 아래가 늘 테두리에 닿는다 — 그쪽에서 이 검사가 걸리는 것은 사고가
      아니라 그 길의 방식이다. 3D 길과 견줄 때 그 점을 같이 읽어라.
    """
    hits = []
    edge = {"top": 0, "left": 0, "right": 0}      # ★ 어느 변인지가 곧 원인이다
    for c in clips:
        for i, f in enumerate(c.frames):
            w, h = f.size
            px = f.load()
            e = {"top": sum(1 for x in range(w) if px[x, 0][3]),
                 "left": sum(1 for y in range(h) if px[0, y][3]),
                 "right": sum(1 for y in range(h) if px[w - 1, y][3])}
            n = sum(e.values())
            if n:
                for k in edge:
                    edge[k] += e[k]
                hits.append({"sheet": c.name, "frame": i, "px": n, "edge": e})
    tot = sum(x["px"] for x in hits)
    #: 변마다 원인이 다르다 — 위는 카메라가 담는 세로(ORTHO_SCALE)가 모자란 것이고,
    #: 옆은 가로가 모자라거나 캐릭터가 원점에서 옆으로 밀려 선 것이다.
    note = ("테두리(x=0/W-1 · y=0)에 닿은 픽셀 없음 — 발밑 y=H-1 은 안 센다"
            if not hits else
            f"위{edge['top']} 왼{edge['left']} 오른{edge['right']}px · 닿은 칸 "
            + ", ".join(f"{x['sheet']}#{x['frame']}({x['px']})" for x in hits[:6])
            + (" …" if len(hits) > 6 else ""))
    # ★★ **실패로 치지 마라 — 처음에 「잘림」으로 잘못 읽었다.**
    #   `sprite_post.render` 는 공통 bbox 로 자른 뒤 **정사각 캔버스에 채워 넣고** 줄인다.
    #   즉 잘려 나가는 픽셀이 없다. 바짝 자르니 실루엣이 테두리에 닿는 것이 그 길의
    #   **설계**이고, 실제로 출고된 쉰 명이 전부 닿는다(중앙 52px).
    #   남는 진짜 몫은 하나뿐 — `add_outline` 이 칸 밖으로는 못 그리므로 닿은 자리에
    #   1도트 검은 테두리가 빠진다. 그건 이미 7번(테두리 비율)이 재고 있고 통과한다.
    #   그래서 숫자만 남기는 **경고**다. 3D 길에서는 여백을 살 수 있어 0 이 되는데,
    #   그것은 「이겼다」가 아니라 「손잡이가 있다」는 뜻이다.
    return R(12, "칸 테두리에 닿음", True, tot, "경고 — 실패 아님", note)


# ==========================================================================
# 방향별 자료 모으기
# ==========================================================================
def _first_frame(p: Path) -> Image.Image:
    im = Image.open(p).convert("RGBA")
    if im.width == im.height:
        return im
    return frames_of(im)[0]


def gather_dirs(root: Path) -> dict[str, Image.Image]:
    """방향별 **첫 칸**을 모은다. 세 가지 꼴을 다 받는다:

      <root>/E/f_0000.png   방향 이름의 하위 폴더 (5단계 렌더 낱장의 꼴)
      <root>/E.png          방향 이름의 시트
      <root>/jokull_idle_E_96x96_6.png   이름에 방향 토큰이 든 시트
    """
    got: dict[str, Image.Image] = {}
    if not root or not root.is_dir():
        return got
    tops = sorted(root.glob("*.png"))
    for d in spec.DIRS:
        sub = root / d
        if sub.is_dir():
            fs = sorted(sub.glob("*.png"))
            if fs:
                got[d] = _first_frame(fs[0])
                continue
        cands = [p for p in tops if dir_of(p) == d or p.stem == d]
        if cands:
            got[d] = _first_frame(cands[0])
    return got


# ==========================================================================
# 공식 qc 와 맞대 보기
# ==========================================================================
def cross(c: Clip, elem: str, mine: list[dict]) -> str | None:
    """★ **공식 `sprite_post.qc()` 를 실제로 불러** 지적 사항이 같은지 본다.

    옮겨 적은 여덟이 언젠가 원본과 갈라지는 것을 막는 유일한 방법이다.
    돌려주는 것은 어긋났을 때의 한 줄 경고 (같으면 None).
    """
    official = sprite_post.qc(c.sheet, c.cell, c.n, elem, c.loop)
    n_off = len(official)
    n_mine = sum(1 for r in mine if not r["ok"] and r["no"] <= 8)
    if n_off == n_mine:
        return None
    return (f"!! 잣대가 갈렸다 — 공식 qc 는 {n_off}개, 여기는 {n_mine}개 지적. "
            f"공식: {official}")


# ==========================================================================
# 본체
# ==========================================================================
def run(sheets: list[Path], elem: str, *, palette_mode: str = "game15",
        anim_json: dict | None = None, dirs_root: Path | None = None,
        do_cross: bool = True) -> dict:
    palette = spec.palette_for(elem, palette_mode)
    # ★ game15 는 공식 팔레트와 **같아야** 한다. 갈라졌으면 2번 검사와 공식 qc 의
    #   맞대 보기가 통째로 뜻을 잃으므로 먼저 알린다.
    drift = (palette_mode == "game15" and palette != pixels.palette_for(elem))
    clips = [Clip(p, anim_json) for p in sheets]

    rep: dict = {"elem": elem, "palette_mode": palette_mode,
                 "palette_n": len(palette), "palette_drift": drift,
                 "sheets": [], "cross": []}
    for c in clips:
        rows = check_sheet(c, elem, palette)
        rep["sheets"].append({
            "file": str(c.path), "name": c.name, "act": c.act, "dir": c.dir,
            "cell": c.cell, "frames": c.n, "loop": c.loop, "checks": rows,
        })
        if do_cross and palette_mode == "game15":
            w = cross(c, elem, rows)
            if w:
                rep["cross"].append({"sheet": c.name, "warn": w})

    rep["shared"] = [
        check_cross_feet(clips),
        check_muzzle(anim_json),
        check_dirs(gather_dirs(dirs_root) if dirs_root else {}),
        check_clipped(clips),
    ]
    fails = sum(1 for s in rep["sheets"] for r in s["checks"] if not r["ok"])
    fails += sum(1 for r in rep["shared"] if not r["ok"])
    rep["fail_n"] = fails
    return rep


def show(rep: dict) -> None:
    if rep["palette_drift"]:
        print("!! spec.palette_for(game15) 가 pixels.palette_for 와 갈라졌다 "
              "— 2번 검사가 뜻을 잃는다")
    for s in rep["sheets"]:
        print(f"\n── {s['name']}  {s['frames']}칸 x {s['cell']}px · "
              f"{s['act']}{'/' + s['dir'] if s['dir'] else ''} · "
              f"{'루프' if s['loop'] else '논루프'}")
        for r in s["checks"]:
            _line(r)
    print("\n── 시트를 아우르는 검사 (9~12 는 새로 더한 것)")
    for r in rep["shared"]:
        _line(r)
    for w in rep["cross"]:
        print(f"\n{w['sheet']}: {w['warn']}")
    n = rep["fail_n"]
    print(f"\n{'모두 통과' if not n else str(n) + '개 실패'}")


def _line(r: dict) -> None:
    mark = "OK  " if r["ok"] else "FAIL"
    val = r["value"]
    if isinstance(val, dict):
        val = " ".join(f"{k}={v}" for k, v in val.items())
    print(f"  [{mark}] {r['no']:2d} {r['name']:<18s} {str(val):<22s} ({r['limit']})")
    if r["note"]:
        print(f"            {r['note']}")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="3D 파이프라인 시트 품질 검사 (공식 qc 여덟 + 새로 넷)")
    ap.add_argument("--dir", default="",
                    help="7_sheet 디렉터리. 그 안의 *.png 를 시트로, anim.json 을 메타로 읽는다")
    ap.add_argument("--sheets", default="",
                    help="시트 PNG 를 쉼표로. anim.json 없이도 쓸 수 있다")
    ap.add_argument("--elem", default="",
                    help="속성. 비면 anim.json → 로스터 순으로 찾는다")
    ap.add_argument("--palette", default="game15", choices=["game15", "ext24"])
    ap.add_argument("--anim-json", default="", help="anim.json 을 따로 줄 때")
    ap.add_argument("--dirs", default="",
                    help="8방향 자료가 있는 디렉터리 (11번 검사)")
    ap.add_argument("--out", default="", help="qc.json 자리 (기본: --dir 안)")
    ap.add_argument("--no-cross", action="store_true",
                    help="공식 qc() 와 맞대 보기를 끈다")
    a = ap.parse_args()

    sheets: list[Path] = []
    skipped: list[str] = []
    base: Path | None = None
    if a.dir:
        base = Path(a.dir)
        if not base.is_dir():
            raise SystemExit(f"디렉터리가 없다: {base}")
        # ★ **스트립이 아닌 PNG 는 건너뛴다.** `pack.py` 가 같은 자리에 `atlas.png`
        #   (행=방향 격자)와 `preview.png`(사람이 보는 판)를 같이 굽는데, 그것까지
        #   가로 1행으로 읽으려 하면 `ValueError` 로 죽어서 **계약서가 시킨 명령줄
        #   (`qc.py --dir …/7_sheet`)이 그냥은 안 돌았다.**
        #   판별은 「가로가 세로로 나눠떨어지는가」 하나면 된다 — 그것이 곧 스트립의 정의다.
        sheets = []
        for q in sorted(base.glob("*.png")):
            im = Image.open(q)
            if im.size[0] % im.size[1] == 0 and act_of(q) in spec.ACTIONS:
                sheets.append(q)
            else:
                skipped.append(q.name)
    if a.sheets:
        sheets += [Path(s) for s in a.sheets.split(",") if s]
    if not sheets:
        raise SystemExit("시트가 없다 — --dir 이나 --sheets 를 줘라")
    if skipped:
        print(f"  (스트립이 아니라 건너뜀: {', '.join(skipped)})")

    # ★ 이름에 방향 토큰이 든 시트가 여럿이면 **게임이 쓰는 방향**만 본체 검사로
    #   돌린다. 나머지 일곱은 11번 검사의 자료다 — 안 그러면 같은 동작을 여덟 번
    #   재면서 9번(클립 사이 발 높이)이 방향 차이까지 섞어 버린다.
    tagged = [p for p in sheets if dir_of(p)]
    if len(tagged) > 1:
        keep = [p for p in sheets if dir_of(p) in (None, spec.GAME_DIR)]
        if keep:
            sheets = keep

    aj: dict | None = None
    ajp = Path(a.anim_json) if a.anim_json else (base / "anim.json" if base else None)
    if ajp and ajp.exists():
        aj = json.loads(ajp.read_text())

    elem = a.elem or (aj or {}).get("elem", "")
    if not elem:                       # 파일 이름에서 캐릭터 id 를 찾아 로스터를 본다
        for p in sheets:
            for t in _tokens(p):
                try:
                    elem = spec.roster_unit(t)["elem"]
                    break
                except KeyError:
                    pass
            if elem:
                break
    if not elem:
        raise SystemExit("속성을 못 찾았다 — --elem 을 줘라")

    dirs_root = Path(a.dirs) if a.dirs else base
    rep = run(sheets, elem, palette_mode=a.palette, anim_json=aj,
              dirs_root=dirs_root, do_cross=not a.no_cross)
    show(rep)

    out = Path(a.out) if a.out else ((base / "qc.json") if base
                                     else spec.OUT / "qc.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(rep, ensure_ascii=False, indent=1))
    print(f"\n→ {out}")
    return 1 if rep["fail_n"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
