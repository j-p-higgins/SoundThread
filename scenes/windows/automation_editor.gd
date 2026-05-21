extends Control
class_name AutomationEditor

@onready var value_edit_x = $"../../EditorData/XEdit"
@onready var value_edit_y = $"../../EditorData/YEdit"
@onready var scroll_bar = $"../../AutomationScrollBar"

var pencil_icon = load("res://theme/images/pencil_32.png")
var pencil_icon_hidpi = load("res://theme/images/pencil_64.png")
var eraser_icon = load("res://theme/images/eraser_32.png")
var eraser_icon_hidpi = load("res://theme/images/eraser_64.png")
var curve_icon = load("res://theme/images/curve_32.png")
var curve_icon_hidpi = load("res://theme/images/curve_64.png")

var ease_in_icon = load("res://theme/images/ease_in_button.png")
var ease_out_icon = load("res://theme/images/ease_out_button.png")
var s_curve_icon = load("res://theme/images/s_curve_button.png")

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
var pre_edited_automation_points = []

var selection_start = null
var selection_end = null

var mouse_down = false
var mouse_down_value = 0.0
var previous_horizontal_mouse_direction = null
var previous_vertical_mouse_direction = null
var alt_tool = "pencil"
var curve_mode = "s_curve"

var predraw_automation_count = 0

var default_font : Font = ThemeDB.fallback_font

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	
	if DisplayServer.screen_get_dpi(0) >= 144:
		Input.set_custom_mouse_cursor(pencil_icon_hidpi, Input.CURSOR_HELP)
		Input.set_custom_mouse_cursor(eraser_icon_hidpi, Input.CURSOR_FORBIDDEN)
		Input.set_custom_mouse_cursor(curve_icon_hidpi, Input.CURSOR_WAIT)
	else:
		Input.set_custom_mouse_cursor(pencil_icon, Input.CURSOR_HELP)
		Input.set_custom_mouse_cursor(eraser_icon, Input.CURSOR_FORBIDDEN)
		Input.set_custom_mouse_cursor(curve_icon, Input.CURSOR_WAIT)
	
	
	

func _gui_input(event):
	if event is InputEventMouseButton:
		# double-click: delete only if not fixed, otherwise add new
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			if !event.alt_pressed:
				add_remove_point(event.position)

		# begin drag on press
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var automation_value = convert_to_automation_value(event.position)
			mouse_down = true
			mouse_down_value = automation_value
			
			pre_edited_automation_points = automation_points.duplicate()
			if !event.alt_pressed:
				select_points(automation_value, event.shift_pressed)
			predraw_automation_count = automation_points.size() - 1
			previous_horizontal_mouse_direction = null
			previous_vertical_mouse_direction = null
			
				
		# end drag on release
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			mouse_down = false
			previous_horizontal_mouse_direction = null
			previous_vertical_mouse_direction = null
			set_default_cursor_shape(Control.CURSOR_ARROW)
			select_points_in_drag_range()
			
		# edit point value
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			print("Right CLick")
		
		# zoom in
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if !event.ctrl_pressed:
				zoom_automation(zoom_per_scroll, event.position.x)
			else:
				horizontal_scroll(10)
			
		# zoom out
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if !event.ctrl_pressed:
				zoom_automation(zoom_per_scroll * -1, event.position.x)
			else:
				horizontal_scroll(-10)
			
	elif event is InputEventMouseMotion:
		var automation_value = convert_to_automation_value(event.position)
		
		if event.alt_pressed:
			change_cursor()
		else:
			set_default_cursor_shape(Control.CURSOR_ARROW)
		
		if mouse_down:
			if selection_start != null and !event.alt_pressed:
				set_default_cursor_shape(Control.CURSOR_IBEAM)
				selection_end = automation_value.x
			
			if selected_points.size() > 0 and !event.alt_pressed:
				drag_automation_points(automation_value)
				
			if event.alt_pressed:
				match alt_tool:
					"pencil":
						selection_end = null
						selected_points.clear()
						pencil_draw_automation(event.relative.x, automation_value)
					"erase":
						selection_end = null
						selected_points.clear()
						erase_points(automation_value)
					"scale_v":
						selection_end = null
						if selected_points.size() > 1:
							scale_vertically(automation_value, selected_points)
						else:
							selected_points.clear()
							scale_vertically(automation_value, range(automation_points.size()))
					"scale_h":
						selection_end = null
						if selected_points.size() > 1:
							scale_horizontally(automation_value, selected_points)
						else:
							selected_points.clear()
							scale_horizontally(automation_value, range(automation_points.size()))
					"skew":
						selection_end = null
						if selected_points.size() > 1:
							skew_points(automation_value, selected_points)
						else:
							selected_points.clear()
							skew_points(automation_value, range(automation_points.size()))
					"curve":
						selection_end = null
						draw_realtime_curve(automation_value)

					
			queue_redraw()
			
		fill_coordinate_boxes(automation_value)
		
			
	if event is InputEventKey:
		if (event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE) and event.pressed:
			delete_selected_points()
		elif event.keycode == KEY_ALT and event.pressed:
			change_cursor()
		elif event.keycode == KEY_ALT and not event.pressed:
			set_default_cursor_shape(Control.CURSOR_ARROW)

