@tool
extends Control

const PluginUtils = preload("res://addons/InstanceDock/PluginUtils.gd")
const PROJECT_SETTING_CONFIG = "addons/instance_dock/scene_data_file"
const PROJECT_SETTING_LEGACY = "addons/instance_dock/scenes"
const PROJECT_SETTING_PREVIEW = "addons/instance_dock/preview_resolution"
var PREVIEW_SIZE = Vector2i(64, 64)
var CONFIG_FILE = "res://InstanceDockSceneData.txt"

enum {SLOT_MODE_ICONS, SLOT_MODE_TEXT}

class Data:
	class Instance:
		var scene: String
		var custom_texture: String
		var overrides: Dictionary[StringName, Variant]
	
	class Tab:
		var name: String
		var instances: Array[Instance]
	
	var version: int
	var tab_data: Array[Tab]
	
	func load_data(loaded):
		var dict: Dictionary
		if loaded is Dictionary:
			dict = loaded
		else:
			dict = {"tab_data": loaded}
		
		version = dict.get("version", -1)
		
		for tab_dict: Dictionary in dict["tab_data"]:
			var tab := Data.Tab.new()
			tab_data.append(tab)
			tab.name = tab_dict.get("name", "")
			
			for dict_instance: Dictionary in tab_dict.get("scenes", []):
				var instance := Data.Instance.new()
				tab.instances.append(instance)
				
				instance.scene = dict_instance.get("scene", "")
				if version == -1:
					var uid := ResourceLoader.get_resource_uid(instance.scene)
					if uid != ResourceUID.INVALID_ID:
						instance.scene = ResourceUID.id_to_text(uid)
				
				instance.custom_texture = dict_instance.get("custom_texture", "")
				if version == -1:
					var uid := ResourceLoader.get_resource_uid(instance.custom_texture)
					if uid != ResourceUID.INVALID_ID:
						instance.custom_texture = ResourceUID.id_to_text(uid)
				
				instance.overrides.assign(dict_instance.get("overrides", {}))
		
		version = 0
	
	func save_data() -> Dictionary:
		var data: Dictionary
		
		data["version"] = version
		
		var save_tabs: Array
		data["tab_data"] = save_tabs
		
		for tab in tab_data:
			var tab_dict: Dictionary
			save_tabs.append(tab_dict)
			tab_dict["name"] = tab.name
			
			var instances: Array
			for instance in tab.instances:
				var instance_dict: Dictionary
				instances.append(instance_dict)
				
				if instance:
					instance_dict["scene"] = instance.scene
					if not instance.custom_texture.is_empty():
						instance_dict["custom_texture"] = instance.custom_texture
					if not instance.overrides.is_empty():
						var untyped: Dictionary
						untyped.assign(instance.overrides)
						instance_dict["overrides"] = untyped
				
				if not instances.is_empty():
					tab_dict["scenes"] = instances
		
		return data

class ProcessedItem:
	var icon_path: String
	var icon: Texture2D
	var instance_path: String
	var instance: Node
	var slot: Control
	var overrides: Dictionary[StringName, Variant]

@onready var tabs: TabBar = %Tabs
@onready var tab_add_confirm := %AddTabConfirm
@onready var tab_add_name := %AddTabName
@onready var tab_delete_confirm := %DeleteConfirm
@onready var filter_line_edit: LineEdit = %FilterLineEdit
@onready var view_menu: MenuButton = %ViewMenu

@onready var scroll := %ScrollContainer
@onready var add_tab_label := %AddTabLabel
@onready var drag_label := %DragLabel

@onready var extras_toggle: Button = %ExtrasToggle
@onready var extras: VBoxContainer = %Extras
@onready var parent_selector: HBoxContainer = %ParentSelector
@onready var parent_icon: TextureRect = %ParentIcon
@onready var parent_name: LineEdit = %ParentName
@onready var paint_mode: VBoxContainer = %PaintMode

@onready var icon_generator := $Viewport

var slot_container: Node
var slot_scene: PackedScene

var data: Data
var initialized: int

var icon_cache: Dictionary
var previous_tab: int
var current_slot_mode: int = -1

var tab_to_remove := -1
var icon_queue: Array[ProcessedItem]
var icon_progress: int
var current_processed_item: ProcessedItem

var default_parent: Node

var plugin: EditorPlugin

