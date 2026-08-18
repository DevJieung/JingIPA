#!/usr/bin/env python3
"""개구리 용사 — 스토어/런처 아이콘과 런치 스크린 이미지 생성기.

게임 내부 그래픽은 전부 코드로 그리지만, 앱 아이콘과 iOS 런치 스크린만은
스토어가 PNG 파일을 요구한다. 그 PNG 들만 여기서 만든다.

사용법:
    python3 tools/gen_icons.py

만들어지는 파일:
    appstore_icon_1024.png            App Store 마스터 (1024x1024, 알파 없음 — 필수)
    splash@2x.png / splash@3x.png     iOS 런치 스크린 (알파 있음)
    android/launcher_main_192.png     Android 런처
    android/adaptive_fore_432.png     Android 적응형 아이콘 전경 (알파 있음)
    android/adaptive_back_432.png     Android 적응형 아이콘 배경
    android/adaptive_mono_432.png     Android 모노크롬 (테마 아이콘)

의존성: Pillow
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 게임 팔레트와 같은 색 (src/core/palette.gd)
SKY = (159, 220, 255)
GROUND = (116, 194, 100)
FROG = (95, 211, 90)
FROG_DARK = (63, 174, 66)
BELLY = (214, 247, 174)
EYE_W = (255, 255, 255)
PUPIL = (34, 48, 42)
CHEEK = (255, 157, 177)
HELMET = (255, 204, 77)
HELMET_DARK = (224, 169, 43)
GEM = (89, 208, 255)
GEM_LIGHT = (166, 233, 255)
INK = (40, 56, 46)

SS = 4  # 슈퍼샘플링 배율 (안티에일리어싱)


def _ellipse(d: ImageDraw.ImageDraw, cx, cy, rx, ry, fill):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)


def draw_frog(size: int, background: bool = True, mono: bool = False,
              margin: float = 0.0) -> Image.Image:
    """개구리 용사 얼굴을 그린다. margin 은 적응형 아이콘의 안전 여백 비율."""
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if background and not mono:
        d.rectangle([0, 0, S, S], fill=SKY + (255,))
        _ellipse(d, S * 0.5, S * 1.03, S * 0.72, S * 0.38, GROUND + (255,))

    def C(col):
        return (255, 255, 255, 255) if mono else col + (255,)

    # 캐릭터 전체를 margin 만큼 안쪽으로
    k = 1.0 - margin
    ox, oy = S * 0.5, S * 0.5

    def P(x, y):
        return (ox + (x - 0.5) * S * k, oy + (y - 0.5) * S * k)

    def E(x, y, rx, ry, col):
        cx, cy = P(x, y)
        _ellipse(d, cx, cy, rx * S * k, ry * S * k, col)

    # 몸통
    E(0.50, 0.69, 0.325, 0.245, C(FROG_DARK))
    E(0.50, 0.665, 0.318, 0.228, C(FROG))
    E(0.50, 0.735, 0.195, 0.130, C(BELLY) if not mono else (255, 255, 255, 140))

    # 발
    E(0.285, 0.835, 0.105, 0.058, C(FROG_DARK))
    E(0.715, 0.835, 0.105, 0.058, C(FROG_DARK))

    # 투구 (눈보다 먼저 — 눈이 투구 아랫부분을 가려야 얼굴에 얹힌 것처럼 보인다)
    if not mono:
        d.line([P(0.50, 0.200), P(0.552, 0.105), P(0.612, 0.062)],
               fill=(224, 85, 111, 255), width=int(S * 0.040 * k), joint="curve")
    hx0, _hy = P(0.272, 0.340)
    hx1, hy0 = P(0.728, 0.340)
    hh = S * 0.235 * k
    d.pieslice([hx0, hy0 - hh, hx1, hy0 + hh * 0.30], 180, 360, fill=C(HELMET_DARK))
    d.pieslice([hx0 + S * 0.016 * k, hy0 - hh + S * 0.022 * k,
                hx1 - S * 0.016 * k, hy0 + hh * 0.16], 180, 360, fill=C(HELMET))
    bx0, by0 = P(0.266, 0.316)
    bx1, by1 = P(0.734, 0.366)
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=int(S * 0.026 * k),
                        fill=C(HELMET_DARK))

    # 눈
    E(0.355, 0.415, 0.152, 0.152, C(FROG))
    E(0.645, 0.415, 0.152, 0.152, C(FROG))
    E(0.355, 0.415, 0.113, 0.113, C(EYE_W) if not mono else (255, 255, 255, 200))
    E(0.645, 0.415, 0.113, 0.113, C(EYE_W) if not mono else (255, 255, 255, 200))
    E(0.378, 0.432, 0.057, 0.057, C(PUPIL) if not mono else (255, 255, 255, 255))
    E(0.668, 0.432, 0.057, 0.057, C(PUPIL) if not mono else (255, 255, 255, 255))
    if not mono:
        E(0.398, 0.408, 0.021, 0.021, C(EYE_W))
        E(0.688, 0.408, 0.021, 0.021, C(EYE_W))
        # 볼
        E(0.255, 0.605, 0.065, 0.045, CHEEK + (215,))
        E(0.745, 0.605, 0.065, 0.045, CHEEK + (215,))

    # 입
    m0 = P(0.392, 0.605)
    m1 = P(0.608, 0.605)
    mm = P(0.50, 0.688)
    pts = []
    for i in range(25):
        t = i / 24.0
        x = (1 - t) ** 2 * m0[0] + 2 * (1 - t) * t * mm[0] + t * t * m1[0]
        y = (1 - t) ** 2 * m0[1] + 2 * (1 - t) * t * mm[1] + t * t * m1[1]
        pts.append((x, y))
    d.line(pts, fill=C(INK), width=int(S * 0.032 * k), joint="curve")

    # 코 가리개 — 두 눈 사이로 내려온다 (눈 다음에 그려야 앞으로 나온다)
    nx0, ny0 = P(0.466, 0.320)
    nx1, ny1 = P(0.534, 0.520)
    d.rounded_rectangle([nx0, ny0, nx1, ny1], radius=int(S * 0.028 * k), fill=C(HELMET))
    d.rounded_rectangle([nx0 + S * 0.007 * k, ny0 + S * 0.006 * k,
                         nx1 - S * 0.007 * k, ny1 - S * 0.010 * k],
                        radius=int(S * 0.021 * k), fill=C(HELMET_DARK))
    # 보석 — 투구 이마 쪽, 눈 위
    E(0.50, 0.238, 0.050, 0.050, C(GEM))
    E(0.50, 0.231, 0.030, 0.030, C(GEM_LIGHT))

    return img.resize((size, size), Image.LANCZOS)


def rounded(img: Image.Image, radius_ratio: float) -> Image.Image:
    S = img.size[0] * SS
    big = img.resize((S, S), Image.LANCZOS)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, S - 1, S - 1], radius=int(S * radius_ratio), fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(big, (0, 0), mask)
    return out.resize(img.size, Image.LANCZOS)


def flatten(img: Image.Image, bg=SKY) -> Image.Image:
    """알파 제거. App Store 아이콘은 알파 채널이 있으면 업로드가 거부된다."""
    out = Image.new("RGB", img.size, bg)
    out.paste(img, (0, 0), img.split()[-1] if img.mode == "RGBA" else None)
    return out


def make_splash(size: int) -> Image.Image:
    """런치 스크린용 로고 (배경은 투명 — Godot 이 boot_splash 색 위에 올린다)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    frog = draw_frog(size, background=False)
    img.alpha_composite(frog)
    return img


