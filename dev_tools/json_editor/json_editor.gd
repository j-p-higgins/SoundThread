extends Control

var node_data = {} #stores json file
@onready var parameter_container = $HBoxContainer/VBoxContainer2/ScrollContainer/parameter_container
var json = "res://scenes/main/process_help.json"

func _ready() -> void:
		
	load_json()
	hidpi_adjustment()
	
func hidpi_adjustment():
	#checks if display is hidpi and scales ui accordingly hidpi - 144
	if DisplayServer.screen_get_dpi(0) >= 144:
		get_window().content_scale_factor = 2.0



func load_json():
	var file = FileAccess.open(json, FileAccess.READ)
	if file:
		node_data = JSON.parse_string(file.get_as_text())
		
	fill_search("")


func fill_search(filter: String):
	# Remove all existing items from the VBoxContainer
	var container = $HBoxContainer/VBoxContainer/search/MarginContainer/VBoxContainer/ScrollContainer/ItemContainer
	for child in container.get_children():
		child.queue_free()
	for key in node_data.keys():
		var item = node_data[key]
		var title = item.get("title", "")
		
		var category = item.get("category", "")
		var subcategory = item.get("subcategory", "")
		var short_desc = item.get("short_description", "")
		
		# If filter is not empty, skip non-matches populate all other buttons
		if filter != "":
			var filter_lc = filter.to_lower()
			if not (filter_lc in title.to_lower() or filter_lc in short_desc.to_lower() or filter_lc in category.to_lower() or filter_lc in subcategory.to_lower()):
				continue
		
		
		var hbox = HBoxContainer.new()
		var label = RichTextLabel.new()
		var editbtn = Button.new()
		var margin = MarginContainer.new()
		
		hbox.size.x = container.size.x
		label.bbcode_enabled = true
		label.text = "[b]%s[/b]\n%s" % [title, short_desc]
		label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		label.set_v_size_flags(Control.SIZE_EXPAND_FILL)
		label.fit_content = true
		
		
		editbtn.text = "Edit"
		editbtn.custom_minimum_size = Vector2(80, 40)
		editbtn.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		editbtn.connect("pressed", Callable(self, "edit_node").bind(key)) #pass key (process name) when button is pressed
		
		margin.add_theme_constant_override("margin_bottom", 3)
		container.add_child(hbox)
		hbox.add_child(label)
		hbox.add_child(editbtn)
		container.add_child(margin)


func _on_search_bar_text_changed(new_text: String) -> void:
	fill_search(new_text)
	
