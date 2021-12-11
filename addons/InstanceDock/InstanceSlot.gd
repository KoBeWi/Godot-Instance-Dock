tool
extends PanelContainer

enum MenuOption {EDIT, REMOVE, REFRESH, CLEAR}

onready var icon := $TextureRect
onready var popup := $PopupMenu

var plugin: EditorPlugin
var scene: String
var custom_texture: String

signal request_icon(instance, ignore_cache)
signal scene_set(path)
signal remove_scene

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
		set_texture(load(file))
	elif file.get_extension() == "tscn":
		var drag_texture: String
		if "from_slot" in data:
			var slot2: Control = data.from_slot
			drag_texture = slot2.custom_texture
			slot2.set_scene(scene, custom_texture)
		
		set_scene(file, drag_texture)
		emit_signal("scene_set", file)

func get_drag_data(position: Vector2):
	if not scene:
		return null
	
	return {files = [scene], type = "files", from_slot = self}

func set_scene(s: String, custom_icon: String):
	scene = s
	hint_tooltip = scene.get_file()
	
	custom_texture = custom_icon
	if scene.empty():
		set_texture(null)
	elif custom_texture.empty():
		emit_signal("request_icon", scene)
	else:
		set_texture(load(custom_texture))

func set_texture(texture: Texture):
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
		popup.add_item("Remove Icon", MenuOption.CLEAR)
	popup.rect_size = Vector2()

func menu_option(id: int) -> void:
	match id:
		MenuOption.EDIT:
			plugin.open_scene(scene)
		MenuOption.REMOVE:
			set_scene("", "")
			emit_signal("remove_scene")
		MenuOption.REFRESH:
			emit_signal("request_icon", scene, true)
		MenuOption.CLEAR:
			custom_texture = ""
			set_texture(null)
			emit_signal("request_icon", scene, true)
