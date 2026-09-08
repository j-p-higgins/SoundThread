extends VBoxContainer

var min_y: float
var max_y: float

var automation_points = []

@onready var main_container = $ScrollContainer/MarginContainer/TextEditorGridContainer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func create_gui(old_x_index = null, new_value = null) -> void:
	#figure out if text box needs to be focused after a rebuild of the UI
	var current_focus = get_current_focused_line_edit()

	for child in main_container.get_children():
		child.queue_free()
		
	automation_points.sort_custom(sort_points)
	
	#figure out if focus has changed its position in the UI
	if current_focus.index != null:
		if new_value != null:
			var new_value_index = automation_points.find(new_value)
			if current_focus.value == new_value:
				#the currently focused value is the one that changed, reset focus to its new position in the array
				if current_focus.x_y == "x":
					print("don't restore")
					#user hit enter, box still has non visble focus no need to restore it
					current_focus.index = null
				else:
					current_focus.index = new_value_index
			elif current_focus.index < old_x_index and current_focus.index > new_value_index:
				current_focus.index += 1
			elif current_focus.index > old_x_index and current_focus.index < new_value_index:
				current_focus.index -= 1
	
	var label_x = Label.new()
	var label_y = Label.new()
	var dummy = Label.new()
	var dummy2 = Label.new()
	
	label_x.text = "Time (%)"
	label_y.text = "Value (Min: %.2f, Max: %.2f)" % [min_y, max_y]
	
	main_container.add_child(label_x)
	main_container.add_child(label_y)
	main_container.add_child(dummy)
	main_container.add_child(dummy2)
	
	var index = 0
	for point in automation_points:
		var point_x = LineEdit.new()
		var point_y = LineEdit.new()
		var remove_point
		var add_point = Button.new()
		
		#make remove point a blank control if it is the first or last entry in the array
		if index == 0 or index == automation_points.size() - 1:
			remove_point = MarginContainer.new()
		else:
			remove_point = Button.new()
			remove_point.text = "x"
			remove_point.tooltip_text = "Delete automation point"
			remove_point.pressed.connect(_remove_point.bind(index))
		
		point_x.text = str(point.x)
		point_y.text = str(point.y)
		add_point.text = "+"
		add_point.tooltip_text = "Add automation point"
		
		point_x.custom_minimum_size.x = 300
		point_y.custom_minimum_size.x = 300
		remove_point.custom_minimum_size.x = 30
		add_point.custom_minimum_size.x = 30
		
		point_x.select_all_on_focus = true
		point_y.select_all_on_focus = true
		
		#make buttons only focusable with the mouse to allow tabbing between the text fields
		remove_point.focus_mode = Control.FOCUS_CLICK
		add_point.focus_mode = Control.FOCUS_CLICK
		
		point_x.caret_column = point_x.text.length()
		point_y.caret_column = point_y.text.length()
		
		#make first and last time fields uneditable and unfocusable for smooth navigation with tab
		if index == 0 or index == automation_points.size() - 1:
			point_x.focus_mode = Control.FOCUS_NONE
			point_x.editable = false
		if  index == automation_points.size() - 1:
			add_point.hide()
		
		point_x.focus_exited.connect(_update_x_value.bind(index, point_x))
		point_x.text_submitted.connect(_update_x_value.bind(index, point_x).unbind(1))
		point_y.focus_exited.connect(_update_y_value.bind(index, point_y))
		point_y.text_submitted.connect(_update_y_value.bind(index, point_y).unbind(1))
		add_point.pressed.connect(_add_point.bind(index))
		
		main_container.add_child(point_x)
		main_container.add_child(point_y)
		main_container.add_child(remove_point)
		main_container.add_child(add_point)
		
		if current_focus.index != null:
			if current_focus.index == index:
				if current_focus.x_y == "x":
					point_x.grab_focus.call_deferred()
					point_x.select_all()
				else:
					point_y.grab_focus.call_deferred()
					point_y.select_all()
		
		index += 1
		

func get_current_focused_line_edit() -> Dictionary:
	var focused_line_edit = {
		"index": 0,
		"x_y": "x",
		"value": Vector2(0,0)
	}
	
	for child in main_container.get_children():
		if child is LineEdit:
			if child.has_focus():
				child.release_focus()
				focused_line_edit.value = automation_points[focused_line_edit.index]
				return focused_line_edit
			if focused_line_edit.x_y == "x":
				focused_line_edit.x_y = "y"
			else:
				focused_line_edit.index += 1
				focused_line_edit.x_y = "x"
				
	focused_line_edit.index = null
	return focused_line_edit
	

func sort_points(a, b):
	return a.x < b.x
	
func _update_x_value(index: int, text_box: LineEdit) -> void:
	var previous_value = automation_points[index].x
	
	var new_value = text_box.text
	
	if new_value.is_valid_float():
		new_value = new_value.to_float()
		if new_value == previous_value:
			#no edit, skip making changes
			return
		if new_value < 0.1 or new_value > 99.9:
			#value out of range reset ui to old value
			text_box.text = str(previous_value)
			return
	else:
		#value not a number reset value to old value
		text_box.text = str(previous_value)
		return
			
	automation_points[index].x = new_value
	
	#only update gui if the order actually needs to change
	if automation_points[index].x < automation_points[index - 1].x or automation_points[index].x > automation_points[index + 1].x:
		await get_tree().process_frame #this might be a bad idea
		create_gui(index, automation_points[index])
	
func _update_y_value(index: int, text_box: LineEdit) -> void:
	var previous_value = automation_points[index].y
	
	var new_value = text_box.text
	
	if new_value.is_valid_float():
		new_value = new_value.to_float()
		if new_value == previous_value:
			#no edit, skip making changes
			return
		if new_value < min_y or new_value > max_y:
			#value out of range reset ui to old value
			text_box.text = str(previous_value)
			return
	else:
		#value not a number reset value to old value
		text_box.text = str(previous_value)
		return
			
	automation_points[index].y = new_value


func _remove_point(index: int) -> void:
	automation_points.remove_at(index)
	create_gui()


func _add_point(index: int) -> void:
	var a = automation_points[index].x
	var b = automation_points[index + 1].x
	var new_time = (a + b) / 2.0
	
	automation_points.insert(index + 1, Vector2(new_time, automation_points[index].y))
	create_gui()
