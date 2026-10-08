#!/usr/bin/env python3
"""게임 데이터 DB — 표는 data/game.db 한 곳에서 고치고, 승인된 것만 JSON · 게임 코드로 내린다.

    python3 tools/gamedb.py status             DB 와 게임 파일이 어디가 다른가 (아무것도 안 쓴다)
    python3 tools/gamedb.py apply              내릴 것을 보여 주기만 한다 (아무것도 안 쓴다)
    python3 tools/gamedb.py apply --approved   사용자가 승인했다 — JSON · 게임 코드로 내린다
    python3 tools/gamedb.py pull               게임 파일을 직접 고친 것을 DB 로 들인다
    python3 tools/gamedb.py check              tools/verify.sh 용 (파일이 DB 를 안 거치고 바뀌었으면 실패)
    python3 tools/gamedb.py log                승인 기록
    python3 tools/gamedb.py init               지금 게임 파일에서 DB 를 새로 짓는다

★ **게임은 DB 를 읽지 않는다.** 게임이 읽는 것은 여태 그대로 `core/roster.gd` ·
  `core/balance.gd` 의 상수 · `core/locales/*.json` 이다. DB 는 그 값들의 **원본**이고,
  이 도구가 승인된 값을 그 파일들의 **제자리에** 적어 넣는다. 그래서 폰에는 SQLite 도
  DB 파일도 안 실린다(`data/.gdignore` · export_presets.cfg · tools/ci/check_no_db.py).
★ **코드 쪽은 값만 갈아 끼운다.** `core/balance.gd` 는 숫자마다 「왜 이 값인가」가 주석으로
  붙어 있다. 표를 통째로 다시 찍으면 그 주석이 날아가므로, 리터럴을 읽어서 **바뀐 값의
  글자만** 바꾼다 — 주석 · 줄 맞춤 · 나머지 코드는 한 글자도 안 건드린다.
★ **세 쪽을 견준다** — 게임 파일(F) · DB(D) · 마지막으로 둘을 맞췄을 때의 값(B, DB 안의
  `_baseline`). DB 만 바뀌었으면 「승인 대기」, 파일만 바뀌었으면 「파일 직접 수정」(누가
  DB 를 안 거치고 코드를 고쳤다 → `pull`), 둘 다 바뀌었으면 「충돌」이다. 기준이 없으면
  어느 쪽이 새 값인지 알 길이 없어서, 남이 코드에 고친 숫자를 `apply` 가 말없이 되돌린다.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_REL = "data/game.db"
DB_PATH = os.path.join(ROOT, *DB_REL.split("/"))

ROSTER_JSON = "tools/roster.json"
UI_JSON = "core/locales/ui.json"
HEROES_JSON = "core/locales/heroes.json"
LOCALES = ("ko", "en")

UNIT_KEYS = ("ko", "en", "role", "profile", "bullet", "weapon", "elem", "sc", "desc", "lore",
			 "prompt", "color", "holes", "anim")
MONSTER_KEYS = ("ko", "kind", "body", "desc", "prompt", "color", "holes")
THEME_KEYS = ("ko", "main_body", "boss_body", "rank", "weights", "bg", "floor", "prompt", "floor_prompt")
ART_KEYS = ("ko", "cut", "fx", "square", "size", "prompt", "color", "art", "holes")
ART_OPTIONAL = ("fx", "square", "size", "art", "holes")

BALANCE = "core/balance.gd"
## 코드 안의 표가 DB 의 어느 표 · 어느 열인가.
##   col    숫자 배열 한 줄 — 칸 번호가 곧 줄이다(길이는 코드가 정한다)
##   flat   {"id": 값} — field 가 있으면 그 표의 한 열, 없으면 값이 곧 줄이다
##   rows   {"id": {열…}} — 줄은 코드가 정한다(속성을 하나 더하려면 코드가 먼저다)
##   list   [{"id": …, 열…}] — 줄을 더하고 뺄 수 있다(순서는 못 바꾼다)
##   bag    정해진 열 밖의 키를 통째로 담는 칸(패시브 효과 · 탄 방식의 손잡이)
##   open   flat 인데 줄을 더하고 뺄 수 있다
SPECS = (
	{"kind": "col", "file": BALANCE, "const": "TIER_ATK", "sec": "hero_tiers", "field": "atk"},
	{"kind": "col", "file": BALANCE, "const": "TIER_RATE", "sec": "hero_tiers", "field": "rate"},
	{"kind": "flat", "file": BALANCE, "const": "WEAPON_RANGE", "sec": "weapons", "field": "range"},
	{"kind": "flat", "file": BALANCE, "const": "PROFILE_RANGE", "sec": "profiles", "field": "range_mult"},
	{"kind": "rows", "file": BALANCE, "const": "PROFILE", "sec": "profiles", "base": ("atk", "rate", "ko")},
	{"kind": "rows", "file": BALANCE, "const": "BULLET", "sec": "bullets", "base": ("ko", "dmg", "speed"), "bag": "params"},
	{"kind": "rows", "file": BALANCE, "const": "ROLE", "sec": "roles", "base": ("ko", "atk", "desc")},
	{"kind": "rows", "file": BALANCE, "const": "ELEM", "sec": "elements", "base": ("ko", "color", "rider", "dmg")},
	{"kind": "rows", "file": BALANCE, "const": "MBODY", "sec": "bodies", "base": ("ko", "color", "weak", "resist", "immune")},
	{"kind": "rows", "file": BALANCE, "const": "STATUS", "sec": "statuses", "base": ("ko", "sec"), "bag": "params"},
	{"kind": "rows", "file": BALANCE, "const": "MKIND", "sec": "monster_kinds", "base": ("hp", "spd", "gold", "crush", "ko")},
	{"kind": "list", "file": BALANCE, "const": "UPGRADES", "sec": "upgrades", "base": ("ko", "desc", "show", "base", "grow", "cap")},
	{"kind": "list", "file": BALANCE, "const": "PASSIVES", "sec": "passives", "base": ("ko", "desc", "cost", "rank", "icon", "tint"), "bag": "effects"},
	{"kind": "col", "file": BALANCE, "const": "THEME_RANK_HP", "sec": "theme_rank_hp", "field": "mult"},
	{"kind": "col", "file": BALANCE, "const": "RITE_GATE", "sec": "rite_gates", "field": "width"},
	{"kind": "scalars", "file": BALANCE, "sec": "tuning"},
	{"kind": "flat", "file": "core/sound.gd", "const": "GAP", "sec": "sfx_gaps", "field": None, "open": True},
	{"kind": "flat", "file": "core/scenery.gd", "const": "MAP_MOTIFS", "sec": "themes", "field": "motif", "open": True},
)

## 화면에 적는 이름과, 그 표가 내려가는 파일들.
ROSTER_FILES = (ROSTER_JSON, "core/roster.gd")
SECTIONS = {
	"art_tiers": ("원화 격", ROSTER_FILES),
	"units": ("영웅", ROSTER_FILES + (HEROES_JSON,)),
	"monsters": ("몬스터", ROSTER_FILES),
	"themes": ("테마", ROSTER_FILES + ("core/scenery.gd",)),
	"arts": ("화면 그림", ROSTER_FILES),
	"strings": ("문구", (UI_JSON,)),
	"hero_tiers": ("등급 배수", (BALANCE,)),
	"weapons": ("무기 사거리", (BALANCE,)),
	"profiles": ("성향", (BALANCE,)),
	"bullets": ("공격 방식", (BALANCE,)),
	"roles": ("역할", (BALANCE,)),
	"elements": ("공격 속성", (BALANCE,)),
	"bodies": ("몸 · 상성", (BALANCE,)),
	"statuses": ("상태이상", (BALANCE,)),
	"monster_kinds": ("몬스터 형", (BALANCE,)),
	"upgrades": ("상점 능력치", (BALANCE,)),
	"passives": ("패시브", (BALANCE,)),
	"theme_rank_hp": ("테마 체력 배수", (BALANCE,)),
	"rite_gates": ("의식 문 너비", (BALANCE,)),
	"tuning": ("숫자 상수", (BALANCE,)),
	"sfx_gaps": ("효과음 간격", ("core/sound.gd",)),
}


class DataError(Exception):
	"""값이 틀렸거나 내릴 수 없는 변경. 그 까닭을 그대로 화면에 적는다."""


# --------------------------------------------------------------------------- #
# GDScript 리터럴 — 읽을 때 **글자의 자리**를 같이 적어 둔다
# --------------------------------------------------------------------------- #
class Node:
	__slots__ = ("kind", "start", "end", "value", "items")

	def __init__(self, kind, start, end, value=None, items=None):
		self.kind, self.start, self.end, self.value, self.items = kind, start, end, value, items


_NUM = re.compile(r"[-+]?(?:\d[\d_]*(?:\.[\d_]*)?(?:[eE][-+]?\d+)?|\.\d[\d_]*)")
_WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "0": "\0"}


def _skip(src: str, i: int) -> int:
	"""공백 · 줄바꿈 · 주석을 건너뛴다. 문자열 안의 #(색 값)은 여기 안 온다."""
	n = len(src)
	while i < n:
		c = src[i]
		if c in " \t\r\n":
			i += 1
		elif c == "#":
			j = src.find("\n", i)
			i = n if j < 0 else j
		else:
			break
	return i


