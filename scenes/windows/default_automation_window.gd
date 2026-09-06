extends Window

var min_x = 0.0 #min max values currently filled with arbitrary values, will be assigned when window is actually made
var max_x = 100.0
var min_y: float
var max_y: float
var exponential: bool
var slider_value: float
var automation_values

@onready var automation_editor = $"TabContainer/Visual Editor/PanelContainer/AutomationEditor"
@onready var text_editor = $"TabContainer/Text Editor"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$"TabContainer/Visual Editor/Label".text = "Min: " + str(min_y) + ", Max: " + str(max_y) + ", Exponential: " + str(exponential)
	
	automation_editor.min_y = min_y
	automation_editor.max_y = max_y
	automation_editor.exponential = exponential
	
	#intialise automation start and end
	if automation_values == null:
		automation_editor.automation_points = [Vector2(0.0, slider_value), Vector2(100, slider_value)]
	else:
		automation_editor.automation_points = automation_values

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_close_requested() -> void:
	if automation_editor.automation_points == [Vector2(0.0, slider_value), Vector2(100, slider_value)]:
		#user just saw the default values and then closed without drawing anything dont save values
		pass
	else:
		var instance_id = self.get_meta("slider_id")
		var slider = instance_from_id(instance_id)
		var data = automation_editor.automation_points
		slider.on_automation_data_received(data)
	self.hide()
	self.queue_free()


func _on_tab_container_tab_changed(tab: int) -> void:
	if tab == 1:
		text_editor.automation_points = automation_editor.automation_points.duplicate()
		text_editor.create_gui()
