@tool
extends PanelContainer

const PROJECT_SETTING = "addons/instance_dock/scenes"
const PREVIEW_SIZE = Vector2i(64, 64)

@onready var tabs := %Tabs
@onready var tab_add_confirm := %AddTabConfirm
@onready var tab_add_name := %AddTabName
@onready var tab_delete_confirm := %DeleteConfirm

@onready var scroll := %ScrollContainer
@onready var slot_container := %Slots
@onready var add_tab_label := %AddTabLabel
@onready var drag_label := %DragLabel

@onready var icon_generator := $Viewport

var data: Array
var initialized: int

var icon_cache: Dictionary
var previous_tab: int

var tab_to_remove: int
var icon_queue: Array[Dictionary]
var icon_progress: int
var current_processed_item: Dictionary

var plugin: EditorPlugin

func _ready() -> void:
	set_process(false)
	DirAccess.make_dir_recursive_absolute(".godot/InstanceIconCache")
	
	if plugin:
		icon_generator.size = PREVIEW_SIZE
		
		if ProjectSettings.has_setting(PROJECT_SETTING):
			data = ProjectSettings.get_setting(PROJECT_SETTING)
		else:
			ProjectSettings.set_setting(PROJECT_SETTING, data)
		
		for tab in data:
			tabs.add_tab(tab.name)

func _notification(what: int) -> void:
	if initialized == 2:
		return
	
	if what == NOTIFICATION_ENTER_TREE:
		initialized = 1
	
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree() and slot_container != null and initialized == 1:
			refresh_tab_contents()
			initialized = 2

func on_add_tab_pressed() -> void:
	tab_add_name.text = ""
	tab_add_confirm.popup_centered()
	tab_add_name.grab_focus.call_deferred()

func add_tab_confirm(q = null) -> void:
	if q != null:
		tab_add_confirm.hide()
	
	tabs.add_tab(tab_add_name.text)
	data.append({name = tab_add_name.text, scenes = [], scroll = 0})
	ProjectSettings.save()
	
	if data.size() == 1:
		refresh_tab_contents()

func on_tab_close_attempt(tab: int) -> void:
	tab_to_remove = tab
	tab_delete_confirm.popup_centered()

func remove_tab_confirm() -> void:
	if tab_to_remove == tabs.current_tab or tabs.get_tab_count() == 1:
		refresh_tab_contents.call_deferred()
	
	remove_scene(tab_to_remove)
	ProjectSettings.save()

func on_tab_changed(tab: int) -> void:
	data[previous_tab].scroll = scroll.scroll_vertical
	previous_tab = tab
	
	if initialized == 2:
		refresh_tab_contents()

func refresh_tab_contents():
	for c in slot_container.get_children():
		c.free()
	
	if tabs.get_tab_count() == 0:
		slot_container.hide()
		add_tab_label.show()
		drag_label.hide()
		return
	else:
		slot_container.show()
		add_tab_label.hide()
		drag_label.show()
	
	var tab_data: Dictionary = data[tabs.current_tab]
	var scenes: Array = tab_data.scenes
	
	adjust_slot_count()
	for i in slot_container.get_child_count():
		if i < scenes.size() and not scenes[i].is_empty():
			slot_container.get_child(i).set_data(scenes[i])
		else:
			slot_container.get_child(i).set_data({})
	
	scroll.scroll_vertical = tab_data.scroll

func remove_scene(slot: int):
	var tab_scenes: Array = data[tabs.current_tab].scenes
	tab_scenes[slot] = {}
	while not tab_scenes.is_empty() and tab_scenes.back().is_empty():
		tab_scenes.pop_back()

func _process(delta: float) -> void:
	if icon_queue.is_empty() and current_processed_item.is_empty():
		set_process(false)
		return
	
	if current_processed_item.is_empty():
		get_item_from_queue()
	
	var slot = current_processed_item.slot
	
	if "png" in current_processed_item:
		icon_cache[slot.scene] = current_processed_item.png
		slot.set_icon(current_processed_item.png)
		get_item_from_queue()
		return
	
	var instance: Node = current_processed_item.instance
	
	while not is_instance_valid(slot):
		icon_progress = 0
		instance.free()
		get_item_from_queue()
		
		if current_processed_item.is_empty():
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
			image.save_png(".godot/InstanceIconCache/%s.png" % slot.scene.hash())
			var texture = ImageTexture.create_from_image(image)
			slot.set_icon(texture)
			icon_cache[slot.scene] = texture
			instance.free()
			
			icon_progress = -1
			get_item_from_queue()
	
	icon_progress += 1

func get_item_from_queue():
	if icon_queue.is_empty():
		current_processed_item = {}
		return
	
	current_processed_item = icon_queue.pop_front()
	if "png" in current_processed_item:
		var texture := ImageTexture.create_from_image(Image.load_from_file(current_processed_item.png))
		current_processed_item.png = texture
	else:
		current_processed_item.instance = load(current_processed_item.scene).instantiate()

func assign_icon(scene_path: String, ignore_cache: bool, slot: Control):
	if not ignore_cache:
		var icon := icon_cache.get(scene_path) as Texture2D
		if icon:
			slot.set_icon(icon)
			return
		else:
			var hash := scene_path.hash()
			if FileAccess.file_exists(".godot/InstanceIconCache/%s.png" % hash):
				icon_queue.append({png = ".godot/InstanceIconCache/%s.png" % hash, slot = slot})
				set_process(true)
				return
	generate_icon(scene_path, slot)

func generate_icon(scene_path: String, slot: Control):
	icon_queue.append({scene = scene_path, slot = slot})
	set_process(true)

func add_slot() -> Control:
	var slot = preload("res://addons/InstanceDock/InstanceSlot.tscn").instantiate()
	slot.plugin = plugin
	slot_container.add_child(slot)
	slot.request_icon.connect(assign_icon.bind(slot))
	slot.changed.connect(recreate_tab_data, CONNECT_DEFERRED)
	return slot

func recreate_tab_data():
	var tab_scenes: Array = data[tabs.current_tab].scenes
	tab_scenes.clear()
	
	for slot in slot_container.get_children():
		tab_scenes.append(slot.get_data())
	
	while not tab_scenes.is_empty() and tab_scenes.back().is_empty():
		tab_scenes.pop_back()
	
	ProjectSettings.save()
	adjust_slot_count()

func adjust_slot_count():
	var tab_scenes: Array[Dictionary]
	tab_scenes.assign(data[tabs.current_tab].scenes)
	var desired_slots := tab_scenes.size() + 1
	
	while desired_slots > slot_container.get_child_count():
		add_slot()
	
	while desired_slots < slot_container.get_child_count():
		slot_container.get_child(slot_container.get_child_count() - 1).free()