def _parse(src: str, i: int) -> Node:
	i = _skip(src, i)
	if i >= len(src):
		raise DataError("리터럴이 끝나지 않았다")
	c = src[i]
	if c == "[":
		items, j = [], _skip(src, i + 1)
		while src[j] != "]":
			node = _parse(src, j)
			items.append(node)
			j = _skip(src, node.end)
			if src[j] == ",":
				j = _skip(src, j + 1)
			elif src[j] != "]":
				raise DataError("배열에서 , 나 ] 가 와야 한다")
		return Node("list", i, j + 1, items=items)
	if c == "{":
		items, j = [], _skip(src, i + 1)
		while src[j] != "}":
			key = _parse(src, j)
			j = _skip(src, key.end)
			if src[j] != ":":
				raise DataError("사전에서 : 가 와야 한다")
			val = _parse(src, j + 1)
			items.append((key, val))
			j = _skip(src, val.end)
			if src[j] == ",":
				j = _skip(src, j + 1)
			elif src[j] != "}":
				raise DataError("사전에서 , 나 } 가 와야 한다")
		return Node("dict", i, j + 1, items=items)
	if c in "\"'":
		out, j = [], i + 1
		while src[j] != c:
			if src[j] == "\n":
				raise DataError("문자열이 줄 안에서 안 닫혔다")
			if src[j] == "\\":
				if src[j + 1] not in _ESC:
					raise DataError("모르는 이스케이프 \\%s" % src[j + 1])
				out.append(_ESC[src[j + 1]])
				j += 2
			else:
				out.append(src[j])
				j += 1
		return Node("str", i, j + 1, value="".join(out))
	m = _NUM.match(src, i)
	if m:
		plain = m.group().replace("_", "")
		if re.fullmatch(r"[-+]?\d+", plain):
			return Node("int", i, m.end(), value=int(plain))
		return Node("float", i, m.end(), value=float(plain))
	m = _WORD.match(src, i)
	if m and m.group() in ("true", "false"):
		return Node("bool", i, m.end(), value=m.group() == "true")
	# Vector2(…) · 다른 상수 · 식. 이 도구가 다루는 것은 값 그대로 적힌 리터럴뿐이다.
	raise DataError("리터럴이 아니다: %s" % src[i:i + 24].split("\n")[0])


def _value(node: Node):
	if node.kind == "list":
		return [_value(n) for n in node.items]
	if node.kind == "dict":
		return {_value(k): _value(v) for k, v in node.items}
	return node.value


def gd_str(s: str) -> str:
	return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def gd_val(v, old: str = "") -> str:
	"""파이썬 값을 GDScript 글자로. old 는 그 자리에 있던 글자 — 자릿수와 밑줄을 따라 쓴다."""
	if isinstance(v, bool):
		return "true" if v else "false"
	if isinstance(v, str):
		return gd_str(v)
	if isinstance(v, list):
		return "[" + ", ".join(gd_val(i) for i in v) + "]"
	if isinstance(v, int):
		return format(v, "_") if "_" in old else str(v)
	if "." in old:
		# 1.90 자리에 2.1 을 넣으면 2.10 — 옆 줄과 자릿수가 맞아야 표가 읽힌다.
		decimals = len(re.split(r"[eE]", old)[0].split(".")[1].replace("_", ""))
		text = "%.*f" % (max(decimals, 1), v)
		if float(text) == v:
			return text
	text = repr(float(v))
	if "inf" in text or "nan" in text:
		raise DataError("쓸 수 없는 숫자: %s" % text)
	return text if ("." in text or "e" in text) else text + ".0"


_KIND = {bool: "bool", int: "int", float: "float", str: "str", list: "list", dict: "dict"}


class GdFile:
	"""GDScript 파일 하나. 고칠 자리를 모아 뒀다가 한 번에 갈아 끼운다."""

	def __init__(self, rel: str):
		self.rel = rel
		self.src = _read(rel)
		self.edits: list[tuple[int, int, int, str]] = []

	def _where(self, pos: int) -> str:
		return "%s:%d" % (self.rel, self.src.count("\n", 0, pos) + 1)

	def const(self, name: str) -> Node:
		m = re.search(r"^const %s\b[^=\n]*=" % re.escape(name), self.src, re.M)
		if not m:
			raise DataError("%s 에 const %s 가 없다" % (self.rel, name))
		try:
			return _parse(self.src, m.end())
		except IndexError:
			raise DataError("%s 의 %s: 리터럴이 끝나지 않았다" % (self.rel, name)) from None
		except DataError as e:
			raise DataError("%s 의 %s: %s" % (self.rel, name, e)) from None

	def scalars(self) -> dict[str, Node]:
		"""값 하나가 그대로 적힌 상수 전부(선언한 차례대로). 식으로 정한 것은 뺀다."""
		out: dict[str, Node] = {}
		for m in re.finditer(r"^const (\w+)\b[^=\n]*=[ \t]*", self.src, re.M):
			try:
				node = _parse(self.src, m.end())
			except (DataError, IndexError):
				continue
			if node.kind not in ("int", "float", "str", "bool"):
				continue
			end = self.src.find("\n", node.end)
			rest = self.src[node.end:len(self.src) if end < 0 else end]
			if rest.strip() == "" or rest.lstrip().startswith("#"):
				out[m.group(1)] = node
		return out

	def docs(self) -> dict[str, str]:
		"""상수 바로 위의 ## 설명과 줄 끝 설명. DB 에서 그 숫자가 무엇인지 보라고 같이 싣는다."""
		lines = self.src.split("\n")
		out: dict[str, str] = {}
		for i, line in enumerate(lines):
			m = re.match(r"const (\w+)\b", line)
			if not m:
				continue
			doc: list[str] = []
			j = i - 1
			while j >= 0 and lines[j].startswith("##"):
				doc.insert(0, lines[j][2:].strip())
				j -= 1
			tail = re.search(r"\s##\s*(.*)$", line)
			if tail:
				doc.append(tail.group(1).strip())
			out[m.group(1)] = "\n".join(doc)
		return out

	def put(self, start: int, end: int, text: str) -> None:
		self.edits.append((start, end, len(self.edits), text))

	def set(self, node: Node, want, what: str) -> None:
		"""그 자리의 값이 want 와 다르면 그 글자만 바꾼다."""
		if _canon(_value(node)) == _canon(want):
			return
		if node.kind != _KIND[type(want)]:
			raise DataError("%s (%s): 코드는 %s 인데 DB 는 %s 이다 — 형은 코드가 정한다"
							% (what, self._where(node.start), node.kind, _KIND[type(want)]))
		self.put(node.start, node.end, gd_val(want, self.src[node.start:node.end]))

	def cut(self, start: int, end: int) -> None:
		"""표의 한 칸(start~end)을 뺀다. 뒤따르는 쉼표까지, 그 줄에 혼자였으면 줄째로.

		앞쪽 글자는 안 건드린다 — 앞 칸의 쉼표가 끝에 남아도 GDScript 는 그대로 읽는다.
		"""
		m = re.compile(r"[ \t]*,[ \t]*").match(self.src, end)
		end = m.end() if m else end
		head, tail = self.line_start(start), self.line_end(end)
		rest = self.src[end:tail].strip()
		if rest == "" or rest.startswith("#"):
			lead = self.src[head:start]
			# 줄의 마지막 칸이다: 혼자였으면 줄째로, 아니면 앞의 빈칸부터 줄 끝(주석 앞)까지.
			if lead.strip() == "":
				self.put(head, tail, "")
				return
			start -= len(lead) - len(lead.rstrip())
			end = tail - 1 if rest == "" and self.src[tail - 1:tail] == "\n" else end
		self.put(start, end, "")

	def line_start(self, pos: int) -> int:
		return self.src.rfind("\n", 0, pos) + 1

	def line_end(self, pos: int) -> int:
		j = self.src.find("\n", pos)
		return len(self.src) if j < 0 else j + 1

	def render(self) -> str:
		out, pos = [], 0
		for start, end, _, text in sorted(self.edits):
			if start < pos:
				raise DataError("%s: 고칠 자리가 겹친다 (%s)" % (self.rel, self._where(start)))
			out.append(self.src[pos:start])
			out.append(text)
			pos = end
		out.append(self.src[pos:])
		return "".join(out)


