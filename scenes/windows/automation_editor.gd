extends Control
class_name AutomationEditor

const max_zoom = 10.0
const zoom_per_scroll = 0.2
const point_size = 10

var zoom_factor = 1.0
var zoomed_offset = 0.0

var min_y: float
var max_y: float
var exponential: bool

var automation_points = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	

func _gui_input(event):
	if event is InputEventMouseButton:
		# double-click: delete only if not fixed, otherwise add new
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			add_remove_point(event.position)

		# begin drag on press
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("Drag Started")
			print(event.position)

		# end drag on release
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			print("Drag released")
			
		# edit point value
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			print("Right CLick")
		
		# zoom in
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_automation(zoom_per_scroll, event.position.x)
			
		# zoom out
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_automation(zoom_per_scroll * -1, event.position.x)
			
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
	else:
		automation_points.append(automation_value)
		
	queue_redraw()

func _draw():
	var sorted = []
	sorted = automation_points.duplicate()
	sorted.sort_custom(sort_points)
	
	var screen_points = []
	for point in sorted:
		var screen_point = convert_to_screen_position(point)
		
		screen_points.append(screen_point)
	
	for i in range(automation_points.size() - 1):
		var point_a = screen_points[i]
		var point_b = screen_points[i + 1]
		
		if point_b.x < 0:
			continue
		
		if point_a.x > size.x:
			continue
		
		draw_dashed_line(point_a, point_b, Color(0.7, 0.7, 0.7, 0.6), 2.0, 6.0, true, true)
	
	var maximum_percent = (100 / zoom_factor) + zoomed_offset
	
	for point in screen_points:
		if point.x >= 0 and point.x <= self.size.x:
			draw_rect(Rect2(point.x - (point_size / 2), point.y  - (point_size / 2), point_size, point_size), Color(0.9, 0.9, 0.9, 0.8))

func convert_to_screen_position(automation_point: Vector2) -> Vector2:
	var point_x_pos = (((automation_point.x - zoomed_offset) * zoom_factor) / 100) * self.size.x
	var point_y_pos = self.size.y - (((automation_point.y - min_y) / (max_y - min_y)) * self.size.y)
	
	return Vector2(point_x_pos, point_y_pos)

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
