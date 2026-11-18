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
var pulse_width = 50.0
var chaos_speed = 10

@onready var ui_container = $GeneratorCustomUI
@onready var generate_button = $GenerateAutomation

var value_slider = preload("res://scenes/Nodes/simpleslider.tscn")
var rng = RandomNumberGenerator.new()

func init() -> void:
	_on_generator_type_item_selected(0)
	range_min = min_y
	range_max = max_y

func _on_generator_type_item_selected(index: int) -> void:
			
	match index:
		0, 1, 2, 3, 4:
			if selected_generator not in [0, 1, 2, 3, 4]:
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
				var pw_label = Label.new()
				var pw_slider = value_slider.instantiate()
				
				cycles_label.text = "Cycle Count:"
				phase_label.text = "Starting Phase:"
				min_label.text = "Minimum Value:"
				max_label.text = "Maxium Value:"
				pw_label.text = "Pulse Width:"
				
				cycles_slider.min_value = 0.1
				cycles_slider.max_value = 20
				cycles_slider.exponential = false
				cycles_slider.step_amount = 0.1
				cycles_slider.init_value = 2
				cycles_slider.value_changed.connect(_on_cycle_count_changed)
				
				phase_slider.min_value = 0
				phase_slider.max_value = 359
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
				
				pw_slider.min_value = 5
				pw_slider.max_value = 95
				pw_slider.exponential = false
				pw_slider.step_amount = 0.1
				pw_slider.init_value = 50
				pw_slider.value_changed.connect(_on_pw_changed)
				
				for ui_element in [cycles_label, cycles_slider, phase_label, phase_slider, min_label, min_slider, max_label, max_slider, pw_label, pw_slider]:
					if index != 2:
						pw_label.hide()
						pw_slider.hide()
					ui_container.add_child(ui_element)
					
			elif index in [0, 1, 3, 4]:
				#a horrible fix to hide the pulse width slider if not needed
				var i = 0
				for child in ui_container.get_children():
					if i > 7:
						child.hide()
					i += 1
			else:
				for child in ui_container.get_children():
					child.show()
		5:
			if selected_generator != 5:
				for child in ui_container.get_children():
					child.queue_free()
			
		6:
			if selected_generator != 6:
				for child in ui_container.get_children():
					child.queue_free()
				var min_label = Label.new()
				var min_slider = value_slider.instantiate()
				var max_label = Label.new()
				var max_slider = value_slider.instantiate()
				var rate_label = Label.new()
				var rate_slider = value_slider.instantiate()
				
				min_label.text = "Minimum Value:"
				max_label.text = "Maxium Value:"
				rate_label.text = "Chaos Rate:"
				
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
				
				rate_slider.min_value = 1
				rate_slider.max_value = 100
				rate_slider.exponential = true
				rate_slider.step_amount = 1.0
				rate_slider.init_value = 10.0
				rate_slider.value_changed.connect(_on_chaos_speed_changed)
				
				for ui_element in [min_label, min_slider, max_label, max_slider, rate_label, rate_slider]:
					ui_container.add_child(ui_element)
					
		7:
			if selected_generator != 7:
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

func _on_pw_changed(value: float) -> void:
	pulse_width = value
	
func _on_chaos_speed_changed(value: float) -> void:
	chaos_speed = value



func _on_generate_automation_pressed() -> void:
	generate_automation_points.emit()