# --------------------------------------------------------------------------- #
# 견주기 — 값을 길(path)마다 펴서 본다
# --------------------------------------------------------------------------- #
MISSING = object()


def _canon(v) -> str:
	"""형까지 가르는 글자. 1 과 1.0 · true 와 1 이 서로 다르게 나온다."""
	return "(없음)" if v is MISSING else json.dumps(v, ensure_ascii=False, sort_keys=True)


def _hash(v) -> str:
	return hashlib.sha1(_canon(v).encode("utf-8")).hexdigest()[:20]


def flatten(doc: dict) -> dict[tuple, object]:
	"""사전만 타고 내려간다. 배열(줄 차례 · 상성 목록)과 값이 잎이다."""
	out: dict[tuple, object] = {}

	def walk(node, path):
		if isinstance(node, dict):
			for k, v in node.items():
				walk(v, path + (k,))
		else:
			out[path] = node
	walk(doc, ())
	return out


def unflatten(flat: dict[tuple, object]) -> dict:
	doc: dict = {}
	for path, v in flat.items():
		cur = doc
		for k in path[:-1]:
			cur = cur.setdefault(k, {})
		cur[path[-1]] = v
	return doc


def compare(F: dict, D: dict, B: dict) -> dict[str, list]:
	"""길마다 파일 · DB · 기준을 견줘 셋으로 가른다. 값은 (길, 파일 값, DB 값)."""
	out = {"pending": [], "drift": [], "conflict": []}
	gone = _hash(MISSING)
	for path in sorted(set(F) | set(D), key=_canon):
		f, d = F.get(path, MISSING), D.get(path, MISSING)
		if _canon(f) == _canon(d):
			continue
		base = B.get(_hash(list(path)), gone)
		f_moved, d_moved = _hash(f) != base, _hash(d) != base
		kind = "pending" if d_moved and not f_moved else "drift" if f_moved and not d_moved else "conflict"
		out[kind].append((path, f, d))
	return out


# --------------------------------------------------------------------------- #
# 게임 파일 쪽 — 읽기
# --------------------------------------------------------------------------- #
def _read(rel: str) -> str:
	with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
		return f.read()


def _write(rel: str, text: str) -> None:
	with open(os.path.join(ROOT, rel), "w", encoding="utf-8") as f:
		f.write(text)


def _load_json(rel: str):
	return json.loads(_read(rel))


def _take(row: dict, keys, optional=(), where: str = "") -> dict:
	"""정해진 열만 받는다. 모르는 키를 말없이 버리면 다음에 내릴 때 그 값이 사라진다."""
	extra = set(row) - set(keys) - {"id"}
	if extra:
		raise DataError("%s: 모르는 키 %s — tools/gamedb.py 의 표에 열을 먼저 더해야 한다" % (where, sorted(extra)))
	missing = set(keys) - set(optional) - set(row)
	if missing:
		raise DataError("%s: 빠진 키 %s" % (where, sorted(missing)))
	return {k: row[k] for k in keys if k in row}


def _table(doc: dict, sec: str, ordered: bool = False) -> dict:
	t = doc.setdefault(sec, {})
	t.setdefault("rows", {})
	if ordered:
		t.setdefault("order", [])
	return t


def read_gd(spec: dict, gf: GdFile, doc: dict) -> None:
	kind, sec = spec["kind"], spec["sec"]
	rows = _table(doc, sec, ordered=kind == "list")["rows"]
	if kind == "scalars":
		for name, node in gf.scalars().items():
			rows[name] = node.value
		return
	node = gf.const(spec["const"])
	what = "%s 의 %s" % (gf.rel, spec["const"])
	if kind == "col":
		if node.kind != "list":
			raise DataError("%s: 배열이어야 한다" % what)
		for i, item in enumerate(node.items):
			rows.setdefault(str(i), {})[spec["field"]] = _value(item)
	elif kind == "flat":
		for key, val in node.items:
			if spec["field"] is None:
				rows[key.value] = _value(val)
			elif key.value in rows or not spec.get("open"):
				rows.setdefault(key.value, {})[spec["field"]] = _value(val)
			else:
				raise DataError("%s: %s 는 %s 표에 없는 줄이다" % (what, key.value, sec))
	else:
		base, bag = spec["base"], spec.get("bag")
		if kind == "list":
			pairs = [(_value(item).get("id") if item.kind == "dict" else None, item) for item in node.items]
		else:
			pairs = [(key.value, val) for key, val in node.items]
		for rid, item in pairs:
			if item.kind != "dict" or rid is None:
				raise DataError("%s: 줄마다 사전이어야 하고 list 표는 id 가 있어야 한다" % what)
			row = rows.setdefault(rid, {})
			if bag:
				row[bag] = {}
			for key, val in item.items:
				if key.value == "id" and kind == "list":
					continue
				if key.value in base:
					row[key.value] = _value(val)
				elif bag:
					row[bag][key.value] = _value(val)
				else:
					raise DataError("%s: %s 줄에 모르는 키 %s" % (what, rid, key.value))
			lost = [b for b in base if b not in row]
			if lost:
				raise DataError("%s: %s 줄에 %s 가 없다" % (what, rid, lost))
			if kind == "list":
				doc[sec]["order"].append(rid)


def read_files() -> dict:
	"""게임이 지금 들고 있는 값 전부."""
	doc: dict = {}
	r = _load_json(ROSTER_JSON)
	extra = set(r) - {"tiers", "monsters", "themes", "arts"}
	if extra:
		raise DataError("%s: 모르는 묶음 %s" % (ROSTER_JSON, sorted(extra)))
	tiers, units = _table(doc, "art_tiers", True), _table(doc, "units", True)
	for t in r["tiers"]:
		tiers["order"].append(t["tier"])
		tiers["rows"][t["tier"]] = {"ko": t["ko"], "n": t["n"]}
		for u in t["units"]:
			units["order"].append(u["id"])
			units["rows"][u["id"]] = {"art_tier": t["tier"], **_take(u, UNIT_KEYS, where="units." + u["id"])}
	for sec, key, keys, optional in (("monsters", "monsters", MONSTER_KEYS, ()), ("themes", "themes", THEME_KEYS, ()),
									 ("arts", "arts", ART_KEYS, ART_OPTIONAL)):
		table = _table(doc, sec, True)
		for row in r[key]:
			table["order"].append(row["id"])
			table["rows"][row["id"]] = _take(row, keys, optional, where="%s.%s" % (sec, row["id"]))

	heroes = _load_json(HEROES_JSON)
	for uid, entry in heroes.items():
		if uid not in units["rows"]:
			raise DataError("%s: %s 는 로스터에 없는 영웅이다" % (HEROES_JSON, uid))
		for loc in LOCALES:
			if loc in entry:
				units["rows"][uid]["blurb_" + loc] = entry[loc]

	ui = _load_json(UI_JSON)
	if set(ui) != set(LOCALES):
		raise DataError("%s: 언어는 %s 여야 한다" % (UI_JSON, list(LOCALES)))
	doc["strings"] = {loc: {"order": list(ui[loc]), "rows": dict(ui[loc])} for loc in LOCALES}

	files: dict[str, GdFile] = {}
	for spec in SPECS:
		gf = files.setdefault(spec["file"], GdFile(spec["file"]))
		read_gd(spec, gf, doc)
	return doc


# --------------------------------------------------------------------------- #
# 게임 파일 쪽 — 쓰기
# --------------------------------------------------------------------------- #
def _row_text(pairs) -> str:
	return "{" + ", ".join("%s: %s" % (gd_str(k), gd_val(v)) for k, v in pairs) + "}"


def _want_row(spec: dict, rid: str, row: dict) -> dict:
	want = {"id": rid} if spec["kind"] == "list" else {}
	want.update((b, row[b]) for b in spec["base"])
	want.update(row.get(spec.get("bag", ""), {}))
	return want


def _patch_row(gf: GdFile, node: Node, want: dict, what: str) -> None:
	have = {k.value: v for k, v in node.items}
	if set(have) == set(want):
		for key, val in have.items():
			gf.set(val, want[key], "%s.%s" % (what, key))
		return
	# 키가 늘거나 줄었다 — 그 줄만 다시 적는다. 남는 값은 원래 글자를 그대로 쓴다.
	parts = []
	for key, val in have.items():
		if key in want:
			same = _canon(_value(val)) == _canon(want[key])
			text = gf.src[val.start:val.end]
			parts.append("%s: %s" % (gd_str(key), text if same else gd_val(want[key], text)))
	parts += ["%s: %s" % (gd_str(k), gd_val(v)) for k, v in want.items() if k not in have]
	gf.put(node.start, node.end, "{" + ", ".join(parts) + "}")


