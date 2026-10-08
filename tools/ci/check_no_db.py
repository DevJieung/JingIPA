#!/usr/bin/env python3
"""배포물(APK · IPA · PCK)에 게임 데이터 DB 가 실려 있지 않은가.

    python3 tools/ci/check_no_db.py <파일.apk | .ipa | .zip | .pck> [...]

★ `data/game.db` 는 **만드는 쪽의 원본**이다. 게임은 거기서 내린 JSON · 코드만 읽는다
  (docs/GAME_DB.md). 폰에 실리면 쓰지도 않는 파일로 꾸러미가 커지고, 아직 승인 안 된 값과
  그림 프롬프트가 같이 나간다.
★ **이름만 보지 않는다.** 누가 DB 를 다른 이름으로 옮겨 놓아도 잡히게 SQLite 파일의
  첫 16바이트를 찾는다. 꾸러미 안의 .pck 는 통째로 훑는다 — PCK 는 파일을 그대로 이어
  붙인 것이라 DB 가 들었으면 그 머리글자가 그대로 보인다.
★ `tools/ci/` 에 두는 까닭: IPA 를 굽는 macOS 작업은 이 폴더만 내려받는다
  (.github/workflows/stellardefense.yml 의 sparse-checkout).
"""
from __future__ import annotations

import sys
import zipfile

MAGIC = b"SQLite format 3\x00"
NAMES = (".db", ".sqlite", ".sqlite3", ".db-journal", ".db-wal", ".db-shm")
PATHS = (b"data/game.db",)
CHUNK = 1 << 20


def scan(stream, where: str) -> list[str]:
	"""이어 붙인 덩어리(PCK) 안에서 DB 의 흔적을 찾는다. 조각 경계에 걸친 것도 놓치지 않는다."""
	found: list[str] = []
	keep = max(len(MAGIC), max(len(p) for p in PATHS)) - 1
	tail = b""
	while True:
		block = stream.read(CHUNK)
		if not block:
			break
		data = tail + block
		if MAGIC in data and "SQLite" not in "".join(found):
			found.append("%s: 안에 SQLite 파일이 들어 있다" % where)
		for path in PATHS:
			if path in data and path.decode() not in "".join(found):
				found.append("%s: 안에 %s 가 들어 있다" % (where, path.decode()))
		tail = data[-keep:]
	return found


def check(path: str) -> list[str]:
	if not zipfile.is_zipfile(path):
		with open(path, "rb") as f:
			return scan(f, path)
	found: list[str] = []
	with zipfile.ZipFile(path) as z:
		for info in z.infolist():
			name = info.filename
			if name.lower().endswith(NAMES) or "data/game." in name:
				found.append("%s: %s" % (path, name))
				continue
			with z.open(info) as f:
				if name.lower().endswith(".pck"):
					found += scan(f, "%s 의 %s" % (path, name))
				elif f.read(len(MAGIC)) == MAGIC:
					found.append("%s: %s (SQLite 파일)" % (path, name))
	return found


def main() -> int:
	if len(sys.argv) < 2:
		print(__doc__.strip().split("\n\n")[1].strip())
		return 2
	bad: list[str] = []
	for path in sys.argv[1:]:
		found = check(path)
		bad += found
		if not found:
			print("DB 없음: %s" % path)
	for line in bad:
		print("!! 배포물에 게임 데이터 DB 가 실렸다 — %s" % line)
	return 1 if bad else 0


if __name__ == "__main__":
	raise SystemExit(main())
