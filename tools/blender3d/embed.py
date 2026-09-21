#!/usr/bin/env python3
"""보고서 HTML 안의 자리표시자에 그림을 **data URI 로 박아 넣는다.**

    python3 tools/blender3d/embed.py <입력.src.html> <출력.html>

자리표시자 두 가지:
    {{IMG:<파일경로>:<폭>}}    폭에 맞춰 줄여서 넣는다 (0 이면 원본 크기)
    {{PIX:<파일경로>:<배수>}}  **최근접 확대**로 넣는다 (도트 그림 전용)

★ 아티팩트로 게시하는 페이지는 바깥 이미지 호스트를 못 쓴다(CSP). 그림을 페이지에
  넣는 길은 data URI 뿐이다.
★ **줄일 때는 `Image.BOX`(면적 평균)다** — `tools/embed_shots.py` 가 배운 것과 같다.
  Lanczos 로 줄이면 1도트 검은 테두리 둘레에 링잉이 생겨 도트가 흐려진다.
★ **키울 때는 반드시 NEAREST** 다. 도트를 보간해서 키우면 이 파이프라인이 무엇을
  만들었는지가 화면에서 사라진다.
★ 알파를 살려야 하므로 PNG 로 다시 굽는다(WebP 도 알파를 살리지만, 96px 스프라이트는
  PNG 가 이미 작다 — 실측 30KB 안팎).
"""
from __future__ import annotations

import base64
import io
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
IMG = re.compile(r"\{\{IMG:([^:}]+):(\d+)\}\}")
PIX = re.compile(r"\{\{PIX:([^:}]+):(\d+)\}\}")


def _uri(im: Image.Image, fmt: str = "PNG") -> str:
    buf = io.BytesIO()
    im.save(buf, fmt, optimize=True)
    b = base64.b64encode(buf.getvalue()).decode()
    return f"data:image/{fmt.lower()};base64,{b}"


def _open(rel: str) -> Image.Image:
    p = Path(rel)
    if not p.is_absolute():
        p = ROOT / rel
    if not p.exists():
        raise SystemExit(f"!! 그림이 없습니다: {p}")
    return Image.open(p).convert("RGBA")


def sub_img(m: re.Match) -> str:
    im = _open(m.group(1))
    w = int(m.group(2))
    if w and w < im.width:
        im = im.resize((w, max(1, round(im.height * w / im.width))), Image.BOX)
    return _uri(im)


def sub_pix(m: re.Match) -> str:
    im = _open(m.group(1))
    k = max(1, int(m.group(2)))
    if k > 1:
        im = im.resize((im.width * k, im.height * k), Image.NEAREST)
    return _uri(im)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    s = src.read_text()
    s = PIX.sub(sub_pix, s)
    s = IMG.sub(sub_img, s)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(s)
    kb = len(s.encode()) / 1024
    print(f"{dst} — {kb:,.0f}KB")
    if kb > 15 * 1024:
        print("!! 16MB 상한에 가깝습니다. 폭을 줄이세요.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