func change_cursor() -> void:
	match alt_tool:
		"pencil":
			set_default_cursor_shape(Control.CURSOR_HELP)
		"erase":
			set_default_cursor_shape(Control.CURSOR_FORBIDDEN)
		"scale_v":
			set_default_cursor_shape(Control.CURSOR_VSIZE)
		"scale_h":
			set_default_cursor_shape(Control.CURSOR_HSIZE)
		"scale_h":
			set_default_cursor_shape(Control.CURSOR_HSIZE)
		"skew":
			set_default_cursor_shape(Control.CURSOR_BDIAGSIZE)
		"curve":
			set_default_cursor_shape(Control.CURSOR_WAIT)

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
	
	scroll_bar.page = 100 / zoom_factor
	scroll_bar.value = zoomed_offset
	queue_redraw()
	
func horizontal_scroll(amount: float) -> void:
	zoomed_offset = clamp(zoomed_offset + (amount / zoom_factor), 0, 100 - (100 / zoom_factor))
	scroll_bar.value = zoomed_offset
	queue_redraw()
	
func add_remove_point(mouse_position: Vector2) -> void:
	var automation_value = convert_to_automation_value(mouse_position)
	var matching_point = get_point_at_pos(automation_value, 1) 
	
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
	
func delete_selected_points() -> void:
	if selected_points.size() > 0:
		#iterate over selected indexes in reverse order then remove
		selected_points.sort()
		selected_points.reverse()
		for point in selected_points:
			if automation_points[point].x == 0 or automation_points[point].x == 100:
				pass
			else:
				automation_points.remove_at(point)
		
		selected_points.clear()
		selection_start = null
		selection_end = null
		queue_redraw()
		
func select_points(automation_value: Vector2, shift_pressed: bool) -> void:

	var point_selected = get_point_at_pos(automation_value, 1)
	
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
		
func drag_automation_points(automation_value: Vector2) -> void:
	set_default_cursor_shape(Control.CURSOR_DRAG)
	var point_offset_x = clamp(automation_value.x, 0.0, 100.0) - mouse_down_value.x
	var point_offset_y = value_to_normalised(clamp(automation_value.y, min_y, max_y)) - value_to_normalised(mouse_down_value.y)
	
	for index in selected_points:
		if automation_points[index].x == 0.0 or automation_points[index].x == 100.0:
			pass
		else:
			automation_points[index].x = clamp(pre_edited_automation_points[index].x + point_offset_x, 0.0001, 99.999)
			
		var point_normalised = value_to_normalised(pre_edited_automation_points[index].y)
		var new_y_value = clamp(point_normalised + point_offset_y, 0.0, 1.0)
		
		automation_points[index].y = normalised_to_value(new_y_value)
		
		
