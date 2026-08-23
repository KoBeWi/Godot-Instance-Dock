extends EditorPlugin

var _translation_list: Array[Translation]
var _tracked_settings: PackedStringArray
var _updating_translations: bool

var tr_extract: RefCounted

func add_plugin_translation(translation: Translation):
	assert(not is_inside_tree(), "Translations should be added before plugin enters tree.")
	_translation_list.append(translation)

func add_plugin_translations_from_directory(path: String):
	assert(not is_inside_tree(), "Translations should be added before plugin enters tree.")
	
	for file in ResourceLoader.list_directory(path):
		var translation := load(path.path_join(file)) as Translation
		if translation:
			_translation_list.append(translation)

func register_editor_shortcut(path: String, shortcut_name: String, default: int):
	if EditorInterface.get_editor_settings().has_shortcut(path):
		return
	
	var event := InputEventKey.new()
	
	if default & KEY_MASK_SHIFT:
		event.shift_pressed = true
	
	if default & KEY_MASK_CMD_OR_CTRL:
		event.command_or_control_autoremap = true
		event.ctrl_pressed = true
	elif default & KEY_MASK_CTRL:
		event.ctrl_pressed = true
	
	if default & KEY_MASK_ALT:
		event.alt_pressed = true
	
	event.keycode = default & KEY_CODE_MASK
	
	var shortcut := Shortcut.new()
	shortcut.resource_name = shortcut_name
	shortcut.events.append(event)
	
	EditorInterface.get_editor_settings().add_shortcut(path, shortcut)

func define_project_setting(setting: String, default_value: Variant, hint := PROPERTY_HINT_NONE, hint_string := "", basic := false, restart_if_changed := false, internal := false) -> Variant:
	var value: Variant
	if ProjectSettings.has_setting(setting):
		value = ProjectSettings.get_setting(setting)
	else:
		value = default_value
		ProjectSettings.set_setting(setting, default_value)
	
	ProjectSettings.set_initial_value(setting, default_value)
	if hint != PROPERTY_HINT_NONE:
		ProjectSettings.add_property_info({"name": setting, "type": typeof(default_value), "hint": hint, "hint_string": hint_string})
	
	ProjectSettings.set_as_basic(setting, basic)
	ProjectSettings.set_restart_if_changed(setting, restart_if_changed)
	ProjectSettings.set_as_internal(setting, internal)
	
	return value

func track_project_setting(setting: StringName):
	_tracked_settings.append(setting)
	if not ProjectSettings.settings_changed.is_connected(_check_settings):
		ProjectSettings.settings_changed.connect(_check_settings)

func _check_settings():
	for setting in _tracked_settings:
		if ProjectSettings.check_changed_settings_in_group(setting):
			_on_setting_changed(setting)

func _on_setting_changed(setting: String):
	pass

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		if not tr_extract:
			tr_extract = RefCounted.new()
			tr_extract.set_message_translation(false)
		
		var domain := TranslationServer.get_or_add_domain(&"godot.editor")
		for translation in _translation_list:
			domain.add_translation(translation)
		
		return
	
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		if _updating_translations:
			return
		var any_missing: bool
		
		var domain := TranslationServer.get_or_add_domain(&"godot.editor")
		for translation in _translation_list:
			any_missing = any_missing or not domain.has_translation(translation)
			domain.add_translation(translation)
		
		if any_missing:
			_updating_translations = true
			get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
			_updating_translations = false
	
	if what == NOTIFICATION_EXIT_TREE:
		var domain := TranslationServer.get_or_add_domain(&"godot.editor")
		for translation in _translation_list:
			domain.remove_translation(translation)
		
		return