def patch_gd(spec: dict, gf: GdFile, doc: dict) -> None:
	kind, sec = spec["kind"], spec["sec"]
	rows = doc.get(sec, {}).get("rows", {})
	label = "%s(%s)" % (sec, SECTIONS[sec][0])
	fixed = "%s 의 줄은 코드가 정한다 — %s 를 고치고 `pull` 하거나 DB 를 되돌려라" % (label, gf.rel)
	if kind == "scalars":
		have = gf.scalars()
		if set(have) != set(rows):
			raise DataError("%s (다른 줄: %s)" % (fixed, sorted(set(have) ^ set(rows))))
		for name, node in have.items():
			gf.set(node, rows[name], "%s.%s" % (sec, name))
		return
	node = gf.const(spec["const"])
	what = "%s.%s" % (sec, spec["const"])
	if kind == "col":
		if len(node.items) != len(rows):
			raise DataError("%s (줄 수 %d ≠ %d)" % (fixed, len(node.items), len(rows)))
		for i, item in enumerate(node.items):
			gf.set(item, rows[str(i)][spec["field"]], "%s[%d]" % (what, i))
	elif kind == "flat":
		field = spec["field"]
		want = {k: (v if field is None else v.get(field)) for k, v in rows.items()}
		want = {k: v for k, v in want.items() if v is not None}
		have = {k.value: (k, v) for k, v in node.items}
		if not spec.get("open") and set(have) != set(want):
			raise DataError("%s (다른 줄: %s)" % (fixed, sorted(set(have) ^ set(want))))
		last = None   # 남는 마지막 줄 — 새 줄을 그 뒤에 잇는다
		for key, (knode, vnode) in have.items():
			if key in want:
				gf.set(vnode, want[key], "%s.%s" % (what, key))
				last = vnode
			else:
				gf.cut(knode.start, vnode.end)
		new = ["%s: %s" % (gd_str(k), gd_val(v)) for k, v in want.items() if k not in have]
		if new and last is not None:
			gf.put(last.end, last.end, "".join(", " + n for n in new))
		elif new:
			gf.put(node.start + 1, node.start + 1, ", ".join(new) + (", " if have else ""))
	elif kind == "rows":
		have = {k.value: v for k, v in node.items}
		if set(have) != set(rows):
			raise DataError("%s (다른 줄: %s)" % (fixed, sorted(set(have) ^ set(rows))))
		for rid, item in have.items():
			_patch_row(gf, item, _want_row(spec, rid, rows[rid]), "%s.%s" % (what, rid))
	else:
		listed = [i for i in doc.get(sec, {}).get("order", []) if i in rows]
		order = listed + [i for i in rows if i not in listed]
		have = {_value(item)["id"]: item for item in node.items}
		kept = [i for i in have if i in rows]
		if kept != [i for i in order if i in have]:
			raise DataError("%s 의 줄 차례는 자동으로 못 내린다 — %s 에서 줄을 옮기고 `pull` 하라" % (label, gf.rel))
		for rid, item in have.items():
			if rid in rows:
				_patch_row(gf, item, _want_row(spec, rid, rows[rid]), "%s.%s" % (what, rid))
				continue
			gf.cut(item.start, item.end)
		anchor = gf.line_end(node.start)   # 여는 괄호 줄의 끝
		for rid in order:
			if rid in have:
				anchor = gf.line_end(have[rid].end)
			else:
				gf.put(anchor, anchor, "\t%s,\n" % _row_text(_want_row(spec, rid, rows[rid]).items()))


def _dump(obj, indent: int) -> str:
	return json.dumps(obj, ensure_ascii=False, indent=indent) + "\n"


def render_json(doc: dict) -> dict[str, str]:
	"""DB 의 값으로 JSON 세 장을 찍는다. 키 차례는 여기 적힌 대로 한 가지다."""
	units, tiers = doc["units"], doc["art_tiers"]
	bodies = list(doc["bodies"]["rows"])
	out_tiers = []
	for key in tiers["order"]:
		members = [{"id": uid, **{k: units["rows"][uid][k] for k in UNIT_KEYS}}
				   for uid in units["order"] if units["rows"][uid]["art_tier"] == key]
		out_tiers.append({"tier": key, "ko": tiers["rows"][key]["ko"], "n": tiers["rows"][key]["n"], "units": members})
	stray = [u for u in units["order"] if units["rows"][u]["art_tier"] not in tiers["rows"]]
	if stray:
		raise DataError("units: 없는 원화 격을 가리킨다 %s" % stray)
	themes = []
	for tid in doc["themes"]["order"]:
		row = doc["themes"]["rows"][tid]
		if set(row["weights"]) != set(bodies):
			raise DataError("themes.%s: weights 는 몸 다섯(%s)을 다 적어야 한다" % (tid, bodies))
		themes.append({"id": tid, **{k: ({b: row["weights"][b] for b in bodies} if k == "weights" else row[k]) for k in THEME_KEYS}})
	roster = {
		"tiers": out_tiers,
		"monsters": [{"id": i, **{k: doc["monsters"]["rows"][i][k] for k in MONSTER_KEYS}} for i in doc["monsters"]["order"]],
		"themes": themes,
		"arts": [{"id": i, **{k: doc["arts"]["rows"][i][k] for k in ART_KEYS if k in doc["arts"]["rows"][i]}} for i in doc["arts"]["order"]],
	}
	heroes = {}
	for uid in units["order"]:
		entry = {loc: units["rows"][uid]["blurb_" + loc] for loc in LOCALES if "blurb_" + loc in units["rows"][uid]}
		if entry:
			heroes[uid] = entry
	ui = {loc: {src: doc["strings"][loc]["rows"][src] for src in doc["strings"][loc]["order"]} for loc in LOCALES}
	return {ROSTER_JSON: _dump(roster, 1), HEROES_JSON: _dump(heroes, 2), UI_JSON: _dump(ui, 2)}


def write_files(doc: dict) -> list[str]:
	"""DB 의 값을 게임 파일에 내린다. 값이 같은 파일은 안 건드린다. 쓴 파일 목록을 준다.

	★ 다 쓴 뒤 **다시 읽어서** DB 와 같은지 본다. 다르면 전부 원래대로 돌려놓고 멈춘다 —
	  반쯤 내려간 표는 어느 쪽도 아닌 값이라 검사기도 못 잡는다.
	"""
	texts: dict[str, str] = {}
	for rel, text in render_json(doc).items():
		if json.loads(_read(rel)) != json.loads(text):
			texts[rel] = text
	files: dict[str, GdFile] = {}
	for spec in SPECS:
		patch_gd(spec, files.setdefault(spec["file"], GdFile(spec["file"])), doc)
	for rel, gf in files.items():
		if gf.edits:
			texts[rel] = gf.render()
	if not texts:
		return []

	touched = list(texts) + (["core/roster.gd"] if ROSTER_JSON in texts else [])
	backup = {rel: _read(rel) for rel in touched}
	try:
		for rel, text in texts.items():
			_write(rel, text)
		if ROSTER_JSON in texts:
			# 로스터는 JSON 에서 한 번 더 내려간다 — 게임이 읽는 것은 core/roster.gd 다.
			run = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gen_roster.py")],
								 capture_output=True, text=True)
			if run.returncode != 0:
				raise DataError("tools/gen_roster.py 가 실패했다:\n" + (run.stdout + run.stderr).strip())
		after, want = flatten(read_files()), flatten(doc)
		wrong = [p for p in set(after) | set(want) if _canon(after.get(p, MISSING)) != _canon(want.get(p, MISSING))]
		if wrong:
			raise DataError("내린 뒤 다시 읽은 값이 DB 와 다르다: %s"
							% " / ".join(_path_text(p) for p in sorted(wrong, key=_canon)[:5]))
	except BaseException:
		for rel, text in backup.items():
			_write(rel, text)
		raise
	return [rel for rel in touched if _read(rel) != backup[rel]]


# --------------------------------------------------------------------------- #
# DB 쪽
# --------------------------------------------------------------------------- #
def _real(col: str, null: bool = False) -> str:
	return '"%s" REAL %sCHECK (%stypeof("%s") = \'real\')' % (col, "" if null else "NOT NULL ", '"%s" IS NULL OR ' % col if null else "", col)


def _int(col: str) -> str:
	return '"%s" INTEGER NOT NULL CHECK (typeof("%s") = \'integer\')' % (col, col)


def _flag(col: str, null: bool = False) -> str:
	return '"%s" INTEGER %sCHECK ("%s" IN (0, 1))' % (col, "" if null else "NOT NULL ", col)


def _color(col: str) -> str:
	return '"%s" TEXT NOT NULL CHECK ("%s" GLOB \'#%s\')' % (col, col, "[0-9A-Fa-f]" * 6)


