extends Node

var DefaultWindow = preload("res://scenes/windows/default_automation_window.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func automation_window_requested(slider_id: int, automation_parent_name: StringName, slider_properties: Dictionary, slider_value: float) -> void:
	if !is_automation_open(slider_id):
		create_automation_window(slider_id, automation_parent_name, slider_properties, slider_value)

func is_automation_open(slider_id: int) -> bool:
	for child in get_tree().current_scene.get_children():
		if child is Window and child.has_meta("slider_id") and child.get_meta("slider_id") == slider_id:
			# Found existing window, bring it to front
			if child.is_visible():
				child.hide()
				child.popup()
			else:
				child.popup()
			return true
	return false
	
func create_automation_window(slider_id: int, automation_parent_name: StringName, slider_properties: Dictionary, slider_value: float) -> void:
	var automation_window = DefaultWindow.instantiate()
	
	automation_window.set_meta("automation_parent_name", automation_parent_name)
	automation_window.set_meta("slider_id", slider_id)
	
	automation_window.title = slider_properties.node_title + " - " + slider_properties.parameter_name
	
	automation_window.min_y = slider_properties.minimum_value
	automation_window.max_y = slider_properties.maximum_value
	automation_window.exponential = slider_properties.exponential
	automation_window.slider_value = slider_value
	
	get_tree().current_scene.add_child(automation_window)
	automation_window.popup()

func close_windows(nodes: Array[StringName]) -> void:
	for child in get_tree().current_scene.get_children():
		if child is Window and child.has_meta("automation_parent_name"):
			for node in nodes:
				if child.get_meta("automation_parent_name") == node:
					child.queue_free()
