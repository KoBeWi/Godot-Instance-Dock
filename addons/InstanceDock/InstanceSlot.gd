tool
extends PanelContainer

export var normal: StyleBox
export var custom: StyleBox

enum MenuOption {EDIT, REMOVE, REFRESH, CLEAR}

onready var icon := $Icon
onready var popup := $PopupMenu
onready var loading := $Loading/AnimationPlayer

var plugin: EditorPlugin
var scene: String
var custom_texture: String
var thread: Thread

signal request_icon(instance, ignore_cache)
signal changed

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	if not thread.is_active():
		thread.wait_to_finish()
		thread = null
		set_process(false)

func can_drop_data(position: Vector2, data) -> bool:
	if not "type" in data:
		return false
	
	if data.type != "files":
		return false
	
	if data.files.size() != 1:
		return false
	
	return data.files[0].get_extension() == "tscn" or data.files[0].get_extension() == "png"

func drop_data(position: Vector2, data) -> void:
	var file: String = data.files[0]
	if file.get_extension() == "png" and scene:
		custom_texture = file
		apply_data()
		emit_signal("changed")
	elif file.get_extension() == "tscn":
		if "from_slot" in data:
			var slot2: Control = get_parent().get_child(data.from_slot)
			var data2: Dictionary = slot2.get_data()
			slot2.set_data(get_data())
			set_data(data2)
		else:
			scene = file
			custom_texture = ""
			apply_data()
		emit_signal("changed")

func get_drag_data(position: Vector2):
	if not scene:
		return null
	
	return {files = [scene], type = "files", from_slot = get_index()}

func set_icon(texture: Texture):
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture = texture
	
	if loading.get_parent().visible:
		icon.hide()
		thread = Thread.new()
		thread.start(self, "check_if_transparent", texture.get_data())
		set_process(true)

func check_if_transparent(data: Image):
	var is_valid: bool
	data.lock()
	for x in data.get_width():
		for y in data.get_height():
			if data.get_pixel(x, y).a > 0:
				is_valid = true
				break
		
		if is_valid:
			break
	
	data.unlock()
	icon.show()
	loading.get_parent().hide()
	loading.stop()
	
	if not is_valid:
		set_icon(preload("res://addons/InstanceDock/Missing.png"))
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED

func _gui_input(event: InputEvent) -> void:
	if not scene:
		return
	
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == BUTTON_RIGHT:
			create_popup()
			popup.popup()
			popup.rect_global_position = event.global_position

func create_popup():
	popup.clear()
	popup.add_item("Open Scene", MenuOption.EDIT)
	popup.add_item("Remove", MenuOption.REMOVE)
	if custom_texture:
		popup.add_item("Remove Custom Icon", MenuOption.CLEAR)
	else:
		popup.add_item("Refresh Icon", MenuOption.REFRESH)
	popup.rect_size = Vector2()

func menu_option(id: int) -> void:
	match id:
		MenuOption.EDIT:
			plugin.open_scene(scene)
		MenuOption.REMOVE:
			scene = ""
			custom_texture = ""
			apply_data()
			emit_signal("changed")
		MenuOption.REFRESH:
			start_load()
			emit_signal("request_icon", scene, true)
		MenuOption.CLEAR:
			custom_texture = ""
			emit_signal("changed")
			apply_data()

func get_data() -> Dictionary:
	if scene.empty():
		return {}
	
	var data := {scene = scene}
	if not custom_texture.empty():
		data.custom_texture = custom_texture
	return data

func set_data(data: Dictionary):
	scene = data.get("scene", "")
	custom_texture = data.get("custom_texture", "")
	apply_data()

func apply_data():
	hint_tooltip = scene.get_file()
	set_icon(null)
	add_stylebox_override("panel", normal)
	
	if scene.empty():
		set_icon(null)
	elif custom_texture.empty():
		start_load()
		emit_signal("request_icon", scene, false)
	else:
		set_icon(load(custom_texture))
		add_stylebox_override("panel", custom)

func start_load():
	loading.play("Rotate")
	loading.get_parent().show()
