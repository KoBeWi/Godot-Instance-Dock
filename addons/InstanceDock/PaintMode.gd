@tool
extends Control

const GRID_SIZE = 7

@onready var plugin: EditorPlugin = owner.plugin

@onready var status: Label = %Status
@onready var snap_enabled: CheckBox = %SnapEnabled
@onready var snap_x: SpinBox = %SnapX
@onready var snap_y: SpinBox = %SnapY

var buttons := ButtonGroup.new()
var enabled: bool

var selected_scene: String
var overrides: Dictionary

var edited_node: CanvasItem:
	set(n):
		edited_node = n
		update_preview()
		update_status()

var preview: CanvasItem

var font: Font
var help: bool
var rotating: bool
var scaling: bool

var transform_from: Variant
var transform_from_point: Vector2

func _ready() -> void:
	if not plugin:
		return
	
	hide()
	font = EditorInterface.get_editor_theme().get_font(&"main", &"EditorFonts")
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
	update_overlays()

func on_button_pressed(button: BaseButton):
	selected_scene = button.owner.scene
	overrides = button.owner.overrides
	
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
			for override in overrides:
				preview.set(override, overrides[override])
	
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
	
	if event is InputEventMouseMotion:
		if rotating:
			preview.rotation = transform_from_point.direction_to(get_local_mouse_position()).angle()
			update_overlays()
		elif scaling:
			preview.scale = (get_local_mouse_position() - transform_from_point) * 0.1
			update_overlays()
		else:
			var target_pos := edited_node.get_global_mouse_position()
			
			if snap_enabled.button_pressed:
				preview.global_position = target_pos.snapped(Vector2(snap_x.value, snap_y.value))
				update_overlays()
			else:
				preview.global_position = target_pos
	
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var parent: Node = owner.get_default_parent()
				if not parent:
					parent = edited_node
				
				var instance: CanvasItem = load(preview.scene_file_path).instantiate()
				for override in overrides:
					instance.set(override, overrides[override])
				
				var undo_redo := plugin.get_undo_redo()
				undo_redo.create_action("InstanceDock paint node", UndoRedo.MERGE_DISABLE, parent)
				undo_redo.add_do_reference(instance)
				undo_redo.add_do_method(self, &"add_instance", parent, EditorInterface.get_edited_scene_root(), instance, preview.get_global_transform())
				undo_redo.add_undo_method(parent, &"remove_child", instance)
				undo_redo.commit_action()
				
				return true
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if rotating:
					preview.rotation = 0
					rotating = false
					update_overlays()
					return true
				elif scaling:
					preview.scale = Vector2.ONE
					scaling = false
					update_overlays()
					return true
	
	if event is InputEventKey:
		if event.echo:
			return false
		
		if event.pressed:
			if event.keycode == KEY_H:
				help = not help
				update_overlays()
				return true
		
		if event.keycode == KEY_R:
			if scaling:
				return false
			
			rotating = event.pressed
			if rotating:
				transform_from = preview.rotation
				transform_from_point = get_local_mouse_position()
			
			update_overlays()
			return true
		
		if event.keycode == KEY_S:
			if rotating:
				return false
			
			scaling = event.pressed
			if scaling:
				transform_from = preview.scale
				transform_from_point = get_local_mouse_position()
			
			update_overlays()
			return true
	
	return false

func add_instance(parent: Node, own: Node, instance: CanvasItem, trans: Transform2D):
	parent.add_child(instance, true)
	instance.owner = own
	instance.global_position = trans.origin
	instance.rotation = trans.get_rotation()
	instance.scale = trans.get_scale()

func paint_draw(viewport_control: Control):
	if not enabled or not edited_node or not preview:
		return
	
	var font_pos_base := viewport_control.size * Vector2.DOWN + Vector2(40, -40)
	if help:
		viewport_control.draw_string(font, font_pos_base + Vector2.UP * 40, "Press H to toggle help")
		
		if rotating:
			viewport_control.draw_string(font, font_pos_base + Vector2.UP * 20, "Rotating: %0.2f°" % rad_to_deg(preview.rotation))
			viewport_control.draw_string(font, font_pos_base, "Press Right Mouse Button to reset")
		elif not scaling:
			viewport_control.draw_string(font, font_pos_base + Vector2.UP * 20, "Hold R to rotate")
		
		if scaling:
			viewport_control.draw_string(font, font_pos_base + Vector2.UP * 20, "Scaling: %0.1f × %0.1f" % [preview.scale.x, preview.scale.y])
			viewport_control.draw_string(font, font_pos_base, "Press Right Mouse Button to reset")
		elif not rotating:
			viewport_control.draw_string(font, font_pos_base, "Hold S to scale")
	else:
		viewport_control.draw_string(font, font_pos_base, "Press H to toggle help")
	
	if not snap_enabled.button_pressed:
		return
	
	for x in range(-GRID_SIZE / 2, GRID_SIZE / 2 + 1):
		for y in range(-GRID_SIZE / 2, GRID_SIZE / 2 + 1):
			var snap_vector := Vector2(snap_x.value, snap_y.value)
			var canvas_transform := edited_node.get_viewport().global_canvas_transform
			
			var pos := edited_node.get_global_mouse_position().snapped(snap_vector)
			pos += Vector2(x, y) * snap_vector
			pos = canvas_transform * pos
			viewport_control.draw_circle(pos, 2, Color(Color.WHITE, 1.0 - absf(x) * 0.2 - absf(y) * 0.2))

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

func update_overlays() -> void:
	plugin.update_overlays()
