## 화면을 PNG 로 찍어 두는 개발용 도구 (빌드에 포함되지 않는다 — tests/* 는 익스포트 제외).
##
## 이 머신은 화면이 없어서 눈으로 확인할 방법이 웹 빌드뿐이었다.
## 가상 프레임버퍼(Xvfb) 위에서 이 씬을 돌리면 화면을 그대로 파일로 받을 수 있다.
##   python3 tools/screenshot.py hub:0 map:0 battle:2
extends Node

var _out := "user://shots"
var _shots: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--out="):
			_out = a.substr(6)
		else:
			_shots.append(a)
	if _shots.is_empty():
		_shots = ["map:0"]
	DirAccess.make_dir_recursive_absolute(_out)
	# ★ 촬영이 아이 기록을 덮지 않게 한다. 아래에서 stars 를 잠깐 조작한다.
	Shell.save_disabled = true
	# 진행도를 잠깐 조작하므로(잠긴 탄만 있으면 지도가 밋밋하다) 원래 값을 되돌려 둔다.
	# MathGame 은 창이 닫힐 때 저장하므로, 안 되돌리면 개발자의 저장 파일이 덮어써진다.
	var saved := MathGame.stars.duplicate()
	await _run()
	MathGame.stars = saved
	get_tree().quit()


