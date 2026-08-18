#!/usr/bin/env python3
"""내려받아서 Godot 으로 열 수 있는 프로젝트 zip 을 만든다.

    python3 tools/make_zip.py              # -> ~/frogwarrior.zip
    python3 tools/make_zip.py -o /tmp/a.zip

★ 제외 목록을 손으로 쓰지 말고 반드시 이 스크립트를 쓸 것.
  `.godot/` 안에는 **안드로이드 서명 비밀번호**(export_credentials.cfg)가 있고
  `.certs/` 에는 **개발용 개인 키**가 있다. 한 번이라도 같이 묶여 나가면
  키를 새로 만들어야 한다. 그래서 마지막에 한 번 더 훑어서 확인한다.

반대로 `*.uid` 와 `*.import` 는 **반드시 넣어야 한다** —
Godot 4.4+ 가 리소스 참조에 쓰기 때문에 빠지면 링크가 통째로 깨진다.
"""

from __future__ import annotations

import argparse
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP = "frogwarrior"

# 통째로 뺄 디렉터리 (프로젝트 루트 기준)
SKIP_DIRS = {
    ".godot",      # 임포트 캐시 + 서명 비밀번호. Godot 이 열 때 다시 만든다
    ".certs",      # 개발용 자체 서명 개인 키
    "build",       # 이전 익스포트 결과물. 다시 뽑으면 된다
    "comments",    # 코드가 참조하지 않는 참고용 스크린샷
    ".git",
}
# 어디에 있든 뺄 디렉터리 이름
SKIP_ANYWHERE = {"__pycache__", ".ipynb_checkpoints"}
# 파일 이름/확장자
SKIP_SUFFIX = (".pyc", ".tmp", ".zip")
SKIP_NAMES = {".DS_Store", "Thumbs.db", "export_credentials.cfg"}

# 묶고 나서 "절대 들어있으면 안 되는 것" — 하나라도 걸리면 실패로 끝낸다.
FORBIDDEN_SUFFIX = (".keystore", ".jks", ".key", ".crt", ".pem", ".p12")
FORBIDDEN_NAMES = {"export_credentials.cfg"}


def collect() -> list[tuple[str, str]]:
    """(실제 경로, zip 안 경로) 목록."""
    out: list[tuple[str, str]] = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT)
        if rel_dir == ".":
            rel_dir = ""
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        dirnames[:] = [d for d in dirnames if d not in SKIP_ANYWHERE]
        for name in filenames:
            if name in SKIP_NAMES or name.endswith(SKIP_SUFFIX):
                continue
            src = os.path.join(dirpath, name)
            if os.path.islink(src):
                continue
            rel = os.path.join(rel_dir, name) if rel_dir else name
            out.append((src, os.path.join(TOP, rel)))
    out.sort(key=lambda p: p[1])
    return out


def audit(names: list[str]) -> list[str]:
    bad = []
    for n in names:
        base = os.path.basename(n)
        if base in FORBIDDEN_NAMES or base.endswith(FORBIDDEN_SUFFIX):
            bad.append(n)
        if f"/{TOP}/.godot/" in f"/{n}" or n.startswith(f"{TOP}/.certs/"):
            bad.append(n)
    return bad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out",
                    default=os.path.join(os.path.expanduser("~"), "frogwarrior.zip"))
    args = ap.parse_args()

    if not os.path.exists(os.path.join(ROOT, "project.godot")):
        print("project.godot 이 없습니다. 프로젝트 루트에서 실행하세요.", file=sys.stderr)
        return 1

    items = collect()
    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    tmp = args.out + ".part"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for src, arc in items:
            z.write(src, arc)
        names = z.namelist()

    bad = audit(names)
    if bad:
        os.remove(tmp)
        print("비밀 파일이 섞여 들어갔습니다. 만들지 않았습니다:", file=sys.stderr)
        for b in bad[:20]:
            print("  " + b, file=sys.stderr)
        return 2

    os.replace(tmp, args.out)
    uids = sum(1 for n in names if n.endswith(".uid"))
    imports = sum(1 for n in names if n.endswith(".import"))
    size = os.path.getsize(args.out)
    print(f"{args.out}")
    print(f"  파일 {len(names)}개 / {size / 1024 / 1024:.1f}MB "
          f"(.uid {uids}개, .import {imports}개 포함)")
    print("  제외: " + ", ".join(sorted(SKIP_DIRS)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
