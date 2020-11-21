tool
extends PanelContainer
var edited := true

const PROJECT_SETTING = "addons/instance_dock/scenes"

onready var tabs := $ScrollContainer/VBoxContainer/HBoxContainer/Tabs
onready var tab_add_confirm := $Control/ConfirmationDialog2
onready var tab_add_name := tab_add_confirm.get_node("LineEdit")
onready var tab_delete_confirm := $Control/ConfirmationDialog

onready var slot_container := $ScrollContainer/VBoxContainer/GridContainer
onready var add_tab_label := $ScrollContainer/VBoxContainer/Label
onready var drag_label := $ScrollContainer/VBoxContainer/Label2

onready var icon_generator := $Viewport

var scenes: Dictionary
var icon_cache: Dictionary

var tab_to_remove: int
var icon_generator_free := true

signal icon_generated

func _ready() -> void:
	if not edited:
		if ProjectSettings.has_setting(PROJECT_SETTING):
			scenes = ProjectSettings.get_setting(PROJECT_SETTING)
		else:
			ProjectSettings.set_setting(PROJECT_SETTING, scenes)
		
		for key in scenes:
			tabs.add_tab(key)
		
		refresh_tabs()

func add_tab_pressed() -> void:
	tab_add_name.text = ""
	tab_add_confirm.popup_centered()

func add_tab_confirm() -> void:
	tabs.add_tab(tab_add_name.text)
	scenes[tab_add_name.text] = []
	refresh_tabs()

func tab_close_attempt(tab: int) -> void:
	tab_to_remove = tab
	tab_delete_confirm.popup_centered()

func remove_tab_confirm() -> void:
	tabs.remove_tab(tab_to_remove)
	scenes.erase(scenes.keys()[tab_to_remove])
	refresh_tabs()

func on_tab_changed(tab: int) -> void:
	refresh_tabs()

func refresh_tabs():
	for c in slot_container.get_children():
		c.queue_free()
	
	if tabs.get_tab_count() == 0:
		slot_container.hide()
		add_tab_label.show()
		drag_label.hide()
		return
	else:
		slot_container.show()
		add_tab_label.hide()
		drag_label.show()
	
	var tab_scenes = scenes[scenes.keys()[tabs.current_tab]]
	
	for i in ceil((tab_scenes.size() + 1) / 5.0) * 5:
		var slot = add_slot(i)
		
		if i < tab_scenes.size() and tab_scenes[i]:
			slot.set_scene(tab_scenes[i])
			
			var icon = icon_cache.get(tab_scenes[i], null)
			if icon:
				slot.set_texture(icon)
			else:
				var instance = load(tab_scenes[i]).instance()
				generate_icon(instance as Node2D, slot)

func scene_set(scene: String, slot: int):
	var tab_scenes = scenes[scenes.keys()[tabs.current_tab]]
	if tab_scenes.size() <= slot:
		tab_scenes.resize(slot + 1)
	
	tab_scenes[slot] = scene
	
	if slot == slot_container.get_child_count() - 1:
		for i in 5:
			var sloti = preload("res://addons/InstanceDock/InstanceSlot.tscn").instance()
			slot_container.add_child(sloti)
			sloti.connect("scene_set", self, "scene_set", [slot + i + 1])

func generate_icon(instance: Node2D, slot: Control):
	if not instance:
		return
	
	while not icon_generator_free:
		yield(self, "icon_generated")
	
	icon_generator_free = false
	
	icon_generator.add_child(instance)
	instance.position = Vector2(32, 32)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	
	var texture = ImageTexture.new()
	texture.create_from_image(icon_generator.get_texture().get_data())
	slot.set_texture(texture)
	instance.free()
	
	icon_generator_free = true
	emit_signal("icon_generated")

func add_slot(scene_id: int) -> Control:
	var slot = preload("res://addons/InstanceDock/InstanceSlot.tscn").instance()
	slot_container.add_child(slot)
	slot.connect("request_icon", self, "generate_icon", [slot])
	slot.connect("scene_set", self, "scene_set", [scene_id])
	return slot
