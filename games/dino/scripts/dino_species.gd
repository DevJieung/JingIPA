class_name DinoSpecies
extends RefCounted

## 공룡 50종. 그림은 tools/dino/gen_dinos.py 가 Krea 2 로 만들어 games/dino/dinos/ 에 넣는다.
## (그림이 없으면 dino_art.gd 의 손그림으로 자동 대체된다 — 게임은 그래도 돌아간다.)
##
## h    : 화면에서의 키(px). 1280x720 기준.
## art  : dino_art.gd 의 손그림 번호 (그림 파일이 없을 때 쓰는 대체용)
## col  : 찾았을 때 터지는 반짝이 색 (그림의 대표색)

const DIR := "res://games/dino/dinos/"
const MAX_W := 250.0  ## 너무 옆으로 긴 공룡은 이 폭에 맞춰 줄인다
## (피규어 그림은 실제 몸 비율이라 가로로 길다. 폭을 맞추면 목 긴 공룡만
##  제 키가 나오고 네발 공룡은 납작해져서, 실제 크기 느낌이 자연스럽게 산다)

static var LIST := [
	{"id": "trex", "ko": "티라노사우루스", "h": 168.0, "art": 3, "col": Color("6fbf5a")},
	{"id": "triceratops", "ko": "트리케라톱스", "h": 146.0, "art": 2, "col": Color("f08a3c")},
	{"id": "stegosaurus", "ko": "스테고사우루스", "h": 150.0, "art": 1, "col": Color("4fb3a8")},
	{"id": "brachiosaurus", "ko": "브라키오사우루스", "h": 178.0, "art": 0, "col": Color("8cc76a")},
	{"id": "diplodocus", "ko": "디플로도쿠스", "h": 152.0, "art": 0, "col": Color("6aa9e0")},
	{"id": "ankylosaurus", "ko": "안킬로사우루스", "h": 132.0, "art": 1, "col": Color("b08050")},
	{"id": "parasaurolophus", "ko": "파라사우롤로푸스", "h": 160.0, "art": 2, "col": Color("f292b4")},
	{"id": "spinosaurus", "ko": "스피노사우루스", "h": 170.0, "art": 3, "col": Color("a684d8")},
	{"id": "pteranodon", "ko": "프테라노돈", "h": 140.0, "art": 4, "col": Color("7cc7ef")},
	{"id": "pachycephalosaurus", "ko": "파키케팔로사우루스", "h": 150.0, "art": 2, "col": Color("f2c74a")},
	{"id": "velociraptor", "ko": "벨로키랍토르", "h": 134.0, "art": 3, "col": Color("d1704f")},
	{"id": "dilophosaurus", "ko": "딜로포사우루스", "h": 148.0, "art": 3, "col": Color("7fd8a8")},
	{"id": "oviraptor", "ko": "오비랍토르", "h": 130.0, "art": 4, "col": Color("eec98a")},
	{"id": "iguanodon", "ko": "이구아노돈", "h": 158.0, "art": 2, "col": Color("c2a077")},
	{"id": "carnotaurus", "ko": "카르노타우루스", "h": 162.0, "art": 3, "col": Color("c0553f")},
	{"id": "allosaurus", "ko": "알로사우루스", "h": 160.0, "art": 3, "col": Color("e8b845")},
	{"id": "giganotosaurus", "ko": "기가노토사우루스", "h": 172.0, "art": 3, "col": Color("d06a4a")},
	{"id": "maiasaura", "ko": "마이아사우라", "h": 156.0, "art": 2, "col": Color("cf9b6a")},
	{"id": "ceratosaurus", "ko": "케라토사우루스", "h": 158.0, "art": 3, "col": Color("8f6fd0")},
	{"id": "compsognathus", "ko": "콤프소그나투스", "h": 118.0, "art": 3, "col": Color("9ed36a")},
	{"id": "gallimimus", "ko": "갈리미무스", "h": 150.0, "art": 3, "col": Color("d9c07a")},
	{"id": "deinonychus", "ko": "데이노니쿠스", "h": 138.0, "art": 3, "col": Color("e08a4a")},
	{"id": "utahraptor", "ko": "유타랍토르", "h": 150.0, "art": 3, "col": Color("b5563f")},
	{"id": "microraptor", "ko": "미크로랍토르", "h": 122.0, "art": 4, "col": Color("5f7fd0")},
	{"id": "archaeopteryx", "ko": "시조새", "h": 124.0, "art": 4, "col": Color("e0b45f")},
	{"id": "quetzalcoatlus", "ko": "케찰코아틀루스", "h": 168.0, "art": 4, "col": Color("a0d0e8")},
	{"id": "rhamphorhynchus", "ko": "람포링쿠스", "h": 126.0, "art": 4, "col": Color("d9a05f")},
	{"id": "dimorphodon", "ko": "디모르포돈", "h": 130.0, "art": 4, "col": Color("e07a9a")},
	{"id": "mosasaurus", "ko": "모사사우루스", "h": 120.0, "art": 0, "col": Color("4a8fc0")},
	{"id": "plesiosaurus", "ko": "플레시오사우루스", "h": 132.0, "art": 0, "col": Color("5fb0c8")},
	{"id": "elasmosaurus", "ko": "엘라스모사우루스", "h": 140.0, "art": 0, "col": Color("6fc8b0")},
	{"id": "ichthyosaurus", "ko": "이크티오사우루스", "h": 116.0, "art": 0, "col": Color("7a9fd8")},
	{"id": "dimetrodon", "ko": "디메트로돈", "h": 132.0, "art": 1, "col": Color("c85f7a")},
	{"id": "apatosaurus", "ko": "아파토사우루스", "h": 172.0, "art": 0, "col": Color("7fa8d8")},
	{"id": "camarasaurus", "ko": "카마라사우루스", "h": 166.0, "art": 0, "col": Color("8fb86a")},
	{"id": "mamenchisaurus", "ko": "마멘키사우루스", "h": 182.0, "art": 0, "col": Color("a8c86a")},
	{"id": "argentinosaurus", "ko": "아르젠티노사우루스", "h": 184.0, "art": 0, "col": Color("9a8fc8")},
	{"id": "brontosaurus", "ko": "브론토사우루스", "h": 176.0, "art": 0, "col": Color("6fc0a8")},
	{"id": "kentrosaurus", "ko": "켄트로사우루스", "h": 142.0, "art": 1, "col": Color("c8a05f")},
	{"id": "nodosaurus", "ko": "노도사우루스", "h": 126.0, "art": 1, "col": Color("9a8f7a")},
	{"id": "protoceratops", "ko": "프로토케라톱스", "h": 128.0, "art": 2, "col": Color("d8b08f")},
	{"id": "styracosaurus", "ko": "스티라코사우루스", "h": 150.0, "art": 2, "col": Color("e07a5f")},
	{"id": "pachyrhinosaurus", "ko": "파키리노사우루스", "h": 148.0, "art": 2, "col": Color("c88f5f")},
	{"id": "torosaurus", "ko": "토로사우루스", "h": 152.0, "art": 2, "col": Color("d09a4a")},
	{"id": "corythosaurus", "ko": "코리토사우루스", "h": 160.0, "art": 2, "col": Color("6fa8d8")},
	{"id": "lambeosaurus", "ko": "람베오사우루스", "h": 158.0, "art": 2, "col": Color("d86f9a")},
	{"id": "edmontosaurus", "ko": "에드몬토사우루스", "h": 162.0, "art": 2, "col": Color("8fb8a0")},
	{"id": "therizinosaurus", "ko": "테리지노사우루스", "h": 168.0, "art": 3, "col": Color("b09ad8")},
	{"id": "ornithomimus", "ko": "오르니토미무스", "h": 148.0, "art": 3, "col": Color("c8b88f")},
	{"id": "troodon", "ko": "트로오돈", "h": 134.0, "art": 3, "col": Color("8fc87a")},
]

