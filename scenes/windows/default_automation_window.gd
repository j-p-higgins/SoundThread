extends Window

var min_x = 0.0 #min max values currently filled with arbitrary values, will be assigned when window is actually made
var max_x = 100.0
var min_y: float
var max_y: float
var exponential: bool
var slider_value: float
var automation_values

@onready var tab_container = $TabContainer
@onready var automation_editor = $"TabContainer/Visual Editor/PanelContainer/AutomationEditor"
@onready var text_editor = $"TabContainer/Text Editor"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$"TabContainer/Visual Editor/Label".text = "Min: " + str(min_y) + ", Max: " + str(max_y) + ", Exponential: " + str(exponential)
	
	automation_editor.min_y = min_y
	automation_editor.max_y = max_y
	automation_editor.exponential = exponential
	
	text_editor.min_y = min_y
	text_editor.max_y = max_y
	
	#intialise automation start and end
	if automation_values == null:
		automation_editor.automation_points = [Vector2(0.0, slider_value), Vector2(100, slider_value)]
		text_editor.automation_points = [Vector2(0.0, slider_value), Vector2(100, slider_value)]
	else:
		automation_editor.automation_points = automation_values
		text_editor.automation_points = automation_values

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_close_requested() -> void:

	var data
	#check which tab was edited last and pass that data to the slider
	match tab_container.current_tab:
		0:
			data = automation_editor.automation_points
		1:
			data = text_editor.automation_points
	if data != [Vector2(0.0, slider_value), Vector2(100, slider_value)]:
		#if it does equal this no automation was added only the default state was loaded up and then closed again so dont save
		var instance_id = self.get_meta("slider_id")
		var slider = instance_from_id(instance_id)
		slider.on_automation_data_received(data)
		
	self.hide()
	self.queue_free()


func _on_tab_container_tab_changed(tab: int) -> void:
	match tab:
		0:
			automation_editor.selected_points = []
			automation_editor.automation_points = text_editor.automation_points.duplicate()
			#get last point and move it to position 1 to maintain my stupid data structure
			var last_point = automation_editor.automation_points[automation_editor.automation_points.size() - 1]
			automation_editor.automation_points.insert(1, last_point)
			automation_editor.automation_points.remove_at(automation_editor.automation_points.size() - 1)
			
			automation_editor.select_points_in_drag_range()
		1:
			text_editor.automation_points = automation_editor.automation_points.duplicate()
			text_editor.create_gui()
