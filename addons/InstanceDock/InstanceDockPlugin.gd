@tool
extends "ExtendedEditorPlugin.gd"

var dock: EditorDock

func _init() -> void:
	add_plugin_translations_from_directory("res://addons/InstanceDock/Translations")

func _ready() -> void:
	dock = preload("res://addons/InstanceDock/Scenes/InstanceDock.tscn").instantiate()
	dock.plugin = self
	add_dock(dock)

func _exit_tree():
	remove_dock(dock)
	dock.free()

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

func _on_setting_changed(setting: String) -> void:
	dock._project_setting_changed(setting, ProjectSettings.get_setting(setting))
