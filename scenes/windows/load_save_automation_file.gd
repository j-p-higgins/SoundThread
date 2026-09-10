extends MarginContainer

var min_y: float
var max_y: float
var exponential: bool

var automation_points = []



func write_breakfile(points: Array, path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		for point in points:
			var line = str(point.x) + " " + str(point.y) + "\n"
			file.store_string(line)
		file.close()
	#else:
		#log_console("Failed to open file to write breakfile", true)


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
