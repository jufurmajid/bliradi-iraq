extends Control
## Fullscreen landscape UI for an offline, native Godot billiards game.

const TABLE_SCRIPT = preload("res://scripts/table.gd")
const GAUGE_SCRIPT = preload("res://scripts/power_gauge.gd")
const NAVY = Color("10192c")
const GOLD = Color("f3cc77")
const WHITE = Color("f1f5ff")
const MUTED = Color("aabbd7")

var menu_screen: Control
var game_screen: Control
var table = null
var gauge = null
var difficulty := 1
var difficulty_buttons: Array[Button] = []
var message_label: Label
var turn_label: Label
var human_group_label: Label
var bot_group_label: Label
var human_balls_label: Label
var bot_balls_label: Label
var top_controls: GridContainer
var top_buttons: Array[Button] = []
var end_layer: ColorRect
var end_title: Label
var end_body: Label
var menu_preview = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_menu()
	_build_game()
	_build_result()
	_show_menu()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), NAVY, true)
	for i in range(20):
		var alpha := .012 * (20.0 - float(i)) / 20.0
		draw_circle(Vector2(size.x * .67, size.y * .23), size.y * (.35 + i * .055), Color(.28, .48, .8, alpha))

func _panel_style(color: Color = Color("192740"), radius: int = 20, border: Color = Color("344667")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _label(text: String, font_size: int = 18, color: Color = WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	# No wrapping by default: headers must never collapse into one-letter columns.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label

func _wrapped_label(text: String, font_size: int = 18, color: Color = WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var label := _label(text, font_size, color, align)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(title: String, primary: bool = false, font_size: int = 19) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(100, 56)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color("111b2c") if primary else WHITE)
	button.add_theme_color_override("font_hover_color", Color("111b2c") if primary else WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(Color("f2c977") if primary else Color("2b3e60"), 13))
	button.add_theme_stylebox_override("hover", _panel_style(Color("ffe2a0") if primary else Color("405b84"), 13))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("deb35c") if primary else Color("182943"), 13))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button

func _frame(parent: Node, fill: bool = true) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	if fill:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	return panel