func generate_automation(selection_start: float, selection_end: float, point_spacing: float) -> Array:
	var new_automation_points = []
	
	var current_automation_points = [] #delete
	
	match selected_generator:
		0: #sine
			var number_of_points_to_generate = ((selection_end - selection_start) / point_spacing) + 1
			for i in range(number_of_points_to_generate):
				var step = (i / number_of_points_to_generate) * (2 * PI)
				var generated_y = generate_sine(step)
				var new_x = selection_start + (point_spacing * i)
				new_automation_points.append(Vector2(new_x, generated_y))
				
		1: #triangle
			var number_of_points_to_generate = (cycle_count * 4)
			var step = (selection_end - selection_start) / number_of_points_to_generate
			var normalised_phase_offset = starting_phase / 360
			
			new_automation_points.append(Vector2(selection_start, generate_triangle(0)))
			
			var current_step = selection_start - (((selection_end - selection_start) / cycle_count) * normalised_phase_offset)
			
			while current_step <= selection_end:
				if current_step > selection_start:
					var normalised_x = (current_step - selection_start) / (selection_end - selection_start)
					var generated_y = generate_triangle(normalised_x)
					new_automation_points.append(Vector2(current_step, generated_y))
				
				current_step += step
				
			if (current_step - step) < selection_end:
				new_automation_points.append(Vector2(selection_end, generate_triangle(1)))


		2: #square
			var step = (selection_end - selection_start) / cycle_count
			var normalised_phase_offset = starting_phase / 360
			var normalised_pulse_width = pulse_width / 100
			
			var current_step = selection_start - (step * normalised_phase_offset)
			
			if current_step <= selection_start:
				var generated_y
				if normalised_phase_offset <= normalised_pulse_width:
					generated_y = 1
				else:
					generated_y = 0
				new_automation_points.append(Vector2(selection_start, normalised_generation_to_value(generated_y)))
			
			while current_step <= selection_end:
				var generated_x = current_step
				if generated_x > selection_start and generated_x <= selection_end:
					new_automation_points.append(Vector2(generated_x, normalised_generation_to_value(1)))
				generated_x = current_step + (step * normalised_pulse_width)
				if generated_x > selection_start and generated_x <= selection_end:
					new_automation_points.append(Vector2(generated_x, normalised_generation_to_value(1)))
				generated_x = current_step + (step * normalised_pulse_width) + minimum_point_spacing
				if generated_x > selection_start and generated_x <= selection_end:
					new_automation_points.append(Vector2(generated_x, normalised_generation_to_value(0)))
				generated_x = current_step + step - minimum_point_spacing
				if generated_x > selection_start and generated_x <= selection_end:
					new_automation_points.append(Vector2(generated_x, normalised_generation_to_value(0)))
				current_step += step
				
			if (current_step - step) < selection_end:
				var last_value = new_automation_points[new_automation_points.size() - 1].y
				new_automation_points.append(Vector2(100.0, last_value))
			
				
		3, 4: #saw and ramp
			var step = (selection_end - selection_start) / cycle_count
			var normalised_phase_offset = starting_phase / 360
			
			var starting_value = normalised_phase_offset
			if selected_generator == 3:
				starting_value = (starting_value * -1) + 1
			new_automation_points.append(Vector2(selection_start, normalised_generation_to_value(starting_value)))
			
			var current_step = selection_start - (step * normalised_phase_offset)
			
			var phase_0 = 1
			var phase_360 = 0
			if selected_generator == 4:
				phase_0 = 0
				phase_360 = 1
			
			
			while current_step <= selection_end:
				var generated_y
				var generated_x
				if current_step > selection_start:
					generated_y = normalised_generation_to_value(phase_0)
					generated_x = current_step
					new_automation_points.append(Vector2(generated_x, generated_y))
					if current_step + step <= selection_end:
						generated_y = normalised_generation_to_value(phase_360)
						generated_x = current_step + step - point_spacing
						new_automation_points.append(Vector2(generated_x, generated_y))
				else:
					if current_step + step <= selection_end:
						generated_y = normalised_generation_to_value(phase_360)
						generated_x = current_step + step - point_spacing
						new_automation_points.append(Vector2(generated_x, generated_y))
					
				current_step += step
					
			if (current_step - step) < selection_end:
				var final_point_normalised_phase = fmod((current_step - selection_end) / step, 1)
				if selected_generator == 4:
					final_point_normalised_phase = (final_point_normalised_phase * -1) + 1
				var generated_y = normalised_generation_to_value(final_point_normalised_phase)
				new_automation_points.append(Vector2(selection_end, generated_y))
		5: #noise
			generate_noise(current_automation_points, selection_start, selection_end)
		6: #chaos
			var x = rng.randf_range(-10, 10)
			var y = rng.randf_range(-15, 15)
			var z = rng.randf_range(10, 40)

			var number_of_points_to_generate = ((selection_end - selection_start) / point_spacing) + 1
			
			for i in range(number_of_points_to_generate):
				var generated_chaos = generate_chaos(x, y, z)
				x = generated_chaos[0]
				y = generated_chaos[1]
				z = generated_chaos[2]
				#scale x value, it should range between -20 and 20
				var normalised_y = remap(clamp(x, -20, 20), -20, 20, 0, 1)
				var generated_y = normalised_generation_to_value(normalised_y)
				var generated_x = selection_start + (point_spacing * i)
				new_automation_points.append(Vector2(generated_x, generated_y))
				
				
				
				
				
		7: #drunk walk
			generate_drunk_walk(current_automation_points, selection_start, selection_end)
	
	return new_automation_points
func generate_sine(step: float) -> float:
	var value = sin((step * cycle_count) + deg_to_rad(starting_phase))
	value = (value + 1) * 0.5
	value = normalised_generation_to_value(value)
	return value

func generate_triangle(step: float) -> float:
	step += 0.25 / cycle_count #offset starting phase so that wavecycle starts at "0" crossing
	var value = fposmod((step * cycle_count) + (starting_phase / 360), 1.0)
	value = 1 - (abs(2.0 * value - 1.0))
	value = normalised_generation_to_value(value)
	return value
	
func generate_square(current_automation_points: Array, selection_start: float, selection_end: float) -> void:
	return

	
func generate_noise(current_automation_points: Array, selection_start: float, selection_end: float) -> float:
	var my_random_number = rng.randf_range(min_y, max_y)
	return my_random_number
	
func generate_chaos(x: float, y: float, z: float) -> Array:
	for i in range(chaos_speed):
		var dx = (10 * (y - x)) * 0.005
		var dy = ((x * (28 - z)) - y) * 0.005
		var dz = ((x * y) - (z * 2.67)) * 0.005
		
		x += dx
		y += dy
		z += dz
		
	return [x, y, z]
	
func generate_drunk_walk(current_automation_points: Array, selection_start: float, selection_end: float) -> void:
	return


func normalised_generation_to_value(t: float) -> float:
	if exponential:
		var log_min = log(range_min)
		var log_max = log(range_max)
		
		return exp(lerp(log_min, log_max, t))
	
	return lerp(range_min, range_max, t)
