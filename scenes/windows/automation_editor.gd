extends Control
class_name AutomationEditor

const max_zoom = 5.0
const zoom_per_scroll = 0.3
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
	
	#dummy automation for testing - DELETE
	automation_points = [Vector2(0.0, 5), Vector2(10, 40), Vector2(20, 30), Vector2(30, 55), Vector2(40, 25), Vector2(50, 10), Vector2(60, 20), Vector2(70, 10), Vector2(80, 40), Vector2(90, 20), Vector2(100, 5)]

func _gui_input(event):
	if event is InputEventMouseButton:
		# double-click: delete only if not fixed, otherwise add new
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			print("Double click")

		# begin drag on press
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("Drag Started")

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
	
func _draw():
	var sorted = []
	sorted = automation_points.duplicate()
	sorted.sort_custom(sort_points)
	#for i in range(automation_points.size() - 1):
		#draw_dashed_line(sorted[i], sorted[i + 1], Color(0.1, 0.1, 0.1, 0.6), 2.0, 6.0, true, true)
	
	var maximum_percent = (100 / zoom_factor) + zoomed_offset
	
	for point in automation_points:
		if point.x >= zoomed_offset and point.x <= maximum_percent:
			var point_x_pos = ((((point.x - zoomed_offset) * zoom_factor) / 100) * self.size.x) - (point_size / 2)
			var point_y_pos = (self.size.y - (((point.y - min_y) / max_y) * self.size.y)) - (point_size / 2)
			draw_rect(Rect2(point_x_pos, point_y_pos, point_size, point_size), Color(0.9, 0.9, 0.9, 0.8))


func sort_points(a, b):
	return a.x < b.x