func _column(parent: Node, separation: int = 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	return box

func _row(parent: Node, separation: int = 12) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	return box

func _margin(parent: Node, left: int = 22, top: int = 16, right: int = 22, bottom: int = 16) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(m)
	return m

func _build_menu() -> void:
	menu_screen = Control.new()
	menu_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu_screen)
	var frame := _margin(menu_screen, 26, 15, 26, 18)
	var vbox := _column(frame, 10)
	var header := _row(vbox, 16)
	header.add_child(_label("🎱  بريالدو العراقي", 27, GOLD))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(_label("IRAQI BILLIARDS  •  GODOT EDITION", 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	var content := _row(vbox, 24)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := _frame(content)
	left.size_flags_stretch_ratio = .95
	# Scroll safely on compact landscape displays instead of overflowing below the screen.
	var intro_scroll := ScrollContainer.new()
	intro_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	intro_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(intro_scroll)
	var intro := _column(intro_scroll, 9)
	intro.add_child(_label("العب البريالدو العراقي", 31, WHITE))
	intro.add_child(_wrapped_label("تحدّي الكمبيوتر   •   قوانين عراقية   •   بدون إنترنت", 15, GOLD))
	var desc := _wrapped_label("طاولة بليارد داخل محرك Godot، تصويب باللمس وتسديد بسحب المسطرة وإفلاتها. اللعب ضد الكمبيوتر حالياً.", 15, MUTED)
	intro.add_child(desc)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	intro.add_child(gap)
	intro.add_child(_label("مستوى الكمبيوتر", 20, WHITE))
	var difficulties := _row(intro, 8)
	for i in range(3):
		var btn := _button(["سهل", "متوسط", "محترف"][i], i == 1, 17)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		difficulties.add_child(btn)
		difficulty_buttons.append(btn)
		btn.pressed.connect(_set_difficulty.bind(i))
	var start := _button("ابدأ المباراة  ◀", true, 24)
	start.custom_minimum_size.y = 64
	intro.add_child(start)
	start.pressed.connect(_start_match)
	intro.add_child(_label("مصمم للأندرويد — يفضّل اللعب بالعرض", 14, MUTED))
	var copyright := Control.new()
	copyright.size_flags_vertical = Control.SIZE_EXPAND_FILL
	intro.add_child(copyright)
	intro.add_child(_label("صناعة جعفر ماجد  🇮🇶", 15, GOLD))
	var right := _frame(content)
	right.size_flags_stretch_ratio = 1.05
	var preview_box := _column(right, 10)
	preview_box.add_child(_label("معاينة الطاولة", 21, WHITE))
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 1000.0 / 560.0
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_box.add_child(aspect)
	menu_preview = TABLE_SCRIPT.new()
	menu_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aspect.add_child(menu_preview)
	menu_preview.new_match(1)
	preview_box.add_child(_label("1 و15 بالجيوب الوسطية   •   السوداء بالتوب", 15, GOLD, HORIZONTAL_ALIGNMENT_CENTER))

func _set_difficulty(selected: int) -> void:
	difficulty = selected
	for i in range(difficulty_buttons.size()):
		var btn := difficulty_buttons[i]
		var selected_style := i == selected
		btn.add_theme_stylebox_override("normal", _panel_style(Color("a87b38") if selected_style else Color("2b3e60"), 13))
		btn.add_theme_color_override("font_color", Color("111b2c") if selected_style else WHITE)

func _build_game() -> void:
	game_screen = Control.new()
	game_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_screen.visible = false
	add_child(game_screen)
	var outer := _margin(game_screen, 10, 7, 10, 10)
	var stack := _column(outer, 7)
	var scoreboard := _row(stack, 10)
	scoreboard.custom_minimum_size.y = 88
	var menu_btn := _button("☰", false, 24)
	menu_btn.custom_minimum_size.x = 64
	menu_btn.pressed.connect(_show_menu)
	scoreboard.add_child(menu_btn)
	var human_panel := _frame(scoreboard)
	var human_stack := _column(human_panel, 1)
	human_stack.add_child(_label("اللاعب 1  •  إنت", 17, GOLD))
	human_group_label = _label("المجموعة: بانتظار أول كرة", 13, MUTED)
	human_stack.add_child(human_group_label)
	human_balls_label = _label("① ② ③ ④ ⑤ ⑥ ⑦", 15, WHITE)
	human_stack.add_child(human_balls_label)
	var center_panel := _frame(scoreboard)
	center_panel.custom_minimum_size.x = 220
	var center_col := _column(center_panel, 1)
	turn_label = _label("دورك", 22, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	center_col.add_child(turn_label)
	center_col.add_child(_label("🎱  VS", 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var bot_panel := _frame(scoreboard)
	var bot_stack := _column(bot_panel, 1)
	bot_stack.add_child(_label("الكمبيوتر  •  AI", 17, GOLD))
	bot_group_label = _label("المجموعة: بانتظار أول كرة", 13, MUTED)
	bot_stack.add_child(bot_group_label)
	bot_balls_label = _label("⑨ ⑩ ⑪ ⑫ ⑬ ⑭ ⑮", 15, WHITE)
	bot_stack.add_child(bot_balls_label)
	var screen_btn := _button("⛶", false, 24)
	screen_btn.custom_minimum_size.x = 64
	screen_btn.pressed.connect(_toggle_fullscreen)
	scoreboard.add_child(screen_btn)

	var arena := _row(stack, 8)
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var power_panel := _frame(arena)
	power_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	power_panel.custom_minimum_size.x = 100
	gauge = GAUGE_SCRIPT.new()
	gauge.size_flags_vertical = Control.SIZE_EXPAND_FILL
	power_panel.add_child(gauge)
	gauge.power_released.connect(_on_release)

	var table_panel := _frame(arena)
	table_panel.size_flags_stretch_ratio = 6.0
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 1000.0 / 560.0
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_panel.add_child(aspect)
	table = TABLE_SCRIPT.new()
	aspect.add_child(table)
	table.match_changed.connect(_refresh_hud)
	table.notice.connect(_set_notice)
	table.match_finished.connect(_on_match_finished)

	var action_panel := _frame(arena)
	action_panel.custom_minimum_size.x = 182
	action_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var actions := _column(action_panel, 10)
	actions.add_child(_label("قوانين بريالدو", 18, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	actions.add_child(_wrapped_label("اختيار التوب للسوداء", 14, WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	top_controls = GridContainer.new()
	top_controls.columns = 2
	actions.add_child(top_controls)
	for i in range(6):
		var top := _button(str(i + 1), false, 16)
		top.custom_minimum_size = Vector2(60, 44)
		top_controls.add_child(top)
		top_buttons.append(top)
		top.pressed.connect(_on_call_pocket.bind(i))
	actions.add_child(_wrapped_label("الكرة 1 و15 فقط في الجيبين الوسطية", 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.add_child(filler)
	var replay := _button("إعادة", false, 17)
	actions.add_child(replay)
	replay.pressed.connect(_start_match)

	var foot := _frame(stack, false)
	foot.custom_minimum_size.y = 52
	message_label = _wrapped_label("حدد التصويب ثم اسحب مسطرة القوة واتركها", 16, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	foot.add_child(message_label)

func _build_result() -> void:
	end_layer = ColorRect.new()
	end_layer.color = Color(0, 0, 0, .85)
	end_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	end_layer.visible = false
	add_child(end_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_layer.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(470, 310)
	box.add_theme_stylebox_override("panel", _panel_style(Color("172943"), 24, GOLD))
	center.add_child(box)
	var stack := _column(box, 15)
	end_title = _label("انتهت المباراة", 34, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	stack.add_child(end_title)
	end_body = _wrapped_label("", 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	stack.add_child(end_body)
	var replay := _button("العب مرة ثانية", true, 20)
	stack.add_child(replay)
	replay.pressed.connect(_start_match)
	var back := _button("القائمة الرئيسية", false, 17)
	stack.add_child(back)
	back.pressed.connect(_show_menu)

func _start_match() -> void:
	menu_screen.visible = false
	game_screen.visible = true
	end_layer.visible = false
	table.new_match(difficulty)
	gauge.set_enabled(true)
	_refresh_hud()

func _show_menu() -> void:
	if table != null:
		table.next_ai_token += 1
		table.set_physics_process(false)
	menu_screen.visible = true
	game_screen.visible = false
	end_layer.visible = false

func _on_release(strength: float) -> void:
	if table.can_human_shoot():
		table.shoot_human(strength)

func _on_call_pocket(index: int) -> void:
	table.set_call(index)

func _set_notice(message: String) -> void:
	if message_label != null:
		message_label.text = message

func _refresh_hud() -> void:
	if table == null or gauge == null or turn_label == null:
		return
	gauge.set_enabled(table.can_human_shoot())
	turn_label.text = "الكرات تتحرك" if table.phase == "moving" else "الكمبيوتر يلعب" if table.turn == 1 else "دورك"
	human_group_label.text = _group_name(table.own_group(0))
	bot_group_label.text = _group_name(table.own_group(1))
	human_balls_label.text = _ball_progress(0)
	bot_balls_label.text = _ball_progress(1)
	var can_call: bool = table.can_human_shoot() and table.needs_top(0)
	for i in range(top_buttons.size()):
		top_buttons[i].disabled = not can_call
		top_buttons[i].modulate = GOLD if table.called_pocket == i else WHITE

func _group_name(id: int) -> String:
	if id == 1:
		return "صوالح 1–7"
	if id == 2:
		return "مخططات 9–15"
	return "المجموعة لم تتحدد"

func _ball_progress(player: int) -> String:
	var group: int = table.own_group(player)
	if group == 0:
		return "○ ○ ○ ○ ○ ○ ○"
	var output: Array[String] = []
	var start: int = 1 if group == 1 else 9
	for n in range(start, start + 7):
		var b: Dictionary = table._find_ball(n)
		output.append("×" if not b["alive"] else str(n))
	return "  ".join(PackedStringArray(output))

func _on_match_finished(won: bool, reason: String) -> void:
	end_title.text = "🏆 فزت بالمباراة!" if won else "الكمبيوتر فاز"
	end_body.text = reason
	end_layer.visible = true

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
