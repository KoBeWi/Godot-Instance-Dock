tool
extends PanelContainer
var edited := true

const PROJECT_SETTING = "addons/instance_dock/scenes"
const PREVIEW_SIZE = Vector2(64, 64)

onready var tabs := $VBoxContainer/HBoxContainer/Tabs as Tabs
onready var tab_add_confirm := $Control/ConfirmationDialog2
onready var tab_add_name := tab_add_confirm.get_node("LineEdit")
onready var tab_delete_confirm := $Control/ConfirmationDialog

onready var scroll := $VBoxContainer/ScrollContainer
onready var slot_container := $VBoxContainer/ScrollContainer/VBoxContainer/GridContainer
onready var add_tab_label := $VBoxContainer/ScrollContainer/VBoxContainer/Label
onready var drag_label := $VBoxContainer/ScrollContainer/VBoxContainer/Label2

onready var icon_generator := $Viewport

var data: Array
var initialized: bool

var icon_cache: Dictionary
var previous_tab: int

var tab_to_remove: int
var icon_queue: Array
var icon_progress: int

var plugin: EditorPlugin

func _ready() -> void:
	set_process(false)
	
	if not edited:
		icon_generator.size = PREVIEW_SIZE
		
		if ProjectSettings.has_setting(PROJECT_SETTING):
			data = ProjectSettings.get_setting(PROJECT_SETTING)
		else:
			ProjectSettings.set_setting(PROJECT_SETTING, data)
		
		for tab in data:
			tabs.add_tab(tab.name)

func _notification(what: int) -> void:
	if initialized:
		return
	
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			refresh_tab_contents()
			initialized = true

func on_add_tab_pressed() -> void:
	tab_add_name.text = ""
	tab_add_confirm.popup_centered_minsize()
	tab_add_name.call_deferred("grab_focus")

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
	tab_delete_confirm.popup_centered_minsize()

func remove_tab_confirm() -> void:
	if tab_to_remove == tabs.current_tab or tabs.get_tab_count() == 1:
		call_deferred("refresh_tab_contents")
	
	tabs.remove_tab(tab_to_remove)
	data.remove(tab_to_remove)
	ProjectSettings.save()

func on_tab_changed(tab: int) -> void:
	data[previous_tab].scroll = scroll.scroll_vertical
	previous_tab = tab
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
		if i < scenes.size() and not scenes[i].empty():
			slot_container.get_child(i).set_data(scenes[i])
		else:
			slot_container.get_child(i).set_data({})
	
	scroll.scroll_vertical = tab_data.scroll

func scene_set(scene: String, slot: int):
	var tab_scenes: Array = data[tabs.current_tab].scenes
	if tab_scenes.size() <= slot:
		var prev_size := tab_scenes.size()
		tab_scenes.resize(slot + 1)
		for i in range(prev_size, slot + 1):
			tab_scenes[i] = {}
	
	tab_scenes[slot] = {name = scene}
	ProjectSettings.save()
	adjust_slot_count()

func remove_scene(slot: int):
	var tab_scenes: Array = data[tabs.current_tab].scenes
	tab_scenes[slot] = {}
	while not tab_scenes.empty() and tab_scenes.back().empty():
		tab_scenes.pop_back()

func _process(delta: float) -> void:
	if icon_queue.empty():
		set_process(false)
		return
	
	var instance: Node = icon_queue.front()[0]
	var slot: Control = icon_queue.front()[1]
	
	while not is_instance_valid(slot):
		icon_progress = 0
		icon_queue.pop_front()
		instance.free()
		
		if icon_queue.empty():
			return
		else:
			instance = icon_queue.front()[0]
			slot = icon_queue.front()[1]
	
	match icon_progress:
		0:
			icon_generator.add_child(instance)
			if instance is Node2D:
				instance.position = PREVIEW_SIZE * 0.5
		3:
			var texture = ImageTexture.new()
			texture.create_from_image(icon_generator.get_texture().get_data())
			slot.set_icon(texture)
			icon_cache[slot.scene] = texture
			instance.free()
			
			icon_progress = -1
			icon_queue.pop_front()
	
	icon_progress += 1

func assign_icon(scene_path: String, ignore_cache: bool, slot: Control):
	if not ignore_cache:
		var icon := icon_cache.get(scene_path, null) as Texture
		if icon:
			slot.set_icon(icon)
			return
	generate_icon(scene_path, slot)

func generate_icon(scene_path: String, slot: Control):
	var instance: Node = load(scene_path).instance()
	icon_queue.append([instance, slot])
	set_process(true)

func add_slot() -> Control:
	var slot = preload("res://addons/InstanceDock/InstanceSlot.tscn").instance()
	slot.plugin = plugin
	slot_container.add_child(slot)
	slot.connect("request_icon", self, "assign_icon", [slot])
	slot.connect("changed", self, "recreate_tab_data")
	return slot

func recreate_tab_data():
	var tab_scenes: Array = data[tabs.current_tab].scenes
	tab_scenes.clear()
	
	for slot in slot_container.get_children():
		tab_scenes.append(slot.get_data())
	
	while not tab_scenes.empty() and tab_scenes.back().empty():
		tab_scenes.pop_back()
	
	ProjectSettings.save()
	adjust_slot_count()

func adjust_slot_count():
	var tab_scenes: Array = data[tabs.current_tab].scenes
	var desired_slots: int = ceil((tab_scenes.size() + 1) / 5.0) * 5
	
	while desired_slots > slot_container.get_child_count():
		add_slot()
	
	while desired_slots < slot_container.get_child_count():
		slot_container.get_child(slot_container.get_child_count() - 1).free()
