## 손전등 찾기 — 방이 **비춰서 찾을 수 있는 방**인지 무더기로 검사한다.
##
## ★ 이 게임의 난이도는 어둠 x 가림 x 좁은 빛의 **곱**이다. 셋 다 따로 보면 온건한데
##   합치면 "아이가 방을 통째로 훑어도 못 찾는 방"이 된다. 그래서 TorchGen.hardness()
##   한 숫자로 재고 여기서 상한을 강제한다.
##
## ★ 그리고 **규칙 자체**를 검사한다: 어두운 데의 공룡은 눌러도 안 찾아지고,
##   비춘 다음에 누르면 찾아진다. 이게 뒤집히면 게임이 그냥 어두운 공룡 찾기가 된다 —
##   화면을 눈으로 봐서는 절대 안 잡히는 종류의 회귀다.
##
##   ~/.local/bin/godot --headless --path . res://tests/torch_check.tscn
##   ~/.local/bin/godot --headless --path . res://tests/torch_check.tscn -- --pre
extends Node

const ROUNDS := 24      ## 유효탄마다 몇 방씩
const STAGES := [1, 3, 5, 8, 12, 16, 20, 25, 30, 40, 60, 100, 200]
## 진짜 씬을 띄워 끝까지 놀아 볼 탄 (축이 하나씩 새로 켜지는 지점들)
const PLAY_STAGES := [1, 2, 7, 11, 15, 21, 40]

## 방 하나를 훑는 데 드는 탭 수의 상한. 이걸 넘으면 난이도가 아니라 노동이다.
const SWEEP_MAX := 26.0


func _ready() -> void:
	Shell.save_disabled = true
	Engine.max_fps = 0
	# 소리는 검사 대상이 아니고, 재생 중인 소리가 남으면 종료할 때 누수 경고가 뜬다.
	Shell.sfx_enabled = false
	if "--pre" in OS.get_cmdline_user_args():
		Shell.profile()["age_band"] = "pre"
		Shell.profile()["tuning"] = Shell.default_tuning("pre")
	var t := Shell.tuning()
	print("   프로필: %s" % String(Shell.profile()["age_band"]))

	var bad_axes := 0
	var short_rooms := 0
	var bad_cov := 0
	var rooms_n := 0
	var rng := RandomNumberGenerator.new()
	print("   %5s %5s %5s %6s %6s %8s %7s %8s %9s"
			% ["E", "공룡", "가구", "반경", "어둠", "가림밴드", "곱", "훑기탭", "실제가림"])
	for ei in STAGES:
		var e := int(ei)
		var ax := TorchGen.axes(e, t)
		var band: Vector2i = ax["band"]
		var beam := float(ax["beam"])
		var dark := float(ax["dark"])
		var hard := TorchGen.hardness(ax)
		var sweep := 1280.0 * 720.0 / (PI * beam * beam) * 1.7
		# --- 축 자체의 안전 한계 (아이가 못 찾는 방이 나올 수 있는 조합) ---
		var ax_ok := beam >= TorchGen.BEAM_ABS_MIN and dark <= TorchGen.DARK_CEIL \
				and hard <= TorchGen.HARD_CEIL and sweep <= SWEEP_MAX
		if not ax_ok:
			bad_axes += 1
			print("!! E=%d 축이 한계를 넘었다: 반경 %.0f 어둠 %.2f 곱 %.2f 훑기 %.1f탭"
					% [e, beam, dark, hard, sweep])
		# --- 실제로 방을 만들어 본다 ---
		var cov_sum := 0
		var cov_n := 0
		var cov_hi := 0
		var pair_in_beam := 0
		var us := 0
		for r in ROUNDS:
			rng.seed = hash("t_%d_%d" % [e, r])
			var t0 := Time.get_ticks_usec()
			var room := TorchGen.stage_room(e, rng, e, t)
			us += Time.get_ticks_usec() - t0
			rooms_n += 1
			var need := int(room["count"])
			if need < int(room.get("want", need)):
				short_rooms += 1
			var pts: Array = []
			for sp in (room["spots"] as Array).slice(0, need):
				var st: Dictionary = Rooms.spot_transform(room["front"], sp)
				var cov := Rooms.coverage(st["pos"], room["front"])
				if cov < Rooms.COV_HARD_LO or cov > Rooms.COV_HARD_HI:
					bad_cov += 1
					if bad_cov <= 3:
						print("!! E=%d 가림 %d%% (한계 %d~%d)"
								% [e, cov, Rooms.COV_HARD_LO, Rooms.COV_HARD_HI])
				cov_sum += cov
				cov_n += 1
				cov_hi = maxi(cov_hi, cov)
				for q in pts:
					if (q as Vector2).distance_to(st["pos"]) < beam * 0.9:
						pair_in_beam += 1
				pts.append(st["pos"])
		print("   %5d %5d %5d %6.0f %6.2f %8s %7.2f %8.1f   평균 %.0f%% 최대 %d%% (한 빛에 둘 %d쌍, %.1fms)"
				% [e, int(ax["dinos"]), int(ax["props"]), beam, dark,
				   "%d~%d" % [band.x, band.y], hard, sweep,
				   float(cov_sum) / float(maxi(1, cov_n)), cov_hi, pair_in_beam,
				   float(us) / float(ROUNDS) / 1000.0])

	var play_bad := await _play_stages()

	var short_pct := 100.0 * float(short_rooms) / float(maxi(1, rooms_n))
	var ok := bad_axes == 0 and bad_cov == 0 and short_pct <= 1.0 and play_bad == 0
	print("%s 방 %d개: 축한계이탈 %d건, 가림한계이탈 %d건, 마릿수부족 %d건(%.1f%%), 플레이실패 %d건"
			% ["  " if ok else "!!", rooms_n, bad_axes, bad_cov, short_rooms, short_pct, play_bad])
	print("   판정: %s" % ("정상" if ok else "이상 — 위 !! 줄을 보세요"))
	get_tree().quit(0 if ok else 1)


