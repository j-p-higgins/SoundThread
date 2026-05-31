extends Node

var control_script
var graph_edit
var open_help
var register_movement
var register_input
var link_output

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func init(main_node: Node, graphedit: GraphEdit, openhelp: Callable, registermovement: Callable, registerinput: Callable, linkoutput: Callable) -> void:
	control_script = main_node
	graph_edit = graphedit
	open_help = openhelp
	register_movement = registermovement
	register_input = registerinput
	link_output = linkoutput
	
	
func save_graph_edit(path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("Failed to open file for saving")
		return

	var node_data_list = []
	var connection_data_list = []
	var node_id_map = {}  # Map node name to numeric ID

	var node_id = 1
	# Assign each node a unique numeric ID and gather node data
	for node in graph_edit.get_children():
		if node is GraphNode:
			node_id_map[node.name] = node_id

			var offset = node.position_offset
			var node_data = {
				"id": node_id,
				"name": node.name,
				"command": node.get_meta("command"),
				"offset": { "x": offset.x, "y": offset.y },
				"slider_values": {},
				"addremoveinlets":{},
				"notes": {},
				"checkbutton_states": {},
				"optionbutton_values": {}
			}

			# Save slider values and metadata
			for child in node.find_children("*", "Slider", true, false):
				var relative_path = node.get_path_to(child)
				var path_str = str(relative_path)

				node_data["slider_values"][path_str] = {
					"value": child.value,
					"editable": child.editable,
					"meta": {}
				}
				for key in child.get_meta_list():
					node_data["slider_values"][path_str]["meta"][str(key)] = child.get_meta(key)
				
			#save add remove inlet meta data
			if node.has_node("addremoveinlets"):
				if node.get_node("addremoveinlets").has_meta("inlet_count"):
					node_data["addremoveinlets"]["inlet_count"] = node.get_node("addremoveinlets").get_meta("inlet_count")
					
			# Save notes from CodeEdit children
			for child in node.find_children("*", "CodeEdit", true, false):
				node_data["notes"][child.name] = child.text
			
			#save checkbutton states
			for child in node.find_children("*", "CheckButton", true, false):
				node_data["checkbutton_states"][child.name] = child.button_pressed
			
			#save optionbutton states
			for child in node.find_children("*", "OptionButton", true, false):
				node_data["optionbutton_values"][child.name] = child.selected
				
			node_data_list.append(node_data)
			node_id += 1

	# Save connections using node IDs instead of names
	for conn in graph_edit.get_connection_list():
		# Map from_node and to_node names to IDs
		var from_id = node_id_map.get(conn["from_node"], null)
		var to_id = node_id_map.get(conn["to_node"], null)

		if from_id != null and to_id != null:
			connection_data_list.append({
				"from_node_id": from_id,
				"from_port": conn["from_port"],
				"to_node_id": to_id,
				"to_port": conn["to_port"]
			})
		else:
			print("Warning: Connection references unknown node(s). Skipping connection.")

	var graph_data = {
		"nodes": node_data_list,
		"connections": connection_data_list,
		"fftsize": control_script.fft_size_option_button.selected,
		"fftoverlap": control_script.fft_overlap_option_button.selected
	}

	var json = JSON.new()
	var json_string = json.stringify(graph_data, "\t")
	file.store_string(json_string)
	file.close()
	print("Graph saved.")
	control_script.changesmade = false
	get_window().title = "SoundThread - " + path.get_file().trim_suffix(".thd")
	

func load_graph_edit(path: String):
	control_script.run_thread.clear_cache()
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("Failed to open file for loading")
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		print("Error parsing JSON")
		return

	var graph_data = json.get_data()
	graph_edit.clear_connections()

	# Remove all existing GraphNodes from graph_edit
	for node in graph_edit.get_children():
		if node is GraphNode:
			node.queue_free()

	await get_tree().process_frame  # Ensure nodes are freed before adding new ones
	

	#set fft size and window overlap if available
	if graph_data.has("fftsize"):
		control_script.fft_size_option_button.select(graph_data["fftsize"])
		control_script._on_fft_size_item_selected(graph_data["fftsize"])
	if graph_data.has("fftoverlap"):
		control_script.fft_overlap_option_button.select(graph_data["fftoverlap"])
		control_script._on_fft_overlap_item_selected(graph_data["fftoverlap"])
		
	var id_to_node = {}

	# Create nodes
	for node_data in graph_data["nodes"]:
		var command_name = node_data.get("command", "")
		var new_node = graph_edit._make_node(command_name, true)
		if new_node == null:
			print("Failed to create node for command:", command_name)
			continue

		new_node.name = node_data["name"]
		new_node.position_offset = Vector2(node_data["offset"]["x"], node_data["offset"]["y"])
		id_to_node[node_data["id"]] = new_node

		# Restore sliders
		for slider_path_str in node_data["slider_values"]:
			var slider = new_node.get_node_or_null(slider_path_str)
			if slider and (slider is HSlider or slider is VSlider):
				var slider_info = node_data["slider_values"][slider_path_str]
				if typeof(slider_info) == TYPE_DICTIONARY:
					slider.value = slider_info.get("value", slider.value)
					if slider_info.has("editable"):
						slider.editable = slider_info["editable"]
					if slider_info.has("meta"):
						for key in slider_info["meta"]:
							var value = slider_info["meta"][key]
							if key == "brk_data" and typeof(value) == TYPE_ARRAY:
								var new_array: Array = []
								for item in value:
									if typeof(item) == TYPE_STRING:
										var numbers: PackedStringArray = item.strip_edges().trim_prefix("(").trim_suffix(")").split(",")
										if numbers.size() == 2:
											var x = float(numbers[0])
											var y = float(numbers[1])
											new_array.append(Vector2(x, y))
								value = new_array
							slider.set_meta(key, value)
				else:
					slider.value = slider_info
		
		#fill label for output file node on load
		if new_node.has_meta("command") and new_node.get_meta("command") == "outputfile":
			#set label for last output folder
			var interface_settings = ConfigHandler.load_interface_settings()
			control_script.output_folder_label = new_node.get_node("OutputFolderMargin/OutputFolderLabel")
			if control_script.output_folder_label != null and interface_settings.last_used_output_folder != "no_file":
				control_script.output_folder_label.text = interface_settings.last_used_output_folder
				control_script.output_folder_label.get_parent().tooltip_text = interface_settings.last_used_output_folder

		# Restore notes
		for codeedit_name in node_data["notes"]:
			var codeedit = new_node.find_child(codeedit_name, true, false)
			if codeedit and (codeedit is CodeEdit):
				codeedit.text = node_data["notes"][codeedit_name]
				
		# Restore check buttons if this exists in the file (if statement is to stop crashes when opening old save files)
		if node_data.has("checkbutton_states"):
			for checkbutton_name in node_data["checkbutton_states"]:
				var checkbutton = new_node.find_child(checkbutton_name, true, false)
				if checkbutton and (checkbutton is CheckButton):
					checkbutton.button_pressed = node_data["checkbutton_states"][checkbutton_name]
					
		# Restore option buttons if this exists in the file (if statement is to stop crashes when opening old save files)
		if node_data.has("optionbutton_values"):
			for optionbutton_name in node_data["optionbutton_values"]:
				var optionbutton = new_node.find_child(optionbutton_name, true, false)
				if optionbutton and (optionbutton is OptionButton):
					optionbutton.selected = node_data["optionbutton_values"][optionbutton_name]

		#restore dynamic inlets
		if node_data.has("addremoveinlets") and new_node.has_node("addremoveinlets"):
			print("restoring inlets")
			var addremoveinlets = new_node.get_node("addremoveinlets")
			addremoveinlets.set_meta("inlet_count", node_data["addremoveinlets"]["inlet_count"])
			await get_tree().process_frame
			addremoveinlets.restore_inlets()
		
		
		register_input.call(new_node)

	# Recreate connections
	for conn in graph_data["connections"]:
		var from_node = id_to_node.get(conn["from_node_id"], null)
		var to_node = id_to_node.get(conn["to_node_id"], null)

		if from_node != null and to_node != null:
			graph_edit.connect_node(
				from_node.name, conn["from_port"],
				to_node.name, conn["to_port"]
			)
		else:
			print("Warning: Connection references unknown node ID(s). Skipping connection.")

	link_output.call()
	print("Graph loaded.")
	get_window().title = "SoundThread - " + path.get_file().trim_suffix(".thd")
	
	#clear all undo history from old threads and building this one
	control_script.undo_redo.clear_history()
	control_script.changesmade = false
	
	
