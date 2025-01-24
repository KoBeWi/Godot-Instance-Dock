extends RefCounted

static func translate_plugin(plugin: EditorPlugin) -> PluginTranslator:
	var translator := PluginTranslator.new(plugin)
	return translator

static func define_project_setting(setting: String, default_value: Variant, hint := PROPERTY_HINT_NONE, hint_string := "") -> Variant:
	var value: Variant
	if ProjectSettings.has_setting(setting):
		value = ProjectSettings.get_setting(setting)
	else:
		value = default_value
		ProjectSettings.set_setting(setting, default_value)
	
	ProjectSettings.set_initial_value(setting, default_value)
	if hint != PROPERTY_HINT_NONE:
		ProjectSettings.add_property_info({"name": setting, "type": typeof(default_value), "hint": hint, "hint_string": hint_string})
	
	return value

static func track_project_setting(setting: String, owner: Object, callback: Callable) -> void:
	var tracker := ProjectSettingTracker.new(owner, setting)
	tracker.callback = callback

class PluginTranslator:
	var domain: TranslationDomain
	var translation_list: Array[Translation]

	func _init(for_plugin: EditorPlugin) -> void:
		domain = TranslationServer.get_or_add_domain(&"godot.editor")
		
		var existing = for_plugin.get_meta(&"_translator", false)
		if existing:
			push_error("The plugin is already translated.")
			return
		
		for_plugin.set_meta(&"_translator", self)
		for_plugin.tree_entered.connect(_submit_translations)
		for_plugin.tree_exited.connect(_revoke_translations)

	func add_translation(translation: Translation):
		translation_list.append(translation)

	func add_translations_from_directory(path: String):
		for file in ResourceLoader.list_directory(path):
			var translation := load(path.path_join(file)) as Translation
			if translation:
				translation_list.append(translation)

	func _submit_translations():
		for translation in translation_list:
			domain.add_translation(translation)

	func _revoke_translations():
		for translation in translation_list:
			domain.remove_translation(translation)

class ProjectSettingTracker:
	var callback: Callable
	var tracked_setting: String
	var prev_value: Variant
	
	func _init(owner: Object, setting: String) -> void:
		owner.set_meta(str("_tracker", abs(get_instance_id())), self)
		tracked_setting = setting
		prev_value = ProjectSettings.get_setting(tracked_setting)
		ProjectSettings.settings_changed.connect(_check_setting)
	
	func _check_setting():
		var new_value := ProjectSettings.get_setting(tracked_setting)
		if new_value != prev_value:
			callback.call(tracked_setting, new_value)
			prev_value = new_value
