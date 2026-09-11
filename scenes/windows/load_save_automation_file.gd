extends MarginContainer

signal automation_loaded(loaded_automation_points)

const minimum_point_spacing = 0.1

var min_y: float
var max_y: float
var exponential: bool

var automation_points = []

@onready var error_label = $VBoxContainer/ErrorLabel

func _ready() -> void:
	error_label.hide()

func _on_save_button_pressed() -> void:
	var interface_settings = ConfigHandler.load_interface_settings()
	var save_folder = interface_settings.last_used_brk_save_folder
	if save_folder != "no_file" and DirAccess.open(save_folder) != null:
		$SaveDialog.current_dir = save_folder
	
	$SaveDialog.popup()


func _on_save_dialog_file_selected(path: String) -> void:
	ConfigHandler.save_interface_settings("last_used_brk_save_folder", path.get_base_dir())
	
	automation_points.sort_custom(sort_points)
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(";SoundThread\n")
		file.store_string(";Min: %f\n" % min_y)
		file.store_string(";Max: %f\n" % max_y)
		file.store_string(";Exponential: %s\n" % exponential)
		
		for point in automation_points:
			var line = str(point.x) + " " + str(point.y) + "\n"
			file.store_string(line)
		file.close()
		
func sort_points(a, b):
	return a.x < b.x
	

func _on_load_button_pressed() -> void:
	error_label.hide()
	
	var interface_settings = ConfigHandler.load_interface_settings()
	var load_folder = interface_settings.last_used_brk_load_folder
	if load_folder != "no_file" and DirAccess.open(load_folder) != null:
		$LoadDialog.current_dir = load_folder
		
	$LoadDialog.popup()


func _on_load_dialog_file_selected(path: String) -> void:
	ConfigHandler.save_interface_settings("last_used_brk_load_folder", path.get_base_dir())
	#regex for splitting string at whitespace
	var regex = RegEx.create_from_string("\\S+")
	
	var brk_file = FileAccess.open(path, FileAccess.READ)
	
	if brk_file == null:
		error_label.text = "Error: Could not open file"
		error_label.show()
		return
		
	var soundthread_format = false
	var loaded_min_value = null
	var loaded_max_value = null
	var loaded_exponential = null
	var loaded_automation_points = []
	
	while brk_file.get_position() < brk_file.get_length():
		var line = brk_file.get_line().strip_edges()
		
		if line.is_empty():
			continue
			
		if line.begins_with(";"):
			if line == ";SoundThread":
				soundthread_format = true
				continue
				
			elif line.begins_with(";Min:"):
				loaded_min_value = line.trim_prefix(";Min:").strip_edges()
				if loaded_min_value.is_valid_float():
					loaded_min_value = loaded_min_value.to_float()
				else:
					#malformed
					loaded_min_value = null
				continue
					
			elif line.begins_with(";Max:"):
				loaded_max_value = line.trim_prefix(";Max:").strip_edges()
				if loaded_max_value.is_valid_float():
					loaded_max_value = loaded_max_value.to_float()
				else:
					#malformed
					loaded_max_value = null
				continue
			
			elif line.begins_with(";Exponential:"):
				var exp_value = line.trim_prefix(";Exponential:").strip_edges()
				if exp_value.to_lower() == "false":
					loaded_exponential = false
				elif exp_value.to_lower() == "true":
					loaded_exponential = true
				else:
					#malformed
					loaded_exponential = null
				continue
				
			else:
				#non-soundthread comment in file, ignore
				continue
		else:
			var values_in_line = regex.search_all(line)
			if values_in_line.size() == 2:
				var new_x = values_in_line[0].get_string()
				var new_y = values_in_line[1].get_string()
				
				if new_x.is_valid_float() and new_y.is_valid_float():
					new_x = new_x.to_float()
					new_y = new_y.to_float()
					
					loaded_automation_points.append(Vector2(new_x, new_y))
				
				
	brk_file.close()
	
	if loaded_automation_points.size() < 2:
		error_label.text = "Error: No automation data found in file"
		error_label.show()
		return
	
	if soundthread_format == true and (loaded_min_value == null or loaded_max_value == null or loaded_exponential == null):
		#missing some meta data so treat as non-soundthread format
		print("Malformed meta data, treating file as non-soundthread format")
		soundthread_format = false
	
	if soundthread_format:
		if loaded_min_value != min_y or loaded_max_value != max_y or loaded_exponential != exponential:
			#if needed rescale values to match the current process
			for i in range(loaded_automation_points.size()):
				var loaded_y = loaded_automation_points[i].y
				var normalised_y = value_to_normalised(loaded_y, loaded_min_value, loaded_max_value, loaded_exponential)
				var remapped_y = normalised_to_value(normalised_y)
				loaded_automation_points[i].y = remapped_y
	
	#cleanup the data
	loaded_automation_points.sort_custom(sort_points)
	var loaded_min_x = loaded_automation_points[0].x
	var loaded_max_x = loaded_automation_points[loaded_automation_points.size() - 1].x
	for i in range(loaded_automation_points.size()):
		#clip automation values to the current parameters range
		loaded_automation_points[i].y = clamp(loaded_automation_points[i].y, min_y, max_y)
	if loaded_min_x != 0 or loaded_max_x != 100:
		for i in range(loaded_automation_points.size()):
			loaded_automation_points[i].x = remap(loaded_automation_points[i].x, loaded_min_x, loaded_max_x, 0, 100)
			
	for i in range(loaded_automation_points.size() -1, -1, -1):
		if i == loaded_automation_points.size() - 1:
			continue
		elif i == 0:
			if abs(loaded_automation_points[1].x - loaded_automation_points[0].x) < minimum_point_spacing:
				loaded_automation_points.remove_at(1)
		else:
			if abs(loaded_automation_points[i + 1].x - loaded_automation_points[i].x) < minimum_point_spacing:
				loaded_automation_points.remove_at(i)
		
			
	if loaded_automation_points.size() > 1:
		automation_loaded.emit(loaded_automation_points)
		automation_points = loaded_automation_points

func value_to_normalised(value: float, loaded_min_y: float, loaded_max_y: float, loaded_exponential: bool) -> float:
	if loaded_exponential:
		var log_min = log(loaded_min_y)
		var log_max = log(loaded_max_y)
		
		return inverse_lerp(log_min, log_max, log(value))
	
	return inverse_lerp(loaded_min_y, loaded_max_y, value)
	
func normalised_to_value(t: float) -> float:
	if exponential:
		var log_min = log(min_y)
		var log_max = log(max_y)
		
		return exp(lerp(log_min, log_max, t))
	
	return lerp(min_y, max_y, t)
