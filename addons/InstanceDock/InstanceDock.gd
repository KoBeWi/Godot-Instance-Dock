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
var initialized: bool

var icon_cache: Dictionary
var previous_tab: int

var tab_to_remove: int
var icon_queue: Array
var icon_progress: int

var plugin: EditorPlugin

func _ready() -> void:
	set_process(false)
	
	if plugin:
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
		if is_visible_in_tree() and slot_container != null:
			refresh_tab_contents()
			initialized = true

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
	if icon_queue.is_empty():
		set_process(false)
		return
	
	var instance: Node = icon_queue.front()[0]
	var slot: Control = icon_queue.front()[1]
	
	while not is_instance_valid(slot):
		icon_progress = 0
		icon_queue.pop_front()
		instance.free()
		
		if icon_queue.is_empty():
			return
		else:
			instance = icon_queue.front()[0]
			slot = icon_queue.front()[1]
	
	match icon_progress:
		0:
			icon_generator.add_child(instance)
			if instance is Node2D:
				instance.position = PREVIEW_SIZE / 2
		3:
			var texture = ImageTexture.create_from_image(icon_generator.get_texture().get_image())
			slot.set_icon(texture)
			icon_cache[slot.scene] = texture
			instance.free()
			
			icon_progress = -1
			icon_queue.pop_front()
	
	icon_progress += 1

func assign_icon(scene_path: String, ignore_cache: bool, slot: Control):
	if not ignore_cache:
		var icon := icon_cache.get(scene_path, null) as Texture2D
		if icon:
			slot.set_icon(icon)
			return
	generate_icon(scene_path, slot)

func generate_icon(scene_path: String, slot: Control):
	var instance: Node = load(scene_path).instantiate()
	icon_queue.append([instance, slot])
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
	var tab_scenes: Array[Dictionary] = data[tabs.current_tab].scenes
	var desired_slots := tab_scenes.size() + 1
	
	while desired_slots > slot_container.get_child_count():
		add_slot()
	
	while desired_slots < slot_container.get_child_count():
		slot_container.get_child(slot_container.get_child_count() - 1).free()
