tool
extends PanelContainer

enum MenuOption {EDIT, REMOVE, REFRESH, CLEAR}

onready var icon := $TextureRect
onready var popup := $PopupMenu

var plugin: EditorPlugin
var scene: String
var custom_texture: String

signal request_icon(instance, ignore_cache)
signal changed

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
		set_icon(load(file))
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
	icon.texture = texture

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
	popup.add_item("Refresh Icon", MenuOption.REFRESH)
	if custom_texture:
		popup.add_item("Remove Custom Icon", MenuOption.CLEAR)
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
	
	if scene.empty():
		set_icon(null)
	elif custom_texture.empty():
		emit_signal("request_icon", scene, false)
	else:
		set_icon(load(custom_texture))
