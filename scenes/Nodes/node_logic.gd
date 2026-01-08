extends GraphNode

@export var min_gap: float = 0.5  # editable value in inspector for the minimum gap between min and max
var undo_redo: UndoRedo
var button_states = {}
signal open_help
signal inlet_removed
signal node_moved

func _ready() -> void:
	var sliders := _get_all_hsliders(self) #finds all sliders
	#links sliders to this script
	for slider in sliders:
		slider.value_changed.connect(_on_slider_value_changed.bind(slider))
		
	#link all buttons for undo redo
	get_all_buttons()
	#add button to title bar
	var titlebar = self.get_titlebar_hbox()
	
	#add randomise button
	if sliders.size() > 0:
		var rnd_btn = Button.new()
		rnd_btn.text = "!"
		rnd_btn.tooltip_text = "Randomise Slider Values"
		rnd_btn.connect("pressed", Callable(self, "_randomise_sliders")) #pass key (process name) when button is pressed
		titlebar.add_child(rnd_btn)
	
	#add help button
	var btn = Button.new()
	btn.text = "?"
	btn.tooltip_text = "Open help for " + self.title
	btn.connect("pressed", Callable(self, "_open_help")) #pass key (process name) when button is pressed
	titlebar.add_child(btn)
	
	#add bypass
	var bypass_btn = Button.new()
	bypass_btn.text = "⏻"
	bypass_btn.tooltip_text = "Bypass node from thread processing"
	bypass_btn.pressed.connect(_bypass_node)
	titlebar.add_child(bypass_btn)
	
	await get_tree().process_frame
	#reset_size()
	
	self.position_offset_changed.connect(_on_position_offset_changed)
	
	if self.has_node("addremoveinlets"):
		var addremove = self.get_node("addremoveinlets")
		addremove.add_inlet.connect(add_inlet_to_node)
		addremove.remove_inlet.connect(remove_inlet_from_node)
	

func _get_all_hsliders(node: Node) -> Array:
	#moves through all children recusively to find nested sliders
	var result: Array = []
	for child in node.get_children():
		if child is HSlider:
			result.append(child)
		elif child.has_method("get_children"):
			result += _get_all_hsliders(child)
	return result

func get_all_buttons() -> void:
	for child in get_children():
		if child is OptionButton:
			button_states[child] = child.selected
			child.item_selected.connect(button_changed.bind(child))
		elif child is CheckButton:
			button_states[child] = child.button_pressed
			child.toggled.connect(button_changed.bind(child))
			
func _on_slider_value_changed(value: float, changed_slider: HSlider) -> void:
	#checks if the slider moved has min or max meta data
	var is_min = changed_slider.get_meta("min")
	var is_max = changed_slider.get_meta("max")
	var is_outputduration = false
	
	if changed_slider.has_meta("outputduration"):
		is_outputduration = changed_slider.get_meta("outputduration")
	
	#if not exits function
	if not is_min and not is_max:
		return

	var sliders := _get_all_hsliders(self)

	for other_slider in sliders:
		if other_slider == changed_slider:
			continue
		
		if is_min and other_slider.get_meta("max"):
			var max_value: float = other_slider.value
			if changed_slider.value > max_value - min_gap:
				changed_slider.value = max_value - min_gap
		
		elif is_max and other_slider.get_meta("min"):
			var min_value: float = other_slider.value
			if changed_slider.value < min_value + min_gap:
				changed_slider.value = min_value + min_gap
				
	#set output duration meta if this is the output duration slider
	if is_outputduration:
		set_meta("outputduration", value)

func _open_help():
	open_help.emit(self.get_meta("command"), self.title)

func add_inlet_to_node():
	#called when the + button is pressed on an addremoveinlets node in the graphnode
	var inlet_count = self.get_input_port_count()
	var child_count = self.get_child_count()
	
	#check if the number of children is less than the new inlet count
	if child_count < inlet_count + 1:
		#if so add a new control node for the inlet to connect to
		var control = Control.new()
		control.custom_minimum_size.y = 57
		#give it this meta so it can be found and removed later if needed
		control.set_meta("dummynode", true)
		add_child(control)
		#move the ui for adding/removing inlets to the bottom of the node
		move_child(get_node("addremoveinlets"), get_child_count() - 1)
	
	#add the inlet using the same parameters as the first inlet
	set_slot(inlet_count, true, get_input_port_type(0), get_input_port_color(0), false, 0, get_input_port_color(0))
	
func remove_inlet_from_node():
	var inlet_count = self.get_input_port_count()
	var child_count = self.get_child_count()
	
	#emit a signal to the graphedit script to remove any connections to this inlet
	inlet_removed.emit(self.get_name(), inlet_count - 1)
	#remove the inlet note inlet idx starts at 0 hence inlet_count -1
	set_slot(inlet_count - 1, false, get_input_port_type(0), get_input_port_color(0), false, 0, get_input_port_color(0))
	
	#check if a dummy control node has been added to make this inlet -2 because bottom node is the ui for adding removing inlets and idx starts at 0
	if get_child(child_count - 2).has_meta("dummynode"):
		#remove the dummy node
		get_child(child_count - 2).queue_free()
		#wait a frame for it to be removed
		await get_tree().process_frame
		#update the size of the graphnode to shrink to fit smaller ui
		update_minimum_size()
		size.y = get_combined_minimum_size().y

func _on_position_offset_changed():
	node_moved.emit(self, Rect2(position, size))
	
	
func _randomise_sliders():
	undo_redo.create_action("Randomise Sliders")
	var sliders := _get_all_hsliders(self) #finds all sliders
	#links sliders to this script
	for slider in sliders:
		var minimum = slider.min_value
		var maximum = slider.max_value
		var expo = slider.exp_edit
		
		var rnd = randf()
		var rnd_value
		if expo:
			rnd_value = minimum * pow(maximum / minimum, rnd)
		else:
			rnd_value = (rnd * (maximum - minimum)) + minimum
		
		
		undo_redo.add_do_method(set_slider_value.bind(slider, rnd_value))
		undo_redo.add_undo_method(set_slider_value.bind(slider, slider.value))
		
	undo_redo.commit_action()
func set_slider_value(slider: HSlider, value: float) -> void:
	slider.value = value

func button_changed(value, button) -> void:
	if button_states[button] != value:
		undo_redo.create_action("Change Button Value")
		undo_redo.add_do_method(set_button_value.bind(value, button))
		undo_redo.add_undo_method(set_button_value.bind(button_states[button], button))
		undo_redo.commit_action()
		
func set_button_value(value, button) -> void:
	if button is OptionButton:
		button.selected = value
	elif button is CheckButton:
		button.set_pressed_no_signal(value)
		
	button_states[button] = value

func _bypass_node() -> void:
	if has_meta("bypassed") and get_meta("bypassed"):
		set_meta("bypassed", false)
		self.modulate = Color(1.0, 1.0, 1.0)
	else:
		set_meta("bypassed", true)
		self.modulate = Color(1.0, 1.0, 1.0, 0.5)
