@tool
extends PanelContainer

const InstanceDockPropertyEdit = preload("res://addons/InstanceDock/Scripts/InstancePropertyEdit.gd")
const InstanceDock = preload("res://addons/InstanceDock/Scripts/InstanceDock.gd")

enum MenuOption { EDIT, MODIFY, REMOVE, REFRESH, CLEAR, QUICK_LOAD }

@export var normal: StyleBox
@export var custom: StyleBox

@onready var icon: TextureRect = get_node_or_null(^"%Icon")
@onready var path_label: Label = get_node_or_null(^"%Path")

@onready var loading_icon: Sprite2D = %Loading
@onready var loading_animator: AnimationPlayer = %AnimationPlayer
@onready var timer: Timer = $Timer
@onready var has_overrides: TextureRect = $HasOverrides
@onready var text_label: Label = %Label
@onready var paint_button: Button = $PaintButton

var data: InstanceDock.Data.Instance
var popup: PopupMenu
var thread: Thread

var filter_cache: String

signal request_icon(instance, ignore_cache)
signal changed

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	if not thread.is_alive():
		thread.wait_to_finish()
		thread = null
		set_process(false)

func _can_drop_data(at_position: Vector2, drop_data) -> bool:
	if not drop_data is Dictionary or drop_data.get("type", "") != "files":
		return false
	
	if not "files" in drop_data or drop_data["files"].size() != 1:
		return false
	
	if drop_data["files"][0].get_extension() == "tscn" or drop_data["files"][0].get_extension() == "res":
		return true
	
	if is_texture(drop_data["files"][0]) and is_valid():
		return true
	
	return false

func _drop_data(at_position: Vector2, drop_data) -> void:
	var file: String = drop_data["files"][0]
	if is_texture(file) and is_valid():
		data.custom_texture = file
		apply_data()
		changed.emit()
	elif file.get_extension() == "tscn":
		if "from_slot" in drop_data:
			var slot2: Control = get_parent().get_child(drop_data["from_slot"])
			if slot2 == self:
				return
			
			var data2: InstanceDock.Data.Instance = slot2.data
			slot2.set_data(data)
			set_data(data2)
		else:
			set_scene(file)
		changed.emit()

func is_texture(file: String) -> bool:
	return ClassDB.is_parent_class(EditorInterface.get_resource_filesystem().get_file_type(file), &"Texture2D")

func _get_drag_data(position: Vector2):
	if not is_valid():
		return null
	return {"files": [get_scene()], "type": "files", "from_slot": get_index(), "instance_dock_overrides": data.overrides }

func set_icon(texture: Texture2D):
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = texture
	if texture and texture.get_width() <= icon.size.x:
		icon.texture_filter = TEXTURE_FILTER_NEAREST
	
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
	
	transparent_result.call_deferred(is_valid)

func transparent_result(is_valid: bool):
	icon.modulate.a = 1
	loading_icon.hide()
	loading_animator.stop()
	
	if not is_valid:
		set_icon(preload("res://addons/InstanceDock/Textures/Missing.png"))
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			create_popup()
			popup.popup()
			popup.position = get_screen_transform() * event.position
		elif event.double_click and event.button_index == MOUSE_BUTTON_LEFT and is_valid():
			menu_option(MenuOption.EDIT)

func create_popup():
	if not popup:
		popup = PopupMenu.new()
		popup.id_pressed.connect(menu_option)
		add_child(popup)
	
	popup.clear()
	
	if is_valid():
		popup.add_item("Open Scene", MenuOption.EDIT)
		popup.add_item("Override Properties", MenuOption.MODIFY)
		popup.add_item("Remove", MenuOption.REMOVE)
		if data.custom_texture:
			popup.add_item("Remove Custom Icon", MenuOption.CLEAR)
		else:
			popup.add_item("Refresh Icon", MenuOption.REFRESH)
	
	popup.add_item("Quick Load...", MenuOption.QUICK_LOAD)
	
	popup.reset_size()

func menu_option(id: int) -> void:
	match id:
		MenuOption.EDIT:
			EditorInterface.open_scene_from_path(data.scene)
		MenuOption.MODIFY:
			var editor := InstanceDockPropertyEdit.new()
			editor.instance = load(data.scene).instantiate()
			editor.overrides = data.overrides
			EditorInterface.inspect_object(editor, "", true)
			editor.changed.connect(timer.start)
		MenuOption.REMOVE:
			data = null
			unedit()
			apply_data()
			changed.emit()
		MenuOption.REFRESH:
			start_load()
			request_icon.emit(data.scene, true)
		MenuOption.CLEAR:
			data.custom_texture = ""
			apply_data()
			changed.emit()
		MenuOption.QUICK_LOAD:
			EditorInterface.popup_quick_open(func(scene: String):
				if not scene.is_empty():
					set_scene(scene)
					changed.emit()
				, ["PackedScene"])

func get_data() -> InstanceDock.Data.Instance:
	return data

func set_scene(scene: String):
	var uid := ResourceLoader.get_resource_uid(scene)
	if uid != ResourceUID.INVALID_ID:
		scene = ResourceUID.id_to_text(uid)
	
	data = InstanceDock.Data.Instance.new()
	data.scene = scene
	filter_cache = ""
	apply_data()

func set_data(p_data: InstanceDock.Data.Instance):
	data = p_data
	filter_cache = ""
	apply_data()

func set_text_label(vis : bool):
	text_label.visible = vis
	if path_label:
		path_label.visible = not vis

func apply_data():
	var text: PackedStringArray
	text.append(get_scene().get_file())
	text.append(get_scene().get_base_dir())
	
	if data and not data.overrides.is_empty():
		text.append("")
		text.append(tr("Overrides:"))
		for override in data.overrides:
			text.append("%s: %s" % [override, data.overrides[override]])
	tooltip_text = "\n".join(text)
	
	if path_label:
		path_label.text = get_scene().get_file()
	
	set_icon(null)
	set_text_label(false)
	add_theme_stylebox_override(&"panel", normal)
	
	if not is_valid():
		set_icon(null)
		set_text_label(true)
	elif data.custom_texture.is_empty():
		start_load()
		request_icon.emit(data.scene, false)
	else:
		set_icon(load(data.custom_texture))
		add_theme_stylebox_override(&"panel", custom)
	
	paint_button.disabled = not is_valid()
	has_overrides.visible = data != null and not data.overrides.is_empty()

func start_load():
	loading_animator.play(&"Rotate")
	loading_icon.show()

func _on_timer_timeout() -> void:
	has_overrides.visible = not data.overrides.is_empty()
	apply_data()
	menu_option(MenuOption.REFRESH)
	changed.emit()

func get_scene() -> String:
	if not data:
		return ""
	
	var path := data.scene
	if path.begins_with("uid://"):
		path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
	
	return path

func is_valid() -> bool:
	return data != null and not data.scene.is_empty()

func get_hash() -> int:
	if not data:
		return 0
	return str(data.scene, data.overrides).hash()

func setup_button(group: ButtonGroup):
	paint_button.button_group = group

func _exit_tree() -> void:
	unedit()
	if thread:
		thread.wait_to_finish()
		thread = null

func unedit():
	if EditorInterface.get_inspector().get_edited_object() is InstanceDockPropertyEdit:
		EditorInterface.edit_node(null)

func filter(text: String):
	if filter_cache.is_empty():
		filter_cache = get_scene().to_lower()
	
	visible = text.is_empty() or filter_cache.contains(text)