SCHEMA_VERSION = "1"

# ★ CHECK 를 **열에** 붙인다. 표 제약으로 두면 그 뒤에 다른 열을 못 적는다.
_TYPED = ('"type" TEXT NOT NULL DEFAULT \'float\' CHECK ("type" IN (\'int\', \'float\', \'str\', \'bool\')), '
		  '"value" NOT NULL CHECK (("type" = \'int\' AND typeof("value") = \'integer\') '
		  'OR ("type" = \'float\' AND typeof("value") IN (\'real\', \'integer\')) '
		  'OR ("type" = \'str\' AND typeof("value") = \'text\') OR ("type" = \'bool\' AND "value" IN (0, 1)))')

SCHEMA = f"""
-- ── 규칙의 축 (core/balance.gd) ── 줄은 코드가 정한다: 값만 고친다 ─────────────
CREATE TABLE elements (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, {_color("color")},
	rider TEXT NOT NULL DEFAULT '', {_real("dmg")});
CREATE TABLE bodies (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, {_color("color")});
CREATE TABLE affinity (body TEXT NOT NULL REFERENCES bodies(id), elem TEXT NOT NULL REFERENCES elements(id),
	kind TEXT NOT NULL CHECK (kind IN ('weak', 'resist', 'immune')), sort INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (body, elem));
CREATE TABLE statuses (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL,
	{_real("amount", True)}, {_real("chance", True)}, {_real("sec")});
CREATE TABLE hero_tiers (tier INTEGER PRIMARY KEY, {_real("atk")}, {_real("rate")});
CREATE TABLE weapons (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, {_real("range")});
CREATE TABLE profiles (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, {_real("atk")}, {_real("rate")}, {_real("range_mult")});
CREATE TABLE roles (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, {_real("atk")}, "desc" TEXT NOT NULL);
CREATE TABLE bullets (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, {_real("dmg")}, {_real("speed")});
CREATE TABLE bullet_params (bullet TEXT NOT NULL REFERENCES bullets(id), key TEXT NOT NULL, sort INTEGER NOT NULL DEFAULT 0,
	{_TYPED}, PRIMARY KEY (bullet, key));
CREATE TABLE monster_kinds (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, {_real("hp")}, {_real("spd")},
	{_real("gold")}, {_int("crush")});
CREATE TABLE rite_gates (ring INTEGER PRIMARY KEY, {_int("width")});
CREATE TABLE theme_rank_hp (rank INTEGER PRIMARY KEY, {_real("mult")});
CREATE TABLE tuning (key TEXT PRIMARY KEY, sort INTEGER NOT NULL, {_TYPED}, doc TEXT NOT NULL DEFAULT '');

-- ── 상점 (core/balance.gd) ── 줄을 더하고 뺄 수 있다 ───────────────────────────
CREATE TABLE upgrades (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, "desc" TEXT NOT NULL, show TEXT NOT NULL,
	{_int("base")}, {_real("grow")}, {_int("cap")});
CREATE TABLE passives (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, "desc" TEXT NOT NULL, {_int("cost")},
	{_int("rank")}, icon TEXT NOT NULL, {_color("tint")});
CREATE TABLE passive_effects (passive TEXT NOT NULL REFERENCES passives(id) ON DELETE CASCADE, key TEXT NOT NULL,
	sort INTEGER NOT NULL DEFAULT 0, {_TYPED}, PRIMARY KEY (passive, key));

-- ── 캐릭터 · 몬스터 · 테마 · 화면 그림 (tools/roster.json → core/roster.gd) ───────
CREATE TABLE art_tiers (key TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, {_int("n")});
CREATE TABLE units (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, art_tier TEXT NOT NULL REFERENCES art_tiers(key),
	ko TEXT NOT NULL, en TEXT NOT NULL, role TEXT NOT NULL REFERENCES roles(id), profile TEXT NOT NULL REFERENCES profiles(id),
	bullet TEXT NOT NULL REFERENCES bullets(id), weapon TEXT NOT NULL REFERENCES weapons(id), elem TEXT NOT NULL REFERENCES elements(id),
	{_real("sc")}, "desc" TEXT NOT NULL, lore TEXT NOT NULL, prompt TEXT NOT NULL, {_color("color")}, {_flag("holes")}, {_flag("anim")},
	blurb_ko TEXT, blurb_en TEXT);
CREATE TABLE monsters (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, kind TEXT NOT NULL REFERENCES monster_kinds(id),
	body TEXT NOT NULL REFERENCES bodies(id), "desc" TEXT NOT NULL, prompt TEXT NOT NULL, {_color("color")}, {_flag("holes")});
CREATE TABLE themes (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, main_body TEXT NOT NULL REFERENCES bodies(id),
	boss_body TEXT NOT NULL REFERENCES bodies(id), rank INTEGER NOT NULL REFERENCES theme_rank_hp(rank), {_color("bg")}, {_color("floor")},
	prompt TEXT NOT NULL, floor_prompt TEXT NOT NULL, motif TEXT, CHECK (boss_body = main_body));
CREATE TABLE theme_weights (theme TEXT NOT NULL REFERENCES themes(id) ON DELETE CASCADE, body TEXT NOT NULL REFERENCES bodies(id),
	{_real("weight")}, PRIMARY KEY (theme, body));
CREATE TABLE arts (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, ko TEXT NOT NULL, {_flag("cut")}, {_flag("fx", True)}, {_flag("square", True)},
	size TEXT, prompt TEXT NOT NULL, {_color("color")}, art TEXT, {_flag("holes", True)});

-- ── 문구 (core/locales/ui.json) · 효과음 간격 (core/sound.gd) ─────────────────────
CREATE TABLE strings (locale TEXT NOT NULL CHECK (locale IN ('ko', 'en')), source TEXT NOT NULL, sort INTEGER NOT NULL DEFAULT 0,
	text TEXT NOT NULL, PRIMARY KEY (locale, source));
CREATE TABLE sfx_gaps (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, {_real("gap")});

-- ── 도구가 쓰는 표 ── 손으로 고치지 않는다 ───────────────────────────────────
CREATE TABLE _meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE _baseline (path TEXT PRIMARY KEY, hash TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE _approvals (id INTEGER PRIMARY KEY, at TEXT NOT NULL, kind TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',
	count INTEGER NOT NULL, changes TEXT NOT NULL);
INSERT INTO _meta VALUES ('schema', '{SCHEMA_VERSION}');
"""


def connect(write: bool = False) -> sqlite3.Connection:
	if not os.path.exists(DB_PATH):
		raise DataError("%s 가 없다 — `python3 tools/gamedb.py init` 으로 짓는다" % DB_REL)
	conn = sqlite3.connect(DB_PATH if write else "file:%s?mode=ro" % DB_PATH, uri=not write, isolation_level=None)
	conn.execute("PRAGMA foreign_keys = ON")
	try:
		schema = conn.execute("SELECT value FROM _meta WHERE key = 'schema'").fetchone()
	except sqlite3.Error:
		schema = None
	if schema != (SCHEMA_VERSION,):
		raise DataError("%s 는 이 도구가 지은 DB 가 아니거나 판이 다르다 (%r)" % (DB_REL, schema))
	return conn


def _typed(kind: str, value, where: str):
	if kind == "int":
		if isinstance(value, float) and not value.is_integer():
			raise DataError("%s: 정수여야 한다 (%r)" % (where, value))
		return int(value)
	if kind == "float":
		return float(value)
	if kind == "bool":
		return bool(value)
	return str(value)


def _untyped(value) -> tuple[str, object]:
	return _KIND[type(value)], int(value) if isinstance(value, bool) else value


