class_name NoodPieces
extends RefCounted

## 블록 채우기의 조각 세트.
##
## 원래 Kanoodle 은 12조각이지만 아이용으로 **9종**으로 줄였다. 고른 기준:
##   - 눈으로 서로 구분된다 (같은 칸 수라도 모양이 확 다르다)
##   - 2~5칸. 1칸짜리는 넣지 않는다 — 그건 퍼즐이 아니라 메꾸기가 된다
##   - 대칭이 많다 → 뒤집기(반전)가 필요 없다. 회전 버튼 하나로 끝난다
##
## 좌표는 (x, y), 원점은 조각의 좌상단. 회전은 코드로 만든다(표에 안 적는다).

## 조각 하나 = {"id", "cells", "col"}
const LIST := [
	{"id": "i2", "cells": [Vector2i(0, 0), Vector2i(1, 0)], "col": Color("f0988b")},
	{"id": "i3", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "col": Color("e0ca70")},
	{"id": "l3", "cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)], "col": Color("ace070")},
	{"id": "o4", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], "col": Color("58d168")},
	{"id": "i4", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], "col": Color("58d1b9")},
	{"id": "l4", "cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)], "col": Color("5899d1")},
	{"id": "t4", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], "col": Color("6858d1")},
	{"id": "s4", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], "col": Color("b958d1")},
	{"id": "p5", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)], "col": Color("b83e7f")},
]

## 쉬운 판에 먼저 쓰는 조각들 (칸 수가 적고 모양이 단순한 순).
const EASY_ORDER := ["o4", "i2", "i3", "l3", "i4", "t4", "l4", "s4", "p5"]

static var _rot_cache: Dictionary = {}


static func count() -> int:
	return LIST.size()


static func index_of(id: String) -> int:
	for i in LIST.size():
		if String(LIST[i]["id"]) == id:
			return i
	return 0


static func color_of(pi: int) -> Color:
	return LIST[pi % LIST.size()]["col"]


static func size_of(pi: int) -> int:
	return (LIST[pi % LIST.size()]["cells"] as Array).size()


## 이 조각의 서로 다른 회전 모양들. 정사각 대칭인 조각은 개수가 줄어든다.
## 반환: Array[Array[Vector2i]] — 각각 좌상단이 (0,0) 으로 정규화돼 있다.
static func rotations(pi: int) -> Array:
	if _rot_cache.has(pi):
		return _rot_cache[pi]
	var base: Array = LIST[pi % LIST.size()]["cells"]
	var seen := {}
	var out: Array = []
	var cur: Array = base.duplicate()
	for r in 4:
		var norm := normalize(cur)
		var key := key(norm)
		if not seen.has(key):
			seen[key] = true
			out.append(norm)
		cur = rotate_cw(cur)
	_rot_cache[pi] = out
	return out


static func rotate_cw(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append(Vector2i(-(c as Vector2i).y, (c as Vector2i).x))
	return out


static func normalize(cells: Array) -> Array:
	var mx := 9999
	var my := 9999
	for c in cells:
		mx = mini(mx, (c as Vector2i).x)
		my = mini(my, (c as Vector2i).y)
	var out: Array = []
	for c in cells:
		out.append(Vector2i((c as Vector2i).x - mx, (c as Vector2i).y - my))
	out.sort_custom(func(a, b):
		var av: Vector2i = a
		var bv: Vector2i = b
		return av.y < bv.y if av.y != bv.y else av.x < bv.x)
	return out


static func key(cells: Array) -> String:
	var parts := PackedStringArray()
	for c in cells:
		parts.append("%d,%d" % [(c as Vector2i).x, (c as Vector2i).y])
	return "|".join(parts)


## 조각이 차지하는 폭·높이 (칸 단위).
static func extent(cells: Array) -> Vector2i:
	var w := 0
	var h := 0
	for c in cells:
		w = maxi(w, (c as Vector2i).x + 1)
		h = maxi(h, (c as Vector2i).y + 1)
	return Vector2i(w, h)