static var _tex_cache: Dictionary = {}


static func count() -> int:
	return LIST.size()


static func data(i: int) -> Dictionary:
	return LIST[i % LIST.size()]


static func id_of(i: int) -> String:
	return String(data(i)["id"])


## 종 id -> 인덱스. 없으면 0.
static func index_of(id: String) -> int:
	for i in LIST.size():
		if String(LIST[i]["id"]) == id:
			return i
	return 0


## 그림 면적이 작은 순으로 정렬한 인덱스 (난이도 축 D4: 작은 종이 찾기 어렵다).
## 그림이 아직 없으면 키(h)로 대신 정렬한다.
static func by_size_asc() -> Array[int]:
	if not _size_order.is_empty():
		return _size_order
	var pairs: Array = []
	for i in LIST.size():
		var r := draw_rect_for(i)
		var area := r.size.x * r.size.y
		if area <= 0.0:
			area = float(LIST[i]["h"]) * float(LIST[i]["h"]) * 0.9
		pairs.append([i, area])
	pairs.sort_custom(func(a, b): return a[1] < b[1])
	_size_order = []
	for p in pairs:
		_size_order.append(int(p[0]))
	return _size_order


static var _size_order: Array[int] = []


## 헷갈리는 종끼리 짝지은 표 (난이도 축 D6: 미끼).
## 같은 화풍 + 색이 비슷 + 키가 비슷한 쌍만 고른다.
## ★ 이건 "볼 것이 는다"가 아니라 "고를 것이 는다" 축이다 —
##   아이가 튕겨내지 않는 결의 어려움이고, 규칙이 안 바뀌므로 전환 비용이 0이다.
static func look_alikes(i: int) -> Array[int]:
	if _alike_cache.has(i):
		return _alike_cache[i]
	var a := data(i)
	var out: Array[int] = []
	for j in LIST.size():
		if j == i:
			continue
		var b := data(j)
		if int(b["art"]) != int(a["art"]):
			continue
		if absf(float(b["h"]) - float(a["h"])) > 16.0:
			continue
		var ca: Color = a["col"]
		var cb: Color = b["col"]
		var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
		if d < 0.60:
			out.append(j)
	_alike_cache[i] = out
	return out


