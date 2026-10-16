extends Control
## Native Godot physics and rendering — no HTML or WebView.
signal match_changed
signal notice(message: String)
signal match_finished(player_won: bool, reason: String)

const W = 1000.0
const H = 560.0
const LEFT = 67.0
const RIGHT = 933.0
const TOP = 66.0
const BOTTOM = 494.0
const HEAD_LINE = 308.0
const BALL_R = 11.5
const POCKET_R = 24.0
const COLORS = [
	Color("f6f8ff"), Color("f8cc35"), Color("3763d8"), Color("df444e"), Color("7544af"),
	Color("ef9440"), Color("2ca475"), Color("7e3d28"), Color("15191e"), Color("f8c735"),
	Color("396bd8"), Color("df5057"), Color("784eb0"), Color("f0a142"), Color("26a278"), Color("aa6528")
]
const POCKETS = [Vector2(LEFT, TOP), Vector2(500, TOP), Vector2(RIGHT, TOP), Vector2(LEFT, BOTTOM), Vector2(500, BOTTOM), Vector2(RIGHT, BOTTOM)]
const POCKET_LABELS = ["أعلى يسار", "وسط فوق", "أعلى يمين", "أسفل يسار", "وسط جوه", "أسفل يمين"]

var balls: Array[Dictionary] = []
var turn := 0  # 0=human, 1=computer
var phase := "idle" # idle / moving / placing / ended
var groups_assigned := false
var human_group := 1 # 1 = solids, 2 = stripes; provisional until first legal pot
var specials := {1: -1, 15: -1}
var called_pocket := -1
var difficulty := 1
var aim := Vector2.RIGHT
var next_ai_token := 0
var ended := false
var shot: Dictionary = {}
var shot_seconds := 0.0
var move_drag := false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_physics_process(false)
	rng.randomize()

func new_match(level: int = 1) -> void:
	next_ai_token += 1
	difficulty = clampi(level, 0, 2)
	balls.clear()
	turn = 0
	phase = "idle"
	ended = false
	shot.clear()
	groups_assigned = false
	human_group = 1
	called_pocket = -1
	specials = {1: -1, 15: -1}
	_add_ball(0, Vector2(235, 280))
	# Fixed, numbered triangular rack: 8 in the center, 1 at the apex, 15 at the base.
	var rack := [1, 3, 11, 4, 8, 10, 13, 2, 12, 6, 15, 7, 9, 14, 5]
	var index := 0
	var spacing := BALL_R * 2.04
	for row in range(5):
		var x := 735.0 + float(row) * spacing * 0.8660254
		for item in range(row + 1):
			var y := 280.0 + (float(item) - float(row) * 0.5) * spacing
			_add_ball(rack[index], Vector2(x, y))
			index += 1
	aim = Vector2.RIGHT
	set_physics_process(false)
	notice.emit("دورك! وجّه العصا على الطاولة واسحب مسطرة القوة واتركها.")
	match_changed.emit()
	queue_redraw()

func _add_ball(id: int, pos: Vector2) -> void:
	balls.append({"id": id, "pos": pos, "vel": Vector2.ZERO, "alive": true})

func _find_ball(id: int) -> Dictionary:
	for b in balls:
		if b["id"] == id:
			return b
	return {}