func edit_node(key: String):
	if node_data.has(key):
		#looks up the help data from the json and stores it in info
		var info = node_data[key]
		var parameters = info.get("parameters", {})
		
		$HBoxContainer/VBoxContainer2/HBoxContainer/key.text = key
		$HBoxContainer/VBoxContainer2/HBoxContainer2/category.text = info.get("category", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer3/subcategory.text = info.get("subcategory", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer4/title.text = info.get("title", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer5/shortdescription.text = info.get("short_description", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer7/longdescription.text = info.get("description", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer6/stereo.button_pressed = bool(info.get("stereo"))
		$HBoxContainer/VBoxContainer2/HBoxContainer8/outputisstereo.button_pressed = bool(info.get("outputisstereo"))
		$HBoxContainer/VBoxContainer2/HBoxContainer9/inputtype.text = str(info.get("inputtype", ""))
		$HBoxContainer/VBoxContainer2/HBoxContainer11/outputtype.text = str(info.get("outputtype", ""))
		$HBoxContainer/VBoxContainer2/HBoxContainer10/allowbypass.button_pressed = bool(info.get("allowbypass"))
		
		for child in parameter_container.get_children():
			child.queue_free()
			
		var count = 1
		for param_key in parameters.keys():
			var param_box = VBoxContainer.new()
			param_box.set_h_size_flags(Control.SIZE_EXPAND_FILL)
			parameter_container.add_child(param_box)
			
			var label = Label.new()
			label.text = "Parameter " + str(count)
			param_box.add_child(label)
			
			var param_data = parameters[param_key]
			
			for field_key in param_data.keys():
				var field_value = param_data[field_key]
				
				var hbox = HBoxContainer.new()
				var namelabel = RichTextLabel.new()
				var namefield

				
				namelabel.text = field_key
				namelabel.custom_minimum_size.x = 250
				
				if field_value is bool:
					namefield = CheckBox.new()
					namefield.button_pressed = field_value
				else:
					namefield = LineEdit.new()
					namefield.text = str(field_value)
					namefield.set_h_size_flags(Control.SIZE_EXPAND_FILL)
				
				hbox.add_child(namelabel)
				hbox.add_child(namefield)
				param_box.add_child(hbox)
			
			var delete_button = Button.new()
			delete_button.text = "Delete " + param_data.get("paramname", "")
			delete_button.set_h_size_flags(Control.SIZE_EXPAND)
			delete_button.connect("pressed", Callable(self, "delete_param").bind(param_box))
			param_box.add_child(delete_button)
			
			
			var margin = MarginContainer.new()
			margin.add_theme_constant_override("margin_bottom", 5)
			param_box.add_child(margin)
			
			count += 1
			
func delete_param(container: VBoxContainer):
	container.queue_free()




func _on_button_button_down() -> void:
	var info = node_data["distort_replace"]
	var parameters = info.get("parameters", {})
	var parameter = parameters.get("param1", {})
	
	var param_box = VBoxContainer.new()
	param_box.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	parameter_container.add_child(param_box)
	
	var label = Label.new()
	label.text = "New Parameter"
	param_box.add_child(label)
	
	for field_key in parameter.keys():
		var field_value = parameter[field_key]
		
		var hbox = HBoxContainer.new()
		var namelabel = RichTextLabel.new()
		var namefield

		
		namelabel.text = field_key
		namelabel.custom_minimum_size.x = 250
		
		if field_value is bool:
			namefield = CheckBox.new()
		else:
			namefield = LineEdit.new()
			namefield.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		
		hbox.add_child(namelabel)
		hbox.add_child(namefield)
		param_box.add_child(hbox)
	
	var delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.set_h_size_flags(Control.SIZE_EXPAND)
	delete_button.connect("pressed", Callable(self, "delete_param").bind(param_box))
	param_box.add_child(delete_button)
	
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_bottom", 5)
	param_box.add_child(margin)
	

func save_node(is_new: bool) -> void:
	var key = $HBoxContainer/VBoxContainer2/HBoxContainer/key.text.strip_edges()
	if key == "":
		printerr("Key is empty, cannot save")
		return

	var info = {
		"category": $HBoxContainer/VBoxContainer2/HBoxContainer2/category.text,
		"subcategory": $HBoxContainer/VBoxContainer2/HBoxContainer3/subcategory.text,
		"title": $HBoxContainer/VBoxContainer2/HBoxContainer4/title.text,
		"short_description": $HBoxContainer/VBoxContainer2/HBoxContainer5/shortdescription.text,
		"description": $HBoxContainer/VBoxContainer2/HBoxContainer7/longdescription.text,
		"stereo": $HBoxContainer/VBoxContainer2/HBoxContainer6/stereo.button_pressed,
		"outputisstereo": $HBoxContainer/VBoxContainer2/HBoxContainer8/outputisstereo.button_pressed,
		"inputtype": $HBoxContainer/VBoxContainer2/HBoxContainer9/inputtype.text,
		"outputtype": $HBoxContainer/VBoxContainer2/HBoxContainer11/outputtype.text,
		"allowbypass": $HBoxContainer/VBoxContainer2/HBoxContainer10/allowbypass.button_pressed,
		"parameters": {}
	}

	for param_box in parameter_container.get_children():
		var children = param_box.get_children()
		if children.size() < 2:
			continue

		var param_data = {}
		var param_label = children[0] as Label
		var param_id = "param" + str(parameter_container.get_children().find(param_box) + 1)

		for i in range(1, children.size()):
			var node = children[i]
			if node is HBoxContainer and node.get_child_count() >= 2:
				var field_name = node.get_child(0).text
				var input_field = node.get_child(1)
				var field_value

				if input_field is CheckBox:
					field_value = input_field.button_pressed
				else:
					var raw_text = input_field.text
					if raw_text.is_valid_float():
						field_value = raw_text.to_float()
					elif raw_text.is_valid_int():
						field_value = raw_text.to_int()
					elif raw_text.to_lower() == "true":
						field_value = true
					elif raw_text.to_lower() == "false":
						field_value = false
					else:
						field_value = raw_text

				param_data[field_name] = field_value

		if param_data.size() > 0:
			info["parameters"][param_id] = param_data

	# Save or update entry
	node_data[key] = info

	# Write to file
	var file = FileAccess.open(json, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(node_data, "\t"))  # pretty print with tab indent
		file.close()

	fill_search("")  # refresh list
	$HBoxContainer/VBoxContainer/search/MarginContainer/VBoxContainer/SearchBar.text = ""
	
	



func _on_save_changes_button_down() -> void:
	save_node(false)


func _on_save_new_button_down() -> void:
	save_node(true)


func _on_delete_process_button_down() -> void:
	var key = $HBoxContainer/VBoxContainer2/HBoxContainer/key.text.strip_edges()
	if key == "":
		printerr("No key entered – cannot delete.")
		return
	
	if not node_data.has(key):
		printerr("Key '%s' not found in JSON." % key)
		return

	# Remove entry from the dictionary
	node_data.erase(key)

	# Save updated JSON to file
	var file = FileAccess.open(json, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(node_data, "\t"))  # pretty print
		file.close()

	print("Deleted entry: ", key)

	# refresh the list
	fill_search("")
	$HBoxContainer/VBoxContainer/search/MarginContainer/VBoxContainer/SearchBar.text = ""
	_on_new_process_button_down()



func _on_new_process_button_down() -> void:
	$HBoxContainer/VBoxContainer2/HBoxContainer/key.text = ""
	$HBoxContainer/VBoxContainer2/HBoxContainer2/category.text = ""
	$HBoxContainer/VBoxContainer2/HBoxContainer3/subcategory.text = ""
	$HBoxContainer/VBoxContainer2/HBoxContainer4/title.text = ""
	$HBoxContainer/VBoxContainer2/HBoxContainer5/shortdescription.text = ""
	$HBoxContainer/VBoxContainer2/HBoxContainer7/longdescription.text = ""
	$HBoxContainer/VBoxContainer2/HBoxContainer6/stereo.button_pressed = false
	
	for child in parameter_container.get_children():
			child.queue_free()
	


func _on_sort_json_button_down() -> void:
	var is_windows = OS.get_name() == "Windows"
	
	var json_to_sort = ProjectSettings.globalize_path(json)
	var python_script = ProjectSettings.globalize_path("res://dev_tools/helpers/sort_json.py")
	
	print(json_to_sort)
	print(python_script)

	# Run the Python script with the JSON path as an argument
	var output = []
	var exit_code
	if is_windows:
		exit_code = OS.execute("cmd.exe", ["/c", python_script, json_to_sort], output, true)
	else:
		exit_code = OS.execute("python3", [python_script, json_to_sort], output, true)

	# Optionally print the output or check the result
	print("Exit code: ", exit_code)
	print("Output:\n", output)
	
	fill_search("")  # refresh list
	$HBoxContainer/VBoxContainer/search/MarginContainer/VBoxContainer/SearchBar.text = ""
	
	load_json()
