extends Control
class_name AutomationEditor

@onready var value_edit_x = $"../../EditorData/XEdit"
@onready var value_edit_y = $"../../EditorData/YEdit"

const max_zoom = 10.0
const zoom_per_scroll = 0.5
const point_size = 10

var zoom_factor = 1.0
var zoomed_offset = 0.0

var min_y: float
var max_y: float
var exponential: bool

var automation_points = []
var selected_points = []

var selection_start = null
var selection_end = null

var mouse_down = false
var mouse_down_value = 0.0

var default_font : Font = ThemeDB.fallback_font

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	
	
	

func _gui_input(event):
	if event is InputEventMouseButton:
		# double-click: delete only if not fixed, otherwise add new
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			add_remove_point(event.position)

		# begin drag on press
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			select_points(event.position, event.shift_pressed)

		# end drag on release
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			mouse_down = false
			select_points_in_drag_range()
			
		# edit point value
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			print("Right CLick")
		
		# zoom in
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_automation(zoom_per_scroll, event.position.x)
			
		# zoom out
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_automation(zoom_per_scroll * -1, event.position.x)
			
	elif event is InputEventMouseMotion:
		var automation_value = convert_to_automation_value(event.position)
		if mouse_down:
			selection_end = automation_value.x
			
			if selected_points.size() > 0:
				var point_offset_amount = automation_value - mouse_down_value
				mouse_down_value = automation_value
				for index in selected_points:
					if automation_points[index].x == 0.0 or automation_points[index].x == 100.0:
						pass
					else:
						automation_points[index].x = clamp(automation_points[index].x + point_offset_amount.x, 0.0001, 99.999)
					automation_points[index].y = clamp(automation_points[index].y + point_offset_amount.y, min_y, max_y)
			queue_redraw()
			
		if selected_points.size() != 1:
			value_edit_x.editable = false
			value_edit_x.text = "%.3f" % automation_value.x
			value_edit_y.editable = false
			value_edit_y.text = "%.3f" % automation_value.y
		else:
			#check the values are not currently being edited, if not update them with the current value for the selected automation point
			if !value_edit_x.has_focus() and !value_edit_y.has_focus():
				var selected_point_value = automation_points[selected_points[0]]
				if selected_point_value.x == 0.0 or selected_point_value.x == 100.0:
					value_edit_x.editable = false
				else:
					value_edit_x.editable = true
				value_edit_x.text = "%.3f" % selected_point_value.x
				value_edit_y.editable = true
				value_edit_y.text = "%.3f" % selected_point_value.y
			
	if event is InputEventKey and event.pressed:
		if (event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE):
			if selected_points.size() > 0:
				#iterate over selected indexes in reverse order then remove
				selected_points.sort()
				selected_points.reverse()
				for point in selected_points:
					automation_points.remove_at(point)
				
				selected_points.clear()
				selection_start = null
				selection_end = null
				queue_redraw()
				
		
func zoom_automation(zoom_amount: float, zoom_screen_position: float) -> void:
	#convert mouse position to a (decimal) percentage of automation window size
	zoom_screen_position = zoom_screen_position / self.size.x
	
	# calculate what is currently in view and where the mouse is positioned in the automation currently
	var old_percentage_on_screen = 100 / zoom_factor

	var mouse_position_in_automation = (old_percentage_on_screen * zoom_screen_position) + zoomed_offset
	
	#calculate the new zoom factor
	zoom_factor = clamp(zoom_factor + zoom_amount, 1.0, max_zoom)

	#calculate the offset to align the zoomed automation with the mouse position in the old automation
	var new_percentage_on_screen = 100 / zoom_factor
	
	zoomed_offset = clamp(mouse_position_in_automation - (new_percentage_on_screen * zoom_screen_position), 0.0, 100 - new_percentage_on_screen)
	
	queue_redraw()
	
func add_remove_point(mouse_position: Vector2) -> void:
	var automation_value = convert_to_automation_value(mouse_position)
	var matching_point = get_point_at_pos(automation_value) 
	
	if matching_point != -1:
		if automation_points[matching_point].x == 0 or automation_points[matching_point].x == 100:
			pass
		else:
			automation_points.remove_at(matching_point)
			selected_points.clear()
	else:
		automation_points.append(automation_value)
		selected_points.append(automation_points.size() - 1)
	queue_redraw()
	
func select_points(mouse_position: Vector2, shift_pressed: bool) -> void:
	var automation_value = convert_to_automation_value(mouse_position)
	mouse_down = true
	mouse_down_value = automation_value
	
	var point_selected = get_point_at_pos(automation_value)
	
	if point_selected == -1:
		selected_points.clear()
		selection_start = automation_value.x
		selection_end = null
	else:
		if selected_points.has(point_selected):
			pass
		else:
			if !shift_pressed:
				selected_points.clear()
			selected_points.append(point_selected)
			
		selection_start = null
		selection_end = null
	
	queue_redraw()

func select_points_in_drag_range() -> void:
	if selection_start != null and selection_end != null:
		selected_points.clear()
		
		var i = 0
		for point in automation_points:
			if point.x >= min(selection_start, selection_end) and point.x <= max(selection_start, selection_end):
				selected_points.append(i)
			i += 1
				
		queue_redraw()