func _run() -> void:
	for spec in _shots:
		var parts := String(spec).split(":")
		var kind := parts[0]
		var arg := int(parts[1]) if parts.size() > 1 else 0
		var scene := ""
		match kind:
			"kanoodle", "kanoodlehint":
				scene = "res://games/kanoodle/kanoodle.tscn"
				# arg 를 탄으로 쓴다 — 쉬운 판만 찍으면 "아직 차례가 아닌 조각"이
				# 옅게 나오는 모습이나 큰 격자를 눈으로 확인할 수가 없다.
				Shell.profile()["kanoodle"] = {
					"best_stage": maxi(1, arg), "skill": 0, "cleared": 0,
				}
			"torch":
				scene = "res://games/torch/torch.tscn"
				# arg 를 탄으로 쓴다 — 1탄만 찍으면 좁아진 빛도 짙어진 어둠도 못 본다.
				Shell.profile()["torch"] = {
					"best_stage": maxi(1, arg), "lifetime_found": 0,
					"skill": 0, "ease_streak": 0, "cushion": 0,
				}
			"rps", "rpsmeet", "rpsclear":
				scene = "res://games/rps/rps.tscn"
				# arg 를 탄으로 쓴다 — 1탄만 찍으면 옅어진 관계 고리도 "져라"도 못 본다.
				Shell.profile()["rps"] = {
					"best_stage": maxi(1, arg), "hits": 0,
					"skill": 0, "ease_streak": 0, "cushion": 0,
				}
			"cham", "chamcatch", "chamhint":
				scene = "res://games/cham/cham.tscn"
				Shell.profile()["cham"] = {
					"best_stage": maxi(1, arg), "caught": 0,
					"skill": 0, "ease_streak": 0, "cushion": 0,
				}
			"tiers", "map":
				scene = Router.TIERS
				MathGame.stars = {"0": 3, "1": 2, "2": 1, "3": 3, "4": 1}
			"hub":
				scene = Router.HUB
				# 허브가 텅 비면 배치를 못 본다 — 도감을 조금 채워서 찍는다.
				Shell.dex = {}
				for i in mini(14, DinoSpecies.count()):
					Shell.dex[DinoSpecies.id_of(i)] = {
						"first_by": "p_1", "first_at": 0,
						"count": Shell.FAMILY_MEETS if i < 9 else 1,
					}
				MathGame.stars = {"0": 3, "1": 2, "2": 1}
			"rest":
				# 「많이 놀았다」— 상한에 닿아 쉬러 가는 순간. Router 의 캡션은
				# 화면이 덮인 동안만 떠서 다른 방법으로는 눈으로 볼 수가 없다.
				scene = Router.HUB
			"title":
				scene = Router.TITLE
			"battle":
				scene = "res://games/math/game/battle.tscn"
				Router.pending_tier = arg
				Router.pending_endless = false
			_:
				continue
		var packed: PackedScene = load(scene)
		var inst := packed.instantiate()
		add_child(inst)
		# ★ 이 씬의 부모는 Control 이 아니라 그냥 Node 라, 앵커만으로는 크기가 안 잡힌다.
		#   크기가 0 이면 화면이 통째로 비어서 "게임이 안 그려진다"로 오해하게 된다.
		if inst is Control:
			(inst as Control).size = get_viewport().get_visible_rect().size
		if inst.has_method("_layout"):
			inst.call("_layout")
		# ★ 손전등 찾기는 방을 밝게 한 번 보여 준 뒤에야 해가 진다. 그냥 찍으면
		#   밝은 방만 나온다 — 연출을 건너뛰고 공룡 하나를 비춘 채로 찍는다.
		if kind == "torch":
			await get_tree().process_frame
			inst.call("skip_intro")
			var ds: Array = inst.get("dinos")
			# torch:0 = 아직 아무것도 안 누른 화면 (불 꺼짐 + 안내 동그라미)
			if arg > 0 and not ds.is_empty():
				# 한 마리는 찾아 둔다 — 찾은 공룡이 어둠 위에서 빛나는지 눈으로 보려고.
				var c0: Vector2 = (ds[0].call("hit_rect") as Rect2).get_center()
				inst.call("_tap", c0)
				inst.call("_tap", c0)
				(inst.get("hud") as Object).call("hide_card")
				var last: Object = ds[ds.size() - 1]
				(inst.get("beam") as Object).call("aim",
						(last.call("hit_rect") as Rect2).get_center()
						+ Vector2(0, 40) if ds.size() > 1 else c0)
		# ★ 참참참은 **발자국이 있는 모습**이 알맹이라, 몇 번 뛴 뒤로 맞춰 놓고 찍는다.
		if kind == "cham" or kind == "chamcatch" or kind == "chamhint":
			await get_tree().process_frame
			var pat: Array = inst.get("_pat")
			var hist: Array[int] = []
			for i in mini(4, pat.size() + 1):
				hist.append(int(pat[i % pat.size()]))
			inst.set("_hist", hist)
			inst.set("_turn", hist.size())
			inst.set("_state", "wait")
		# ★ 다섯 번 놓치면 맞는 쪽 손이 숨을 쉰다 — 이 게임에서 난이도를 내리는
		#   유일한 통로다(규칙 11). 손을 그림으로 바꾼 뒤로는 살빛으로 말할 수가 없어서
		#   금빛 무리로 바뀌었고, **그게 정말 보이는지**는 눈으로만 알 수 있다.
		if kind == "chamhint":
			inst.set("_miss_streak", 5)
			inst.set("_state", "wait")
		# ★ 참참참은 **잡은 순간**이 상 주는 장면이다 — 친구가 손 위에 앉는다.
		#   손을 그림으로 바꾼 뒤로는 "제대로 손 위에 앉는가"를 눈으로 봐야 한다
		#   (예전에 축하 상자가 친구 손을 반으로 자른 적이 있다).
		if kind == "chamcatch":
			for step in 300:
				if String(inst.get("_state")) == "catch":
					break
				if String(inst.get("_state")) == "wait":
					var z: Rect2 = inst.call("hand_zone", int(inst.call("next_dir")))
					inst.call("_on_tap", z.position + z.size * 0.5)
				inst.call("_process", 0.05)
			inst.set("_slow", 400.0)
		# ★ 가위바위보의 알맹이는 **두 손이 만난 순간**이다 (별이 어느 쪽에 붙는가).
		#   그냥 찍으면 손이 하나뿐인 대기 화면만 나온다.
		# ★ 판을 깬 화면은 **상 주는 순간**이라 눈으로 꼭 봐야 한다. 예전에 축하 상자가
		#   친구 손을 반으로 자르고 두리가 공룡 등에 올라탄 적이 있다.
		if kind == "rpsclear":
			await get_tree().process_frame
			for step in 200:
				if String(inst.get("_state")) == "clear":
					break
				if String(inst.get("_state")) == "wait":
					var w2: int = RpsGen.answer(int(inst.call("friend_hand")),
							int(inst.call("goal_now")))
					var c2: Rect2 = inst.call("card_rect", int(inst.call("card_index", w2)))
					inst.call("_on_tap", c2.position + c2.size * 0.5)
				inst.call("_process", 0.05)
			inst.set("_slow", 400.0)
		if kind == "rpsmeet":
			await get_tree().process_frame
			# ★ 들어오는 연출("enter")이 끝나기 전에는 탭이 안 먹는다. 프레임만 기다리면
			#   실시간이라 안 끝나므로 _process 를 직접 돌려 대기 상태로 만든다.
			for i in 20:
				if String(inst.get("_state")) == "wait":
					break
				inst.call("_process", 0.2)
			# 일부러 **틀린** 손을 낸다 — 틀렸을 때 왜 그런지 보여 주는 화면이 알맹이다.
			var want: int = RpsGen.answer(int(inst.call("friend_hand")),
					int(inst.call("goal_now")))
			for h in (inst.call("cards_now") as Array):
				if int(h) != want:
					var ci := int(inst.call("card_index", int(h)))
					var cr: Rect2 = inst.call("card_rect", ci)
					inst.call("_on_tap", cr.position + cr.size * 0.5)
					break
			# 손이 만날 때까지, 그리고 "왜 그런지"가 다 그려질 때까지 손으로 돌린다
			for i in 40:
				if String(inst.get("_state")) == "no":
					break
				inst.call("_process", 0.02)
			for i in 12:
				inst.call("_process", 0.05)
			# ★ 이 뒤로 엔진이 40프레임을 더 돌린다. 그동안 연출이 지나가 버리면
			#   찍히는 것은 다시 대기 화면이다 — 그래서 시간을 거의 세워 둔다.
			inst.set("_slow", 400.0)
		# ★ 힌트는 오래 막혀 있어야 뜨는 것이라 그냥 찍으면 절대 안 나온다.
		#   갇힌 판에서는 이게 **유일한 탈출 안내**라 눈으로 확인할 길이 있어야 한다.
		if kind == "kanoodlehint":
			await get_tree().process_frame
			inst.call("_show_hint")
		# ★ 쉬러 가는 화면은 **덮인 채로** 떠야 제 모습이다 (허브가 비쳐 보이면 안 된다).
		if kind == "rest":
			await get_tree().process_frame
			(Router.get("_fade") as ColorRect).visible = true
			(Router.get("_fade") as ColorRect).color.a = 1.0
			Router.call("_show_caption", Router.REST_LINE, true)
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s_%d.png" % [_out, kind, arg]
		img.save_png(path)
		print("찍음: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
		inst.queue_free()
		await get_tree().process_frame
