tool
extends EditorPlugin

var dock: Control

func _enter_tree():
	dock = preload("res://addons/InstanceDock/InstanceDock.tscn").instance()
	dock.edited = false
	dock.plugin = self
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, dock)

func _exit_tree():
	remove_control_from_docks(dock)
	dock.free()

func open_scene(scene: String):
	get_editor_interface().open_scene_from_path(scene)