func _draw():
	#draw grid
	for i in range(10):
		var position = convert_x_to_screen_position(i * 10)
		if position < 0:
			pass
		elif position < self.size.x:
			pass
			
		draw_line(Vector2(position, 0), Vector2(position, self.size.y), Color(1, 1, 1, 0.1), 1)
		draw_string(default_font, Vector2(position + 8, 16), str(i * 10) + "%", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.2))
	
	
	#sort points
	var sorted = []
	sorted = automation_points.duplicate()
	sorted.sort_custom(sort_points)
	
	#convert to screen positions
	var screen_points = []
	for point in sorted:
		var screen_point = convert_to_screen_position(point)
		
		screen_points.append(screen_point)
	
	#get screen positions of any selected points
	var selected_screen_points = []
	for index in selected_points:
		selected_screen_points.append(convert_to_screen_position(automation_points[index]))

	
	#draw dotted lines between point positions
	for i in range(automation_points.size() - 1):
		var point_a = screen_points[i]
		var point_b = screen_points[i + 1]
		
		if point_b.x < 0:
			continue
		
		if point_a.x > size.x:
			continue
		
		draw_dashed_line(point_a, point_b, Color(0.7, 0.7, 0.7, 0.4), 2.0, 6.0, true, true)
	
	#draw rectangles for points
	for point in screen_points:
		if point.x >= 0 and point.x <= self.size.x:
			if selected_screen_points.has(point):
				draw_rect(Rect2(point.x - (point_size / 2), point.y  - (point_size / 2), point_size, point_size), Color(0.9, 0.9, 0.9, 1))
			else:
				draw_rect(Rect2(point.x - (point_size / 2), point.y  - (point_size / 2), point_size, point_size), Color(0.9, 0.9, 0.9, 0.5))
				
	#draw selection area
	if selection_start != null and selection_end != null:
		var selection_start_screen = convert_to_screen_position(Vector2(selection_start, 0)).x
		var selection_end_screen = convert_to_screen_position(Vector2(selection_end, 0)).x
		draw_rect(Rect2(min(selection_start_screen, selection_end_screen), 0, abs(selection_end_screen - selection_start_screen), self.size.y), Color(0.9, 0.9, 0.9, 0.1))

func convert_to_screen_position(automation_point: Vector2) -> Vector2:
	var point_x_pos = convert_x_to_screen_position(automation_point.x)
	var point_y_pos = convert_y_to_screen_position(automation_point.y)
	
	return Vector2(point_x_pos, point_y_pos)

func convert_x_to_screen_position(automation_x_value: float) -> float:
	return (((automation_x_value - zoomed_offset) * zoom_factor) / 100) * self.size.x
	
func convert_y_to_screen_position(automation_y_value: float) -> float:
	return self.size.y - (((automation_y_value - min_y) / (max_y - min_y)) * self.size.y)

func convert_to_automation_value(screen_position: Vector2) -> Vector2:
	var point_x_value = ((100 / zoom_factor) * (screen_position.x / self.size.x)) + zoomed_offset
	var point_y_value = (((self.size.y - screen_position.y) / self.size.y) * (max_y - min_y)) + min_y
	
	return Vector2(point_x_value, point_y_value)
	
	
func sort_points(a, b):
	return a.x < b.x

func get_point_at_pos(pos: Vector2) -> int:
	var y_tolerance = (max_y - min_y) / (self.size.y * 0.25)
	
	var i = 0
	for point in automation_points:
		var x_difference = point.x - pos.x
		if x_difference >= (-0.5 / zoom_factor) and x_difference <= (0.5 / zoom_factor):
			var y_difference = point.y - pos.y
			if y_difference >= (y_tolerance * -1) and y_difference <= y_tolerance:
				return i
		i += 1
	return -1


func _on_x_edit_text_submitted(new_text: String) -> void:
	var old_value = automation_points[selected_points[0]]
	
	if new_text.is_valid_float():
		var new_val = new_text.to_float()
		
		if new_val < 0.0001 or new_val > 99.9999:
			value_edit_x.text = "%.3f" % old_value.x
		else:
			automation_points[selected_points[0]].x = new_val
			
		queue_redraw()
	else:
		value_edit_x.text = "%.3f" % old_value.x
		
		
func _on_x_edit_focus_exited() -> void:
	if selected_points.size() == 1:
		_on_x_edit_text_submitted(value_edit_x.text)
	
	
func _on_y_edit_text_submitted(new_text: String) -> void:
	var old_value = automation_points[selected_points[0]]
	
	if new_text.is_valid_float():
		var new_val = new_text.to_float()
		
		if new_val <= min_y or new_val >= max_y:
			value_edit_y.text = "%.3f" % old_value.y
		else:
			automation_points[selected_points[0]].y = new_val
			
		queue_redraw()
	else:
		value_edit_y.text = "%.3f" % old_value.y

func _on_y_edit_focus_exited() -> void:
	if selected_points.size() == 1:
		_on_y_edit_text_submitted(value_edit_y.text)