func pencil_draw_automation(relative_x: float, automation_value: Vector2) -> void:
	var current_mouse_direction
	if relative_x < 0:
		current_mouse_direction = "left"
	elif relative_x > 0:
		current_mouse_direction = "right"
		
	if current_mouse_direction != previous_horizontal_mouse_direction or previous_horizontal_mouse_direction == null:
		predraw_automation_count = automation_points.size() - 1
		selection_start = automation_value.x
	
	previous_horizontal_mouse_direction = current_mouse_direction
	
	if automation_value.x >= 0.01 and automation_value.x <= 99.99:
		for i in range(predraw_automation_count, -1, -1):
			var point = automation_points[i]
			if point.x >= min(selection_start, automation_value.x) and point.x <= max(selection_start, automation_value.x):
				if point.x != 0 and point.x != 100:
					automation_points.remove_at(i)
					predraw_automation_count -= 1
		if abs(automation_points[automation_points.size() - 1].x - automation_value.x) > 2 / zoom_factor:
			automation_points.append(automation_value)
	elif automation_value.x <= 0:
		automation_points[0].y = automation_value.y
	elif automation_value.x >= 100:
		automation_points[1].y = automation_value.y

func scale_vertically(automation_value: Vector2, points_to_scale: Array) -> void:
	var multiplier = 1 + ((automation_value.y - mouse_down_value.y) / (max_y - min_y) * 2)

	for point in points_to_scale:
		var original_y = pre_edited_automation_points[point].y
		
		var distance_from_centre = original_y - mouse_down_value.y
		
		var scaled_y = mouse_down_value.y + (distance_from_centre * multiplier)
		
		automation_points[point].y = clamp(scaled_y, min_y, max_y)

func scale_horizontally(automation_value: Vector2, points_to_scale: Array) -> void:
	var multiplier = 1 + (((automation_value.x - mouse_down_value.x) / 100) * 2)

	for point in points_to_scale:
		if automation_points[point].x == 0 or automation_points[point].x == 100:
			continue
		var original_x = pre_edited_automation_points[point].x
		
		var distance_from_centre = original_x - mouse_down_value.x
		
		var scaled_x = mouse_down_value.x + (distance_from_centre * multiplier)
		
		automation_points[point].x = clamp(scaled_x, 0.001, 99.999)
		
func skew_points(automation_value: Vector2, points_to_scale: Array) -> void:
	var multiplier = ((automation_value.x - mouse_down_value.x) / 100) * 2
	
	for point in points_to_scale:
		var original_x = pre_edited_automation_points[point].x
		var original_y = pre_edited_automation_points[point].y
		
		var distance_from_centre = original_x - mouse_down_value.x
		
		var scaled_y = original_y + (distance_from_centre * multiplier)
		
		automation_points[point].y = clamp(scaled_y, min_y, max_y)

func erase_points(automation_value: Vector2) -> void:
	var point_to_erase = get_point_at_pos(automation_value, 3)
	
	if point_to_erase != -1:
		automation_points.remove_at(point_to_erase)
	
	queue_redraw()
	
func fill_coordinate_boxes(automation_value: Vector2) -> void:
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
		
func draw_realtime_curve(mouse_value: Vector2) -> void:
	var point_count = (abs(mouse_value.x - mouse_down_value.x) / 2) * zoom_factor
	
	#overwrite previous curve
	automation_points.resize(pre_edited_automation_points.size())
	for i in range(automation_points.size()):
		automation_points[i] = pre_edited_automation_points[i]
	
	if point_count < 1:
		#dont calculate a curve if the range is too small
		automation_points.append(mouse_down_value)
		automation_points.append(mouse_value)
		return
	else:
		remove_points_in_range(mouse_down_value.x, mouse_value.x, automation_points.size() - 1)
		automation_points.append(mouse_down_value)
		
		var x_step =  (mouse_value.x - mouse_down_value.x) / int(point_count)
		var y_diff = mouse_down_value.y - mouse_value.y
			
		var start_normalised = value_to_normalised(mouse_down_value.y)
		var end_normalised = value_to_normalised(mouse_value.y)
		
		for i in range(point_count):
			var t = (float(i + 1) / int(point_count))
			var curved = t
			match curve_mode:
				"s_curve":
					curved = curve_s_curve(t)
				"ease_in":
					if y_diff < 0:
						curved = curve_ease_in(t)
					else:
						curved = curve_ease_out(t)
				"ease_out":
					if y_diff < 0:
						curved = curve_ease_out(t)
					else:
						curved = curve_ease_in(t)
			
			var normalised_y = lerp(start_normalised, end_normalised, curved)
			
			var x = clamp(mouse_down_value.x + ((i + 1) * x_step), 0.01, 99.99)
			var y = clamp(normalised_to_value(normalised_y), min_y, max_y)
			
			automation_points.append(Vector2(x, y))

