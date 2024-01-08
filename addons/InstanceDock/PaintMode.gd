@tool
extends Control

@onready var plugin: EditorPlugin = owner.plugin

@onready var status: Label = %Status
@onready var snap_enabled: CheckBox = %SnapEnabled
@onready var snap_x: SpinBox = %SnapX
@onready var snap_y: SpinBox = %SnapY

var buttons := ButtonGroup.new()
var enabled: bool

var selected_scene: String
var edited_node: CanvasItem:
	set(n):
		edited_node = n
		update_preview()
		update_status()

var preview: CanvasItem

func _ready() -> void:
	if not plugin:
		return
	
	hide()
	
	buttons.pressed.connect(on_button_pressed)

func set_paint_mode_enabled(toggled_on: bool) -> void:
	var was_enabled := enabled
	
	enabled = toggled_on
	for button in buttons.get_buttons():
		button.visible = toggled_on and not button.disabled
		if not button.visible:
			button.button_pressed = false
		elif was_enabled:
			if button.owner.scene == selected_scene:
				button.set_pressed_no_signal(true)
	
	if not enabled:
		selected_scene = ""
		
		if preview:
			preview.queue_free()
			preview = null
	
	update_status()

func on_button_pressed(button: BaseButton):
	selected_scene = button.owner.scene
	update_preview()
	update_status()
	
	if not preview:
		push_error("Button does not provide CanvasItem scene.")
		button.button_pressed = false

func on_scene_changed():
	if enabled:
		update_preview()

func update_preview():
	if not is_instance_valid(preview):
		preview = null
	
	if preview and preview.scene_file_path != selected_scene:
		preview.queue_free()
		preview = null
	
	if selected_scene.is_empty():
		return
	
	if not preview:
		var node: Node = load(selected_scene).instantiate()
		if not node:
			return
		
		preview = node as CanvasItem
		if not preview:
			node.queue_free()
			return
		else:
			preview.name = &"_InstanceDock_Preview_"
			RenderingServer.canvas_item_set_z_index(preview.get_canvas_item(), 4096)
	
	preview.visible = (edited_node != null)
	
	var root := EditorInterface.get_edited_scene_root()
	
	if not root:
		return
	
	if not preview.get_parent():
		root.add_child(preview)
	else:
		preview.reparent(root, false)

func paint_input(event: InputEvent) -> bool:
	if not enabled:
		return false
	
	if not edited_node:
		push_error("Can't paint on nothing.")
		return false
	
	if selected_scene.is_empty():
		return false
	
	if event is InputEventMouse:
		var target_pos := edited_node.get_global_mouse_position()
		
		if snap_enabled.button_pressed:
			preview.global_position = target_pos.snapped(Vector2(snap_x.value, snap_y.value))
		else:
			preview.global_position = target_pos
	
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var parent: Node = owner.get_default_parent()
				if not parent:
					parent = edited_node
				
				var instance: CanvasItem = load(preview.scene_file_path).instantiate()
				
				var undo_redo := plugin.get_undo_redo()
				undo_redo.create_action("InstanceDock paint node", UndoRedo.MERGE_DISABLE, parent)
				undo_redo.add_do_reference(instance)
				undo_redo.add_do_method(self, &"add_instance", parent, EditorInterface.get_edited_scene_root(), instance, preview.global_position)
				undo_redo.add_undo_method(parent, &"remove_child", instance)
				undo_redo.commit_action()
				
				return true
	
	return false

func add_instance(parent: Node, own: Node, instance: CanvasItem, pos: Vector2):
	parent.add_child(instance, true)
	instance.owner = own
	instance.global_position = pos

func paint_draw(viewport_control: Control):
	pass

func _exit_tree() -> void:
	if is_instance_valid(preview):
		preview.queue_free()

func update_status():
	if not enabled:
		return
	elif not edited_node:
		status.text = "(Re)Select any CanvasItem to start"
		status.modulate = get_theme_color(&"warning_color", &"Editor")
	elif selected_scene.is_empty():
		status.text = "Click instance slot to select"
		status.modulate = get_theme_color(&"warning_color", &"Editor")
	else:
		status.text = "Use LMB to paint instance"
		status.modulate = Color.WHITE