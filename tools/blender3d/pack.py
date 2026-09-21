#!/usr/bin/env python3
"""7단계 — **시트 패킹 · 임포트.** 6단계가 정리한 낱장을 게임이 읽는 꼴로 굽는다.

    python3 tools/blender3d/pack.py --unit jokull
    python3 tools/blender3d/pack.py --unit fixture --tier 1 --src build/b3d/cand_a/6_clean

★★ **후보 셋이 이 한 파일을 나눠 쓴다.** 2~6단계는 저마다 다른 길로 가도 되지만
   7단계는 하나여야 한다. 까닭은 `post.py` 머리말과 같다 — 마지막 공정이 서로
   다르면 세 결과의 차이가 「3D 를 어떻게 짰나」에서 온 것인지 「시트를 어떻게
   구웠나」에서 온 것인지 갈리지 않는다. 여기서 재는 자(기준점·배율·총구·놓는 칸)가
   같아야 나란히 놓을 수 있다.

들어오는 것
    <src>/<action>/<dir>/*.png          96x96 RGBA · 양자화와 테두리가 끝난 낱장
    <5_frames>/meta.json                ★ 5단계가 남긴 총구 좌표(있으면 그걸 믿는다)

내놓는 것 (`build/b3d/<uid>/7_sheet/`)
    <uid>_idle.png · <uid>_walk.png · <uid>_attack.png   게임 방향(E)의 가로 1행 스트립
    anim.json      ★ **게임 꼴 그대로.** core/anim.gd 가 그대로 읽는다
    sheet.json     일반 꼴(TexturePacker 풍) — 전 동작 x 전 방향의 낱장 표
    atlas.png      행 = 방향 · 열 = 프레임. 라벨 없는 순수 아틀라스
    preview.png    사람이 보는 판 (1배 · 3배 · 방향 격자 · 바닥선)
    pack_report.json  ★ 스스로 매긴 검사 결과와 잣대

---
## anim.json 의 계약 — 여기가 이 파일의 본체다

`core/anim.gd` 와 `tools/gen_roster.py` 와 `tests/ns_check.gd` 셋이 같은 파일을 읽는다.
한 줄이라도 어긋나면 **조용히** 망가진다 — 예외도 로그도 안 난다.

  `name`       PNG 파일명 앞머리와 **반드시 같다.** `Anim.clip()` 이
               `<dir><name>_<clip>.png` 로 그림을 찾으므로, 다르면 텍스처가 null 이
               되고 화면은 **정지 그림 한 장**으로 조용히 되돌아간다(18-1).
  `cell`       기준점의 정규화 분모다(`anim.gd` 가 `anchor.x / cell.w` 를 쓴다).
               실제 칸 크기와 달라지면 발이 바닥선에서 뜬다.
  `anchor`     **아이들 0번 칸**의 (발 가로 가운데, 알파 bbox 아래끝). 칸 좌상단 원점.
  `static`     아이들 0번 칸의 알파 bbox 크기. ★ `h` 가 총구 정규화의 분모라
               (`gen_roster.muzzle_of` 가 `muzzle_at / static.h`) 정확해야 한다.
  `scale`      `spec.unit_h(tier) / static.h`. ★ 로스터의 `sc` 는 **넣지 마라** —
               엔진(`Art.draw_unit`)이 따로 곱하므로 두 번 곱해진다.
  `muzzle_at`  놓는 칸에서 잰 **기준점 상대 좌표**(위가 음수). x 는 반드시 양수.
  `hit_ms`     `sum(ms[0:hit_frame])` **정확히**. `ns_check` 가 `Anim.hit_time()` 이
               세는 값과 2ms 안에서 같은지 잰다 — 그래서 `round(hit * 1000/FPS)` 로
               적으면 안 된다(83x3=249 인데 반올림은 250 이다).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "sprite"))
import spec        # noqa: E402
import pixels      # noqa: E402  ← 공식 파이프라인. 읽기만 한다.

try:                                    # 공식 품질검사 8가지를 그대로 빌려 쓴다
    import sprite_post                  # noqa: E402
except Exception:                       # pragma: no cover
    sprite_post = None


# --------------------------------------------------------------------------
# 자 — 손으로 다시 적지 않는다
# --------------------------------------------------------------------------

#: 발 가로 가운데를 잴 때 보는 **아래 자락**의 비율.
#: ★ 알파 bbox 의 가로 가운데를 쓰면 안 된다 — 대검이 한쪽으로 뻗은 만큼 기준점이
#:   통째로 밀려서, 발밑 그림자와 등급 고리가 발이 아닌 곳에 그려진다.
#: ★★ 값을 0.14 로 둔 것은 **공식 `to_game.foot_x` 와 같은 자**이기 때문이다.
#:   두 길을 견주는 것이 이 테스트의 전부인데 기준점을 다른 자로 재면, 「3D 가
#:   더 안 흔들린다」가 파이프라인 덕인지 자가 달라서인지 갈리지 않는다.
FOOT_BAND = 0.14

#: 총구를 픽셀에서 더듬어 찾을 때 보는 **몸통 위쪽** 비율 (공식 `to_game.muzzle` 과 같다).
MUZ_TOP_BAND = 0.65

#: 총구 가로가 음수/0 으로 나왔을 때 대신 쓰는 값(몸 높이의 배수).
#: `tools/gen_roster.MUZ_FALLBACK` 과 같은 숫자다.
MUZ_FALLBACK_X = 0.34

#: `ns_check._check_muzzle` 이 통과시키는 띠 (몸 높이 `static.h` 로 나눈 값)
MUZ_X_BAND = (0.05, 0.95)
MUZ_Y_BAND = (-1.30, -0.30)
WIND_BAND = (0.05, 0.50)          # 뻗는 시간(초)

#: 발 높이가 흔들려도 되는 한계(px). 공식 `sprite_post.qc` 와 같다.
FOOT_SPREAD_MAX = 2


# --------------------------------------------------------------------------
# 읽기
# --------------------------------------------------------------------------
def _open(f: Path) -> Image.Image:
    """낱장 하나. **칸 크기가 다르면 그 자리에서 멈춘다.**

    ★ 여기서 봐 주면 안 된다. `pixels.pack_sheet` 는 96px 간격으로 붙이므로
      128px 짜리를 넣으면 칸끼리 서로를 덮어쓰고, 기준점·배율·총구가 전부
      **틀린 채로 그럴듯한 JSON** 이 나온다. 그런 파일은 게임에 꽂히고 나서야
      「캐릭터가 조금 어긋난다」로 드러나 아무도 못 잡는다.
    """
    im = Image.open(f).convert("RGBA")
    if im.size != tuple(spec.CELL):
        raise SystemExit("칸 크기가 %s 여야 하는데 %s 이다: %s"
                         % (tuple(spec.CELL), im.size, f))
    return im


def load_clips(src: Path) -> dict[str, dict[str, list[Image.Image]]]:
    """`<src>/<action>/<dir>/*.png` 를 통째로 읽는다.

    ★ 동작·방향의 **차례는 spec 이 정한다.** 디렉터리를 훑은 순서로 두면 파일
      시스템에 따라 아틀라스의 줄 차례가 바뀌어서, 어제 구운 sheet.json 이
      오늘 구운 atlas.png 를 가리키지 못한다.
    """
    out: dict[str, dict[str, list[Image.Image]]] = {}
    for act in spec.ACTIONS:
        adir = src / act
        if not adir.is_dir():
            continue
        got: dict[str, list[Image.Image]] = {}
        for dname in spec.DIRS:
            ddir = adir / dname
            if not ddir.is_dir():
                continue
            files = sorted(ddir.glob("*.png"))
            if files:
                got[dname] = [_open(f) for f in files]
        # spec 에 없는 방향 이름도 버리지 않는다 — 후보가 늘렸을 수 있다
        for ddir in sorted(d for d in adir.iterdir() if d.is_dir()):
            if ddir.name not in got and ddir.name not in spec.DIRS:
                files = sorted(ddir.glob("*.png"))
                if files:
                    got[ddir.name] = [_open(f) for f in files]
        if got:
            out[act] = got
    return out


def read_meta(path: Path) -> dict:
    if path and path.exists():
        try:
            return json.loads(path.read_text())
        except Exception as e:                       # pragma: no cover
            print("  ! meta.json 을 못 읽었다(%s) — 총구를 픽셀에서 찾는다" % e)
    return {}


# --------------------------------------------------------------------------
# 재기
# --------------------------------------------------------------------------
def bbox_of(im: Image.Image) -> tuple[int, int, int, int] | None:
    return im.getbbox()


def foot_x(im: Image.Image) -> float:
    """**발**의 가로 가운데. 알파 bbox 아래 자락의 무게중심으로 잡는다.

    ★ 왜 무게중심인가: 아래 자락에는 두 발이 다 들어오는데, 한 발이 앞으로
      나가 있으면 「양 끝의 가운데」는 넓은 쪽으로 쏠린다. 픽셀 수로 가중하면
      **몸이 실린 쪽**이 잡혀서 그게 실제 무게중심에 가깝다.
    """
    bb = bbox_of(im)
    if bb is None:
        return im.width * 0.5
    x0, y0, x1, y1 = bb
    band = max(2, int(round((y1 - y0) * FOOT_BAND)))
    px = im.load()
    xs = 0
    n = 0
    for y in range(max(y0, y1 - band), y1):
        for x in range(x0, x1):
            if px[x, y][3]:
                xs += x
                n += 1
    return (xs / n) if n else (x0 + x1) * 0.5


def muzzle_from_pixels(im: Image.Image) -> tuple[float, float]:
    """총구를 픽셀에서 더듬어 찾는다 — **5단계 meta.json 이 없을 때의 되돌림 길.**

    공식 `to_game.muzzle` 과 **같은 규칙**이다: 몸통 위쪽 65% 안에서 제일 오른쪽 점.
    아래까지 같이 보면 앞으로 내디딘 발이 팔보다 앞서서 총구가 신발 끝에 붙는다.

    ★★ 3D 길에서 이 함수가 도는 것은 **사고에 가깝다.** 렌더가 칼끝의 3D 좌표를
      이미 아는데 그것을 버리고 픽셀을 훑는 것이라, 소품이 길거나 이펙트가
      붙으면 엉뚱한 데를 짚는다. 5단계가 `meta.json` 을 남기게 하라.
    """
    bb = bbox_of(im)
    if bb is None:
        return (im.width * 0.66, im.height * 0.5)
    x0, y0, x1, y1 = bb
    h = y1 - y0
    px = im.load()
    best = None
    for y in range(y0, y0 + max(1, int(h * MUZ_TOP_BAND))):
        for x in range(x1 - 1, x0 - 1, -1):
            if px[x, y][3]:
                if best is None or x > best[0]:
                    best = (x, y)
                break
    return (float(best[0]), float(best[1])) if best else (float(x1 - 1), float(y0 + h / 3))


def muzzle_from_meta(meta: dict, act: str, dname: str, i: int) -> tuple[float, float] | None:
    """5단계가 남긴 총구 좌표를 읽는다.

    ★★ **이것이 3D 길의 이점을 쓰는 자리다.** 2D 영상 길은 총구를 픽셀에서
      더듬어 찾을 수밖에 없다(원본이 그림뿐이니까). 3D 는 칼끝이 어느 3D 점인지
      알고 있으므로 그 점을 그대로 화면 좌표로 옮기면 끝이다.

    받는 꼴 둘 다 통한다:
        {"muzzle_px": {"attack": [[x,y], …]}}              ← 게임 방향
        {"muzzle_px": {"attack": {"E": [[x,y], …], …}}}    ← 방향마다
    좌표계는 **칸 좌상단 원점 · 아래가 +** 여야 한다(`muzzle_origin`).
    """
    raw = meta.get("muzzle_px")
    if not isinstance(raw, dict):
        return None
    if str(meta.get("muzzle_origin", "cell_topleft")) != "cell_topleft":
        print("  ! meta.json 의 muzzle_origin 이 cell_topleft 가 아니다 — 안 쓴다")
        return None
    if meta.get("muzzle_y_down", True) is False:
        print("  ! meta.json 의 총구 세로가 위로 + 다 — 안 쓴다")
        return None
    val = raw.get(act)
    if isinstance(val, dict):
        val = val.get(dname)
    if not isinstance(val, (list, tuple)) or i >= len(val):
        return None
    p = val[i]
    if not (isinstance(p, (list, tuple)) and len(p) >= 2):
        return None
    return (float(p[0]), float(p[1]))


# --------------------------------------------------------------------------
# 아틀라스 · sheet.json
# --------------------------------------------------------------------------
def order_of(clips: dict) -> list[tuple[str, str]]:
    """(동작, 방향) 차례. spec 의 차례를 그대로 따르고 낯선 이름은 뒤에 붙인다."""
    acts = [a for a in spec.ACTIONS if a in clips] + \
           [a for a in clips if a not in spec.ACTIONS]
    out = []
    for a in acts:
        ds = [d for d in spec.DIRS if d in clips[a]] + \
             [d for d in clips[a] if d not in spec.DIRS]
        out += [(a, d) for d in ds]
    return out


def build_atlas(clips: dict, cw: int, ch: int) -> tuple[Image.Image, list[dict]]:
    """행 = (동작 x 방향) · 열 = 프레임. 라벨 없는 순수 아틀라스.

    ★ 폭은 **가장 긴 동작**에 맞춘다(walk 8칸). 짧은 동작의 오른쪽은 투명하게
      남는데, 그 빈 칸을 sheet.json 이 가리키지 않으므로 아무 해가 없다.
      동작마다 폭을 달리하면 좌표가 줄마다 달라져서 읽는 쪽이 표를 또 만들어야 한다.
    """
    rows = order_of(clips)
    ncol = max((len(clips[a][d]) for a, d in rows), default=0)
    atlas = Image.new("RGBA", (ncol * cw, len(rows) * ch), (0, 0, 0, 0))
    rects: list[dict] = []
    for r, (act, dname) in enumerate(rows):
        for i, im in enumerate(clips[act][dname]):
            atlas.paste(im, (i * cw, r * ch))
            rects.append({"action": act, "dir": dname, "index": i,
                          "x": i * cw, "y": r * ch, "w": cw, "h": ch})
    return atlas, rects


# --------------------------------------------------------------------------
# preview.png
# --------------------------------------------------------------------------
BG = (26, 26, 32, 255)
INK = (226, 230, 238, 255)
GROUND = (232, 96, 96, 200)
FOOTX = (110, 214, 255, 190)
MUZ = (255, 214, 92, 255)

#: ★ 라벨은 **ASCII 만** 쓴다. 번들 폰트가 없어 PIL 기본 글꼴로 그리는데 거기에
#:   한글이 없다 — 한국어로 적으면 네모(두부)가 줄줄이 찍혀서 안 적느니만 못하다.
def _font(sz: int):
    try:
        return ImageFont.load_default(size=sz)
    except TypeError:                                # 낡은 PIL
        return ImageFont.load_default()


def _cross(dr: ImageDraw.ImageDraw, x: float, y: float, r: int) -> None:
    dr.line([(x - r, y), (x + r, y)], fill=MUZ)
    dr.line([(x, y - r), (x, y + r)], fill=MUZ)


def build_preview(clips: dict, gdir: str, meta_json: dict, cw: int, ch: int,
                  grid_action: str = "idle") -> Image.Image:
    """사람이 보는 판 — 스트립 1배와 3배 · 방향 격자 · 바닥선.

    ★ **바닥선을 반드시 그린다.** 발이 튀는가는 숫자로도 재지만(pack_report),
      숫자가 0 인데도 눈에 뜨는 경우가 있다 — 발이 아니라 옷자락이 제일 아래인
      캐릭터가 그렇다. 선을 그어 두면 그것이 한눈에 보인다.
    ★ 세로 파란 선은 **기준점의 가로**다. 대검이 한쪽으로 뻗은 캐릭터에서 이 선이
      몸 가운데가 아니라 칼 쪽에 서 있으면 `FOOT_BAND` 가 잘못 잡힌 것이다.
    """
    anc = meta_json["anchor"]
    ax, ay = float(anc["x"]), float(anc["y"])
    f = _font(13)
    fs = _font(11)

    acts = [a for a in spec.ACTIONS if a in clips and gdir in clips[a]]
    grid_dirs = [d for d in spec.DIRS if grid_action in clips and d in clips[grid_action]]
    gframes = len(clips[grid_action][grid_dirs[0]]) if grid_dirs else 0

    pad = 16
    w_strip = max((len(clips[a][gdir]) * cw * 3 for a in acts), default=cw * 3)
    w_grid = 44 + gframes * cw
    W = max(w_strip, w_grid, 640) + pad * 2
    H = pad + 40 + sum(20 + ch + 6 + ch * 3 + 18 for a in acts) + \
        (26 + len(grid_dirs) * ch if grid_dirs else 0) + pad
    img = Image.new("RGBA", (W, H), BG)
    dr = ImageDraw.Draw(img)

    mz = meta_json["muzzle_at"]
    dr.text((pad, pad), "%s   cell %dx%d   static %dx%d   anchor (%.1f, %.1f)   "
                        "scale %.4f   muzzle (%+d, %+d)   hit_ms %d"
            % (meta_json["name"], cw, ch,
               meta_json["static"]["w"], meta_json["static"]["h"], ax, ay,
               meta_json["scale"], mz["x"], mz["y"], meta_json["hit_ms"]),
            font=f, fill=INK)
    y = pad + 34

    for act in acts:
        fr = clips[act][gdir]
        c = meta_json["clips"][act]
        dr.text((pad, y), "%s  %df  %dms/f  %s%s"
                % (act, len(fr), c["ms"][0], "loop" if c["loop"] else "once",
                   ("  hit@%d" % c["hit_frame"]) if "hit_frame" in c else ""),
                font=fs, fill=INK)
        y += 18
        # 1배
        for i, im in enumerate(fr):
            img.alpha_composite(im, (pad + i * cw, y))
        dr.line([(pad, y + ay), (pad + len(fr) * cw, y + ay)], fill=GROUND)
        dr.line([(pad + ax, y), (pad + ax, y + ch)], fill=FOOTX)
        if "hit_frame" in c:
            _cross(dr, pad + c["hit_frame"] * cw + ax + mz["x"], y + ay + mz["y"], 4)
        y += ch + 6
        # 3배
        for i, im in enumerate(fr):
            img.alpha_composite(im.resize((cw * 3, ch * 3), Image.NEAREST),
                                (pad + i * cw * 3, y))
        dr.line([(pad, y + ay * 3), (pad + len(fr) * cw * 3, y + ay * 3)], fill=GROUND)
        if "hit_frame" in c:
            # ★ 놓는 칸에 **총구 십자**를 찍는다. 숫자로도 재지만(pack_report),
            #   「탄이 칼끝에서 나가는가」는 눈으로만 판가름 난다 — 십자가 손목이나
            #   신발에 붙어 있으면 5단계 meta.json 이 딴 점을 가리키는 것이다.
            _cross(dr, pad + c["hit_frame"] * cw * 3 + (ax + mz["x"]) * 3,
                   y + (ay + mz["y"]) * 3, 9)
        y += ch * 3 + 18

    if grid_dirs:
        dr.text((pad, y), "8 directions  (%s)" % grid_action, font=fs, fill=INK)
        y += 20
        for d in grid_dirs:
            dr.text((pad, y + ch // 2 - 6), d, font=fs, fill=INK)
            for i, im in enumerate(clips[grid_action][d]):
                img.alpha_composite(im, (pad + 44 + i * cw, y))
            dr.line([(pad + 44, y + ay), (pad + 44 + gframes * cw, y + ay)], fill=GROUND)
            y += ch
    return img


# --------------------------------------------------------------------------
# 스스로 검증
# --------------------------------------------------------------------------
def _chk(rep: dict, ok: bool, name: str, detail: str) -> None:
    rep["checks"].append({"ok": bool(ok), "name": name, "detail": detail})


def verify(rep: dict, meta_json: dict, sheets: dict[str, Image.Image],
           clips: dict, gdir: str, cw: int, ch: int, elem: str,
           atlas: Image.Image | None = None, rects: list[dict] | None = None) -> None:
    """★ 만든 것을 **다시 열어 보고** 잰다. 만든 값을 그대로 믿으면 검사가 아니다."""
    name = meta_json["name"]
    anc = meta_json["anchor"]
    st = meta_json["static"]
    mz = meta_json["muzzle_at"]

    # 1) 스트립 — 폭이 칸수로 나누어떨어지는가 · 높이가 칸 높이인가 · 알파가 이진인가
    for act, sh in sheets.items():
        n = meta_json["clips"][act]["frames"]
        _chk(rep, sh.width % n == 0 and sh.width // n == cw,
             "%s: PNG 폭 %d 가 %d칸으로 나누어떨어지고 칸 폭이 %d 인가"
             % (act, sh.width, n, cw), "%d x %d" % (sh.width, sh.height))
        _chk(rep, sh.height == ch, "%s: PNG 높이 == cell.h" % act,
             "%d vs %d" % (sh.height, ch))
        alphas = {p[3] for p in sh.getdata()}
        _chk(rep, alphas <= {0, 255}, "%s: 알파가 0/255 뿐인가" % act,
             "알파 값 %d가지" % len(alphas))

    # 2) 놓는 시각 — sum(ms[:hit]) 와 **정확히** 같은가
    ac = meta_json["clips"].get("attack")
    if ac:
        want = sum(ac["ms"][:ac["hit_frame"]])
        _chk(rep, meta_json["hit_ms"] == want,
             "hit_ms == sum(ms[0:hit_frame])",
             "%d vs %d" % (meta_json["hit_ms"], want))
        wind = meta_json["hit_ms"] / 1000.0
        _chk(rep, WIND_BAND[0] <= wind <= WIND_BAND[1],
             "뻗는 시간이 %.2f~%.2f초인가 (ns_check)" % WIND_BAND, "%.3f초" % wind)

    # 3) 기준점이 칸 안에 있는가
    _chk(rep, 0.0 <= anc["x"] <= cw and 0.0 <= anc["y"] <= ch,
         "anchor 가 칸 안에 있는가", "(%.1f, %.1f) in %dx%d" % (anc["x"], anc["y"], cw, ch))

    # 4) 총구 — x 는 반드시 양수. 음수면 게임이 스프라이트를 통째로 좌우 반전한다
    _chk(rep, mz["x"] > 0, "muzzle_at.x > 0 인가 (음수면 그림이 뒤집힌다)",
         "x=%+d" % mz["x"])
    # ★ 못 박아 넣은 것은 **고친 것이 아니다.** 값은 쓸 만해졌지만 스프라이트는
    #   여전히 왼쪽을 보고 있으므로, 빨간 줄을 남겨 5단계로 돌려보낸다.
    _chk(rep, not rep.get("muzzle_forced_positive"),
         "총구 가로를 억지로 못 박지 않았는가",
         "못 박음 — 5단계에서 방향을 고쳐라" if rep.get("muzzle_forced_positive") else "아니오")
    h = max(1.0, float(st["h"]))
    nx, ny = mz["x"] / h, mz["y"] / h
    _chk(rep, MUZ_X_BAND[0] <= abs(nx) <= MUZ_X_BAND[1],
         "총구 가로/몸높이 가 %.2f~%.2f 인가 (ns_check)" % MUZ_X_BAND, "%.3f" % nx)
    _chk(rep, MUZ_Y_BAND[0] <= ny <= MUZ_Y_BAND[1],
         "총구 세로/몸높이 가 %.2f~%.2f 인가 (ns_check)" % MUZ_Y_BAND, "%.3f" % ny)

    # 5) 이름 — PNG 앞머리와 anim.json 의 name 이 같은가 (다르면 조용히 정지 그림)
    _chk(rep, all(("%s_%s.png" % (name, a)) in rep["files"] for a in sheets),
         "name 이 PNG 파일명 앞머리와 같은가", name)

    # 6) 발 높이 — **클립 사이까지** 한 자로 잰다
    bots = []
    empty = []
    for act, fr in ((a, clips[a][gdir]) for a in sheets):
        for i, im in enumerate(fr):
            bb = bbox_of(im)
            if bb is None:
                empty.append("%s#%d" % (act, i))
            else:
                bots.append(bb[3])
    spread = (max(bots) - min(bots)) if bots else 999
    _chk(rep, spread <= FOOT_SPREAD_MAX,
         "발 높이 흔들림 <= %dpx (클립 사이 포함)" % FOOT_SPREAD_MAX, "%dpx" % spread)
    _chk(rep, not empty, "빈 칸이 없는가", ", ".join(empty) or "없음")

    # 7) 칸 수가 spec 과 같은가
    for act, fr in ((a, clips[a][gdir]) for a in sheets):
        want = spec.ACTIONS.get(act, {}).get("frames")
        if want:
            _chk(rep, len(fr) == want, "%s: 칸 수가 spec 과 같은가" % act,
                 "%d vs %d" % (len(fr), want))

    # 8) 배율이 말이 되는가 — 몸 높이를 잘못 재면 여기서 튄다
    _chk(rep, 0.4 <= meta_json["scale"] <= 3.0, "scale 이 0.4~3.0 인가",
         "%.4f (unit_h %d / 몸높이 %d)"
         % (meta_json["scale"], round(meta_json["scale"] * st["h"]), st["h"]))

    # 9) ★ sheet.json 의 좌표가 atlas.png 를 **정말로** 가리키는가.
    #    아틀라스에서 그 자리를 도로 잘라 원본 낱장과 픽셀로 맞춰 본다.
    #    ☆ 좌표표는 조용히 어긋나는 종류다 — 줄 차례를 한 번 바꾸면 아무 오류도
    #      안 나고 sheet.json 만 거짓말을 한다.
    if atlas is not None and rects:
        bad = []
        for r in rects:
            got = atlas.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]))
            want = clips[r["action"]][r["dir"]][r["index"]]
            if got.tobytes() != want.tobytes():
                bad.append("%s/%s#%d" % (r["action"], r["dir"], r["index"]))
        _chk(rep, not bad, "sheet.json 좌표가 atlas.png 와 픽셀까지 같은가",
             "%d/%d칸 어긋남%s" % (len(bad), len(rects),
                                  (" — " + ", ".join(bad[:4])) if bad else ""))

    # 10) ★ 공식 품질검사 8가지를 **그대로** 돌린다 (색·팔레트·반투명·마젠타·
    #    발높이·빈칸·검은 테두리·루프 이음매). 같은 자로 재야 두 길을 견준다.
    if sprite_post is not None:
        for act, sh in sheets.items():
            n = meta_json["clips"][act]["frames"]
            try:
                bad = sprite_post.qc(sh, cw, n, elem, meta_json["clips"][act]["loop"])
            except Exception as e:                   # pragma: no cover
                bad = ["검사가 터졌다: %s" % e]
            _chk(rep, not bad, "%s: 공식 품질검사 8가지" % act, "; ".join(bad) or "통과")


# --------------------------------------------------------------------------
# 본체
# --------------------------------------------------------------------------
def pack(uid: str, src: Path, out: Path, meta_path: Path | None,
         gdir: str, tier_i: int, elem: str, name: str,
         do_atlas: bool = True, do_preview: bool = True) -> dict:
    clips = load_clips(src)
    if not clips:
        raise SystemExit("낱장이 없습니다: %s — 6단계를 먼저 돌리세요" % src)
    if gdir not in clips.get("idle", {}):
        have = sorted(clips.get("idle", {}))
        if not have:
            raise SystemExit("idle 이 없습니다 — 기준점을 잴 칸이 없다")
        print("  ! 게임 방향 %s 가 없다 — %s 로 대신한다" % (gdir, have[0]))
        gdir = have[0]

    cw, ch = spec.CELL
    meta = read_meta(meta_path) if meta_path else {}
    out.mkdir(parents=True, exist_ok=True)

    # --- 1) 게임 방향 스트립 -------------------------------------------------
    sheets: dict[str, Image.Image] = {}
    files: list[str] = []
    for act in spec.ACTIONS:
        if act not in clips or gdir not in clips[act]:
            continue
        sh = pixels.pack_sheet(clips[act][gdir], cw)     # ★ 공식 함수 그대로
        fn = "%s_%s.png" % (name, act)
        sh.save(out / fn)
        sheets[act] = sh
        files.append(fn)

    # --- 2) 기준점 · 몸 상자 · 배율 -----------------------------------------
    idle0 = clips["idle"][gdir][0]
    bb = bbox_of(idle0)
    if bb is None:
        raise SystemExit("아이들 0번 칸이 비었다 — 6단계가 캐릭터를 지웠다")
    x0, y0, x1, y1 = bb
    ax, ay = foot_x(idle0), float(y1)
    body_w, body_h = x1 - x0, y1 - y0
    scale = spec.unit_h(tier_i) / float(body_h)

    # --- 3) 총구 ------------------------------------------------------------
    hit = spec.ACTIONS["attack"]["hit"]
    muz_src = "meta.json (3D 좌표)"
    mp = None
    if "attack" in clips and gdir in clips["attack"]:
        hit = min(hit, len(clips["attack"][gdir]) - 1)
        mp = muzzle_from_meta(meta, "attack", gdir, hit)
        if mp is None:
            mp = muzzle_from_pixels(clips["attack"][gdir][hit])
            muz_src = "픽셀 더듬기 (meta.json 이 없다)"
    else:
        mp = (ax + body_h * MUZ_FALLBACK_X, ay - body_h * 0.80)
        muz_src = "어림수 (attack 클립이 없다)"
    mx, my = int(round(mp[0] - ax)), int(round(mp[1] - ay))
    muz_forced = False
    if mx <= 0:
        # ★★ 음수면 게임이 **스프라이트를 통째로 좌우 반전한다**(Balance.art_aim).
        #   조용히 뒤집힌 캐릭터를 내놓느니 어림수를 박고 크게 알린다.
        mx = int(round(body_h * MUZ_FALLBACK_X))
        muz_forced = True
        print("  !! 총구 가로가 %+d 로 나왔다 — 스프라이트가 왼쪽을 본다는 뜻이다.\n"
              "     %d(=몸높이 x %.2f)로 못 박았지만 **5단계에서 방향을 고쳐라.**"
              % (int(round(mp[0] - ax)), mx, MUZ_FALLBACK_X))

    # --- 4) anim.json -------------------------------------------------------
    step = int(round(1000.0 / spec.FPS))
    cj: dict = {}
    for act in sheets:
        n = len(clips[act][gdir])
        ms = [step] * n
        cj[act] = {"frames": n, "ms": ms, "total_ms": sum(ms),
                   "loop": bool(spec.ACTIONS.get(act, {}).get("loop", act != "attack"))}
        if act == "attack":
            cj[act]["hit_frame"] = hit
    # ★ 놓는 시각은 **칸 시간을 더해서** 낸다. round(hit*1000/FPS) 로 적으면
    #   Anim.hit_time() 이 세는 값과 1~2ms 어긋나고 ns_check 가 그것을 잡는다.
    hit_ms = sum(cj["attack"]["ms"][:hit]) if "attack" in cj else 0

    meta_json = {
        "name": name,
        "ko": meta.get("ko", ""),
        "elem": elem,
        "source": "tools/blender3d (Blender 4.0 low-poly toon)",
        "cell": {"w": cw, "h": ch},
        "static": {"w": body_w, "h": body_h,
                   "note": "아이들 0번 칸의 몸 상자. 배율과 총구를 재는 자다"},
        "anchor": {"x": round(ax, 1), "y": round(ay, 1),
                   "note": "가로 = 발의 가운데 · 세로 = 발밑 (Art.draw_at 과 같은 규칙)"},
        "scale": round(scale, 4),
        "muzzle_at": {"x": mx, "y": my,
                      "note": "기준점에서 잰 상대 좌표. 탄이 여기서 나간다"},
        "hit_ms": hit_ms,
        "face": 1,
        "family": meta.get("family", "slash"),
        "dir": gdir,
        "clips": cj,
    }
    (out / "anim.json").write_text(json.dumps(meta_json, ensure_ascii=False, indent=1))
    files.append("anim.json")

    # --- 5) atlas.png · sheet.json -----------------------------------------
    rects: list[dict] = []
    atlas_size = None
    atlas = None
    if do_atlas:
        atlas, rects = build_atlas(clips, cw, ch)
        atlas.save(out / "atlas.png")
        atlas_size = {"w": atlas.width, "h": atlas.height}
        files.append("atlas.png")

    # 방향마다 기준점을 따로 잰다 — 한 방향의 값을 여덟에 돌려 쓰면 옆모습에서
    # 맞은 발 가운데가 앞모습에서 어긋난다(3D 는 방향마다 실루엣이 다르다).
    anc_of: dict[str, tuple[float, float]] = {}
    for d in clips.get("idle", {}):
        f0 = clips["idle"][d][0]
        b = bbox_of(f0)
        anc_of[d] = (round(foot_x(f0), 1), float(b[3]) if b else float(ch))

    sheet_json = {
        "meta": {
            "app": "tools/blender3d/pack.py",
            "version": "1.0",
            "image": "atlas.png",
            "size": atlas_size or {"w": 0, "h": 0},
            "scale": "1",
            "format": "RGBA8888",
            "unit": uid, "name": name, "elem": elem,
            "cell": {"w": cw, "h": ch},
            "fps": spec.FPS,
            "game_dir": gdir,
            "actions": {a: {"frames": len(clips[a][gdir if gdir in clips[a]
                                                 else next(iter(clips[a]))]),
                            "loop": bool(spec.ACTIONS.get(a, {}).get("loop", a != "attack")),
                            "hit": spec.ACTIONS.get(a, {}).get("hit")}
                        for a in clips},
            "dirs": sorted({d for a in clips for d in clips[a]},
                           key=lambda d: list(spec.DIRS).index(d)
                           if d in spec.DIRS else 99),
            "source": meta_json["source"],
        },
        "frames": [
            {"filename": "%s_%s_%s_%02d.png" % (name, r["action"], r["dir"], r["index"]),
             "action": r["action"], "dir": r["dir"], "index": r["index"],
             "frame": {"x": r["x"], "y": r["y"], "w": r["w"], "h": r["h"]},
             "anchor": {"x": anc_of.get(r["dir"], (ax, ay))[0],
                        "y": anc_of.get(r["dir"], (ax, ay))[1]},
             "duration": step}
            for r in rects
        ],
    }
    (out / "sheet.json").write_text(json.dumps(sheet_json, ensure_ascii=False, indent=1))
    files.append("sheet.json")

    # --- 6) preview.png -----------------------------------------------------
    if do_preview:
        build_preview(clips, gdir, meta_json, cw, ch).save(out / "preview.png")
        files.append("preview.png")

    # --- 7) 스스로 검증 ------------------------------------------------------
    rep: dict = {"unit": uid, "name": name, "dir": gdir, "elem": elem,
                 "tier_i": tier_i, "src": str(src), "out": str(out),
                 "muzzle_source": muz_src, "muzzle_forced_positive": muz_forced,
                 "files": files, "checks": [], "metrics": {}}
    verify(rep, meta_json, sheets, clips, gdir, cw, ch, elem, atlas, rects)

    # 잣대 — 합격/불합격이 아니라 **견줄 숫자**다
    pal = {pixels.hex2rgb(c) for c in spec.palette_for(elem)}
    per_dir = {}
    for act in clips:
        for d, fr in clips[act].items():
            bots = [b[3] for b in (bbox_of(f) for f in fr) if b]
            per_dir.setdefault(d, {})[act] = {
                "n": len(fr),
                "foot_spread": (max(bots) - min(bots)) if bots else -1,
            }
    cols = {p[:3] for f in sheets.values() for p in f.getdata() if p[3]}
    rep["metrics"] = {
        "colors": len(cols),
        "palette_stray": len(cols - pal),
        "outline_ratio": round(min(pixels.outline_ratio(im)
                                   for a in sheets for im in clips[a][gdir]), 4),
        "body_box": [body_w, body_h],
        "anchor": [round(ax, 2), round(ay, 2)],
        "muzzle_px_in_cell": [round(mp[0], 2), round(mp[1], 2)],
        "per_dir": per_dir,
        "atlas": atlas_size,
        "frames_total": len(rects),
    }
    (out / "pack_report.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1))
    return rep


def main() -> int:
    ap = argparse.ArgumentParser(description="7단계 — 시트 패킹 · 임포트")
    ap.add_argument("--unit", default="jokull", help="캐릭터 id (산출물 자리)")
    ap.add_argument("--src", default="", help="6단계 낱장 뿌리 (기본: <unit>/6_clean)")
    ap.add_argument("--meta", default="", help="5단계 meta.json (기본: <unit>/5_frames/meta.json)")
    ap.add_argument("--out", default="", help="산출물 자리 (기본: <unit>/7_sheet)")
    ap.add_argument("--name", default="", help="anim.json 의 name 과 PNG 앞머리 (기본: unit)")
    ap.add_argument("--dir", default=spec.GAME_DIR, help="게임에 반입할 방향")
    ap.add_argument("--tier", type=int, default=-1, help="등급 번호 (기본: 로스터에서 찾는다)")
    ap.add_argument("--elem", default="", help="속성 (기본: 로스터에서 찾는다)")
    ap.add_argument("--no-atlas", action="store_true")
    ap.add_argument("--no-preview", action="store_true")
    a = ap.parse_args()

    uid = a.unit
    p = spec.paths(uid)
    tier_i, elem = a.tier, a.elem
    try:
        u = spec.roster_unit(uid)
        if tier_i < 0:
            tier_i = u["tier_i"]
        elem = elem or u["elem"]
    except KeyError:
        if tier_i < 0:
            tier_i = 0
            print("  ! 로스터에 %s 가 없다 — 등급을 0 으로 둔다 (--tier 로 지정하라)" % uid)
        elem = elem or "ice"

    rep = pack(uid,
               Path(a.src) if a.src else p["clean"],
               Path(a.out) if a.out else p["sheet"],
               Path(a.meta) if a.meta else (p["frames"] / "meta.json"),
               a.dir, tier_i, elem, a.name or uid,
               do_atlas=not a.no_atlas, do_preview=not a.no_preview)

    m = rep["metrics"]
    print("  %s · %s 방향 · 등급 %d · %s" % (rep["name"], rep["dir"], rep["tier_i"], rep["elem"]))
    print("  몸 %dx%d → 배율 %s · 기준점 %s · 총구 %s"
          % (m["body_box"][0], m["body_box"][1],
             json.loads((Path(rep["out"]) / "anim.json").read_text())["scale"],
             m["anchor"], m["muzzle_px_in_cell"]))
    print("  총구 출처: %s" % rep["muzzle_source"])
    print("  색 %d · 팔레트 이탈 %d · 검은 테두리 %.0f%% · 낱장 %d장 · 아틀라스 %s"
          % (m["colors"], m["palette_stray"], m["outline_ratio"] * 100,
             m["frames_total"], m["atlas"]))
    bad = [c for c in rep["checks"] if not c["ok"]]
    for c in rep["checks"]:
        print("   %s %s — %s" % ("OK " if c["ok"] else "!! ", c["name"], c["detail"]))
    print("  → %s" % rep["out"])
    print("판정: %s" % ("정상" if not bad else "실패 %d건" % len(bad)))
    return 0 if not bad else 1


if __name__ == "__main__":
    raise SystemExit(main())