func value_to_normalised(value: float) -> float:
	if exponential:
		var log_min = log(min_y)
		var log_max = log(max_y)
		
		return inverse_lerp(log_min, log_max, log(value))
	
	return inverse_lerp(min_y, max_y, value)
	
func normalised_to_value(t: float) -> float:
	if exponential:
		var log_min = log(min_y)
		var log_max = log(max_y)
		
		return exp(lerp(log_min, log_max, t))
	
	return lerp(min_y, max_y, t)
		

func curve_ease_in(t: float) -> float:
	return pow(t, 3)
	
func curve_ease_out(t: float) -> float:
	return 1 - pow(1 - t, 3)

func curve_s_curve(t: float) -> float:
	return (6 * pow(t, 5)) - (15 * pow(t, 4)) + (10 * pow(t, 3))
	
func remove_points_in_range(from: float, to: float, max_index: int) -> void:
	for i in range(max_index, -1, -1):
			var point = automation_points[i]
			if point.x >= min(from, to) and point.x <= max(from, to):
				if point.x != 0 and point.x != 100:
					automation_points.remove_at(i)

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
	var point_y_pos
	if !exponential:
		point_y_pos = self.size.y - (((automation_y_value - min_y) / (max_y - min_y)) * self.size.y)
	else:
		var log_min = log(min_y) / log(10)
		var log_max = log(max_y) / log(10)
		
		var log_value = log(automation_y_value) / log(10)
		
		var t = inverse_lerp(log_min, log_max, log_value)
		
		t = 1.0 - t
		
		point_y_pos = lerp(0.0, self.size.y, t)
	return point_y_pos

func convert_to_automation_value(screen_position: Vector2) -> Vector2:
	var point_x_value = ((100 / zoom_factor) * (screen_position.x / self.size.x)) + zoomed_offset
	var point_y_value
	
	if !exponential:
		point_y_value = (((self.size.y - screen_position.y) / self.size.y) * (max_y - min_y)) + min_y
	else:
		#normalise value from 0 to 1 and invert to match inverted coordinate system
		var t = clamp(screen_position.y / self.size.y, 0.0, 1.0)
		t = 1.0 - t
		var log_min = log(min_y) / log(10)
		var log_max = log(max_y) / log(10)
		var log_val = lerp(log_min, log_max, t)
		point_y_value = pow(10.0, log_val)
		
	return Vector2(point_x_value, point_y_value)
	
func sort_points(a, b):
	return a.x < b.x

func get_point_at_pos(pos: Vector2, tolerance_scaler: float) -> int:
	var x_tolerance = (0.7 / zoom_factor) * tolerance_scaler
	var y_tolerance = (max_y - min_y) / (self.size.y * 0.4) * tolerance_scaler
	
	var i = 0
	for point in automation_points:
		var x_difference = point.x - pos.x
		if x_difference >= (x_tolerance * -1) and x_difference <= x_tolerance:
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


func _on_pencil_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		alt_tool = "pencil"
		#print(alt_tool)

func _on_erase_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		alt_tool = "erase"


func _on_expand_v_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		alt_tool = "scale_v"


func _on_expand_h_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		alt_tool = "scale_h"


func _on_skew_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		alt_tool = "skew"
		


func _on_curve_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		if alt_tool != "curve":
			alt_tool = "curve"
		else:
			match curve_mode:
				"ease_in":
					curve_mode = "ease_out"
					$"../../EditorData/CurveButton".icon = ease_out_icon
				"ease_out":
					curve_mode = "s_curve"
					$"../../EditorData/CurveButton".icon = s_curve_icon
				"s_curve":
					curve_mode = "ease_in"
					$"../../EditorData/CurveButton".icon = ease_in_icon



func _on_automation_scroll_bar_value_changed(value: float) -> void:
	zoomed_offset = value
	queue_redraw()
