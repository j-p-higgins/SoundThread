extends Node
var control_script
var help_data := {} #stores help data for each node to display in help popup
var shortcuts_data:= {}
var HelpWindowScene = preload("res://scenes/main/help_window.tscn")

func _ready() -> void:
	var file = FileAccess.open("res://scenes/main/process_help.json", FileAccess.READ)
	if file:
		help_data = JSON.parse_string(file.get_as_text())
		
	var shortcuts_file = FileAccess.open("res://scenes/main/shortcuts.json", FileAccess.READ)
	if shortcuts_file:
		shortcuts_data = JSON.parse_string(shortcuts_file.get_as_text())

func init(main_node: Node) -> void:
	control_script = main_node

func show_help_for_node(node_name: String, node_title: String):
	#check if there is already a help window open for this node and pop it up instead of making a new one
	if is_help_open(node_title):
		return
		
	if help_data.has(node_name):
		#looks up the help data from the json and stores it in info
		var info = help_data[node_name]
		#makes an instance of the help_window scene
		var help_window = HelpWindowScene.instantiate()
		help_window.title = "Help - " + node_title
		help_window.get_node("HelpTitle").text = node_title
		
		var output = ""
		output += info.get("short_description", "") + "\n\n"
		
		var parameters = info.get("parameters", {})
		#checks if there are parameters and if there are places them in a table
		if parameters.size() > 0:
			output += "[table=3]\n"
			output += "[cell][b]Parameter Name[/b][/cell][cell][b]Description[/b][/cell][cell][b]Automatable[/b][/cell]\n"
			for key in parameters.keys(): #scans through all parameters
				var param = parameters[key]
				var paramname = param.get("paramname", "")
				var desc = param.get("paramdescription", "")
				var automatable = param.get("automatable", false)
				var autom_text = "[center]✓[/center]" if automatable else "[center]𐄂[/center]" #replaces true and false with ticks and crosses
				output += "[cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]\n" % [paramname, desc, autom_text] #places each param detail into cells of the table
			output += "[/table]\n\n" #ends the table
		
		output += "[b]Functionality[/b]\n"
		var description_text = info.get("description", "")
		output += description_text.strip_edges()
		#check if this is a cdp process or a utility and display the cdp process if it is one
		var category = info.get("category", "")
		if category != "utility":
			output += "\n\n[b]CDP Process[/b]\nThis node runs the CDP Process: " + node_name.replace("_", " ")
		
		help_window.get_node("HelpText").bbcode_text = output
		help_window.get_node("HelpText").scroll_to_line(0) #scrolls to the first line of the help file just incase
		
		# Add to the current scene tree to show it
		get_tree().current_scene.add_child(help_window)
		
		#sort out dpi and custom scaling
		if help_window.content_scale_factor < control_script.uiscale:
			help_window.size = help_window.size * control_script.uiscale
			help_window.content_scale_factor = control_script.uiscale
		help_window.add_to_group("popup_windows")
		
		help_window.popup() 
		
	else:
		# If no help available, even though there always should be, show a window saying no help found
		var help_window = HelpWindowScene.instance()
		help_window.title = "Help - " + node_title
		help_window.get_node("HelpTitle").text = node_title
		help_window.get_node("HelpText").bbcode_text = "No help found."
		get_tree().current_scene.add_child(help_window)
		help_window.popup()

func open_keyboard_shortcuts_help():
	var title = "Keyboard/Mouse Shortcuts"
	#check if there is already a help window open for this node and pop it up instead of making a new one
	if is_help_open(title):
		return
		
	var help_window = HelpWindowScene.instantiate()
	help_window.title = "Help - " + title
	help_window.get_node("HelpTitle").text = title
	
	var help_text = "The main shortcuts available in SoundThread\n\n"
	help_text += "[table=2]"
		
	for section in shortcuts_data.keys():
		help_text += "[cell][b]" + section + "[/b][/cell][cell][/cell]"
		var shortcuts = shortcuts_data.get(section, {})
		for action in shortcuts.keys():
			var shortcut = shortcuts[action]
			help_text += "[cell]%s[/cell][cell]%s[/cell]" % [action, shortcut]
		help_text += "[cell] [/cell][cell][/cell]"
	help_text += "[/table]\n\n"
	help_text += "Note: controls for navigating a thread can be swapped in the settings."
	
	if OS.get_name() == "macOS":
		help_text = help_text.replace("Ctrl", "Cmd")
	
	help_window.get_node("HelpText").bbcode_text = help_text
	help_window.get_node("HelpText").scroll_to_line(0) #scrolls to the first line of the help file just incase
	
	# Add to the current scene tree to show it
	get_tree().current_scene.add_child(help_window)
	if help_window.content_scale_factor < control_script.uiscale:
		help_window.size = help_window.size * control_script.uiscale
		help_window.content_scale_factor = control_script.uiscale
	
	help_window.popup() 
	
func is_help_open(node_title: String) -> bool:
	for child in get_tree().current_scene.get_children():
		if child is Window and child.title == "Help - " + node_title:
			# Found existing window, bring it to front
			if child.is_visible():
				child.hide()
				child.popup()
			else:
				child.popup()
			return true
	return false
