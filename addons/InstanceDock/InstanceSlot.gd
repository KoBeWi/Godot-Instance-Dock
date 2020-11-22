tool
extends PanelContainer

enum MENU_OPTION {EDIT, REMOVE, REFRESH}

onready var icon := $TextureRect
onready var popup := $PopupMenu

var plugin: EditorPlugin
var scene: String

signal request_icon(instance)
signal scene_set(path)
signal remove_scene

func can_drop_data(position: Vector2, data) -> bool:
	if not "type" in data:
		return false
	
	if data.type != "files":
		return false
	
	if data.files.size() != 1:
		return false
	
	return data.files[0].get_extension() == "tscn"

func drop_data(position: Vector2, data) -> void:
	var file = data.files[0]
	set_scene(file)
	
	var instance = load(file).instance()
	emit_signal("request_icon", instance)
	emit_signal("scene_set", file)

func get_drag_data(position: Vector2):
	return {files = [scene], type = "files"}

func set_scene(s: String):
	scene = s
	hint_tooltip = scene.get_file()

func set_texture(texture: Texture):
	icon.texture = texture

func _gui_input(event: InputEvent) -> void:
	if not scene:
		return
	
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == BUTTON_RIGHT:
			popup.popup()
			popup.rect_global_position = event.global_position

func menu_option(id: int) -> void:
	match id:
		MENU_OPTION.EDIT:
			plugin.open_scene(scene)
		MENU_OPTION.REMOVE:
			icon.texture = null
			scene = ""
			hint_tooltip = ""
			emit_signal("remove_scene")
		MENU_OPTION.REFRESH:
			emit_signal("request_icon", load(scene).instance())