func _ready() -> void:
	set_process(false)
	if is_part_of_edited_scene():
		return
	
	var popup := view_menu.get_popup()
	popup.add_radio_check_item("Icons", SLOT_MODE_ICONS)
	popup.add_radio_check_item("Text", SLOT_MODE_TEXT)
	popup.set_item_checked(0, true)
	set_slot_mode(SLOT_MODE_ICONS)
	popup.id_pressed.connect(on_menu_option)
	
	DirAccess.make_dir_recursive_absolute(".godot/InstanceIconCache")
	if ProjectSettings.has_setting(PROJECT_SETTING_LEGACY):
		data = ProjectSettings.get_setting(PROJECT_SETTING_LEGACY)
		for tab in data:
			tab.erase("scroll")
		ProjectSettings.set_setting(PROJECT_SETTING_LEGACY, null)
	
	CONFIG_FILE = PluginUtils.define_project_setting(PROJECT_SETTING_CONFIG, CONFIG_FILE, PROPERTY_HINT_SAVE_FILE)
	load_data()
	
	PREVIEW_SIZE = PluginUtils.define_project_setting(PROJECT_SETTING_PREVIEW, PREVIEW_SIZE)
	icon_generator.size = PREVIEW_SIZE
	
	PluginUtils.track_project_setting(PROJECT_SETTING_CONFIG, self, _project_setting_changed)
	PluginUtils.track_project_setting(PROJECT_SETTING_PREVIEW, self, _project_setting_changed)
	
	for tab in data.tab_data:
		tabs.add_tab(tab.name)
	
	plugin.scene_changed.connect(on_scene_changed.unbind(1))
	
	extras.hide()
	parent_selector.set_drag_forwarding(Callable(), _can_drop_node, _drop_node)

func load_data():
	data = Data.new()
	
	var file := FileAccess.open(CONFIG_FILE, FileAccess.READ)
	if not file:
		#push_error("Failed loading Instance Dock scene data. Error loading file: %d." % FileAccess.get_open_error())
		return
	
	var loaded = str_to_var(file.get_as_text())
	if not loaded is Array and not loaded is Dictionary: # compat
		push_error("Failed loading Instance Dock scene data. File contains invalid data.")
		return
	
	data.load_data(loaded)

func save_data():
	var file := FileAccess.open(CONFIG_FILE, FileAccess.WRITE)
	if not file:
		push_error("Failed saving Instance Dock scene data. Error writing file: %d." % FileAccess.get_open_error())
		return
	
	file.store_string(var_to_str(data.save_data()))

func _project_setting_changed(setting: String, new_value: Variant):
	if setting == PROJECT_SETTING_PREVIEW:
		PREVIEW_SIZE = new_value
		icon_generator.size = PREVIEW_SIZE
	
	elif setting == PROJECT_SETTING_CONFIG:
		if FileAccess.file_exists(CONFIG_FILE):
			DirAccess.rename_absolute(CONFIG_FILE, new_value)
		CONFIG_FILE = new_value

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var drag_data = get_viewport().gui_get_drag_data()
		if drag_data is Dictionary and "instance_dock_overrides" in drag_data:
			get_tree().node_added.connect(node_added)
	elif what == NOTIFICATION_DRAG_END:
		if get_tree().node_added.is_connected(node_added):
			get_tree().node_added.disconnect(node_added)
	
	if initialized == 2:
		return
	
	if what == NOTIFICATION_ENTER_TREE:
		initialized = 1
	
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree() and slot_container != null and initialized == 1:
			refresh_tab_contents()
			initialized = 2

func node_added(node: Node):
	var scene := plugin.get_editor_interface().get_edited_scene_root()
	if not scene or not scene.is_ancestor_of(node):
		return
	
	var drag_data = get_viewport().gui_get_drag_data()
	if not "files" in drag_data or not node.scene_file_path in drag_data["files"]:
		return
	
	var overrides: Dictionary = drag_data["instance_dock_overrides"]
	for override in overrides:
		node.set(override, overrides[override])
	
	if node.get_parent() == EditorInterface.get_edited_scene_root():
		var parent := get_default_parent()
		
		if parent and node.get_parent() != parent:
			do_reparent.call_deferred(node, parent)

func do_reparent(node: Node, to: Node):
	var undo_redo := plugin.get_undo_redo()
	undo_redo.create_action("InstanceDock reparent node")
	undo_redo.add_do_method(node, &"reparent", to)
	undo_redo.add_do_method(node, &"set_owner", node.owner)
	undo_redo.add_do_method(node, &"set_name", node.name)
	undo_redo.add_undo_method(node, &"reparent", node.get_parent())
	undo_redo.add_undo_method(node, &"set_owner", node.owner)
	undo_redo.add_undo_method(node, &"set_name", node.name)
	undo_redo.commit_action()

func on_add_tab_pressed() -> void:
	tab_add_name.text = "" # NO_TRANSLATE
	tab_add_confirm.reset_size()
	tab_add_confirm.popup_centered()
	tab_add_name.grab_focus.call_deferred()

