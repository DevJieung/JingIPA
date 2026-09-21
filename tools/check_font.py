#!/usr/bin/env python3
"""화면에 쓰는 모든 문자가 번들 폰트에 있는지 검사한다.

왜 필요한가: 글리프가 없어도 Godot 은 오류를 내지 않는다. get_string_size() 는
그럴듯한 값을 돌려주고, 화면에서만 두부(□)로 깨진다. 게다가 .import 의
allow_system_fallback 이 켜져 있으면 **실기기에서는 OS 폰트가 메워 줘서**
개발자 눈에는 절대 안 잡히고, 폰트 없는 기기에서만 깨진다.

이 게임은 카드 무늬(♠♥♦♣)와 별표(★)를 화면에 그리므로 특히 중요하다.
번들 UI 폰트에 그 글자들이 없으면 카드가 통째로 못 읽게 된다.

    python3 tools/check_font.py

종료 코드: 빠진 글리프가 있으면 1.
"""
from __future__ import annotations

import glob
import json
import os
import re
import sys

from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = [os.path.join(ROOT, "core", "fonts", name) for name in
         ("RefugeSans-Bold.otf",)]
SCAN_GLOBS = ["core/**/*.gd", "game/**/*.gd", "core/locales/*.json"]

IGNORE_PREFIXES = ("res://", "user://", "uid://")
# 화면에 안 나가는 이름들(딕셔너리 키·id·색 문자열 등)은 검사에서 뺀다.
IGNORE_EXACT = {
    "atk", "rate", "rng", "crit", "critx", "gold", "life", "reroll", "time",
    "balance", "rapid", "heavy", "sniper", "guard",
    "shot", "pierce", "splash", "chain", "beam", "slow", "burn", "zone", "ricochet",
    "swarm", "fast", "tank", "caster", "boss", "early", "mid", "late",
}


def literals_of(path: str) -> list[tuple[int, str]]:
    """주석을 제외한 문자열 리터럴을 (줄번호, 내용) 으로 뽑는다."""
    if path.endswith(".json"):
        def strings(value):
            if isinstance(value, str):
                yield value
            elif isinstance(value, dict):
                for child in value.values():
                    yield from strings(child)
        with open(path, encoding="utf-8") as source:
            return [(1, text) for text in strings(json.load(source))]
    out: list[tuple[int, str]] = []
    for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
        if line.lstrip().startswith("#"):
            continue
        for lit in re.findall(r'"([^"\\\n]*)"', line) + re.findall(r"'([^'\\\n]*)'", line):
            if lit.startswith(IGNORE_PREFIXES) or lit in IGNORE_EXACT:
                continue
            if lit.startswith("#") and len(lit) in (4, 7, 9):   # 색 hex
                continue
            out.append((lineno, lit))
    return out


def main() -> int:
    for font in FONTS:
        if not os.path.exists(font):
            print(f"폰트를 찾을 수 없습니다: {font}", file=sys.stderr)
            return 1
    cmap = set.intersection(*(set(TTFont(font).getBestCmap()) for font in FONTS))

    missing: dict[str, list[str]] = {}
    paths: list[str] = []
    for g in SCAN_GLOBS:
        paths += glob.glob(os.path.join(ROOT, g), recursive=True)
    # core/roster.gd(자동 생성) 의 캐릭터·몬스터 이름도 화면에 그대로 나간다 —
    # core/**/*.gd 에 들어 있으므로 같이 검사된다.
    for path in sorted(set(paths)):
        for lineno, lit in literals_of(path):
            for ch in lit:
                if ch in ("\t", "\n"):
                    continue
                if ord(ch) not in cmap:
                    key = f"{ch}  (U+{ord(ch):04X})"
                    where = f"{os.path.relpath(path, ROOT)}:{lineno}"
                    missing.setdefault(key, [])
                    if where not in missing[key]:
                        missing[key].append(where)

    if missing:
        print("!! 폰트에 없는 글자가 있습니다 — 화면에서 두부(□)로 깨집니다:")
        for k, wheres in sorted(missing.items()):
            print(f"   {k}   {', '.join(wheres[:4])}")
        return 1
    print(f"화면에 쓰는 모든 문자가 폰트에 있습니다 ({len(paths)}개 파일)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