func _living_targets(player: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var desired := human_group if player == 0 else 3 - human_group
	for b in balls:
		var n: int = b["id"]
		if not b["alive"] or n == 0 or n == 8:
			continue
		if not groups_assigned or _group(n) == desired:
			result.append(b)
	if result.is_empty():
		var black := _find_ball(8)
		if not black.is_empty() and black["alive"]:
			result.append(black)
	return result

func _group(id: int) -> int:
	if id >= 1 and id <= 7:
		return 1
	if id >= 9 and id <= 15:
		return 2
	return 0

func own_group(player: int) -> int:
	if not groups_assigned:
		return 0
	return human_group if player == 0 else 3 - human_group

func remaining(player: int) -> int:
	var count := 0
	for b in balls:
		if b["alive"] and _group(b["id"]) == own_group(player):
			count += 1
	return count

func can_human_shoot() -> bool:
	return not ended and turn == 0 and phase == "idle"

func needs_top(player: int) -> bool:
	if not groups_assigned or remaining(player) > 0:
		return false
	var black := _find_ball(8)
	return not black.is_empty() and black["alive"]

func set_call(pocket_id: int) -> void:
	if not can_human_shoot() or not needs_top(0):
		return
	called_pocket = clampi(pocket_id, 0, 5)
	notice.emit("تم اختيار التوب: " + POCKET_LABELS[called_pocket])
	match_changed.emit()
	queue_redraw()

func shoot_human(strength: float) -> void:
	if not can_human_shoot():
		return
	if needs_top(0) and called_pocket == -1:
		notice.emit("لازم تختار جيب التوب للسوداء قبل الضربة.")
		return
	_start_shot(aim, clampf(strength, .12, 1.0))

func _start_shot(direction: Vector2, strength: float) -> void:
	if phase != "idle" or ended or direction.length_squared() < .0001:
		return
	var cue := _find_ball(0)
	if cue.is_empty() or not cue["alive"]:
		return
	shot = {"player": turn, "first": -1, "pots": [], "called": called_pocket}
	shot_seconds = 0.0
	cue["vel"] = direction.normalized() * (220.0 + 1150.0 * strength)
	phase = "moving"
	set_physics_process(true)
	match_changed.emit()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if phase != "moving":
		set_physics_process(false)
		return
	shot_seconds += delta
	# Substeps prevent fast balls from skipping through each other.
	for unused in range(4):
		_integrate(delta / 4.0)
	var moving := false
	for b in balls:
		if not b["alive"]:
			continue
		var velocity: Vector2 = b["vel"]
		b["vel"] = velocity.move_toward(Vector2.ZERO, 290.0 * delta)
		if b["vel"].length() < 7.0:
			b["vel"] = Vector2.ZERO
		else:
			moving = true
	queue_redraw()
	if not moving or shot_seconds > 10.0:
		for b in balls:
			b["vel"] = Vector2.ZERO
		set_physics_process(false)
		_settle_shot()

func _integrate(step: float) -> void:
	for b in balls:
		if not b["alive"]:
			continue
		b["pos"] += b["vel"] * step
		for p in range(6):
			if b["pos"].distance_to(POCKETS[p]) < POCKET_R:
				b["alive"] = false
				b["vel"] = Vector2.ZERO
				shot["pots"].append({"id": b["id"], "pocket": p})
				break
		if not b["alive"]:
			continue
		var pos: Vector2 = b["pos"]
		var vel: Vector2 = b["vel"]
		if pos.x < LEFT + BALL_R:
			pos.x = LEFT + BALL_R
			vel.x = absf(vel.x) * .83
		elif pos.x > RIGHT - BALL_R:
			pos.x = RIGHT - BALL_R
			vel.x = -absf(vel.x) * .83
		if pos.y < TOP + BALL_R:
			pos.y = TOP + BALL_R
			vel.y = absf(vel.y) * .83
		elif pos.y > BOTTOM - BALL_R:
			pos.y = BOTTOM - BALL_R
			vel.y = -absf(vel.y) * .83
		b["pos"] = pos
		b["vel"] = vel
	for i in range(balls.size()):
		var a := balls[i]
		if not a["alive"]:
			continue
		for j in range(i + 1, balls.size()):
			var b := balls[j]
			if not b["alive"]:
				continue
			var sep: Vector2 = b["pos"] - a["pos"]
			var length := sep.length()
			if length >= BALL_R * 2.0:
				continue
			var normal := sep / length if length > .001 else Vector2.RIGHT
			var overlap := BALL_R * 2.0 - length
			a["pos"] -= normal * overlap * .5
			b["pos"] += normal * overlap * .5
			var approaching := (a["vel"] - b["vel"]).dot(normal)
			if approaching <= 0.0:
				continue
			var impulse := approaching * .96
			a["vel"] -= normal * impulse
			b["vel"] += normal * impulse
			if shot["first"] == -1 and (a["id"] == 0 or b["id"] == 0):
				shot["first"] = b["id"] if a["id"] == 0 else a["id"]

func _settle_shot() -> void:
	if shot.is_empty():
		phase = "idle"
		return
	var player: int = shot["player"]
	var opponent := 1 - player
	var scratched := false
	var fouls: Array[String] = []
	var legal_ids: Array[int] = []
	var first: int = shot["first"]
	var my_group := own_group(player)
	if first == 8 and not needs_top(player):
		fouls.append("لمست السوداء قبل دورها")
	elif first > 0 and my_group != 0 and first != 8 and _group(first) != my_group:
		fouls.append("لمست كرة الخصم أولاً")
	var pots: Array = shot["pots"]
	for p in pots:
		var id: int = p["id"]
		var pocket: int = p["pocket"]
		if id == 0:
			scratched = true
			fouls.append("دخلت الكرة البيضاء")
			continue
		if id == 8:
			continue
		if id == 1 or id == 15:
			var mate := 15 if id == 1 else 1
			if (pocket != 1 and pocket != 4) or (specials[mate] >= 0 and specials[mate] == pocket):
				fouls.append("الكرة %d بجيب مخالف" % id)
				_respot(id)
				continue
			specials[id] = pocket
		if my_group != 0 and _group(id) != my_group:
			fouls.append("دخلت كرة الخصم")
		legal_ids.append(id)
	if not groups_assigned and fouls.is_empty():
		for id in legal_ids:
			if _group(id) != 0:
				groups_assigned = true
				human_group = _group(id) if player == 0 else 3 - _group(id)
				break
	var black_potted := false
	var black_pocket := -1
	for p in pots:
		if p["id"] == 8:
			black_potted = true
			black_pocket = p["pocket"]
	if black_potted:
		if not groups_assigned or remaining(player) > 0 or not fouls.is_empty() or shot["called"] != black_pocket:
			_end_game(opponent, "دخلت السوداء بدون توب صحيح أو قبل إكمال الكرات")
		else:
			_end_game(player, "دخلت السوداء بالجيب المحدد! فوز قانوني")
		return
	var own_potted := false
	for id in legal_ids:
		if _group(id) == own_group(player):
			own_potted = true
	var keep_turn := fouls.is_empty() and own_potted
	turn = player if keep_turn else opponent
	called_pocket = -1
	phase = "idle"
	if scratched:
		_restore_white()
		if turn == 0:
			phase = "placing"
			notice.emit("فاول البيضاء: حطّها فقط وراء خط البداية على يسار الطاولة")
		else:
			notice.emit("فاول البيضاء: الكمبيوتر يرجّعها وراء الخط")
	elif not fouls.is_empty():
		notice.emit("فاول: " + "، ".join(PackedStringArray(fouls)) + " — البيضاء تبقى بمكانها")
	elif keep_turn:
		notice.emit("دخلت كرة قانونية، الدور مستمر")
	else:
		notice.emit("انتقل الدور للخصم")
	shot.clear()
	match_changed.emit()
	queue_redraw()
	if turn == 1:
		_schedule_ai()

func _respot(id: int) -> void:
	var b := _find_ball(id)
	if b.is_empty():
		return
	b["alive"] = true
	b["pos"] = _find_open_spot(true)
	b["vel"] = Vector2.ZERO

func _restore_white() -> void:
	var cue := _find_ball(0)
	cue["alive"] = true
	cue["pos"] = _find_open_spot(true)
	cue["vel"] = Vector2.ZERO

func _find_open_spot(behind_line: bool) -> Vector2:
	for col in range(16):
		for row in range(15):
			var pos := Vector2(LEFT + 40.0 + col * 13.5, TOP + 25.0 + row * 26.0)
			if behind_line and pos.x > HEAD_LINE - BALL_R - 2.0:
				continue
			if _valid_spot(pos):
				return pos
	return Vector2(160, 280)

func _valid_spot(pos: Vector2) -> bool:
	if pos.x < LEFT + BALL_R + 2.0 or pos.x > RIGHT - BALL_R - 2.0 or pos.y < TOP + BALL_R + 2.0 or pos.y > BOTTOM - BALL_R - 2.0:
		return false
	for b in balls:
		if b["alive"] and pos.distance_squared_to(b["pos"]) < (BALL_R * 2.35) ** 2:
			return false
	return true

func _schedule_ai() -> void:
	if ended or turn != 1:
		return
	next_ai_token += 1
	var token := next_ai_token
	_ai_wait_and_shoot(token)

func _ai_wait_and_shoot(token: int) -> void:
	await get_tree().create_timer(.82).timeout
	if token != next_ai_token or turn != 1 or ended or phase != "idle":
		return
	_ai_shoot()

func _ai_shoot() -> void:
	var cue := _find_ball(0)
	if cue.is_empty() or not cue["alive"]:
		return
	var targets := _living_targets(1)
	if targets.is_empty():
		return
	var best := Vector2.RIGHT
	var best_score := -1000000.0
	var best_power := .62
	var best_pocket := -1
	for target in targets:
		var id: int = target["id"]
		for pi in range(POCKETS.size()):
			if (id == 1 or id == 15) and pi != 1 and pi != 4:
				continue
			if (id == 1 and specials[15] == pi) or (id == 15 and specials[1] == pi):
				continue
			var to_pocket: Vector2 = (POCKETS[pi] - target["pos"]).normalized()
			var ghost: Vector2 = target["pos"] - to_pocket * (BALL_R * 2.0)
			var line := ghost - cue["pos"]
			if line.length_squared() < 100.0:
				continue
			if not _path_clear(cue["pos"], ghost, id, 0) or not _path_clear(target["pos"], POCKETS[pi], id, 0):
				continue
			var score := 2000.0 - line.length() - target["pos"].distance_to(POCKETS[pi]) * .32
			if score > best_score:
				best_score = score
				best = line.normalized()
				best_pocket = pi
				best_power = clampf((line.length() + target["pos"].distance_to(POCKETS[pi]) * .75) / 1250.0, .28, .85)
	if best_pocket == -1:
		var closest: Dictionary = targets[0]
		for target in targets:
			if cue["pos"].distance_squared_to(target["pos"]) < cue["pos"].distance_squared_to(closest["pos"]):
				closest = target
		best = (closest["pos"] - cue["pos"]).normalized()
		best_power = .63
	if needs_top(1):
		called_pocket = best_pocket if best_pocket >= 0 else 1
	var max_error: float = [0.10, 0.043, 0.012][difficulty]
	best = best.rotated(rng.randf_range(-max_error, max_error))
	_start_shot(best, best_power)
	notice.emit("الكمبيوتر يسدد...")

func _path_clear(start: Vector2, finish: Vector2, ignore_a: int, ignore_b: int) -> bool:
	var delta := finish - start
	var dist_sq := delta.length_squared()
	if dist_sq < 1.0:
		return true
	for b in balls:
		if not b["alive"] or b["id"] == ignore_a or b["id"] == ignore_b:
			continue
		var t := clampf((b["pos"] - start).dot(delta) / dist_sq, 0.0, 1.0)
		if start.lerp(finish, t).distance_squared_to(b["pos"]) < (BALL_R * 2.15) ** 2:
			return false
	return true

func _end_game(winner: int, message: String) -> void:
	ended = true
	phase = "ended"
	set_physics_process(false)
	next_ai_token += 1
	notice.emit(message)
	match_changed.emit()
	match_finished.emit(winner == 0, message)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if ended or turn != 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if phase == "placing":
				move_drag = true
				_place_cue(event.position)
			elif phase == "idle":
				_set_aim(event.position)
		else:
			if phase == "placing" and move_drag:
				_place_cue(event.position)
				move_drag = false
				phase = "idle"
				notice.emit("ثبتت البيضاء وراء الخط. صوب واسحب المسطرة واتركها")
				match_changed.emit()
		accept_event()
	elif event is InputEventMouseMotion:
		if phase == "placing" and move_drag:
			_place_cue(event.position)
		elif phase == "idle" and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_set_aim(event.position)

func _to_logical(pos: Vector2) -> Vector2:
	return Vector2(pos.x / maxf(1.0, size.x) * W, pos.y / maxf(1.0, size.y) * H)

func _set_aim(pointer_pos: Vector2) -> void:
	var cue := _find_ball(0)
	if cue.is_empty() or not cue["alive"]:
		return
	var delta := _to_logical(pointer_pos) - cue["pos"]
	if delta.length_squared() > 20.0:
		aim = delta.normalized()
		queue_redraw()

func _place_cue(pointer_pos: Vector2) -> void:
	var pos := _to_logical(pointer_pos)
	pos.x = clampf(pos.x, LEFT + BALL_R + 3, HEAD_LINE - BALL_R - 3)
	pos.y = clampf(pos.y, TOP + BALL_R + 3, BOTTOM - BALL_R - 3)
	var cue := _find_ball(0)
	cue["alive"] = false
	if _valid_spot(pos):
		cue["pos"] = pos
	cue["alive"] = true
	queue_redraw()

func _draw() -> void:
	var scale_xy := Vector2(size.x / W, size.y / H)
	draw_set_transform(Vector2.ZERO, 0.0, scale_xy)
	_draw_table()
	for b in balls:
		if b["alive"]:
			_draw_ball(b)
	if turn == 0 and (phase == "idle" or phase == "placing") and not ended:
		_draw_guide()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_table() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("111d34"), true)
	draw_rect(Rect2(9, 9, W - 18, H - 18), Color("49301f"), true)
	draw_rect(Rect2(15, 15, W - 30, H - 30), Color("c48b4e"), true)
	draw_rect(Rect2(22, 22, W - 44, H - 44), Color("643b25"), true)
	draw_rect(Rect2(29, 29, W - 58, H - 58), Color("e5c89a"), true)
	draw_rect(Rect2(36, 36, W - 72, H - 72), Color("222b31"), true)
	draw_rect(Rect2(LEFT - 14, TOP - 14, RIGHT - LEFT + 28, BOTTOM - TOP + 28), Color("0a2465"), true)
	draw_rect(Rect2(LEFT, TOP, RIGHT - LEFT, BOTTOM - TOP), Color("1556b1"), true)
	# Felt lighting and fabric grain, inexpensive to render when physics is sleeping.
	for i in range(13):
		var alpha := .028 * (1.0 - float(i) / 13.0)
		draw_rect(Rect2(LEFT + i * 11, TOP + i * 5, RIGHT - LEFT - i * 22, BOTTOM - TOP - i * 10), Color(0.7, .9, 1.0, alpha), false, 2)
	# A subtle line defines the permitted white-ball area on scratches.
	draw_line(Vector2(HEAD_LINE, TOP + 3), Vector2(HEAD_LINE, BOTTOM - 3), Color(1, 1, 1, .24), 2)
	if phase == "placing":
		draw_rect(Rect2(LEFT, TOP, HEAD_LINE - LEFT, BOTTOM - TOP), Color(.3, 1.0, .55, .12), true)
		draw_line(Vector2(HEAD_LINE, TOP), Vector2(HEAD_LINE, BOTTOM), Color("b6ffb7"), 4)
	for i in range(6):
		draw_circle(POCKETS[i], POCKET_R + 7, Color("5c3a28"))
		draw_circle(POCKETS[i], POCKET_R + 2, Color("10161e"))
		draw_circle(POCKETS[i], POCKET_R - 3, Color("010409"))
	for i in range(8):
		var px := 118.0 + i * 109.0
		draw_circle(Vector2(px, 28), 3.5, Color("e6d5bc"))
		draw_circle(Vector2(px, 532), 3.5, Color("e6d5bc"))