def read_db(conn: sqlite3.Connection) -> dict:
	q = lambda sql, *a: conn.execute(sql, a).fetchall()
	doc: dict = {}

	def table(sec, sql, fields, ordered=False, flags=()):
		t = _table(doc, sec, ordered)
		for row in q(sql):
			item = {f: v for f, v in zip(fields, row[1:]) if v is not None}
			for f in flags:
				if f in item:
					item[f] = bool(item[f])
			t["rows"][row[0]] = item
			if ordered:
				t["order"].append(row[0])
		return t

	def bag(sql, key, where):
		return {k: _typed(t, v, "%s.%s.%s" % (where, key, k)) for k, t, v in q(sql, key)}

	table("art_tiers", "SELECT key, ko, n FROM art_tiers ORDER BY sort, key", ("ko", "n"), True)
	table("units", "SELECT u.id, u.art_tier, u.ko, u.en, u.role, u.profile, u.bullet, u.weapon, u.elem, u.sc, u.\"desc\", u.lore, "
		  "u.prompt, u.color, u.holes, u.anim, u.blurb_ko, u.blurb_en FROM units u JOIN art_tiers t ON t.key = u.art_tier "
		  "ORDER BY t.sort, t.key, u.sort, u.id", ("art_tier",) + UNIT_KEYS + ("blurb_ko", "blurb_en"), True, ("holes", "anim"))
	table("monsters", 'SELECT id, ko, kind, body, "desc", prompt, color, holes FROM monsters ORDER BY sort, id', MONSTER_KEYS, True, ("holes",))
	themes = table("themes", "SELECT id, ko, main_body, boss_body, rank, bg, floor, prompt, floor_prompt, motif FROM themes ORDER BY sort, id",
				   ("ko", "main_body", "boss_body", "rank", "bg", "floor", "prompt", "floor_prompt", "motif"), True)
	for tid, row in themes["rows"].items():
		row["weights"] = dict(q("SELECT w.body, w.weight FROM theme_weights w JOIN bodies b ON b.id = w.body WHERE w.theme = ? ORDER BY b.sort", tid))
	arts = table("arts", "SELECT id, ko, cut, fx, square, size, prompt, color, art, holes FROM arts ORDER BY sort, id", ART_KEYS, True,
				 ("cut", "fx", "square", "holes"))
	for aid, row in arts["rows"].items():
		if "size" in row:
			row["size"] = json.loads(row["size"])
	doc["strings"] = {}
	for loc in LOCALES:
		pairs = q("SELECT source, text FROM strings WHERE locale = ? ORDER BY sort, source", loc)
		doc["strings"][loc] = {"order": [s for s, _ in pairs], "rows": dict(pairs)}

	for tier, atk, rate in q("SELECT tier, atk, rate FROM hero_tiers ORDER BY tier"):
		_table(doc, "hero_tiers")["rows"][str(tier)] = {"atk": atk, "rate": rate}
	for ring, width in q("SELECT ring, width FROM rite_gates ORDER BY ring"):
		_table(doc, "rite_gates")["rows"][str(ring)] = {"width": width}
	for rank, mult in q("SELECT rank, mult FROM theme_rank_hp ORDER BY rank"):
		_table(doc, "theme_rank_hp")["rows"][str(rank)] = {"mult": mult}
	table("weapons", "SELECT id, range FROM weapons ORDER BY sort, id", ("range",))
	table("profiles", "SELECT id, ko, atk, rate, range_mult FROM profiles ORDER BY sort, id", ("ko", "atk", "rate", "range_mult"))
	table("roles", 'SELECT id, ko, atk, "desc" FROM roles ORDER BY sort, id', ("ko", "atk", "desc"))
	table("elements", "SELECT id, ko, color, rider, dmg FROM elements ORDER BY sort, id", ("ko", "color", "rider", "dmg"))
	bodies = table("bodies", "SELECT id, ko, color FROM bodies ORDER BY sort, id", ("ko", "color"))
	for bid, row in bodies["rows"].items():
		for kind in ("weak", "resist", "immune"):
			row[kind] = [e for (e,) in q("SELECT elem FROM affinity WHERE body = ? AND kind = ? ORDER BY sort, elem", bid, kind)]
	for sid, ko, amount, chance, sec in q("SELECT id, ko, amount, chance, sec FROM statuses ORDER BY sort, id"):
		params = {k: v for k, v in (("amount", amount), ("chance", chance)) if v is not None}
		_table(doc, "statuses")["rows"][sid] = {"ko": ko, "sec": sec, "params": params}
	table("monster_kinds", "SELECT id, ko, hp, spd, gold, crush FROM monster_kinds ORDER BY sort, id", ("ko", "hp", "spd", "gold", "crush"))
	bullets = table("bullets", "SELECT id, ko, dmg, speed FROM bullets ORDER BY sort, id", ("ko", "dmg", "speed"))
	for bid, row in bullets["rows"].items():
		row["params"] = bag("SELECT key, type, value FROM bullet_params WHERE bullet = ? ORDER BY sort, key", bid, "bullet_params")
	table("upgrades", 'SELECT id, ko, "desc", show, base, grow, cap FROM upgrades ORDER BY sort, id', ("ko", "desc", "show", "base", "grow", "cap"), True)
	passives = table("passives", 'SELECT id, ko, "desc", cost, rank, icon, tint FROM passives ORDER BY sort, id',
					 ("ko", "desc", "cost", "rank", "icon", "tint"), True)
	for pid, row in passives["rows"].items():
		row["effects"] = bag("SELECT key, type, value FROM passive_effects WHERE passive = ? ORDER BY sort, key", pid, "passive_effects")
	for key, kind, value in q("SELECT key, type, value FROM tuning ORDER BY sort, key"):
		_table(doc, "tuning")["rows"][key] = _typed(kind, value, "tuning." + key)
	for sid, gap in q("SELECT id, gap FROM sfx_gaps ORDER BY sort, id"):
		_table(doc, "sfx_gaps")["rows"][sid] = gap
	return doc


def _sync(conn, table: str, keys: tuple, rows: list[dict], sort: str = "") -> None:
	"""표를 rows 대로 맞춘다 — 있는 줄은 그 열만 고치고, 없는 줄은 넣고, 남는 줄은 지운다.

	sort: "order" 면 rows 의 차례가 곧 sort, "keep" 이면 있던 줄의 sort 는 두고 새 줄만 뒤에 붙인다.
	"""
	have = {tuple(r) for r in conn.execute("SELECT %s FROM %s" % (", ".join('"%s"' % k for k in keys), table))}
	tail = conn.execute("SELECT coalesce(max(sort), -1) + 1 FROM %s" % table).fetchone()[0] if sort == "keep" else 0
	want = set()
	for i, row in enumerate(rows):
		key = tuple(row[k] for k in keys)
		want.add(key)
		row = dict(row)
		update = [c for c in row if c not in keys]
		if sort == "order":
			row["sort"] = i
			update.append("sort")
		elif sort == "keep":
			row["sort"] = tail
			tail += key not in have
		cols = list(row)
		conn.execute("INSERT INTO %s (%s) VALUES (%s) ON CONFLICT (%s) DO %s" % (
			table, ", ".join('"%s"' % c for c in cols), ", ".join("?" * len(cols)), ", ".join('"%s"' % k for k in keys),
			"UPDATE SET " + ", ".join('"%s" = excluded."%s"' % (c, c) for c in update) if update else "NOTHING"),
			[row[c] for c in cols])
	for key in have - want:
		conn.execute("DELETE FROM %s WHERE %s" % (table, " AND ".join('"%s" = ?' % k for k in keys)), key)


