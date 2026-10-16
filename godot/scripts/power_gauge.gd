extends Control
## سحب المسطرة للأسفل، وعند الإفلات تنطلق الضربة مباشرة.
signal power_released(strength: float)
signal power_changed(strength: float)

var active := false
var enabled := true
var value := 0.0
const GOLD = Color("ffd37a")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(84, 330)

func set_enabled(allow: bool) -> void:
	enabled = allow
	if not allow:
		active = false
		value = 0.0
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			active = true
			_update_drag(event.position.y)
			accept_event()
		elif active:
			active = false
			var final_value := value
			value = 0.0
			queue_redraw()
			if final_value >= 0.06:
				power_released.emit(clampf(final_value, 0.12, 1.0))
			accept_event()
	elif event is InputEventMouseMotion and active:
		_update_drag(event.position.y)
		accept_event()

func _update_drag(y: float) -> void:
	value = clampf((y - 54.0) / maxf(80.0, size.y - 106.0), 0.0, 1.0)
	power_changed.emit(value)
	queue_redraw()

func _draw() -> void:
	var center := size.x * 0.5
	draw_rect(Rect2(10, 10, size.x - 20, size.y - 20), Color("111b30"), true)
	draw_rect(Rect2(10, 10, size.x - 20, size.y - 20), Color("344764"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(9, 31), "POWER", HORIZONTAL_ALIGNMENT_CENTER, size.x - 18, 12, Color("d8e0f1"))
	var y_start := 53.0
	var length := maxf(80.0, size.y - 106.0)
	draw_rect(Rect2(center - 8, y_start, 16, length), Color("080c16"), true)
	for i in range(11):
		var tick_y := y_start + i * length / 10.0
		draw_line(Vector2(center - 19, tick_y), Vector2(center - 12, tick_y), Color("8798b9"), 1.3)
	var fill_length := length * value
	draw_rect(Rect2(center - 7, y_start, 14, fill_length), Color("cfa24a"), true)
	draw_rect(Rect2(center - 7, y_start, 14, fill_length * 0.55), GOLD, true)
	var handle_y := y_start + fill_length
	draw_circle(Vector2(center + 1, handle_y + 3), 16, Color(0, 0, 0, .5))
	draw_circle(Vector2(center, handle_y), 14, GOLD if enabled else Color("57667c"))
	draw_circle(Vector2(center - 4, handle_y - 4), 4, Color(1, 1, 1, .48))
	draw_string(ThemeDB.fallback_font, Vector2(5, size.y - 10), "%d%%" % int(value * 100), HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 14, Color("ffe8b8"))
