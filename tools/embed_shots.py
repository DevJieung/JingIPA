#!/usr/bin/env python3
"""HTML 안의 `{{IMG:이름:폭}}` 자리에 스크린샷을 **data URI 로 박아 넣는다.**

    python3 tools/embed_shots.py docs/site/intro.src.html build/site/intro.html

왜 필요한가: 게시할 페이지는 바깥 이미지 호스트를 못 쓴다(CSP). 그림을 페이지 안에
넣는 길은 data URI 뿐인데, 1280x800 PNG 한 장이 1MB 라 열 장이면 페이지가 10MB 다.
여기서 폭을 줄이고 WebP 로 다시 압축해서 한 장을 60~200KB 로 낮춘다.

★ **줄이는 것은 Lanczos 가 아니라 `Image.BOX`(면적 평균)다.** 도트 그림을 Lanczos 로
  줄이면 1px 검은 테두리 둘레에 링잉이 생겨서, 96px 스프라이트가 흐려 보인다.
  면적 평균은 링잉이 없고 도트의 결을 그대로 눌러 준다.
"""
from __future__ import annotations

import base64
import io
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "build/shots"
PAT = re.compile(r"\{\{IMG:([a-z0-9_]+):(\d+)(?::(\d+))?\}\}")
# 움직이는 그림(애니메이션 WebP)은 이미 다 구워져 있으므로 **그대로** 박는다.
# 다시 열어 저장하면 PIL 이 첫 칸만 남겨서 정지 그림이 된다.
ANIM = re.compile(r"\{\{ANIM:([a-z0-9_]+)\}\}")
SITE = ROOT / "build/site"


def data_uri(name: str, width: int, quality: int = 80) -> str:
    src = SHOTS / f"{name}.png"
    if not src.exists():
        raise SystemExit(f"!! 그림이 없습니다: {src}")
    im = Image.open(src).convert("RGB")
    if width and width < im.width:
        h = round(im.height * width / im.width)
        im = im.resize((width, h), Image.BOX)
    buf = io.BytesIO()
    im.save(buf, "WEBP", quality=quality, method=6)
    b = buf.getvalue()
    return f"data:image/webp;base64,{base64.b64encode(b).decode()}", len(b)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    html = src.read_text(encoding="utf-8")
    total = 0
    seen: dict[str, tuple[str, int]] = {}

    def sub(m: re.Match) -> str:
        nonlocal total
        name, w, q = m.group(1), int(m.group(2)), int(m.group(3) or 80)
        key = f"{name}@{w}q{q}"
        if key not in seen:
            seen[key] = data_uri(name, w, q)
            total += seen[key][1]
            print(f"  {name:12s} {w:>5}px  {seen[key][1] / 1024:>7.0f}KB")
        return seen[key][0]

    def sub_anim(m: re.Match) -> str:
        nonlocal total
        name = m.group(1)
        key = f"anim:{name}"
        if key not in seen:
            p = SITE / f"{name}.webp"
            if not p.exists():
                raise SystemExit(f"!! 움직이는 그림이 없습니다: {p}")
            b = p.read_bytes()
            seen[key] = (f"data:image/webp;base64,{base64.b64encode(b).decode()}", len(b))
            total += len(b)
            print(f"  {name:12s} {'anim':>5}    {len(b) / 1024:>7.0f}KB")
        return seen[key][0]

    # 세 장이 나눠 쓰는 CSS. 한 곳에서 고치면 셋이 같이 바뀐다.
    def sub_css(m: re.Match) -> str:
        p = src.parent / f"{m.group(1)}.css"
        if not p.exists():
            raise SystemExit(f"!! CSS 가 없습니다: {p}")
        return p.read_text(encoding="utf-8")

    # ★ 표와 차트 자료는 **손으로 안 적는다** — `tools/gen_docparts.py` 가 게임 상수에서
    #   찍어 낸다. 손으로 적으면 밸런스를 만진 날 문서만 옛 숫자로 남는다.
    def sub_part(m: re.Match) -> str:
        p = src.parent / f"_{m.group(1)}.html"
        if not p.exists():
            raise SystemExit(f"!! 조각이 없습니다: {p} — python3 tools/gen_docparts.py")
        return p.read_text(encoding="utf-8")

    html = re.sub(r"\{\{CSS:([a-z0-9_]+)\}\}", sub_css, html)
    html = re.sub(r"\{\{PART:([a-z0-9_]+)\}\}", sub_part, html)
    out = ANIM.sub(sub_anim, PAT.sub(sub, html))
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(out, encoding="utf-8")
    print(f"\n{dst}  ({len(out.encode()) / 1e6:.2f}MB · 그림 {len(seen)}장 "
          f"{total / 1e6:.2f}MB)")
    if len(out.encode()) > 15_000_000:
        print("!! 16MB 상한에 닿습니다 — 폭이나 품질을 낮추세요")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
