extends MarginContainer

signal automation_loaded(loaded_automation_points)

var min_y: float
var max_y: float
var exponential: bool

var automation_points = []

func _on_save_button_pressed() -> void:
	$SaveDialog.popup()


func _on_save_dialog_file_selected(path: String) -> void:
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
	$LoadDialog.popup()


func _on_load_dialog_file_selected(path: String) -> void:
	#regex for splitting string at whitespace
	var regex = RegEx.create_from_string("\\S+")
	
	var brk_file = FileAccess.open(path, FileAccess.READ)
	
	if brk_file == null:
		print("Could not open BRK file")
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
					continue
				else:
					print("Malformed meta data, treating file as non-soundthread format")
					soundthread_format = false
					break
					
			elif line.begins_with(";Max:"):
				loaded_max_value = line.trim_prefix(";Max:").strip_edges()
				if loaded_max_value.is_valid_float():
					loaded_max_value = loaded_max_value.to_float()
					continue
				else:
					print("Malformed meta data, treating file as non-soundthread format")
					soundthread_format = false
					break
			
			elif line.begins_with(";Exponential:"):
				var exp_value = line.trim_prefix(";Exponential:").strip_edges()
				if exp_value.to_lower() == "false":
					loaded_exponential = false
				elif exp_value.to_lower() == "true":
					loaded_exponential = true
				else:
					print("Malformed meta data, treating file as non-soundthread format")
					soundthread_format = false
					break
				
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
	
	print(soundthread_format)
	print(loaded_min_value)
	print(loaded_max_value)
	print(loaded_exponential)
	print(loaded_automation_points)
	
	automation_loaded.emit(loaded_automation_points)