def write_db(conn: sqlite3.Connection, doc: dict) -> None:
	"""doc 의 값을 표에 적는다(init · pull). 부르는 쪽이 트랜잭션을 연다."""
	def rows(sec):
		return doc.get(sec, {}).get("rows", {})

	def order(sec):
		listed = [i for i in doc.get(sec, {}).get("order", []) if i in rows(sec)]
		return listed + [i for i in rows(sec) if i not in listed]

	def need(sec, rid, row, fields):
		lost = [f for f in fields if f not in row]
		if lost:
			raise DataError("%s.%s: %s 가 없다" % (sec, rid, lost))
		return {f: row[f] for f in fields}

	def bags(table, parent, sec, name):
		out = []
		for rid, row in rows(sec).items():
			for i, (k, v) in enumerate(row.get(name, {}).items()):
				kind, value = _untyped(v)
				out.append({parent: rid, "key": k, "sort": i, "type": kind, "value": value})
		_sync(conn, table, (parent, "key"), out)

	conn.execute("PRAGMA defer_foreign_keys = ON")
	for sec, table, key, field in (("hero_tiers", "hero_tiers", "tier", ("atk", "rate")), ("rite_gates", "rite_gates", "ring", ("width",)),
								   ("theme_rank_hp", "theme_rank_hp", "rank", ("mult",))):
		_sync(conn, table, (key,), [{key: int(i), **need(sec, i, r, field)} for i, r in rows(sec).items()])
	for sec, fields in (("weapons", ("range",)), ("profiles", ("ko", "atk", "rate", "range_mult")), ("roles", ("ko", "atk", "desc")),
						("elements", ("ko", "color", "rider", "dmg")), ("bodies", ("ko", "color")),
						("monster_kinds", ("ko", "hp", "spd", "gold", "crush")), ("bullets", ("ko", "dmg", "speed"))):
		_sync(conn, sec, ("id",), [{"id": i, **need(sec, i, r, fields)} for i, r in rows(sec).items()], "keep")
	_sync(conn, "affinity", ("body", "elem"), [{"body": b, "elem": e, "kind": kind, "sort": i}
											   for b, r in rows("bodies").items() for kind in ("weak", "resist", "immune")
											   for i, e in enumerate(r.get(kind, []))])
	status_rows = []
	for sid, row in rows("statuses").items():
		extra = set(row.get("params", {})) - {"amount", "chance"}
		if extra:
			raise DataError("statuses.%s: 모르는 키 %s" % (sid, sorted(extra)))
		status_rows.append({"id": sid, **need("statuses", sid, row, ("ko", "sec")), "amount": row.get("params", {}).get("amount"),
							"chance": row.get("params", {}).get("chance")})
	_sync(conn, "statuses", ("id",), status_rows, "keep")
	bags("bullet_params", "bullet", "bullets", "params")
	_sync(conn, "upgrades", ("id",), [{"id": i, **need("upgrades", i, rows("upgrades")[i], ("ko", "desc", "show", "base", "grow", "cap"))}
									  for i in order("upgrades")], "order")
	_sync(conn, "passives", ("id",), [{"id": i, **need("passives", i, rows("passives")[i], ("ko", "desc", "cost", "rank", "icon", "tint"))}
									  for i in order("passives")], "order")
	bags("passive_effects", "passive", "passives", "effects")
	tuning = []
	for key, value in rows("tuning").items():
		kind, stored = _untyped(value)
		tuning.append({"key": key, "type": kind, "value": stored})
	_sync(conn, "tuning", ("key",), tuning, "keep")
	_sync(conn, "sfx_gaps", ("id",), [{"id": i, "gap": v} for i, v in rows("sfx_gaps").items()], "keep")

	_sync(conn, "art_tiers", ("key",), [{"key": k, **need("art_tiers", k, rows("art_tiers")[k], ("ko", "n"))} for k in order("art_tiers")], "order")
	units = []
	for uid in order("units"):
		row = rows("units")[uid]
		units.append({"id": uid, **need("units", uid, row, ("art_tier",) + UNIT_KEYS), "blurb_ko": row.get("blurb_ko"), "blurb_en": row.get("blurb_en")})
	_sync(conn, "units", ("id",), units, "order")
	_sync(conn, "monsters", ("id",), [{"id": i, **need("monsters", i, rows("monsters")[i], MONSTER_KEYS)} for i in order("monsters")], "order")
	themes, weights = [], []
	for tid in order("themes"):
		row = rows("themes")[tid]
		fields = need("themes", tid, row, THEME_KEYS)
		for body, w in fields.pop("weights").items():
			weights.append({"theme": tid, "body": body, "weight": w})
		themes.append({"id": tid, **fields, "motif": row.get("motif")})
	_sync(conn, "themes", ("id",), themes, "order")
	_sync(conn, "theme_weights", ("theme", "body"), weights)
	arts = []
	for aid in order("arts"):
		row = need("arts", aid, rows("arts")[aid], tuple(k for k in ART_KEYS if k not in ART_OPTIONAL))
		row.update({k: rows("arts")[aid].get(k) for k in ART_OPTIONAL})
		if row["size"] is not None:
			row["size"] = json.dumps(row["size"])
		arts.append({"id": aid, **row})
	_sync(conn, "arts", ("id",), arts, "order")
	strings = []
	for loc in LOCALES:
		sec = doc.get("strings", {}).get(loc, {})
		listed = [s for s in sec.get("order", []) if s in sec.get("rows", {})]
		for i, src in enumerate(listed + [s for s in sec.get("rows", {}) if s not in listed]):
			strings.append({"locale": loc, "source": src, "sort": i, "text": sec["rows"][src]})
	_sync(conn, "strings", ("locale", "source"), strings)


def refresh_docs(conn: sqlite3.Connection) -> None:
	"""숫자 상수 옆의 설명을 코드 주석에서 다시 옮긴다. 보라고 싣는 것이라 내려가지는 않는다."""
	for name, text in GdFile(BALANCE).docs().items():
		conn.execute("UPDATE tuning SET doc = ? WHERE key = ? AND doc <> ?", (text, name, text))


def lint(conn: sqlite3.Connection) -> list[str]:
	"""CHECK 로 못 거르는, 여러 줄에 걸친 규칙."""
	out = ["외래키: %s 표의 %s 번 줄이 없는 %s 를 가리킨다" % (t, rowid, parent)
		   for t, rowid, parent, _ in conn.execute("PRAGMA foreign_key_check")]
	n = conn.execute("SELECT count(*) FROM bodies").fetchone()[0]
	for theme, count, total in conn.execute("SELECT t.id, count(w.body), coalesce(sum(w.weight), 0) FROM themes t "
											"LEFT JOIN theme_weights w ON w.theme = t.id GROUP BY t.id"):
		if count != n or abs(total - 1.0) > 1e-6:
			out.append("themes.%s: 몸 분포는 몸 %d가지를 다 적고 합이 1.0 이어야 한다 (지금 %d가지 · 합 %.4f)" % (theme, n, count, total))
	return out


def load_baseline(conn) -> dict[str, str]:
	"""마지막으로 맞췄을 때의 값. 길도 값도 해시로만 둔다 — 견주는 데는 그것으로 족하다."""
	return dict(conn.execute("SELECT path, hash FROM _baseline"))


def save_baseline(conn, flat: dict) -> None:
	conn.execute("DELETE FROM _baseline")
	conn.executemany("INSERT INTO _baseline VALUES (?, ?)", [(_hash(list(p)), _hash(v)) for p, v in flat.items()])


# --------------------------------------------------------------------------- #
# 화면에 적기
# --------------------------------------------------------------------------- #
def _path_text(path: tuple) -> str:
	return " · ".join(str(p) for p in path if p != "rows")


def _show(v) -> str:
	if v is MISSING:
		return "(없음)"
	text = json.dumps(v, ensure_ascii=False)
	return text if len(text) <= 46 else text[:44] + "…"


def _row_of(path: tuple) -> tuple:
	"""그 값이 든 줄의 길. 줄이 통째로 생기거나 사라진 것은 한 줄로 적는다."""
	i = len(path) - 1 - path[::-1].index("rows") if "rows" in path else -1
	return path[:i + 2] if 0 <= i < len(path) - 1 else path


def report(changes: list, old_side: dict, new_side: dict, arrow: str) -> list[str]:
	"""(길, 왼쪽 값, 오른쪽 값) 목록을 사람이 읽는 줄로. 어느 쪽이 왼쪽인지는 부르는 쪽이 정한다."""
	old_rows = {_row_of(p) for p in old_side}
	new_rows = {_row_of(p) for p in new_side}
	lines, seen = [], set()
	for path, a, b in changes:
		head = "  [%s] " % SECTIONS[path[0]][0]
		row = _row_of(path)
		if path[-1] == "order" and isinstance(a, list) and isinstance(b, list):
			if sorted(a) == sorted(b):
				lines.append(head + "%s — 줄 차례가 바뀌었다" % _path_text(path[:-1]))
			continue   # 줄이 늘고 준 것은 아래에서 줄마다 적는다
		if row not in old_rows or row not in new_rows:
			if row not in seen:
				seen.add(row)
				lines.append(head + "%s — %s" % (_path_text(row), "새 줄" if row not in old_rows else "줄 삭제"))
			continue
		lines.append(head + "%s    %s %s %s" % (_path_text(path), _show(a), arrow, _show(b)))
	return lines


def describe(cmp: dict, F: dict, D: dict) -> dict[str, list[str]]:
	"""셋으로 가른 것을 화면에 적을 줄로. 건수는 이 줄 수다(줄 하나가 통째로 생긴 것은 한 건)."""
	return {
		"pending": report(cmp["pending"], F, D, "→"),
		"drift": report([(p, d, f) for p, f, d in cmp["drift"]], D, F, "←"),
		"conflict": report(cmp["conflict"], F, D, "≠"),
	}


TITLES = {
	"pending": "승인 대기 %d건 — DB 에서 고쳤고 게임 파일에는 아직 안 내렸다 (게임 파일 → DB)",
	"drift": "파일 직접 수정 %d건 — 게임 파일이 DB 를 거치지 않고 바뀌었다 (DB ← 게임 파일)",
	"conflict": "충돌 %d건 — 같은 값을 DB 와 게임 파일에서 서로 다르게 고쳤다 (게임 파일 ≠ DB)",
}


def summary(lines: dict[str, list[str]], only=("pending", "drift", "conflict")) -> None:
	shown = False
	for key in only:
		if lines[key]:
			shown = True
			print(TITLES[key] % len(lines[key]))
			print("\n".join(lines[key]))
	if not shown and only == ("pending", "drift", "conflict"):
		print("DB 와 게임 파일이 같다.")


def _files_of(changes: list) -> list[str]:
	return sorted({rel for p, _, _ in changes for rel in SECTIONS[p[0]][1]})


# --------------------------------------------------------------------------- #
# 명령
# --------------------------------------------------------------------------- #
def _state(conn):
	F, D = flatten(read_files()), flatten(read_db(conn))
	cmp = compare(F, D, load_baseline(conn))
	return F, D, cmp, describe(cmp, F, D)


