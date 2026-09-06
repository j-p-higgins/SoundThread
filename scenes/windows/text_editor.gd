extends VBoxContainer

var automation_points = []

@onready var main_container = $ScrollContainer/MarginContainer/TextEditorGridContainer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func create_gui() -> void:
	for child in main_container.get_children():
		child.queue_free()
	automation_points.sort_custom(sort_points)
	var label_x = Label.new()
	var label_y = Label.new()
	var dummy = Label.new()
	var dummy2 = Label.new()
	
	label_x.text = "Time (%)"
	label_y.text = "Value"
	
	main_container.add_child(label_x)
	main_container.add_child(label_y)
	main_container.add_child(dummy)
	main_container.add_child(dummy2)
	
	for point in automation_points:
		var point_x = LineEdit.new()
		var point_y = LineEdit.new()
		var remove_point = Button.new()
		var add_point = Button.new()
		
		point_x.text = str(point.x)
		point_y.text = str(point.y)
		remove_point.text = "x"
		add_point.text = "+"
		
		point_x.custom_minimum_size.x = 300
		point_y.custom_minimum_size.x = 300
		remove_point.custom_minimum_size.x = 30
		add_point.custom_minimum_size.x = 30
		
		remove_point.pressed.connect(_remove_point.bind(remove_point))
		add_point.pressed.connect(_add_point.bind(add_point))
		
		main_container.add_child(point_x)
		main_container.add_child(point_y)
		main_container.add_child(remove_point)
		main_container.add_child(add_point)
		
		
	
	
func sort_points(a, b):
	return a.x < b.x

func _remove_point(button: Button) -> void:
	var position = button.get_index()
	
	main_container.get_child(position - 2).queue_free()
	main_container.get_child(position - 1).queue_free()
	main_container.get_child(position).queue_free()
	main_container.get_child(position + 1).queue_free()

func _add_point(button: Button) -> void:
	var position = button.get_index()
	
	var point_x = LineEdit.new()
	var point_y = LineEdit.new()
	var remove_point = Button.new()
	var add_point = Button.new()
	
	point_x.text = "test"
	point_y.text = "test"
	remove_point.text = "x"
	add_point.text = "+"
	
	main_container.add_child(point_x)
	main_container.add_child(point_y)
	main_container.add_child(remove_point)
	main_container.add_child(add_point)
	
	remove_point.pressed.connect(_remove_point.bind(remove_point))
	add_point.pressed.connect(_add_point.bind(add_point))
	
	main_container.move_child(point_x, position + 1)
	main_container.move_child(point_y, position + 2)
	main_container.move_child(remove_point, position + 3)
	main_container.move_child(add_point, position + 4)