static var _alike_cache: Dictionary = {}


static func full_name(i: int) -> String:
	return String(data(i)["ko"])


static func texture(i: int) -> Texture2D:
	var id := String(data(i)["id"])
	if _tex_cache.has(id):
		return _tex_cache[id]
	var path := DIR + id + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[id] = tex
	return tex


## 그림을 그릴 네모 (발이 원점, 가운데 정렬). 그림이 없으면 빈 Rect2.
static func draw_rect_for(i: int) -> Rect2:
	var tex := texture(i)
	if tex == null:
		return Rect2()
	var h: float = data(i)["h"]
	var ts := Vector2(tex.get_width(), tex.get_height())
	if ts.y <= 0.0:
		return Rect2()
	var w := h * ts.x / ts.y
	if w > MAX_W:
		h *= MAX_W / w
		w = MAX_W
	return Rect2(-w * 0.5, -h, w, h)


## 아직 그림이 하나도 없으면 true (손그림으로 도는 중)
static func art_missing() -> bool:
	for i in LIST.size():
		if texture(i) != null:
			return false
	return true


# --------------------------------------------------------------------------- #
# 이 종의 그림이 **바라보는 쪽**
# --------------------------------------------------------------------------- #

## 1 = 오른쪽 · -1 = 왼쪽 · 0 = 정면 (뒤집어도 아무 말도 안 되므로 안 뒤집는다).
##
## ★ 규칙 26 이 "뒤집기를 다시 넣고 싶으면 먼저 50종의 방향 표부터 만들어라"고 한 그 표다.
##   50장을 하나씩 눈으로 보고 적었다 (tools/dino/face_table.py --sheet 가 대조표를 만든다).
##   지금은 49종이 오른쪽이고, 딤오포돈만 **정면**을 본다 — 날개를 펴고 카메라를 본다.
## ★ 이 표가 있어야 참참참이 "친구가 뛴 쪽으로 고개를 돌리는" 것을 **거짓말 없이** 할 수 있다.
##   표 없이 그냥 뒤집으면, 원래 왼쪽을 보던 종에서는 아이에게 반대를 말하게 된다.
## ★ 이 표는 **뛴 뒤에만** 쓴다. 뛰기 전(wait)에 고개를 돌리면 답을 미리 알려 주는 것이고,
##   그러면 난이도 축이 통째로 무너진다 (tests/cham_check.gd 가 강제한다).
const FACE := {
	"trex": 1,
	"triceratops": 1,
	"stegosaurus": 1,
	"brachiosaurus": 1,
	"diplodocus": 1,
	"ankylosaurus": 1,
	"parasaurolophus": 1,
	"spinosaurus": 1,
	"pteranodon": 1,
	"pachycephalosaurus": 1,
	"velociraptor": 1,
	"dilophosaurus": 1,
	"oviraptor": 1,
	"iguanodon": 1,
	"carnotaurus": 1,
	"allosaurus": 1,
	"giganotosaurus": 1,
	"maiasaura": 1,
	"ceratosaurus": 1,
	"compsognathus": 1,
	"gallimimus": 1,
	"deinonychus": 1,
	"utahraptor": 1,
	"microraptor": 1,
	"archaeopteryx": 1,
	"quetzalcoatlus": 1,
	"rhamphorhynchus": 1,
	"dimorphodon": 0,
	"mosasaurus": 1,
	"plesiosaurus": 1,
	"elasmosaurus": 1,
	"ichthyosaurus": 1,
	"dimetrodon": 1,
	"apatosaurus": 1,
	"camarasaurus": 1,
	"mamenchisaurus": 1,
	"argentinosaurus": 1,
	"brontosaurus": 1,
	"kentrosaurus": 1,
	"nodosaurus": 1,
	"protoceratops": 1,
	"styracosaurus": 1,
	"pachyrhinosaurus": 1,
	"torosaurus": 1,
	"corythosaurus": 1,
	"lambeosaurus": 1,
	"edmontosaurus": 1,
	"therizinosaurus": 1,
	"ornithomimus": 1,
	"troodon": 1,
}

