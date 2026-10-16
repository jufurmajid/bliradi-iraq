extends SceneTree
## Guard against one-letter-wide headers on Android-sized displays.

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var scene: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var menu: Control = scene.get("menu_screen")
	if menu == null:
		push_error("Menu missing")
		quit(1)
		return
	var title: Label = null
	var start: Button = null
	for item in menu.find_children("*", "Label", true, false):
		if (item as Label).text.contains("بريالدو العراقي") and (item as Label).text.contains("🎱"):
			title = item
	for item in menu.find_children("*", "Button", true, false):
		if (item as Button).text.contains("ابدأ المباراة"):
			start = item
	var good := title != null and start != null
	if good:
		good = title.size.x > 175.0 and title.size.y < 100.0
	if good:
		good = start.size.x > 160.0
	if not good:
		push_error("Menu layout failed: text collapsed or start button missing")
		quit(1)
		return
	print("MENU_LAYOUT_OK title_width=", title.size.x, " start_width=", start.size.x)
	quit(0)
