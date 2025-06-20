extends PopupPanel

@onready var item_container: VBoxContainer = $VBoxContainer/ScrollContainer/ItemContainer
@onready var scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var search_bar = $VBoxContainer/SearchBar
var node_data = {} #stores node data for each node to display in help popup
signal make_node(command)


func _ready() -> void:
	#parse json
	var file = FileAccess.open("res://scenes/main/process_help.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		if typeof(result) == TYPE_DICTIONARY:
			node_data = result
		else:
			push_error("Invalid JSON")
				
	#honestly not sure what of these is actually doing things
	item_container.custom_minimum_size.x = scroll_container.size.x
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.set("theme_override_constants/maximum_height", 400)



func _on_about_to_popup() -> void:
	display_items("") #populate menu when needed
	search_bar.clear()
	search_bar.grab_focus()

func display_items(filter: String):
	# Remove all existing items from the VBoxContainer
	for child in item_container.get_children():
		child.queue_free()
		
	var filters = filter.to_lower().split(" ", false)
	
	for key in node_data.keys():
		var item = node_data[key]
		var title = item.get("title", "")
		
		#filter out output node
		if title == "Output File":
			continue
		
		var category = item.get("category", "")
		var subcategory = item.get("subcategory", "")
		var short_desc = item.get("short_description", "")
		var command = key.replace("_", " ")
		
		
		# Combine all searchable text into one lowercase string
		var searchable_text = "%s %s %s %s %s" % [title, short_desc, category, subcategory, key]
		searchable_text = searchable_text.to_lower()
		
		# If filter is not empty, skip non-matches populate all other buttons
		if filter != "":
			var match_all_words = true
			for word in filters:
				if word != "" and not searchable_text.findn(word) != -1:
					match_all_words = false
					break
			if not match_all_words:
				continue
		
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL #make buttons wide
		btn.alignment = 0 #left align text
		btn.clip_text = true #clip off labels that are too long
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS #and replace with ...
		if category.to_lower() == "pvoc": #format node names correctly, only show the category for PVOC
			btn.text = "%s %s: %s - %s" % [category.to_upper(), subcategory.to_pascal_case(), title, short_desc]
		elif title.to_lower() == "input file":
			btn.text = "%s - %s" % [title, short_desc]
		else:
			btn.text = "%s: %s - %s" % [subcategory.to_pascal_case(), title, short_desc]
		btn.connect("pressed", Callable(self, "_on_item_selected").bind(key)) #pass key (process name) when button is pressed
		
		#apply custom focus theme for keyboard naviagation
		var theme := Theme.new()
		var style_focus := StyleBoxFlat.new()
		style_focus.bg_color = Color.hex(0xffffff4a)
		theme.set_stylebox("focus", "Button", style_focus)
		btn.theme = theme
		
		item_container.add_child(btn)
	
	#resize menu within certain bounds #50
	await get_tree().process_frame
	if DisplayServer.screen_get_dpi(0) >= 144:
		self.size.y = min((item_container.size.y + search_bar.size.y + 12) * 2, 820) #i think this will scale for retina screens but might be wrong
	else:
		self.size.y = min(item_container.size.y + search_bar.size.y + 12, 410)
	
	#highlight first button
	_on_search_bar_editing_toggled(true)
	
func _on_search_bar_text_changed(new_text: String) -> void:
	display_items(new_text)
	
func _on_item_selected(key: String):
	self.hide()
	make_node.emit(key) # send out signal to main patch

func _on_search_bar_text_submitted(new_text: String) -> void:
	var button = item_container.get_child(0)
	if button and button is Button:
		button.emit_signal("pressed")


func _on_search_bar_editing_toggled(toggled_on: bool) -> void:
	#highlight first button when editing is toggled
	var button = item_container.get_child(0)
	if toggled_on:
		if button and button is Button:
			var base_stylebox = button.get_theme_stylebox("normal", "Button")
			var new_stylebox = base_stylebox.duplicate()
			new_stylebox.bg_color = Color.hex(0xffffff4a)
			button.add_theme_stylebox_override("normal", new_stylebox)
			#skip this button on tab navigation
			button.focus_mode = Control.FOCUS_CLICK
	else:
		if button and button is Button:
			button.remove_theme_stylebox_override("normal")