## 그림의 지문 (sha256 앞 12자리). **방향 표가 낡았는지 잡는 유일한 장치다.**
##
## ★ 공룡을 다시 뽑으면 방향이 바뀔 수 있는데 화면 없는 이 머신에서는 아무도 못 본다.
##   그러면 참참참이 아이에게 반대 방향을 말한다 — 규칙 26 이 막으려던 바로 그 일이다.
##   지문이 다르면 tests/cham_check.gd 가 실패시킨다: 눈으로 다시 보고 FACE 를 고친 뒤
##   `python3 tools/dino/face_table.py --sha` 로 지문을 갱신하라는 뜻이다.
const ART_SHA := {
	"trex": "1a1b5c41fd45",
	"triceratops": "313b6256b28d",
	"stegosaurus": "562cab054226",
	"brachiosaurus": "861fb713b59a",
	"diplodocus": "a0d9430e7b89",
	"ankylosaurus": "62ba78e5b5e9",
	"parasaurolophus": "6dc3160f9f60",
	"spinosaurus": "f2ee3d96f2fb",
	"pteranodon": "a3b6b3404ad4",
	"pachycephalosaurus": "721763bf3625",
	"velociraptor": "eb3a84d73faa",
	"dilophosaurus": "c4e5d0ff5751",
	"oviraptor": "1332c9cd5dfd",
	"iguanodon": "86463d5eca80",
	"carnotaurus": "8d40e18e3a2e",
	"allosaurus": "3fe11970dd48",
	"giganotosaurus": "da8e2dc3190c",
	"maiasaura": "68de2744a77a",
	"ceratosaurus": "181709eee529",
	"compsognathus": "bc64a2d5f9e5",
	"gallimimus": "a82eda384b27",
	"deinonychus": "a9dbaddafe29",
	"utahraptor": "fa74a3572479",
	"microraptor": "8f6b22df66f8",
	"archaeopteryx": "f33dd4b30c0a",
	"quetzalcoatlus": "457f2a7bef2a",
	"rhamphorhynchus": "8f4f27513e6d",
	"dimorphodon": "e89eca72b2cc",
	"mosasaurus": "89fc870b36c1",
	"plesiosaurus": "cc636c2d45fd",
	"elasmosaurus": "84525a28ef3d",
	"ichthyosaurus": "7e55785d2b8c",
	"dimetrodon": "88ab56b441d1",
	"apatosaurus": "0f8096b55d82",
	"camarasaurus": "87e2b74857fc",
	"mamenchisaurus": "f04f55904543",
	"argentinosaurus": "eb81ea45574d",
	"brontosaurus": "51605a11eab8",
	"kentrosaurus": "d776bc1eacc7",
	"nodosaurus": "e9301b4440ba",
	"protoceratops": "a1e531e4d250",
	"styracosaurus": "74b9ad32baa5",
	"pachyrhinosaurus": "dbd552bbaba6",
	"torosaurus": "32d5a5461762",
	"corythosaurus": "b871f91a8eb3",
	"lambeosaurus": "4128c6b9ee46",
	"edmontosaurus": "f54ed880a91d",
	"therizinosaurus": "a95f7e827d7a",
	"ornithomimus": "6aa18a6f233d",
	"troodon": "7ee49f8aba46",
}


## 이 종이 바라보는 쪽 (1 오른쪽 · -1 왼쪽 · 0 정면). 표에 없으면 0 — **안 뒤집는다.**
## ★ 모르면 "오른쪽"으로 넘겨짚지 않는다. 모르는 채로 뒤집는 것이 이 표가 막으려는 일이다.
static func face_of(i: int) -> int:
	return int(FACE.get(String(data(i)["id"]), 0))
