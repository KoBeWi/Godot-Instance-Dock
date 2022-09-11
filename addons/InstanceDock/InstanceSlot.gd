@tool
extends PanelContainer

@export var normal: StyleBox
@export var custom: StyleBox

enum MenuOption {EDIT, REMOVE, REFRESH, CLEAR}

@onready var icon := $Icon
@onready var loading_icon = $Loading
@onready var loading_animator := %AnimationPlayer

var popup: PopupMenu

var plugin: EditorPlugin
var scene: String
var custom_texture: String
var thread: Thread

signal request_icon(instance, ignore_cache)
signal changed

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	if not thread.is_alive():
		thread.wait_to_finish()
		thread = null
		set_process(false)

func _can_drop_data(position: Vector2, data) -> bool:
	if not data is Dictionary or not "type" in data:
		return false
	
	if data.type != "files":
		return false
	
	if data.files.size() != 1:
		return false
	
	return data.files[0].get_extension() == "tscn" or data.files[0].get_extension() == "png"

func _drop_data(position: Vector2, data) -> void:
	var file: String = data.files[0]
	if file.get_extension() == "png" and not scene.is_empty():
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

func _get_drag_data(position: Vector2):
	if scene.is_empty():
		return null
	
	return {files = [scene], type = "files", from_slot = get_index()}

func set_icon(texture: Texture2D):
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture = texture
	
	if loading_icon.visible:
		icon.modulate.a = 0
		thread = Thread.new()
		thread.start(check_if_transparent.bind(texture.get_image()))
		set_process(true)

func check_if_transparent(data: Image):
	var is_valid: bool
	for x in data.get_width():
		for y in data.get_height():
			if data.get_pixel(x, y).a > 0:
				is_valid = true
				break
		
		if is_valid:
			break
	
	icon.modulate.a = 1
	loading_icon.hide()
	loading_animator.stop()
	
	if not is_valid:
		set_icon(preload("res://addons/InstanceDock/Missing.png"))
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED

func _gui_input(event: InputEvent) -> void:
	if scene.is_empty():
		return
	
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			create_popup()
			popup.popup()
			popup.position = get_screen_transform() * event.position
		elif event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			menu_option(MenuOption.EDIT)

func create_popup():
	if not popup:
		popup = PopupMenu.new()
		popup.id_pressed.connect(menu_option)
		add_child(popup)
	
	popup.clear()
	popup.add_item("Open Scene", MenuOption.EDIT)
	popup.add_item("Remove", MenuOption.REMOVE)
	if custom_texture:
		popup.add_item("Remove Custom Icon", MenuOption.CLEAR)
	else:
		popup.add_item("Refresh Icon", MenuOption.REFRESH)
	popup.reset_size()

func menu_option(id: int) -> void:
	match id:
		MenuOption.EDIT:
			plugin.get_editor_interface().open_scene_from_path(scene)
		MenuOption.REMOVE:
			scene = ""
			custom_texture = ""
			apply_data()
			changed.emit()
		MenuOption.REFRESH:
			start_load()
			request_icon.emit(scene, true)
		MenuOption.CLEAR:
			custom_texture = ""
			changed.emit()
			apply_data()

func get_data() -> Dictionary:
	if scene.is_empty():
		return {}
	
	var data := {scene = scene}
	if not custom_texture.is_empty():
		data.custom_texture = custom_texture
	return data

func set_data(data: Dictionary):
	scene = data.get("scene", "")
	custom_texture = data.get("custom_texture", "")
	apply_data()

func apply_data():
	tooltip_text = scene.get_file()
	set_icon(null)
	add_theme_stylebox_override(&"panel", normal)
	
	if scene.is_empty():
		set_icon(null)
	elif custom_texture.is_empty():
		start_load()
		request_icon.emit(scene, false)
	else:
		set_icon(load(custom_texture))
		add_theme_stylebox_override(&"panel", custom)

func start_load():
	loading_animator.play(&"Rotate")
	loading_icon.show()
