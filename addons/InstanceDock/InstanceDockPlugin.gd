@tool
extends EditorPlugin

var dock: Control
var paint_mode: Control

var translations: Array[Translation]

func _enter_tree():
	var domain := TranslationServer.get_or_add_domain(&"godot.editor")
	for file in ResourceLoader.list_directory("res://addons/InstanceDock/Translations"):
		var translation: Translation = load("res://addons/InstanceDock/Translations".path_join(file))
		translations.append(translation)
		domain.add_translation(translation)
	
	dock = preload("res://addons/InstanceDock/Scenes/InstanceDock.tscn").instantiate()
	dock.plugin = self
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_BR, dock)
	paint_mode = dock.paint_mode

func _exit_tree():
	remove_control_from_docks(dock)
	dock.free()
	
	var domain := TranslationServer.get_or_add_domain(&"godot.editor")
	for translation in translations:
		domain.remove_translation(translation)

func _handles(object: Object) -> bool:
	return paint_mode.enabled and object is CanvasItem

func _edit(object: Object) -> void:
	paint_mode.edited_node = object

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	return paint_mode.paint_input(event)

func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	paint_mode.paint_draw(viewport_control)

func _get_window_layout(configuration: ConfigFile) -> void:
	var tabs: TabBar = dock.tabs
	if tabs.tab_count == 0:
		return
	
	tabs.set_tab_metadata(tabs.current_tab, dock.scroll.scroll_vertical)
	
	for i in tabs.tab_count:
		configuration.set_value("InstanceDock", "tab_%d_scroll" % i, tabs.get_tab_metadata(i))

func _set_window_layout(configuration: ConfigFile) -> void:
	var tabs: TabBar = dock.tabs
	for i in tabs.tab_count:
		tabs.set_tab_metadata(i, configuration.get_value("InstanceDock", "tab_%d_scroll" % i, 0))