func _draw_ball(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var id: int = b["id"]
	draw_circle(pos + Vector2(3, 4), BALL_R + 1.0, Color(0, 0, 0, .34))
	if id == 0:
		draw_circle(pos, BALL_R, Color("f4f6f9"))
		draw_circle(pos + Vector2(-3.6, -3.7), 3.2, Color(1, 1, 1, .92))
		return
	var color: Color = COLORS[id]
	if id > 8:
		draw_circle(pos, BALL_R, Color("eef2f5"))
		# Banded stripe respecting the circular silhouette.
		var span := 7.3
		var half_width := sqrt(BALL_R * BALL_R - span * span)
		draw_rect(Rect2(pos.x - half_width, pos.y - span, half_width * 2, span * 2), color, true)
		draw_arc(pos, BALL_R, 0, TAU, 24, color.darkened(.45), 1.2)
	else:
		draw_circle(pos, BALL_R, color)
		draw_arc(pos, BALL_R, 0, TAU, 24, color.darkened(.48), 1.2)
	draw_circle(pos + Vector2(-3.3, -3.5), 3.6, Color(1, 1, 1, .35))
	draw_circle(pos, 6.1, Color("f7f7ed"))
	var label := str(id)
	var font_size := 8 if id > 9 else 9
	draw_string(ThemeDB.fallback_font, pos + Vector2(-7, 3.0), label, HORIZONTAL_ALIGNMENT_CENTER, 14, font_size, Color("111927"))

func _draw_guide() -> void:
	var cue := _find_ball(0)
	if cue.is_empty() or not cue["alive"]:
		return
	var pos: Vector2 = cue["pos"]
	if phase == "placing":
		draw_arc(pos, BALL_R + 9, 0, TAU, 32, Color("ffdb7d"), 2)
		return
	for i in range(1, 24):
		var marker := pos + aim * (i * 23.0)
		if marker.x < LEFT or marker.x > RIGHT or marker.y < TOP or marker.y > BOTTOM:
			break
		draw_circle(marker, 2.1, Color(1, 1, 1, .65 - i * .017))
	var back := pos - aim * 36.0
	var stick_end := pos - aim * 360.0
	draw_line(back, stick_end, Color("27170f"), 12.0)
	draw_line(back, stick_end, Color("ad763c"), 7.5)
	draw_line(back, back - aim * 56.0, Color("ebd6a6"), 5.0)
	draw_line(back, back - aim * 9.0, Color("5cbbdf"), 5.5)
