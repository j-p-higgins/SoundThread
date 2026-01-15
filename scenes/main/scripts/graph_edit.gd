extends GraphEdit

var control_script
var graph_edit
var open_help
var multiple_connections
var selected_nodes = {} #used to track which nodes in the GraphEdit are selected
var copied_nodes_data = [] #stores node data on ctrl+c
var copied_connections = [] #stores all connections on ctrl+c
var last_pasted_nodes = [] #stores last pasted nodes for undo/redo
var node_data = {} #stores json with all nodes in it
var valueslider = preload("res://scenes/Nodes/valueslider.tscn") #slider scene for use in nodes
var addremoveinlets = preload("res://scenes/Nodes/addremoveinlets.tscn") #add remove inlets scene for use in nodes
var node_logic = preload("res://scenes/Nodes/node_logic.gd") #load the script logic
var selected_cables:= [] #used to track which cables are selected for changing colour and for deletion
var theme_background #used to track if the theme has changed and if so change the cable selection colour
var theme_custom_background
var high_contrast_cables
var vertical_hotzone = 30


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	snapping_enabled = false
	show_grid = false
	zoom = 0.9
	#parse json
	var file = FileAccess.open("res://scenes/main/process_help.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		if typeof(result) == TYPE_DICTIONARY:
			node_data = result
		else:
			push_error("Invalid JSON")
			
	var interface_settings = ConfigHandler.load_interface_settings()
	theme_background = interface_settings.theme
	theme_custom_background = interface_settings.theme_custom_colour
	high_contrast_cables = interface_settings.high_contrast_selected_cables
	set_cable_colour(interface_settings.theme)

func init(main_node: Node, graphedit: GraphEdit, openhelp: Callable, multipleconnections: Window) -> void:
	control_script = main_node
	graph_edit = graphedit
	open_help = openhelp
	multiple_connections = multipleconnections

func _make_node(command: String, skip_undo_redo := false) -> GraphNode:
	if node_data.has(command):
		var node_info = node_data[command]
		
		if node_info.get("category", "") == "utility":
			#Find utility node with matching name and create a version of it in the graph edit
			#and position it close to the origin right click to open the menu
			#var effect: GraphNode = Nodes.get_node(NodePath(command)).duplicate()
			var effect = Utilities.nodes[command].instantiate()
			effect.name = command
			#add node and register it for undo redo
			control_script.undo_redo.create_action("Add Node")
			control_script.undo_redo.add_do_method(add_child.bind(effect, true))
			control_script.undo_redo.add_do_reference(effect)
			control_script.undo_redo.add_undo_method(delete_node.bind(effect))
			control_script.undo_redo.commit_action()
			
			if command == "outputfile":
				effect.init() #initialise ui from user prefs
			effect.connect("open_help", open_help)
			if effect.has_signal("node_moved"):
				effect.node_moved.connect(_auto_link_nodes)
			effect.dragged.connect(node_position_changed.bind(effect))
			effect.set_position_offset((control_script.effect_position + graph_edit.scroll_offset) / graph_edit.zoom) #set node to current mouse position in graph edit
			_register_inputs_in_node(effect) #link sliders for changes tracking
			_register_node_movement() #link nodes for tracking position changes for changes tracking

			control_script.changesmade = true

			
			
			return effect
		else: #auto generate node from json
			#get the title to display at the top of the node
			var title 
			if node_info.get("category", "") == "pvoc":
				title = "%s: %s" % [node_info.get("category", "").to_upper(), node_info.get("title", "")]
			else:
				title = "%s: %s" % [node_info.get("subcategory", "").to_pascal_case(), node_info.get("title", "")]
			var shortdescription = node_info.get("short_description", "") #for tooltip
			
			#get node properties
			var stereo = node_info.get("stereo", false)
			var outputisstereo = node_info.get("outputisstereo", false) #used to identify the few processes that always output in stereo making the thread need to be stereo
			var inputs = JSON.parse_string(node_info.get("inputtype", ""))
			var outputs = JSON.parse_string(node_info.get("outputtype", ""))
			var portcount = max(inputs.size(), outputs.size())
			var parameters = node_info.get("parameters", {})
			
			var graphnode = GraphNode.new()
			
			#set meta data for the process
			graphnode.set_meta("command", command)
			graphnode.set_meta("stereo_input", stereo)
			graphnode.set_meta("output_is_stereo", outputisstereo)
			if inputs.size() == 0 and outputs.size() > 0:
				graphnode.set_meta("input", true)
			else:
				graphnode.set_meta("input", false)
			
			#adjust size, position and title of the node
			graphnode.title = title
			graphnode.tooltip_text = shortdescription
			graphnode.size.x = 306
			graphnode.custom_minimum_size.y = 80
			graphnode.set_position_offset((control_script.effect_position + graph_edit.scroll_offset) / graph_edit.zoom)
			graphnode.name = command
			
			#add one small control node to the top of the node to aline first inlet to top
			var first_inlet = Control.new()
			graphnode.add_child(first_inlet)
			
			if parameters.is_empty():
				var noparams = Label.new()
				noparams.text = "No adjustable parameters"
				noparams.custom_minimum_size.x = 270
				noparams.custom_minimum_size.y = 57
				noparams.vertical_alignment = 1
				
				graphnode.add_child(noparams)
			else:
				for param_key in parameters.keys():
					var param_data = parameters[param_key]
					if param_data.get("uitype", "") == "hslider":
						#instance the slider scene
						var slider = valueslider.instantiate()
						
						slider.undo_redo = control_script.undo_redo
						
						
						#get slider text
						var slider_label = param_data.get("paramname", "")
						var slider_tooltip  = param_data.get("paramdescription", "")
						
						#name slider
						slider.name = slider_label.replace(" ", "")
						
						#get slider properties
						var brk = param_data.get("automatable", false)
						var time = param_data.get("time", false)
						var outputduration = param_data.get("outputduration", false)
						var minimum = param_data.get("min", false)
						var maximum = param_data.get("max", false)
						var flag = param_data.get("flag", "")
						var fftwindowsize = param_data.get("fftwindowsize", false)
						var fftwindowcount = param_data.get("fftwindowcount", false)
						var minrange = param_data.get("minrange", 0)
						var maxrange = param_data.get("maxrange", 10)
						var step = param_data.get("step", 0.01)
						var value = param_data.get("value", 1)
						var exponential = param_data.get("exponential", false)
						
						#set labels and tooltips
						slider.get_node("SliderLabel").text = slider_label
						if brk == true:
							slider.get_node("SliderLabel").text += "~"
						slider.tooltip_text = slider_tooltip
						slider.get_node("SliderLabel").tooltip_text = slider_tooltip
						
						#set meta data
						var hslider = slider.get_node("HSplitContainer/HSlider")
						hslider.set_meta("brk", brk)
						hslider.set_meta("time", time)
						hslider.set_meta("min", minimum)
						hslider.set_meta("max", maximum)
						hslider.set_meta("flag", flag)
						hslider.set_meta("default_value", value)
						hslider.set_meta("fftwindowsize", fftwindowsize)
						hslider.set_meta("fftwindowcount", fftwindowcount)
						
						#set slider params
						hslider.min_value = minrange
						hslider.max_value = maxrange
						hslider.step = step
						hslider.value = value
						slider.previous_value = value #used for undo redo
						hslider.exp_edit = exponential
						
						#add output duration meta to main if true
						if outputduration:
							graphnode.set_meta("outputduration", value)
							
						#scale automation window
						var automationwindow = slider.get_node("BreakFileMaker")
						if automationwindow.content_scale_factor < control_script.uiscale:
							automationwindow.size = automationwindow.size * control_script.uiscale
							automationwindow.content_scale_factor = control_script.uiscale
						
						graphnode.add_child(slider)
					
					elif param_data.get("uitype", "") == "checkbutton":
						#make a checkbutton
						var checkbutton = CheckButton.new()
						
						#get button text
						var checkbutton_label = param_data.get("paramname", "")
						var checkbutton_tooltip  = param_data.get("paramdescription", "")
						
						#name checkbutton
						checkbutton.name = checkbutton_label.replace(" ", "")
						
						#get checkbutton properties
						var flag = param_data.get("flag", "")
						
						checkbutton.text = checkbutton_label
						checkbutton.tooltip_text = checkbutton_tooltip
						
						var checkbutton_pressed = param_data.get("value", "false")
						#get button state
						if str(checkbutton_pressed).to_lower() == "true":
							checkbutton.button_pressed = true
							
						#set checkbutton meta
						checkbutton.set_meta("flag", flag)
						
						graphnode.add_child(checkbutton)
					elif param_data.get("uitype", "") == "optionbutton":
						#make optionbutton and label
						var label = Label.new()
						var optionbutton = OptionButton.new()
						var margin = MarginContainer.new()
						
						#get button text
						var optionbutton_label = param_data.get("paramname", "")
						var optionbutton_tooltip  = param_data.get("paramdescription", "")
						
						#name optionbutton
						optionbutton.name = optionbutton_label.replace(" ", "").to_lower()
						
						#add meta flag if this is a sample rate selector for running thread sample rate checks
						if optionbutton.name == "samplerate":
							graphnode.set_meta("node_sets_sample_rate", true)
						
						#get optionbutton properties
						var options = JSON.parse_string(param_data.get("step", ""))
						var value = param_data.get("value", 1)
						var flag = param_data.get("flag", "")
						
						label.text = optionbutton_label
						optionbutton.tooltip_text = optionbutton_tooltip
						
						#fill option button
						for option in options:
							optionbutton.add_item(str(option))
						
						
						#select the given id
						optionbutton.select(int(value))
						
						#set flag meta
						optionbutton.set_meta("flag", flag)
						
						#add margin size for vertical spacing
						margin.add_theme_constant_override("margin_bottom", 4)
						
						graphnode.add_child(label)
						graphnode.add_child(optionbutton)
						graphnode.add_child(margin)
					elif param_data.get("uitype", "") == "addremoveinlets":
						var addremove = addremoveinlets.instantiate()
						addremove.name = "addremoveinlets"
						addremove.undo_redo = control_script.undo_redo #link to main undo redo
						
						#get parameters
						var min_inlets = param_data.get("minrange", 0)
						var max_inlets = param_data.get("maxrange", 10)
						var default_inlets = param_data.get("value", 1)
						
						#set meta
						addremove.set_meta("min", min_inlets)
						addremove.set_meta("max", max_inlets)
						addremove.set_meta("default", default_inlets)
						
						graphnode.add_child(addremove)
				
				control_script.changesmade = true
			
			#add control nodes if number of child nodes is lower than the number of inlets or outlets
			for i in range(portcount - graphnode.get_child_count()):
				#add a number of control nodes equal to whatever is higher input or output ports
				var control = Control.new()
				control.custom_minimum_size.y = 57
				graphnode.add_child(control)
				if graphnode.has_node("addremoveinlets"):
					graphnode.move_child(graphnode.get_node("addremoveinlets"), graphnode.get_child_count() - 1)
			
			#add ports
			for i in range(portcount):
				#check if input or output is enabled
				var enable_input = i < inputs.size()
				var enable_output = i < outputs.size()
				
				#get the colour of the port for time or pvoc ins/outs
				var input_colour = Color("#ffffff90")
				var output_colour = Color("#ffffff90")
				
				if enable_input:
					if inputs[i] == 1:
						input_colour = Color("#000000b0")
				if enable_output:
					if outputs[i] == 1:
						output_colour = Color("#000000b0")
				
				#enable and set ports
				if enable_input == true and enable_output == false:
					graphnode.set_slot(i, true, inputs[i], input_colour, false, 0, output_colour)
				elif enable_input == false and enable_output == true:
					graphnode.set_slot(i, false, 0, input_colour, true, outputs[i], output_colour)
				elif enable_input == true and enable_output == true:
					graphnode.set_slot(i, true, inputs[i], input_colour, true, outputs[i], output_colour)
				else:
					pass
			
			graphnode.set_script(node_logic)
			
			control_script.undo_redo.create_action("Add Node")
			control_script.undo_redo.add_do_method(add_child.bind(graphnode))
			control_script.undo_redo.add_do_reference(graphnode)
			control_script.undo_redo.add_undo_method(delete_node.bind(graphnode))
			control_script.undo_redo.commit_action()
			graphnode.undo_redo = control_script.undo_redo
			graphnode.connect("open_help", open_help)
			graphnode.connect("inlet_removed", Callable(self, "on_inlet_removed"))
			graphnode.node_moved.connect(_auto_link_nodes)
			graphnode.dragged.connect(node_position_changed.bind(graphnode))
			_register_inputs_in_node(graphnode) #link sliders for changes tracking
			_register_node_movement() #link nodes for tracking position changes for changes tracking
			
			
			
			
			return graphnode
			
	return null
	

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	#check if this is trying to connect a node to itself and skip
	if from_node == to_node:
		return
	
	var to_graph_node = get_node(NodePath(to_node))
	var from_graph_node = get_node(NodePath(from_node))

	# Get the type of the ports
	var to_port_type = to_graph_node.get_input_port_type(to_port)
	var from_port_type = from_graph_node.get_output_port_type(from_port)
	
	#skip if the nodes are already connected
	if is_node_connected(from_node, from_port, to_node, to_port):
		return
	
	#skip if this isnt a valid connection
	if to_port_type != from_port_type:
		return

	# If port type is 1 and already has a connection, reject the request
	if to_port_type == 1:
		var connections = get_connection_list()
		var existing_connections = 0

		for conn in connections:
			if conn.to_node == to_node and conn.to_port == to_port:
				existing_connections += 1
				if existing_connections >= 1:
					var interface_settings = ConfigHandler.load_interface_settings()
					if interface_settings.disable_pvoc_warning == false:
						multiple_connections.popup_centered()
					return
					
	if from_graph_node.get_meta("command") == "inputfile" and to_graph_node.get_meta("command") == "outputfile":
		return

	
	# If no conflict, allow the connection
	control_script.undo_redo.create_action("Connect Nodes")
	control_script.undo_redo.add_do_method(connect_node.bind(from_node, from_port, to_node, to_port))
	control_script.undo_redo.add_undo_method(disconnect_node.bind(from_node, from_port, to_node, to_port))
	control_script.undo_redo.commit_action()
	control_script.changesmade = true

func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	control_script.undo_redo.create_action("Disconnect Nodes")
	control_script.undo_redo.add_do_method(disconnect_node.bind(from_node, from_port, to_node, to_port))
	control_script.undo_redo.add_undo_method(connect_node.bind(from_node, from_port, to_node, to_port))
	control_script.undo_redo.commit_action()
	control_script.changesmade = true

func _on_graph_edit_node_selected(node: Node) -> void:
	selected_nodes[node] = true

func _on_graph_edit_node_deselected(node: Node) -> void:
	selected_nodes[node] = false

func _on_cut_nodes_request() -> void:
	if selected_nodes.size() == 0:
		return
	
	control_script.undo_redo.create_action("Dissolve Nodes")
	
	for node in selected_nodes:
		if selected_nodes[node] and node is GraphNode and is_instance_valid(node):
			if node.get_meta("command") == "outputfile":
				continue
			
			var node_connections = []
			var incoming_connections = []
			var outgoing_connections = []
			
			for conn in get_connection_list():
				if conn.to_node == node.name:
					node_connections.append(conn)
					incoming_connections.append(conn)
				elif conn.from_node == node.name:
					node_connections.append(conn)
					outgoing_connections.append(conn)
			
			control_script.undo_redo.add_do_method(delete_node.bind(node))
			control_script.undo_redo.add_undo_method(restore_node.bind(node))
			control_script.undo_redo.add_undo_reference(node)
			control_script.undo_redo.add_undo_method(restore_connections.bind(node_connections.duplicate(true)))
			
			for in_conn in incoming_connections:
				for out_conn in outgoing_connections:
					if _same_port_type(in_conn.from_node, in_conn.from_port, out_conn.to_node, out_conn.to_port):
						control_script.undo_redo.add_do_method(connect_node.bind(in_conn.from_node, in_conn.from_port, out_conn.to_node, out_conn.to_port))
						control_script.undo_redo.add_undo_method(disconnect_node.bind(in_conn.from_node, in_conn.from_port, out_conn.to_node, out_conn.to_port))
	
	selected_nodes = {}
	control_script.undo_redo.commit_action()
	force_hide_tooltips()
	control_script.changesmade = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE:
			_on_graph_edit_delete_nodes_request(PackedStringArray(selected_nodes.keys().filter(func(k): return selected_nodes[k])))
			pass

func _on_graph_edit_delete_nodes_request(nodes: Array[StringName]) -> void:
	if nodes.size() == 0:
		return
	
	control_script.undo_redo.create_action("Delete Nodes")
	
	#Collect node data for undo
	for node_name in nodes:
		var node: GraphNode = get_node_or_null(NodePath(node_name))
		if node and is_instance_valid(node):
			# Skip output nodes
			if node.get_meta("command") == "outputfile":
				continue
			
			#register redo
			control_script.undo_redo.add_do_method(delete_node.bind(node))
			#register undo
			control_script.undo_redo.add_undo_method(restore_node.bind(node))
			#store a reference to the removed node
			control_script.undo_redo.add_undo_reference(node)
			
			
	#remove deleted nodes from the selected nodes dictionary
	selected_nodes = {}

	#get all connections going to the deleted nodes and store them in an array
	var connections_to_restore = get_connections_to_nodes(nodes)
			
	#register undo method for restoring those connections
	control_script.undo_redo.add_undo_method(restore_connections.bind(connections_to_restore))
	control_script.undo_redo.commit_action()
	
	force_hide_tooltips()
	

func delete_node(node_to_delete: GraphNode) -> void:
	remove_connections_to_node(node_to_delete)
	#remove child instead of queue free keeps a reference to the node in memory (until undo limit is hit) meaning nodes can be restored easily
	remove_child(node_to_delete)
	selected_nodes[node_to_delete] = false
	control_script.changesmade = true

func restore_node(node_to_restore: GraphNode) -> void:
	add_child(node_to_restore)
	#relink everything
	if not node_to_restore.is_connected("open_help", open_help):
		node_to_restore.connect("open_help", open_help)
	if not node_to_restore.is_connected("node_moved", _auto_link_nodes):
		node_to_restore.node_moved.connect(_auto_link_nodes)
	if "undo_redo" in node_to_restore:
		node_to_restore.undo_redo = control_script.undo_redo
	for child in node_to_restore.get_children():
		if "undo_redo" in child:
			child.undo_redo = control_script.undo_redo
	if not node_to_restore.is_connected("dragged", node_position_changed):
		node_to_restore.dragged.connect(node_position_changed.bind(node_to_restore))
	set_node_selected(node_to_restore, true)
	_track_changes()
	_register_inputs_in_node(node_to_restore)
	_register_node_movement()
	control_script.changesmade = true
	
func get_connections_to_nodes(nodes: Array) -> Array:
	var connections_to_nodes = []
	for con in get_connection_list():
		if (con["from_node"] in nodes or con["to_node"] in nodes) and !connections_to_nodes.has(con):
			connections_to_nodes.append(con)
	return connections_to_nodes

func restore_connections(connections_to_restore: Array) -> void:
	for con in connections_to_restore:
		var from_node = con["from_node"]
		var from_port = con["from_port"]
		var to_node = con["to_node"]
		var to_port = con["to_port"]
		if has_node(NodePath(from_node)) and has_node(NodePath(to_node)):
			connect_node(from_node, from_port, to_node, to_port)

func set_node_selected(node: Node, selected: bool) -> void:
	selected_nodes[node] = selected
#
func remove_connections_to_node(node):
	for con in get_connection_list():
		if con["to_node"] == node.name or con["from_node"] == node.name:
			disconnect_node(con["from_node"], con["from_port"], con["to_node"], con["to_port"])
			control_script.changesmade = true
			
#copy and paste nodes with vertical offset on paste
func copy_selected_nodes():
	if selected_nodes.size() == 0:
		return
	copied_nodes_data.clear()
	copied_connections.clear()
	
	var copied_node_names = []

	# Store selected nodes
	for node in get_children():
		# Check if the node is selected and not an 'outputfile'
		if node is GraphNode and selected_nodes.get(node, false):
			if node.get_meta("command") == "outputfile":
				continue  # Skip these nodes
			
			#this is throwing errors, i think this is due to it trying to deep copy engine level things it doesn't need such as file dialog elements, seems to work anyway
			var copied_node = node.duplicate()
			
			copied_nodes_data.append(copied_node)
			copied_node_names.append(node.name)

	copied_connections = get_connections_to_nodes(copied_node_names)


func paste_copied_nodes():
	if copied_nodes_data.is_empty():
		return

	var pasted_connections = copied_connections.duplicate(true)
	
	
	control_script.undo_redo.create_action("Paste Nodes")
	
	var pasted_nodes = []
	#Find topmost and bottommost Y of copied nodes and decide where to paste
	var min_y = INF
	var max_y = -INF
	for node in copied_nodes_data:
		var y = node.position_offset.y
		min_y = min(min_y, y)
		max_y = max(max_y, y)

	var base_y_offset = max_y + 350  # Pasting below the lowest node

	# Step 3: Paste nodes, preserving vertical layout
	for node in copied_nodes_data:
		#duplicate the copied node again so it can be pasted more than once and add using restore_node function
		var pasted_node = node.duplicate()
		#give the node a random name
		pasted_node.name = node.name + "_copy_" + str(randi() % 10000) 
		control_script.undo_redo.add_do_method(restore_node.bind(pasted_node))
		control_script.undo_redo.add_do_reference(pasted_node) 
		#adjust the offset of the pasted node to be below the copied node
		var relative_y = pasted_node.position_offset.y - min_y
		pasted_node.position_offset.y = base_y_offset + relative_y
		
		for con in pasted_connections:
			if con["from_node"] == node.name:
				con["from_node"] = pasted_node.name
				print(pasted_node.name)
			if con["to_node"] == node.name:
				con["to_node"] = pasted_node.name
		
		control_script.undo_redo.add_undo_method(delete_node.bind(pasted_node))
		pasted_nodes.append(pasted_node)
	
	control_script.undo_redo.add_do_method(restore_connections.bind(pasted_connections))

	control_script.undo_redo.commit_action()
	
	force_hide_tooltips()
	
	#Select pasted nodes
	for pasted_node in pasted_nodes:
		selected_nodes.clear()
		set_selected(pasted_node)
		selected_nodes[pasted_node] = true
	
	control_script.changesmade = true
	
func force_hide_tooltips():
	#very janky fix that makes and removes a popup in one frame to force the engine to hide all visible popups to stop popups getting stuck
	#seems to be more reliable that faking a middle mouse click
	var popup := Popup.new()
	add_child(popup)
	popup.size = Vector2(1,1)
	popup.transparent_bg = true
	popup.borderless = true
	popup.unresizable = true
	await get_tree().process_frame
	popup.popup()
	popup.queue_free()
	
#functions for tracking changes for save state detection
func _register_inputs_in_node(node: Node):
	#tracks input to nodes sliders and codeedit to track if patch is saved
	# Track Sliders
	for slider in node.find_children("*", "HSlider", true, false):
		# Create a Callable to the correct method
		var callable = Callable(self, "_on_any_slider_changed")
		# Check if it's already connected, and connect if not
		if not slider.is_connected("value_changed", callable):
			slider.connect("value_changed", callable)
	
	for slider in node.find_children("*", "VBoxContainer", true, false):
		# Also connect to meta_changed if the slider has that signal
		if slider.has_signal("meta_changed"):
			var meta_callable = Callable(self, "_on_any_slider_meta_changed")
			if not slider.is_connected("meta_changed", meta_callable):
				slider.connect("meta_changed", meta_callable)
		
	# Track CodeEdits
	for editor in node.find_children("*", "CodeEdit", true, false):
		var callable = Callable(self, "_on_any_input_changed")
		if not editor.is_connected("text_changed", callable):
			editor.connect("text_changed", callable)
			
func _on_any_slider_meta_changed():
	control_script.changesmade = true
	print("Meta changed in slider")
	
func _register_node_movement():
	for graphnode in get_children():
		if graphnode is GraphNode:
			var callable = Callable(self, "_on_graphnode_moved")
			if not graphnode.is_connected("position_offset_changed", callable):
				graphnode.connect("position_offset_changed", callable)

func _on_graphnode_moved():
	control_script.changesmade = true
	
func _on_any_slider_changed(value: float) -> void:
	control_script.changesmade = true
	
func _on_any_input_changed():
	control_script.changesmade = true

func _track_changes():
	control_script.changesmade = true


func _on_copy_nodes_request() -> void:
	graph_edit.copy_selected_nodes()
	#get_viewport().set_input_as_handled()


func _on_paste_nodes_request() -> void:
	control_script.simulate_mouse_click() #hacky fix to stop tooltips getting stuck
	await get_tree().process_frame
	graph_edit.paste_copied_nodes()

func on_inlet_removed(node_name: StringName, port_index: int):
	var connections = get_connection_list()
	for conn in connections:
		if conn.to_node == node_name and conn.to_port == port_index:
			disconnect_node(conn.from_node, conn.from_port, conn.to_node, conn.to_port)
			
func _swap_node(old_node: GraphNode, command: String):
	#store the position and name of the node to be replaced
	var position = old_node.position_offset
	var old_name = old_node.name
	#gather all connections in the graph
	var connections = get_connection_list()
	var related_connections = []
	
	#filter the connections to get just those connected to the node to be replaced
	for conn in connections:
		if conn.from_node == old_name or conn.to_node == old_name:
			related_connections.append(conn)
			
	#delete the old node
	_on_graph_edit_delete_nodes_request([old_node.name])
	
	#make the new node and reposition it to the location of the old node
	var new_node = _make_node(command)
	new_node.position_offset = position
	
	#filter through all the connections to the old node
	for conn in related_connections:
		var from = conn.from_node
		var from_port = conn.from_port
		var to = conn.to_node
		var to_port = conn.to_port
		
		#where the old node is referenced replace it with the name of the new node
		if from == old_name:
			from = new_node.name
		if to == old_name:
			to = new_node.name
			
		#check that the ports being connected to/from on the new node actually exist
		if (from == new_node.name and new_node.is_slot_enabled_right(from_port)) or (to == new_node.name and new_node.is_slot_enabled_left(to_port)):
			#check the two ports are the same type
			if _same_port_type(from, from_port, to, to_port):
				_on_connection_request(from, from_port, to, to_port)
	
func _connect_to_clicked_node(clicked_node: GraphNode, command: String):
	var new_node_position = clicked_node.position_offset + Vector2(clicked_node.size.x + 50, 0)
	#make the new node and reposition it to right of the node to connect to
	var new_node = _make_node(command)
	new_node.position_offset = new_node_position
	
	var clicked_node_has_outputs = clicked_node.get_output_port_count() > 0
	var new_node_has_inputs = new_node.get_input_port_count() > 0
	
	if clicked_node_has_outputs and new_node_has_inputs:
		if _same_port_type(clicked_node.name, 0, new_node.name, 0):
			_on_connection_request(clicked_node.name, 0, new_node.name, 0)


func _on_gui_input(event: InputEvent) -> void:
	#check if this is an unhandled mouse click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		
		#get dictionary of a cable if nearby
		var closest_connection = get_closest_connection_at_point(get_local_mouse_position())
		
		#check if there is anything in that dictionary
		if closest_connection.size() > 0:
			#check if the background has changed colour for highlighted cable colour
			var interface_settings = ConfigHandler.load_interface_settings()
			if interface_settings.theme != theme_background or interface_settings.theme_custom_colour != theme_custom_background or interface_settings.high_contrast_selected_cables != high_contrast_cables:
				#if bg has changed colour since last cable highlight reset to new bg and change cable colour
				theme_background = interface_settings.theme
				theme_custom_background = interface_settings.theme_custom_colour
				high_contrast_cables = interface_settings.high_contrast_selected_cables
				set_cable_colour(interface_settings.theme)
				
			#get details of nearby cable
			var from_node = closest_connection.from_node
			var from_port = closest_connection.from_port
			var to_node = closest_connection.to_node
			var to_port = closest_connection.to_port
			
			#check if user was holding shift and if so allow for multiple cables to be selected
			if event.shift_pressed:
				selected_cables.append(closest_connection)
				set_connection_activity(from_node, from_port, to_node, to_port, 1)
			
			#if user double clicked unselect all cables and delete the nearest cable
			elif event.double_click:
					for conn in selected_cables:
						set_connection_activity(conn.from_node, conn.from_port, conn.to_node, conn.to_port, 0)
					_on_graph_edit_disconnection_request(from_node, from_port, to_node, to_port)
					
			#else just a single click, unselect any previously selected cables and select just the nearest
			else:
				for conn in selected_cables:
					set_connection_activity(conn.from_node, conn.from_port, conn.to_node, conn.to_port, 0)
				selected_cables = []
				selected_cables.append(closest_connection)
				set_connection_activity(from_node, from_port, to_node, to_port, 1)
		
		#user didnt click on a cable unselect all cables
		else:
			for conn in selected_cables:
				set_connection_activity(conn.from_node, conn.from_port, conn.to_node, conn.to_port, 0)
			selected_cables = []
			
	#if this is an unhandled delete check if there are any cables selected and deleted them
	if event is InputEventKey and event.pressed:
		if (event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE) and selected_cables.size() > 0:
			for conn in selected_cables:
				_on_graph_edit_disconnection_request(conn.from_node, conn.from_port, conn.to_node, conn.to_port)
				selected_cables = []
	
func set_cable_colour(theme_colour: int):
	var background_colour
	var cable_colour
	var interface_settings = ConfigHandler.load_interface_settings()
	match theme_colour:
		0:
			background_colour = Color("#2f4f4e")
		1:
			background_colour = Color("#000807")
		2:
			background_colour = Color("#98d4d2")
		3:
			background_colour = Color(interface_settings.theme_custom_colour)
			
	if interface_settings.high_contrast_selected_cables:
		#180 colour shift from background and up sv
		cable_colour = Color.from_hsv(fposmod(background_colour.h + 0.5, 1.0), clamp(background_colour.s + 0.2, 0, 1), clamp(background_colour.v + 0.2, 0, 1))
		var luminance = 0.299 * background_colour.r + 0.587 * background_colour.g + 0.114 * background_colour.b
		if luminance > 0.5 and cable_colour.get_luminance() > 0.5:
			cable_colour = cable_colour.darkened(0.4)
		elif luminance <= 0.5 and cable_colour.get_luminance() < 0.5:
			#increase s and v again
			cable_colour = Color.from_hsv(cable_colour.h, clamp(cable_colour.s + 0.2, 0, 0.8), clamp(cable_colour.v + 0.2, 0, 0.8))
	else:
		#keep hue but up saturation and variance
		cable_colour = Color.from_hsv(background_colour.h, clamp(background_colour.s + 0.2, 0, 1), clamp(background_colour.v + 0.2, 0, 1))
	#overide theme for cable highlight
	add_theme_color_override("activity", cable_colour)

func _auto_link_nodes(node: GraphNode, rect: Rect2):
	#get all cables that overlap with the node being moved
	var potential_connections = get_connections_intersecting_with_rect(rect)
	
	#if there are anyoverlapping and shift is being held down then
	if potential_connections.size() > 0 and Input.is_action_pressed("auto_link_nodes"):
		#sort through all the cables that overlap
		for conn in potential_connections:
			#get their info
			var new_node_name = node.name
			var new_node_has_inputs = node.get_input_port_count() > 0
			var new_node_has_outputs = node.get_output_port_count() > 0
			var from = conn.from_node
			var from_port = conn.from_port
			var to = conn.to_node
			var to_port = conn.to_port
			
			if new_node_has_inputs and new_node_has_outputs:
				#connect in the middle of the two nodes if they are the same port type
				var from_matches = _same_port_type(from, from_port, new_node_name, 0)
				var to_matches = _same_port_type(new_node_name, 0, to, to_port)
				
				#skip deleting cables if they are the same as the node being dragged or the ports don't match
				if from_matches and to_matches and from != new_node_name and to != new_node_name:
					_on_graph_edit_disconnection_request(from, from_port, to, to_port)
				if from_matches:
					_on_connection_request(from, from_port, new_node_name, 0)
				if to_matches:
					_on_connection_request(new_node_name, 0, to, to_port)
				

			elif new_node_has_inputs:
				#only has inputs check if the ports match and if they do connect but leave original connection in place
				if _same_port_type(from, from_port, new_node_name, 0):
					_on_connection_request(from, from_port, new_node_name, 0)
					
			elif new_node_has_outputs:
				#only has outputs check if the ports match and if they do connect but leave original connection in place
				if _same_port_type(new_node_name, 0, to, to_port):
					_on_connection_request(new_node_name, 0, to, to_port)

# function for checking if an inlet and an outlet are the same type
func _same_port_type(from: String, from_port: int, to: String, to_port: int) -> bool:
	var from_node = get_node_or_null(NodePath(from))
	var to_node = get_node_or_null(NodePath(to))
	#safety incase one somehow no longer exists
	if from_node != null and to_node != null:
		#check if the port types are the same e.g. both time or both pvoc
		if from_node.get_output_port_type(from_port) == to_node.get_input_port_type(to_port):
			return true
		else:
			return false
	else:
		return false
		
func node_position_changed(from: Vector2, to: Vector2, node: Node) -> void:
	control_script.undo_redo.create_action("Move Node")
	control_script.undo_redo.add_do_method(move_node.bind(node, to))
	control_script.undo_redo.add_undo_method(move_node.bind(node, from))
	control_script.undo_redo.commit_action()

func move_node(node: Node, to: Vector2) -> void:
	node.position_offset = to

func _is_in_input_hotzone(in_node: Object, in_port: int, mouse_position: Vector2) -> bool:
	var port_size = Vector2(get_theme_constant("port_hotzone_inner_extent"), vertical_hotzone * 2)
	var port_pos = in_node.get_position() + in_node.get_input_port_position(in_port) - port_size / 2
	var rect = Rect2(port_pos, port_size)
	return rect.has_point(mouse_position)

func _is_in_output_hotzone(in_node: Object, in_port: int, mouse_position: Vector2) -> bool:
	var port_size = Vector2(get_theme_constant("port_hotzone_outer_extent"), vertical_hotzone * 2)
	var port_pos = in_node.get_position() + in_node.get_output_port_position(in_port) - port_size / 2
	var rect = Rect2(port_pos, port_size)
	return rect.has_point(mouse_position)