def main() -> int:
    out_android = os.path.join(ROOT, "android_icons")
    os.makedirs(out_android, exist_ok=True)

    made = []

    # --- iOS / App Store 마스터: 1024, 알파 없음, 모서리 둥글리기 금지(애플이 자동 처리) ---
    p = os.path.join(ROOT, "appstore_icon_1024.png")
    flatten(draw_frog(1024)).save(p)
    made.append(p)

    # --- iOS 런치 스크린 ---
    for name, s in (("splash@2x.png", 600), ("splash@3x.png", 900)):
        p = os.path.join(ROOT, name)
        make_splash(s).save(p)
        made.append(p)

    # --- Android 런처 ---
    p = os.path.join(out_android, "launcher_main_192.png")
    rounded(draw_frog(192), 0.22).save(p)
    made.append(p)

    # 적응형 아이콘: 432x432 캔버스에 66% 안전 영역. 전경은 여백을 크게 둔다.
    p = os.path.join(out_android, "adaptive_fore_432.png")
    draw_frog(432, background=False, margin=0.30).save(p)
    made.append(p)

    p = os.path.join(out_android, "adaptive_back_432.png")
    bg = Image.new("RGBA", (432, 432), SKY + (255,))
    dd = ImageDraw.Draw(bg)
    dd.ellipse([-60, 250, 492, 640], fill=GROUND + (255,))
    bg.save(p)
    made.append(p)

    p = os.path.join(out_android, "adaptive_mono_432.png")
    draw_frog(432, background=False, mono=True, margin=0.30).save(p)
    made.append(p)

    for f in made:
        im = Image.open(f)
        print(f"  {os.path.relpath(f, ROOT):<42} {im.size[0]}x{im.size[1]} {im.mode}"
              f"  {os.path.getsize(f) / 1024:6.1f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