func add_tab_confirm(q = null) -> void:
	if q != null:
		tab_add_confirm.hide()
	
	tabs.add_tab(tab_add_name.text)
	var new_tab := Data.Tab.new()
	new_tab.name = tab_add_name.text
	data.tab_data.append(new_tab)
	save_data()
	
	if data.tab_data.size() == 1:
		refresh_tab_contents()

func on_tab_close_attempt(tab: int) -> void:
	tab_to_remove = tab
	tab_delete_confirm.popup_centered()

func remove_tab_confirm() -> void:
	if tab_to_remove != tabs.current_tab:
		tab_to_remove = -1
	data.tab_data.remove_at(tab_to_remove)
	tabs.remove_tab(tab_to_remove)
	save_data()
	
	if tabs.tab_count == 0:
		refresh_tab_contents()

func on_tab_changed(tab: int) -> void:
	if tab_to_remove == -1 and data.tab_data.size() > 0:
		tabs.set_tab_metadata(previous_tab, scroll.scroll_vertical)
	tab_to_remove = -1
	previous_tab = tab
	
	if initialized == 2:
		icon_queue.clear()
		current_processed_item = null
		set_process(false)
		
		refresh_tab_contents()

func refresh_tab_contents():
	for c in slot_container.get_children():
		c.free()
	
	if tabs.tab_count == 0:
		slot_container.hide()
		add_tab_label.show()
		drag_label.hide()
		filter_line_edit.clear()
		filter_line_edit.editable = false
		return
	else:
		slot_container.show()
		add_tab_label.hide()
		drag_label.show()
		filter_line_edit.editable = true
	
	if data.tab_data.size() > 0:
		var tab_data := data.tab_data[tabs.current_tab]
		var scenes := tab_data.instances
		
		adjust_slot_count()
		for i in slot_container.get_child_count():
			if i < scenes.size():
				slot_container.get_child(i).set_data(scenes[i])
			else:
				slot_container.get_child(i).set_data(Data.Instance.new())
		
		var scroll_value = tabs.get_tab_metadata(tabs.current_tab)
		await get_tree().process_frame
		if scroll_value is int:
			scroll.scroll_vertical = scroll_value
	
	if not filter_line_edit.text.is_empty():
		_on_filter_changed(filter_line_edit.text)
	
	if paint_mode.enabled:
		paint_mode.set_paint_mode_enabled(true)

func remove_scene(slot: int):
	var tab_scenes := data.tab_data[tabs.current_tab].instances
	tab_scenes[slot] = Data.Instance.new()
	while not tab_scenes.is_empty() and tab_scenes.back().is_empty():
		tab_scenes.pop_back()

func _process(delta: float) -> void:
	if icon_queue.is_empty() and not current_processed_item:
		set_process(false)
		return
	
	if not current_processed_item:
		get_item_from_queue()
	
	var slot := current_processed_item.slot
	if current_processed_item.icon:
		icon_cache[slot.get_hash()] = current_processed_item.icon
		slot.set_icon(current_processed_item.icon)
		get_item_from_queue()
		return
	
	var instance := current_processed_item.instance
	var overrides := current_processed_item.overrides
	for override in overrides:
		instance.set(override, overrides[override])
	
	while not is_instance_valid(slot):
		icon_progress = 0
		instance.free()
		get_item_from_queue()
		
		if not current_processed_item:
			return
		else:
			instance = current_processed_item.instance
			slot = current_processed_item.slot
	
	match icon_progress:
		0:
			icon_generator.add_child(instance)
			if instance is Node2D:
				instance.position = PREVIEW_SIZE / 2
		3:
			var image = icon_generator.get_texture().get_image()
			image.save_png(".godot/InstanceIconCache/%s.png" % slot.get_hash())
			var texture = ImageTexture.create_from_image(image)
			slot.set_icon(texture)
			icon_cache[slot.get_hash()] = texture
			instance.free()
			
			icon_progress = -1
			get_item_from_queue()
	
	icon_progress += 1

func get_item_from_queue():
	if icon_queue.is_empty():
		current_processed_item = null
		return
	
	current_processed_item = icon_queue.pop_front()
	if not current_processed_item.icon_path.is_empty():
		var texture := ImageTexture.create_from_image(Image.load_from_file(current_processed_item.icon_path))
		current_processed_item.icon = texture
	else:
		current_processed_item.instance = load(current_processed_item.instance_path).instantiate()
		current_processed_item.overrides = current_processed_item.slot.data.overrides