def _record(conn, kind: str, note: str, lines: list[str]) -> None:
	conn.execute("INSERT INTO _approvals (at, kind, note, count, changes) VALUES (?, ?, ?, ?, ?)",
				 (datetime.now().astimezone().isoformat(timespec="seconds"), kind, note, len(lines),
				  json.dumps([line.strip() for line in lines], ensure_ascii=False)))


def cmd_status(args) -> int:
	conn = connect()
	F, D, cmp, lines = _state(conn)
	summary(lines)
	for line in lint(conn):
		print("!! " + line)
	if cmp["drift"] or cmp["conflict"]:
		print("\n파일 쪽 값을 DB 로 들이려면: python3 tools/gamedb.py pull")
	if cmp["pending"]:
		print("\n내리려면(사용자 승인 뒤에만): python3 tools/gamedb.py apply --approved")
	return 0


def cmd_check(args) -> int:
	conn = connect()
	F, D, cmp, lines = _state(conn)
	bad = lint(conn)
	if cmp["drift"] or cmp["conflict"]:
		summary(lines, ("drift", "conflict"))
		print("게임 데이터는 %s 에서 고친다. 이미 파일을 고쳤으면 `python3 tools/gamedb.py pull` 로 DB 에 들여라." % DB_REL)
	for line in bad:
		print("!! " + line)
	if cmp["pending"]:
		print("알림: 승인 대기 %d건 — DB 에만 있고 게임에는 아직 안 내려갔다 (`python3 tools/gamedb.py status`)" % len(lines["pending"]))
	if cmp["drift"] or cmp["conflict"] or bad:
		return 1
	print("게임 데이터 DB 일치" if not cmp["pending"] else "게임 파일은 마지막 승인 그대로다")
	return 0


def cmd_apply(args) -> int:
	conn = connect(write=args.approved)
	F, D, cmp, lines = _state(conn)
	bad = lint(conn)
	summary(lines)
	for line in bad:
		print("!! " + line)
	if bad:
		print("\nDB 의 값부터 바로잡아야 내릴 수 있다.")
		return 1
	blocked = cmp["drift"] + cmp["conflict"]
	if blocked and not args.force:
		print("\n게임 파일 쪽에 DB 가 모르는 변경이 있다. 먼저 `python3 tools/gamedb.py pull` 로 들이거나,"
			  "\nDB 값으로 덮으려면 --force 를 붙여라(파일 쪽 변경은 사라진다).")
		return 1
	changes = cmp["pending"] + (blocked if args.force else [])
	if not changes:
		return 0
	if not args.approved:
		print("\n아직 아무것도 안 썼다. 승인하면 바뀌는 파일:")
		for rel in _files_of(changes):
			print("  " + rel)
		print("사용자가 승인하면: python3 tools/gamedb.py apply --approved")
		return 2
	written = write_files(read_db(conn))
	going = lines["pending"] + (lines["drift"] + lines["conflict"] if args.force else [])
	conn.execute("BEGIN")
	save_baseline(conn, D)
	_record(conn, "apply", args.note, going)
	refresh_docs(conn)
	conn.execute("COMMIT")
	print("\n내렸다 (%d건). 바뀐 파일:" % len(going))
	for rel in written:
		print("  " + rel)
	return 0


def cmd_pull(args) -> int:
	conn = connect(write=True)
	F, D, cmp, lines = _state(conn)
	if cmp["conflict"] and not args.force:
		summary(lines, ("conflict",))
		print("\n어느 쪽이 맞는지 정해야 한다. 파일 값으로 덮으려면 `pull --force`, DB 값으로 덮으려면 `apply --approved --force`.")
		return 1
	take = cmp["drift"] + (cmp["conflict"] if args.force else [])
	coming = lines["drift"] + (report([(p, d, f) for p, f, d in cmp["conflict"]], D, F, "←") if args.force else [])
	merged = dict(D)
	for path, f, _ in take:
		if f is MISSING:
			merged.pop(path, None)
		else:
			merged[path] = f
	conn.execute("BEGIN")
	try:
		write_db(conn, unflatten(merged))
		save_baseline(conn, F)
		if take:
			_record(conn, "pull", args.note, coming)
		refresh_docs(conn)
		conn.execute("COMMIT")
	except BaseException:
		conn.execute("ROLLBACK")
		raise
	if take:
		print("DB 로 들였다 (%d건):" % len(coming))
		print("\n".join(coming))
	else:
		print("들일 것이 없다.")
	left = _state(conn)[3]["pending"]
	if left:
		print("승인 대기 %d건은 그대로 남아 있다." % len(left))
	return 0


def cmd_log(args) -> int:
	conn = connect()
	rows = conn.execute("SELECT id, at, kind, note, count, changes FROM _approvals ORDER BY id DESC LIMIT ?", (args.limit,)).fetchall()
	if not rows:
		print("기록이 없다.")
	for rid, at, kind, note, count, changes in rows:
		print("#%d  %s  %s %d건%s" % (rid, at, {"apply": "내림", "pull": "들임"}.get(kind, kind), count, "  — " + note if note else ""))
		for line in json.loads(changes)[:args.rows]:
			print("    " + line)
		if count > args.rows:
			print("    … 외 %d건" % (count - args.rows))
	return 0


def cmd_init(args) -> int:
	if os.path.exists(DB_PATH) and not args.force:
		raise DataError("%s 가 이미 있다. 통째로 다시 지으려면 --force (승인 대기 변경과 기록이 사라진다)" % DB_REL)
	doc = read_files()
	os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
	tmp = DB_PATH + ".new"
	if os.path.exists(tmp):
		os.remove(tmp)
	conn = sqlite3.connect(tmp, isolation_level=None)
	try:
		conn.executescript(SCHEMA)
		conn.execute("PRAGMA foreign_keys = ON")
		conn.execute("BEGIN")
		write_db(conn, doc)
		save_baseline(conn, flatten(doc))
		refresh_docs(conn)
		conn.execute("COMMIT")
		bad = lint(conn)
		back = flatten(read_db(conn))
		flat = flatten(doc)
		wrong = [p for p in set(back) | set(flat) if _canon(back.get(p, MISSING)) != _canon(flat.get(p, MISSING))]
		if bad or wrong:
			raise DataError("지은 DB 가 게임 파일과 다르다: %s" % (bad + [_path_text(p) for p in wrong[:5]]))
	except BaseException:
		conn.close()
		os.remove(tmp)
		raise
	conn.close()
	os.replace(tmp, DB_PATH)
	print("지었다: %s (%d바이트 · 값 %d개)" % (DB_REL, os.path.getsize(DB_PATH), len(flat)))
	return 0


def main() -> int:
	ap = argparse.ArgumentParser(description="게임 데이터 DB (%s) ↔ JSON · 게임 코드" % DB_REL)
	sub = ap.add_subparsers(dest="cmd", required=True)
	sub.add_parser("status", help="DB 와 게임 파일의 차이 (아무것도 안 쓴다)").set_defaults(fn=cmd_status)
	sub.add_parser("check", help="verify.sh 용 — 게임 파일이 DB 를 안 거치고 바뀌었으면 실패").set_defaults(fn=cmd_check)
	p = sub.add_parser("apply", help="DB 의 값을 JSON · 게임 코드로 내린다 (--approved 가 있어야 쓴다)")
	p.add_argument("--approved", action="store_true", help="사용자가 이 변경을 승인했다")
	p.add_argument("--force", action="store_true", help="파일 쪽 직접 수정 · 충돌도 DB 값으로 덮는다")
	p.add_argument("-m", "--note", default="", help="승인 기록에 남길 한 줄")
	p.set_defaults(fn=cmd_apply)
	p = sub.add_parser("pull", help="게임 파일을 직접 고친 값을 DB 로 들인다")
	p.add_argument("--force", action="store_true", help="충돌도 파일 값으로 덮는다")
	p.add_argument("-m", "--note", default="", help="기록에 남길 한 줄")
	p.set_defaults(fn=cmd_pull)
	p = sub.add_parser("log", help="내리고 들인 기록")
	p.add_argument("--limit", type=int, default=10)
	p.add_argument("--rows", type=int, default=8)
	p.set_defaults(fn=cmd_log)
	p = sub.add_parser("init", help="지금 게임 파일에서 DB 를 새로 짓는다")
	p.add_argument("--force", action="store_true")
	p.set_defaults(fn=cmd_init)
	args = ap.parse_args()
	try:
		return args.fn(args)
	except DataError as e:
		print("!! " + str(e))
		return 1
	except sqlite3.Error as e:
		print("!! DB 오류: %s" % e)
		return 1


if __name__ == "__main__":
	raise SystemExit(main())
