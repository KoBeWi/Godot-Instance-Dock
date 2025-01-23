extends RefCounted

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
