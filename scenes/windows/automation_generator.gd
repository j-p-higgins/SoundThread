extends VBoxContainer

signal generate_automation_points

var min_y: float
var max_y: float
var exponential: bool
var step_amount: float
var minimum_point_spacing = 0.1

var selected_generator
var cycle_count = 2
var starting_phase = 0
var range_min
var range_max

@onready var ui_container = $GeneratorCustomUI
@onready var generate_button = $GenerateAutomation

var value_slider = preload("res://scenes/Nodes/simpleslider.tscn")

func init() -> void:
	_on_generator_type_item_selected(0)
	range_min = min_y
	range_max = max_y

func _on_generator_type_item_selected(index: int) -> void:
			
	match index:
		0, 1, 2, 3:
			if selected_generator not in [0, 1, 2, 3]:
				for child in ui_container.get_children():
					child.queue_free()
					
				var cycles_label = Label.new()
				var cycles_slider = value_slider.instantiate()
				var phase_label = Label.new()
				var phase_slider = value_slider.instantiate()
				var min_label = Label.new()
				var min_slider = value_slider.instantiate()
				var max_label = Label.new()
				var max_slider = value_slider.instantiate()
				
				cycles_label.text = "Cycle Count:"
				phase_label.text = "Starting Phase:"
				min_label.text = "Minimum Value:"
				max_label.text = "Maxium Value:"
				
				cycles_slider.min_value = 0.1
				cycles_slider.max_value = 20
				cycles_slider.exponential = false
				cycles_slider.step_amount = 0.1
				cycles_slider.init_value = 2
				cycles_slider.value_changed.connect(_on_cycle_count_changed)
				
				phase_slider.min_value = 0
				phase_slider.max_value = 360
				phase_slider.exponential = false
				phase_slider.step_amount = 1.0
				phase_slider.init_value = 0
				phase_slider.value_changed.connect(_on_starting_phase_changed)
				
				min_slider.min_value = min_y
				min_slider.max_value = max_y
				min_slider.exponential = exponential
				min_slider.step_amount = step_amount
				min_slider.init_value = min_y
				min_slider.value_changed.connect(_on_range_min_changed)
				
				max_slider.min_value = min_y
				max_slider.max_value = max_y
				max_slider.exponential = exponential
				max_slider.step_amount = step_amount
				max_slider.init_value = max_y
				max_slider.value_changed.connect(_on_range_max_changed)
				
				for ui_element in [cycles_label, cycles_slider, phase_label, phase_slider, min_label, min_slider, max_label, max_slider]:
					ui_container.add_child(ui_element)
					
		4:
			if selected_generator != 4:
				for child in ui_container.get_children():
					child.queue_free()
			
		5:
			if selected_generator != 5:
				for child in ui_container.get_children():
					child.queue_free()
					
		6:
			if selected_generator != 6:
				for child in ui_container.get_children():
					child.queue_free()
					
			
			
	selected_generator = index

func _on_cycle_count_changed(value: float) -> void:
	cycle_count = value
	
func _on_starting_phase_changed(value: float) -> void:
	starting_phase = value

func _on_range_min_changed(value: float) -> void:
	range_min = value
	
func _on_range_max_changed(value: float) -> void:
	range_max = value


func _on_generate_automation_pressed() -> void:
	generate_automation_points.emit()

func generate_automation(current_automation_points: Array, selection_start: float, selection_end: float) -> Array:
	var new_automation_points = []
	
	var number_of_points_to_generate = (selection_end - selection_start) / minimum_point_spacing
	
	
	match selected_generator:
		0:
			generate_sine(current_automation_points, selection_start, selection_end)
		1:
			generate_triangle(current_automation_points, selection_start, selection_end)
		2:
			generate_square(current_automation_points, selection_start, selection_end)
		3:
			generate_saw(current_automation_points, selection_start, selection_end)
		4:
			generate_noise(current_automation_points, selection_start, selection_end)
		5:
			generate_chaos(current_automation_points, selection_start, selection_end)
		6:
			generate_drunk_walk(current_automation_points, selection_start, selection_end)

	return new_automation_points
func generate_sine(current_automation_points: Array, selection_start: float, selection_end: float) -> void:
	return

func generate_triangle(current_automation_points: Array, selection_start: float, selection_end: float) -> void:
	return
	
func generate_square(current_automation_points: Array, selection_start: float, selection_end: float) -> void:
	return

func generate_saw(current_automation_points: Array, selection_start: float, selection_end: float) -> void:
	return
	
func generate_noise(current_automation_points: Array, selection_start: float, selection_end: float) -> void:
	return
	
func generate_chaos(current_automation_points: Array, selection_start: float, selection_end: float) -> void:
	return
	
func generate_drunk_walk(current_automation_points: Array, selection_start: float, selection_end: float) -> void:
	return