## 진짜 씬을 띄워서 **규칙 그대로** 놀아 본다.
##
## 여기서 보는 것 넷:
##   1. 어두운 데의 공룡은 눌러도 안 찾아진다        <- 이 게임의 정체성
##   2. 비춘 다음에 누르면 찾아진다                  <- 막히지 않는다
##   3. 방이 끝까지 깨진다
##   4. 처음 두 방은 안내 동그라미가 공룡 위에 있다   <- 첫 60초 안에 성공 (편입 규칙 5)
##   5. **힌트가 실제로 뜬다**  <- 안전망이 살아 있는가
##
## ★ 5번이 제일 미묘하다. 이 게임은 탭마다 idle 을 리셋하므로(훑는 아이에게 힌트가
##   터지면 안 되니까) "가만히 있으면 힌트"라는 조건 하나만으로는 두드리는 동안
##   힌트가 **영영 안 뜬다.** 그러면 힌트 횟수를 신호로 쓰는 적응형이 "힌트 0회"를
##   "잘했다"로 오독해서 헤매는 아이의 난이도까지 올린다. 실제로 그렇게 짜여 있었다.
func _play_stages() -> int:
	var bad := 0
	print("   %5s %7s %9s %9s %7s %7s %8s"
			% ["탄", "공룡", "어둠속탭", "비추고탭", "첫안내", "힌트", "결과"])
	for si in PLAY_STAGES:
		var st := int(si)
		# ★ 탄과 연출 배속을 **_ready 가 돌기 전에** 정해 둔다. add_child 한 뒤에 고쳐서
		#   방을 다시 만들면, 첫 번째 방의 해질녘 연출이 1초짜리 타이머를 붙든 채로
		#   남아서 검사가 끝날 때까지 살아 있다 (종료할 때 누수 경고로 나온다).
		Shell.profile()["torch"] = {
			"best_stage": st, "lifetime_found": 0,
			"skill": 0, "ease_streak": 0, "cushion": 0,
		}
		var g: Node = load("res://games/torch/torch.tscn").instantiate()
		g.set("dev_mode", true)
		g.set("_slow", 0.02)
		add_child(g)
		await get_tree().process_frame
		g.call("skip_intro")
		var beam: Object = g.get("beam")
		var dinos: Array = g.get("dinos")

		# 4. 안내 동그라미 — 1~2탄은 반드시 공룡 위에 있어야 한다
		var guide := "-"
		if st <= 2:
			var on_dino := false
			for d in dinos:
				if (d.call("hit_rect") as Rect2).has_point(beam.get("suggest")):
					on_dino = true
					break
			guide = "공룡위" if on_dino else "빗나감"
			if not on_dino:
				print("!! %d탄: 첫 안내가 공룡 위가 아니다 (%s)" % [st, str(beam.get("suggest"))])

		# 5. 헛되이 비추기만 하면 힌트가 뜨는가.
		#    (a) 공룡에서 가장 먼 자리를 비추면 "헛걸음"이 세어지는가
		#    (b) 헛걸음이 한계에 닿으면 힌트가 뜨는가
		var es := _empty_spot(dinos)
		var hint := "-"
		var dry0 := int(g.get("dry_taps"))
		if float(es["dist"]) > float(beam.get("radius")) * 0.95:
			g.call("_tap", es["pos"])
			if int(g.get("dry_taps")) <= dry0:
				hint = "안셈"
				print("!! %d탄: 아무것도 없는 데를 비췄는데 헛걸음이 안 세어진다" % st)
		else:
			beam.call("aim", es["pos"])
		if hint == "-":
			g.set("dry_taps", int(g.call("dry_limit")))
			g.call("_process", 0.01)
			hint = "뜸" if int(g.get("hints_this_room")) > 0 else "안뜸"
			if hint == "안뜸":
				print("!! %d탄: 헛걸음이 한계(%d)에 닿아도 힌트가 안 뜬다"
						% [st, int(g.call("dry_limit"))])
		g.set("hints_this_room", 0)

		var dark_found := 0
		var lit_missed := 0
		for d in dinos:
			var c: Vector2 = (d.call("hit_rect") as Rect2).get_center()
			# 1. 공룡에서 가장 먼 구석을 비춰 둔다 — 그 공룡은 확실히 어둠 속이다
			beam.call("aim", Vector2(0.0 if c.x > 640.0 else 1280.0,
					0.0 if c.y > 360.0 else 720.0))
			g.call("_tap", c)
			if bool(d.get("found")):
				dark_found += 1
				print("!! %d탄: 어두운 데의 공룡이 찾아졌다 (%s)" % [st, str(c)])
			# 2. 이제 빛이 그 자리에 있다. 한 번 더 누르면 찾아져야 한다.
			g.call("_tap", c)
			if not bool(d.get("found")):
				lit_missed += 1
				print("!! %d탄: 비췄는데도 안 찾아졌다 (%s, 빛 %s r=%.0f)"
						% [st, str(c), str(beam.get("pos")), float(beam.get("radius"))])
		# 3. 다 찾았으면 방이 끝나 있어야 한다
		var cleared := String(g.get("state")) == "clear"
		var row_ok: bool = dark_found == 0 and lit_missed == 0 and cleared \
				and (st > 2 or guide == "공룡위") and hint == "뜸"
		if not row_ok:
			bad += 1
			if not cleared:
				print("!! %d탄: 다 찾았는데 방이 안 끝났다 (state=%s found=%d/%d)"
						% [st, String(g.get("state")), int(g.get("found")), dinos.size()])
		print("   %5d %7d %9d %9d %7s %7s %8s"
				% [st, dinos.size(), dark_found, lit_missed, guide, hint,
				   "정상" if row_ok else "이상"])
		(g.get("sfx") as Object).call("stop_all")
		g.queue_free()
		await get_tree().process_frame
	return bad


## 공룡들에서 가장 먼 자리. 거기를 비추면 아무것도 안 보이므로 "헛걸음"이 세어져야 한다.
func _empty_spot(dinos: Array) -> Dictionary:
	var best := Vector2(64.0, 130.0)
	var bd := -1.0
	for gx in 13:
		for gy in 7:
			var p := Vector2(60.0 + 1160.0 * float(gx) / 12.0, 120.0 + 560.0 * float(gy) / 6.0)
			var m := 1e30
			for d in dinos:
				m = minf(m, p.distance_to((d.call("hit_rect") as Rect2).get_center()))
			if m > bd:
				bd = m
				best = p
	return {"pos": best, "dist": bd}
