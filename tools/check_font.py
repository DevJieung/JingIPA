#!/usr/bin/env python3
"""화면에 쓰는 모든 문자가 번들 폰트에 있는지 검사한다.

왜 필요한가: 글리프가 없어도 Godot 은 오류를 내지 않는다. get_string_size() 는
그럴듯한 값을 돌려주고, 화면에서만 두부(□)로 깨진다. 그래서 눈으로 보기 전에는
발견되지 않는다. (실제로 가운뎃점 '·' 가 Jua 에 없어서 한 번 물렸다.)

사용법:
    python3 tools/check_font.py

종료 코드: 빠진 글리프가 있으면 1.
"""

from __future__ import annotations

import glob
import os
import re
import sys

from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 셈놀이 화면은 Jua 를 직접 preload 해서 draw_string 에 넘긴다.
# 공룡 찾기·허브는 프로젝트 fallback(DinoKR)을 쓰므로 여기서 검사하지 않는다
# (DinoKR 은 한글 11,172/11,172 = 100% 라 빠질 글리프가 없다).
FONT = os.path.join(ROOT, "core", "fonts", "Jua-Regular.ttf")
# Jua 를 실제로 쓰는 코드만 검사한다.
SCAN_GLOBS = ["games/math/**/*.gd"]

# 코드에는 있지만 화면에는 안 나가는 문자열 (파일 경로, 노드 경로, 규칙 이름 등)
IGNORE_PREFIXES = ("res://", "user://", "uid://")


def literals_of(path: str) -> list[tuple[int, str]]:
    """주석을 제외한 큰따옴표 문자열 리터럴을 (줄번호, 내용) 으로 뽑는다."""
    out: list[tuple[int, str]] = []
    for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        # 문자열 안의 '#' 을 주석으로 오인하지 않도록, 리터럴을 먼저 뽑고 나서 검사한다.
        # 작은따옴표 리터럴도 본다 — 예전에는 큰따옴표만 훑어서 절반을 놓쳤다.
        for lit in re.findall(r'"([^"\\\n]*)"', line) + re.findall(r"'([^'\\\n]*)'", line):
            if lit.startswith(IGNORE_PREFIXES):
                continue
            out.append((lineno, lit))
    return out


def main() -> int:
    if not os.path.exists(FONT):
        print(f"폰트를 찾을 수 없습니다: {FONT}", file=sys.stderr)
        return 1
    cmap = set(TTFont(FONT).getBestCmap())

    missing: dict[str, list[str]] = {}
    scanned = 0
    paths: list[str] = []
    for g in SCAN_GLOBS:
        paths += glob.glob(os.path.join(ROOT, *g.split("/")), recursive=True)
    for path in sorted(set(paths)):
        scanned += 1
        rel = os.path.relpath(path, ROOT)
        for lineno, lit in literals_of(path):
            for ch in lit:
                if ord(ch) < 0x20:
                    continue
                if ord(ch) in cmap:
                    continue
                missing.setdefault(ch, []).append(f"{rel}:{lineno}")

    print(f"검사한 파일 {scanned}개, 폰트 글리프 {len(cmap)}자")
    # ★ 검사 대상이 0개면 실패다. 경로가 바뀌면 이 검사기가 조용히 초록불을 내는데,
    #   두 폰트의 .import 가 allow_system_fallback=true 라 실기기에서는 OS 폰트가
    #   빠진 글리프를 메워 준다 — 눈으로도 절대 안 잡힌다.
    if scanned == 0:
        print("!! 검사한 파일이 0개입니다. SCAN_GLOBS 경로가 틀렸습니다.", file=sys.stderr)
        return 1
    if not missing:
        print("화면에 쓰는 모든 문자가 폰트에 있습니다.")
        return 0

    print("\n폰트에 없는 문자 — 화면에서 □ 로 깨집니다:")
    for ch, where in sorted(missing.items()):
        print(f"  U+{ord(ch):04X}  {ch!r}")
        for w in where[:6]:
            print(f"      {w}")
        if len(where) > 6:
            print(f"      ... 외 {len(where) - 6}곳")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
