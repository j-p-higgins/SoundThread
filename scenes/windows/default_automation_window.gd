extends Window

var min_x = 0.0 #min max values currently filled with arbitrary values, will be assigned when window is actually made
var max_x = 100.0
var min_y: float
var max_y: float
var exponential: bool

@onready var automation_editor = $"TabContainer/Visual Editor/PanelContainer/AutomationEditor"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$"TabContainer/Visual Editor/Label".text = "Min: " + str(min_y) + ", Max: " + str(max_y) + ", Exponential: " + str(exponential)
	
	automation_editor.min_y = min_y
	automation_editor.max_y = max_y
	automation_editor.exponential = exponential

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_close_requested() -> void:
	self.hide()
	self.queue_free()
