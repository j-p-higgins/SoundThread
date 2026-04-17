extends Window

var min_x = 0.0 #min max values currently filled with arbitrary values, will be assigned when window is actually made
var max_x = 100.0
var min_y = 0.0
var max_y = 50.0
var exponential = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$"TabContainer/Visual Editor/Label".text = "Min: " + str(min_y) + ", Max: " + str(max_y) + ", Exponential: " + str(exponential)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_close_requested() -> void:
	self.hide()
	self.queue_free()