func assign_icon(scene_path: String, ignore_cache: bool, slot: Control):
	if not ignore_cache:
		var hash: int = slot.get_hash()
		var icon := icon_cache.get(hash) as Texture2D
		if icon:
			slot.set_icon(icon)
			return
		else:
			var cache_path := ".godot/InstanceIconCache/%s.png" % hash
			if FileAccess.file_exists(cache_path):
				var queued := ProcessedItem.new()
				queued.icon_path = cache_path
				queued.slot = slot
				icon_queue.append(queued)
				set_process(true)
				return
	generate_icon(scene_path, slot)

func generate_icon(scene_path: String, slot: Control):
	var queued := ProcessedItem.new()
	queued.instance_path = scene_path
	queued.slot = slot
	icon_queue.append(queued)
	set_process(true)

func add_slot() -> Control:
	var slot: Control = slot_scene.instantiate()
	slot_container.add_child(slot)
	slot.setup_button(paint_mode.buttons)
	slot.request_icon.connect(assign_icon.bind(slot))
	slot.changed.connect(recreate_tab_data, CONNECT_DEFERRED)
	return slot

func recreate_tab_data():
	var tab_scenes := data.tab_data[tabs.current_tab].instances
	tab_scenes.clear()
	
	for slot in slot_container.get_children():
		tab_scenes.append(slot.get_data())
	
	while not tab_scenes.is_empty() and (not tab_scenes.back() or tab_scenes.back().scene.is_empty()):
		tab_scenes.pop_back()
	
	save_data()
	adjust_slot_count()

func adjust_slot_count():
	var tab_scenes := data.tab_data[tabs.current_tab].instances
	var desired_slots := tab_scenes.size() + 1
	
	while desired_slots > slot_container.get_child_count():
		add_slot()
	
	while desired_slots < slot_container.get_child_count():
		slot_container.get_child(slot_container.get_child_count() - 1).free()

func on_rearrange(idx_to: int) -> void:
	var old_data := data.tab_data[previous_tab]
	data.tab_data[previous_tab] = data.tab_data[idx_to]
	data.tab_data[idx_to] = old_data
	previous_tab = idx_to
	save_data()

func toggle_extras() -> void:
	extras.visible = not extras.visible
	if extras.visible:
		extras_toggle.icon = preload("res://addons/InstanceDock/Textures/Collapse.svg")
	else:
		extras_toggle.icon = preload("res://addons/InstanceDock/Textures/Uncollapse.svg")

func set_default_parent(node: Node):
	if default_parent == node and not (default_parent and not node):
		return
	
	default_parent = node
	if node:
		parent_icon.show()
		parent_icon.texture = get_theme_icon(node.get_class(), &"EditorIcons")
		parent_name.text = node.name
		parent_selector.tooltip_text = EditorInterface.get_edited_scene_root().get_path_to(node)
	else:
		parent_icon.hide()
		parent_name.text = "" # NO_TRANSLATE
		parent_selector.tooltip_text = "" # NO_TRANSLATE

func get_default_parent() -> Node:
	var parent := default_parent
	if is_instance_valid(parent):
		if not parent.is_inside_tree():
			set_default_parent(null)
		else:
			return parent
	elif parent:
		set_default_parent(null)
	return null

func set_slot_mode(new_slot_mode: int):
	if new_slot_mode == current_slot_mode:
		return
	
	if slot_container:
		for child in slot_container.get_children():
			child.free()
	
	current_slot_mode = new_slot_mode
	if current_slot_mode == SLOT_MODE_TEXT:
		slot_container = %TextSlots
		slot_scene = preload("res://addons/InstanceDock/Scenes/InstanceSlotText.tscn")
	else:
		slot_container = %IconSlots
		slot_scene = preload("res://addons/InstanceDock/Scenes/InstanceSlot.tscn")
	
	refresh_tab_contents()

func on_menu_option(id: int):
	var popup := view_menu.get_popup()
	if id == SLOT_MODE_ICONS or id == SLOT_MODE_TEXT:
		popup.set_item_checked(0, id == SLOT_MODE_ICONS)
		popup.set_item_checked(1, id == SLOT_MODE_TEXT)
		set_slot_mode(id)

func on_scene_changed():
	set_default_parent(null)

func _can_drop_node(at: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	
	if not data.get("type", "") == "nodes":
		return false
	
	if not "nodes" in data or not data["nodes"] is Array:
		return false
	
	if data["nodes"].size() != 1 or not data["nodes"][0] is NodePath:
		return false
	
	return true

func _drop_node(at: Vector2, data: Variant):
	var node: Node = get_tree().root.get_node_or_null(data["nodes"][0])
	if not node:
		return
	
	set_default_parent(node)

func _on_filter_changed(new_text: String) -> void:
	for slot in slot_container.get_children():
		slot.filter(new_text)
	
	drag_label.visible = new_text.is_empty()
