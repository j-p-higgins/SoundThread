extends Control

var mainmenu_visible : bool = false #used to test if mainmenu is open
var effect_position = Vector2(40,40) #tracks mouse position for node placement offset
@onready var graph_edit = $GraphEdit
var cdpprogs_location #stores the cdp programs location from user prefs for easy access
var delete_intermediate_outputs # tracks state of delete intermediate outputs toggle
@onready var console_output: RichTextLabel = $Console/ConsoleOutput
var undo_redo := UndoRedo.new() 
var output_audio_player #tracks the node that is the current output player for linking
var input_audio_player #potentially unused, remove? tracks node that is the current input player for linking
var currentfile = "none" #tracks dir of currently loaded file for saving
var changesmade = false #tracks if user has made changes to the currently loaded save file
var savestate # tracks what the user is trying to do when savechangespopup is called
var helpfile #tracks which help file the user was trying to load when savechangespopup is called
var outfilename #links to the user name for outputfile field
var foldertoggle #links to the reuse folder button
#var lastoutputfolder = "none" #tracks last output folder, this can in future be used to replace global.outfile but i cba right now
var uiscale = 0.0 # tracks the overal ui scale after hidpi adjustment and user offset
var retina_scaling = 1.0 #tracks scaling for retina screens
var use_anyway #used to store the folder selected for cdprogs when it appears the wrong folder is selected but the user wants to use it anyway
var main_theme = preload("res://theme/main_theme.tres") #load the theme
var default_input_node #stores a reference to the input node created on launch to allow auto loading a wav file
var output_folder_label
@onready var fft_size_option_button = $FFTSize
@onready var fft_overlap_option_button = $FFTOverlap


#scripts
var open_help
var run_thread
var save_load

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$mainmenu.hide()
	$NoLocationPopup.hide()
	$Console.hide()
	$NoInputPopup.hide()
	$MultipleConnectionsPopup.hide()
	$AudioSettings.hide()
	$AudioDevicePopup.hide()
	$SearchMenu.hide()
	$Settings.hide()
	$ProgressWindow.hide()
	$WrongFolderPopup.hide()
	$SaveChangesPopup.hide()
	
	$SaveDialog.access = FileDialog.ACCESS_FILESYSTEM
	$SaveDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	$SaveDialog.filters = ["*.thd"]
	
	$LoadDialog.access = FileDialog.ACCESS_FILESYSTEM
	$LoadDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	$LoadDialog.filters = ["*.thd"]
	
	undo_redo.max_steps = 40
	
	get_tree().set_auto_accept_quit(false) #disable closing the app with the x and instead handle it internally
	
	
	load_scripts()
	make_signal_connections()
	hidpi_adjustment()
	check_user_preferences()
	new_patch()
	await get_tree().process_frame
	load_from_filesystem()
	check_cdp_location_set()
	
func load_scripts():
	#load and initialise scripts
	open_help = preload("res://scenes/main/scripts/open_help.gd").new()
	open_help.init(self)
	add_child(open_help)
	
	run_thread = preload("res://scenes/main/scripts/run_thread.gd").new()
	run_thread.init(self, $ProgressWindow, $ProgressWindow/ProgressLabel, $ProgressWindow/ProgressBar, $GraphEdit, $Console, $Console/ConsoleOutput)
	add_child(run_thread)
	
	graph_edit.init(self, $GraphEdit, Callable(open_help, "show_help_for_node"), $MultipleConnectionsPopup)
	
	save_load = preload("res://scenes/main/scripts/save_load.gd").new()
	save_load.init(self, $GraphEdit, Callable(open_help, "show_help_for_node"), Callable(graph_edit, "_register_node_movement"), Callable(graph_edit, "_register_inputs_in_node"), Callable(self, "link_output"))
	add_child(save_load)

func make_signal_connections():
	get_node("SearchMenu").make_node.connect(graph_edit._make_node)
	get_node("SearchMenu").swap_node.connect(graph_edit._swap_node)
	get_node("SearchMenu").connect_to_clicked_node.connect(graph_edit._connect_to_clicked_node)
	get_node("mainmenu").make_node.connect(graph_edit._make_node)
	get_node("mainmenu").open_help.connect(open_help.show_help_for_node)
	get_node("Settings").open_cdp_location.connect(show_cdp_location)
	get_node("Settings").console_on_top.connect(change_console_settings)
	get_node("Settings").invert_ui.connect(invert_theme_toggled)
	get_node("Settings").swap_zoom_and_move.connect(swap_zoom_and_move)
	get_node("Settings").ui_scale_multiplier_changed.connect(scale_ui)
	get_window().files_dropped.connect(on_files_dropped)
	
func hidpi_adjustment():
	#checks if display is hidpi and scales ui accordingly hidpi - 144
	if DisplayServer.screen_get_dpi(0) >= 144:
		retina_scaling = 2.0
	else:
		retina_scaling = 1.0
		

func scale_ui(scale_multiplier: float):
	var old_uiscale = uiscale
	uiscale = retina_scaling * scale_multiplier
	get_window().content_scale_factor = uiscale
	#goes through popup_windows group and scales all popups and resizes them
	for window in get_tree().get_nodes_in_group("popup_windows"):
		if old_uiscale != 0: #if ui scale = 0 this is the first time this is being adjusted so no need to revert values back to default first
			window.size = (window.size / old_uiscale) * uiscale
		else:
			window.size = window.size * uiscale
		window.content_scale_factor = uiscale
	

func load_from_filesystem():
	#checks if user has opened a file from the system file menu and loads it
	var args = OS.get_cmdline_args()
	for arg in args:
		var path = arg.strip_edges()
		if FileAccess.file_exists(path) and path.get_extension().to_lower() == "thd":
			save_load.load_graph_edit(path)
			break
		if FileAccess.file_exists(path) and path.get_extension().to_lower() == "wav":
			default_input_node.get_node("AudioPlayer")._on_file_selected(path)
			break

func new_patch():
	#clear old patch
	graph_edit.clear_connections()

	for node in graph_edit.get_children():
		if node is GraphNode:
			node.queue_free()
	
	await get_tree().process_frame  # Wait for nodes to actually be removed
	
	undo_redo.clear_history()
	
	graph_edit.scroll_offset = Vector2(0, 0)
	
		#Generate input and output nodes
	var effect = Utilities.nodes["inputfile"].instantiate()
	effect.name = "inputfile"
	get_node("GraphEdit").add_child(effect, true)
	effect.connect("open_help", Callable(open_help, "show_help_for_node"))
	if effect.has_signal("node_moved"):
		effect.node_moved.connect(graph_edit._auto_link_nodes)
	effect.dragged.connect(graph_edit.node_position_changed.bind(effect))
	effect.position_offset = Vector2(20,80)
	default_input_node = effect #store a reference to this node to allow for loading into it directly if software launched with a wav file argument
	
	effect = Utilities.nodes["outputfile"].instantiate()
	effect.name = "outputfile"
	get_node("GraphEdit").add_child(effect, true)
	effect.init() #initialise ui from user prefs
	effect.connect("open_help", Callable(open_help, "show_help_for_node"))
	if effect.has_signal("node_moved"):
		effect.node_moved.connect(graph_edit._auto_link_nodes)
	effect.dragged.connect(graph_edit.node_position_changed.bind(effect))
	effect.position_offset = Vector2((DisplayServer.screen_get_size().x - 480) / uiscale, 80)
	graph_edit._register_node_movement() #link nodes for tracking position changes for changes tracking
	
	#set label for last output folder
	var interface_settings = ConfigHandler.load_interface_settings()
	output_folder_label = effect.get_node("OutputFolderMargin/OutputFolderLabel")
	if output_folder_label != null and interface_settings.last_used_output_folder != "no_file":
		output_folder_label.text = interface_settings.last_used_output_folder
		output_folder_label.get_parent().tooltip_text = interface_settings.last_used_output_folder
	
	changesmade = false #so it stops trying to save unchanged empty files
	get_window().title = "SoundThread"
	link_output()
	
	#set fft size and overlap to default
	$FFTSize.select(9)
	_on_fft_size_item_selected(9)
	$FFTOverlap.select(2)
	_on_fft_overlap_item_selected(2)
	
	
func link_output():
	#links various buttons and function in the input nodes - this is called after they are created so that it still works on new and loading files
	for control in get_tree().get_nodes_in_group("outputnode"): #check all items in outputnode group
		if control.has_meta("outputfunction"):
			if control.get_meta("outputfunction") == "deleteintermediate": #link delete intermediate files toggle to script
				control.toggled.connect(_toggle_delete)
				_toggle_delete(control.button_pressed)
				#control.button_pressed = interface_settings.get("delete_intermediate", true)

			elif control.get_meta("outputfunction") == "runprocess": #link runprocess button
				control.button_down.connect(_run_process)
			elif control.get_meta("outputfunction") == "audioplayer": #link output audio player
				output_audio_player = control
			elif control.get_meta("outputfunction") == "filename":
				control.text = "outfile"
				outfilename = control
			elif control.get_meta("outputfunction") == "reusefolder":
				foldertoggle = control
				#foldertoggle.button_pressed = interface_settings.get("reuse_output_folder", true)
			elif control.get_meta("outputfunction") == "openfolder":
				control.button_down.connect(_open_output_folder)


	#for control in get_tree().get_nodes_in_group("inputnode"):
		#if control.get_meta("inputfunction") == "audioplayer": #link input for recycle function
			#print("input player found")
			#input_audio_player = control

func check_user_preferences():
	var interface_settings = ConfigHandler.load_interface_settings()
	var audio_settings = ConfigHandler.load_audio_settings()
	var audio_devices = AudioServer.get_output_device_list()
	$Console.always_on_top = interface_settings.console_on_top
	if audio_devices.has(audio_settings.device):
		AudioServer.set_output_device(audio_settings.device)
	else:
		$AudioDevicePopup.popup_centered()
	
	match interface_settings.theme:
		0:
			RenderingServer.set_default_clear_color(Color("#2f4f4e"))
		1:
			RenderingServer.set_default_clear_color(Color("#000807"))
		2:
			RenderingServer.set_default_clear_color(Color("#98d4d2"))
		3:
			RenderingServer.set_default_clear_color(Color(interface_settings.theme_custom_colour))
			
	#set the theme to either the main theme or inverted theme depending on user preferences
	invert_theme_toggled(interface_settings.invert_theme)
	swap_zoom_and_move(interface_settings.swap_zoom_and_move)
	
	#scale ui
	scale_ui(interface_settings.ui_scale_multiplier)

		
func show_cdp_location():
	$CdpLocationDialog.show()
	
func check_cdp_location_set():
	#checks if the location has been set and prompts user to set it
	var cdpprogs_settings = ConfigHandler.load_cdpprogs_settings()
	if cdpprogs_settings.location == "no_location":
		$NoLocationPopup.popup_centered()
	else:
		#if location is set, stores it in a variable
		cdpprogs_location = str(cdpprogs_settings.location)
		print(cdpprogs_location)

func _on_ok_button_button_down() -> void:
	#after user has read dialog on where to find cdp progs this loads the file browser
	$NoLocationPopup.hide()
	if OS.get_name() == "Windows":
		$CdpLocationDialog.current_dir = "C:/"
	else:
		$CdpLocationDialog.current_dir = OS.get_environment("HOME")
	$CdpLocationDialog.show()

func _on_cdp_location_dialog_dir_selected(dir: String) -> void:
	var is_windows = OS.get_name() == "Windows"
	var cdprogs_correct
	
	#check if the selected folder contains the hilite program as it has a reasonably unique name and will indicate that the CDP processes do exist in that folder
	if is_windows:
		cdprogs_correct = FileAccess.file_exists(dir + "/distort.exe")
	else:
		cdprogs_correct = FileAccess.file_exists(dir + "/distort")
	
	
	if cdprogs_correct:
		#if this location does seem to contain cdp programs
		#saves default location for cdp programs in config file
		ConfigHandler.save_cdpprogs_settings(dir)
		cdpprogs_location = dir
	else:
		#if it doesn't seem to contain the programs then try and extrapolate the correct folder from the one selected
		var selected_folder = dir.get_slice("/", (dir.get_slice_count("/") - 1))
		print(selected_folder)
		if selected_folder.to_lower() == "cdpr8":
			dir = dir + "/_cdp/_cdprogs"
			#run this function recursively to check if the programs do exist
			_on_cdp_location_dialog_dir_selected(dir)
		elif selected_folder.to_lower() == "_cdp":
			dir = dir + "/_cdprogs"
			#run this function recursively to check if the programs do exist
			_on_cdp_location_dialog_dir_selected(dir)
		else:
			#can't find them
			use_anyway = dir
			$WrongFolderPopup.popup_centered()

func _on_cdp_location_dialog_canceled() -> void:
	#cycles around the set location prompt if user cancels the file dialog
	check_cdp_location_set()
	
func _on_select_folder_button_button_down() -> void:
	$WrongFolderPopup.hide()
	_on_ok_button_button_down()

func _on_use_anyway_button_button_down() -> void:
	$WrongFolderPopup.hide()
	ConfigHandler.save_cdpprogs_settings(use_anyway)
	cdpprogs_location = use_anyway

func _input(event):
	if event.is_action_pressed("undo"):
		simulate_mouse_click()
		await get_tree().process_frame
		undo_redo.undo()
		graph_edit.force_hide_tooltips()
	elif event.is_action_pressed("redo"):
		undo_redo.redo()
		graph_edit.force_hide_tooltips()
	elif event.is_action_pressed("save"):
		if currentfile == "none":
			savestate = "saveas"
			$SaveDialog.popup_centered()
		else:
			save_load.save_graph_edit(currentfile)
	elif event.is_action_pressed("open_explore"):
		open_explore()
	elif event.is_action_pressed("search"):
		var pos = graph_edit.get_local_mouse_position()
		_on_graph_edit_popup_request(pos)
	elif event.is_action_pressed("run_thread"):
		_run_process()
	elif event.is_action_pressed("new"):
		if changesmade == true:
			savestate = "newfile"
			$SaveChangesPopup.popup_centered()
		else:
			new_patch()
			currentfile = "none" #reset current file to none for save tracking
	elif event.is_action_pressed("save_as"):
		savestate = "saveas"
		$SaveDialog.popup_centered()
	
func simulate_mouse_click():
	#simulates clicking the middle mouse button in order to hide any visible tooltips
	var click_pos = get_viewport().get_mouse_position()

	var down_event := InputEventMouseButton.new()
	down_event.button_index = MOUSE_BUTTON_MIDDLE
	down_event.pressed = true
	down_event.position = click_pos
	Input.parse_input_event(down_event)

	var up_event := InputEventMouseButton.new()
	up_event.button_index = MOUSE_BUTTON_MIDDLE
	up_event.pressed = false
	up_event.position = click_pos
	Input.parse_input_event(up_event)


func _run_process() -> void:
	#check if any of the inputfile nodes don't have files loaded
	var interface_settings = ConfigHandler.load_interface_settings()
	for node in graph_edit.get_children():
		if node.get_meta("command") == "inputfile" and node.get_node("AudioPlayer").has_meta("inputfile") == false:
			$NoInputPopup.popup_centered()
			return
	#check if the reuse folder toggle is set and a folder has been previously chosen
	var output_folder = interface_settings.last_used_output_folder
	if foldertoggle.button_pressed == true and output_folder != "no_file" and DirAccess.open(output_folder) != null:
		_on_file_dialog_dir_selected(output_folder)
	else:
		$FileDialog.show()
			

func _on_file_dialog_dir_selected(dir: String) -> void:
	ConfigHandler.save_interface_settings("last_used_output_folder", dir)
	if output_folder_label != null:
		output_folder_label.text = dir
		output_folder_label.get_parent().tooltip_text = dir
	console_output.clear()
	var interface_settings = ConfigHandler.load_interface_settings()
	if interface_settings.disable_progress_bar == false:
		$ProgressWindow.show()
	else:
		if $Console.is_visible():
			$Console.hide()
			await get_tree().process_frame  # Wait a frame to allow hide to complete
			$Console.popup_centered()
		else:
			$Console.popup_centered()
	await get_tree().process_frame
	run_thread.log_console("Generating processing queue", true)
	await get_tree().process_frame

	#get the current time in hh-mm-ss format as default : causes file name issues
	var time_dict = Time.get_time_dict_from_system()
	# Pad with zeros to ensure two digits for hour, minute, second
	var hour = str(time_dict.hour).pad_zeros(2)
	var minute = str(time_dict.minute).pad_zeros(2)
	var second = str(time_dict.second).pad_zeros(2)
	var time_str = hour + "-" + minute + "-" + second
	Global.outfile = dir + "/" + outfilename.text.get_basename() + "_" + Time.get_date_string_from_system() + "_" + time_str
	
	#check path and file name do not contain special characters
	var check_file_name = Global.check_for_invalid_chars(Global.outfile)
	
	if check_file_name["contains_invalid_characters"] == false:
		run_thread.log_console("Output directory and file name(s):" + Global.outfile, true)
		await get_tree().process_frame
		
		run_thread.run_thread_with_branches()
	else:
		run_thread.log_console("[color=#9c2828][b]Error:[/b][/color] Chosen file name or folder path " + Global.outfile.get_basename() + " contains invalid characters.", true)
		run_thread.log_console("File names and paths can only contain A-Z a-z 0-9 - _ + and space.", true)
		run_thread.log_console("Chosen file name/path contains the following invalid characters: " + " ".join(check_file_name["invalid_characters_found"]), true)
		if $ProgressWindow.visible:
			$ProgressWindow.hide()
		if !$Console.visible:
			$Console.popup_centered()

func _toggle_delete(toggled_on: bool):
	delete_intermediate_outputs = toggled_on
	print(toggled_on)

func _on_console_close_requested() -> void:
	$Console.hide()



func _on_console_open_folder_button_down() -> void:
	$Console.hide()
	var interface_settings = ConfigHandler.load_interface_settings()
	var output_folder = interface_settings.last_used_output_folder
	if output_folder != "no_file" and DirAccess.open(output_folder) != null:
		OS.shell_open(output_folder)


func _on_ok_button_2_button_down() -> void:
	$NoInputPopup.hide()


func _on_ok_button_3_button_down() -> void:
	$MultipleConnectionsPopup.hide()



func _on_settings_button_index_pressed(index: int) -> void:
	
	match index:
		0:
			$Settings.cdpprogs_location = cdpprogs_location
			$Settings.popup_centered()
		1:
			$AudioSettings.popup_centered()
		2:
			if $Console.is_visible():
				$Console.hide()
				await get_tree().process_frame  # Wait a frame to allow hide to complete
				$Console.popup_centered()
			else:
				$Console.popup_centered()

func _on_file_button_index_pressed(index: int) -> void:
	match index:
		0:
			if changesmade == true:
				savestate = "newfile"
				$SaveChangesPopup.popup_centered()
			else:
				new_patch()
				currentfile = "none" #reset current file to none for save tracking
			
		1:
			if currentfile == "none":
				savestate = "saveas"
				$SaveDialog.popup_centered()
			else:
				save_load.save_graph_edit(currentfile)
			
			print("save pressed, changes made =")
			print(changesmade)
			print("current file =")
			print(currentfile)
		2:
			savestate = "saveas"
			$SaveDialog.popup_centered()
		3:
			if changesmade == true:
				savestate = "load"
				$SaveChangesPopup.popup_centered()
			else:
				$LoadDialog.popup_centered()



func _on_save_dialog_file_selected(path: String) -> void:
	save_load.save_graph_edit(path) #save file
	#check what the user was trying to do before save and do that action
	if savestate == "newfile":
		new_patch()
		currentfile = "none" #reset current file to none for save tracking
	elif savestate == "load":
		$LoadDialog.popup_centered()
	elif savestate == "helpfile":
		currentfile = "none" #reset current file to none for save tracking so user cant save over help file
		save_load.load_graph_edit(helpfile)
	elif savestate == "quit":
		undo_redo.free()
		await get_tree().create_timer(0.25).timeout #little pause so that it feels like it actually saved even though it did
		get_tree().quit()
	elif savestate == "saveas":
		currentfile = path
		
	savestate = "none" #reset save state, not really needed but feels good


func _on_load_dialog_file_selected(path: String) -> void:
	currentfile = path #tracking path here only means "save" only saves patches the user has loaded rather than overwriting help files
	save_load.load_graph_edit(path)

func _on_help_button_index_pressed(index: int) -> void:
	match index:
		0:
			pass
		1:
			open_a_helpfile("res://examples/getting_started.thd")

		2:
			open_a_helpfile("res://examples/navigating.thd")
		3:
			open_a_helpfile("res://examples/building_a_thread.thd")
		4:
			open_a_helpfile("res://examples/frequency_domain.thd")
		5:
			open_a_helpfile("res://examples/automation.thd")
		6:
			open_a_helpfile("res://examples/trimming.thd")
		7:
			open_a_helpfile("res://examples/multiple_inputs.thd")
		8:
			open_a_helpfile("res://examples/preview_nodes.thd")
		9:
			open_a_helpfile("res://examples/randomising_values.thd")
		10:
			pass
		11:
			open_a_helpfile("res://examples/wetdry.thd")
		12:
			open_a_helpfile("res://examples/resonant_filters.thd")
		13:
			pass
		14:
			open_help.open_keyboard_shortcuts_help()
		15:
			OS.shell_open("https://www.composersdesktop.com/docs/html/ccdpndex.htm")
		16:
			OS.shell_open("https://github.com/j-p-higgins/SoundThread/issues")

func open_a_helpfile(help_file: String) -> void:
	if changesmade == true:
		savestate = "helpfile"
		helpfile = help_file
		$SaveChangesPopup.popup_centered()
	else:
		currentfile = "none" #reset current file to none for save tracking so user cant save over help file
		save_load.load_graph_edit(help_file)


func _on_save_changes_button_down() -> void:
	$SaveChangesPopup.hide()
	if currentfile == "none":
		$SaveDialog.show()
	else:
		save_load.save_graph_edit(currentfile)
		if savestate == "newfile":
			new_patch()
			currentfile = "none" #reset current file to none for save tracking
		elif savestate == "load":
			$LoadDialog.popup_centered()
		elif savestate == "helpfile":
			currentfile = "none" #reset current file to none for save tracking so user cant save over help file
			save_load.load_graph_edit(helpfile)
		elif savestate == "quit":
			undo_redo.free()
			await get_tree().create_timer(0.25).timeout #little pause so that it feels like it actually saved even though it did
			get_tree().quit()
			
		savestate = "none"


func _on_dont_save_changes_button_down() -> void:
	$SaveChangesPopup.hide()
	if savestate == "newfile":
		new_patch()
		currentfile = "none" #reset current file to none for save tracking
	elif savestate == "load":
		$LoadDialog.popup_centered()
	elif savestate == "helpfile":
		currentfile = "none" #reset current file to none for save tracking so user cant save over help file
		save_load.load_graph_edit(helpfile)
	elif savestate == "quit":
		undo_redo.free()
		get_tree().quit()
	
	savestate = "none"
	
func _on_cancel_changes_button_down() -> void:
	$SaveChangesPopup.hide()
	savestate = "none"
	
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		run_thread._on_kill_process_button_down()
		$Console.hide()
		if changesmade == true:
			savestate = "quit"
			$SaveChangesPopup.popup_centered()
			#$HelpWindow.hide()
		else:
			undo_redo.free()
			get_tree().quit() # default behavior
			
func _open_output_folder():
	var interface_settings = ConfigHandler.load_interface_settings()
	var output_folder = interface_settings.last_used_output_folder
	if output_folder != "no_file" and DirAccess.open(output_folder) != null:
		OS.shell_open(output_folder)
		

func _on_rich_text_label_meta_clicked(meta: Variant) -> void:
	print(str(meta))
	OS.shell_open(str(meta))


func _on_graph_edit_popup_request(at_position: Vector2) -> void:
 
	effect_position = at_position
	
	#give search menu ui scale
	$SearchMenu.uiscale = uiscale

	#get the mouse position in screen coordinates
	var mouse_screen_pos = DisplayServer.mouse_get_position()  
	#get the window position in screen coordinates
	var window_screen_pos = get_window().position
	#get the window size relative to its scaling for retina displays
	var window_size = get_window().size * DisplayServer.screen_get_scale()

	#see if it was empty space or a node that was right clicked
	var clicked_position = (effect_position + graph_edit.scroll_offset) / graph_edit.zoom
	var clicked_node
	for child in graph_edit.get_children():
		if child is GraphNode:
			if Rect2(child.position_offset, child.size).has_point(clicked_position):
				clicked_node = child
				break
	
	if clicked_node and clicked_node.get_meta("command") != "outputfile":
		var title = clicked_node.title
		if Input.is_action_pressed("auto_link_nodes"):
			$SearchMenu/VBoxContainer/ReplaceLabel.text = "Connect to " + title
			$SearchMenu/VBoxContainer/ReplaceLabel.show()
			$SearchMenu.replace_node = false
			$SearchMenu.connect_to_node = true
			$SearchMenu.node_to_connect_to = clicked_node
		else:
			$SearchMenu/VBoxContainer/ReplaceLabel.text = "Replace " + title
			$SearchMenu/VBoxContainer/ReplaceLabel.show()
			$SearchMenu.replace_node = true
			$SearchMenu.connect_to_node = false
			$SearchMenu.node_to_replace = clicked_node
	else:
		var interface_settings = ConfigHandler.load_interface_settings()
		if interface_settings.right_click_opens_explore:
			open_explore()
			return
		else:
			$SearchMenu/VBoxContainer/ReplaceLabel.hide()
			$SearchMenu.replace_node = false
			$SearchMenu.connect_to_node = false
	
	#calculate the xy position of the mouse clamped to the size of the window and menu so it doesn't go off the screen
	var clamped_x = clamp(mouse_screen_pos.x, window_screen_pos.x, window_screen_pos.x + window_size.x - $SearchMenu.size.x)
	var clamped_y = clamp(mouse_screen_pos.y, window_screen_pos.y, window_screen_pos.y + window_size.y - (420 * DisplayServer.screen_get_scale()))
	
	#position and show the menu
	$SearchMenu.position = Vector2(clamped_x, clamped_y)
	$SearchMenu.popup()

func _on_audio_settings_close_requested() -> void:
	$AudioSettings.hide()


func _on_open_audio_settings_button_down() -> void:
	$AudioDevicePopup.hide()
	$AudioSettings.popup_centered()


func _on_audio_device_popup_close_requested() -> void:
	$AudioDevicePopup.hide()

func _on_mainmenu_close_requested() -> void:
	#closes menu if click is anywhere other than the menu as it is a window with popup set to true
	$mainmenu.hide()

func open_explore():
	effect_position = graph_edit.get_local_mouse_position()
	
	#get the mouse position in screen coordinates
	var mouse_screen_pos = DisplayServer.mouse_get_position()  
	#get the window position in screen coordinates
	var window_screen_pos = get_window().position
	#get the window size relative to its scaling for retina displays
	var window_size = get_window().size * DisplayServer.screen_get_scale()
	#get the size of the popup menu
	var popup_size = $mainmenu.size

	#calculate the xy position of the mouse clamped to the size of the window and menu so it doesn't go off the screen
	var clamped_x = clamp(mouse_screen_pos.x, window_screen_pos.x, window_screen_pos.x + window_size.x - popup_size.x)
	var clamped_y = clamp(mouse_screen_pos.y, window_screen_pos.y, window_screen_pos.y + window_size.y - popup_size.y)
	
	#position and show the menu
	$mainmenu.position = Vector2(clamped_x, clamped_y)
	$mainmenu.popup()
	
func change_console_settings(toggled: bool):
	$Console.always_on_top = toggled


func _on_kill_process_button_down() -> void:
	run_thread._on_kill_process_button_down()

func invert_theme_toggled(toggled: bool):
	if toggled:
		var inverted = invert_theme(main_theme)
		get_tree().root.theme = inverted # force refresh
		$MenuBarBackground.color = Color(0.934, 0.934, 0.934)
		for color_rect in get_tree().get_nodes_in_group("invertable_background"):
			if color_rect is ColorRect:
				color_rect.color = Color(0.898, 0.898, 0.898, 0.6)
		
	else:
		get_tree().root.theme = main_theme # force refresheme = main_theme
		$MenuBarBackground.color = Color(0.065, 0.065, 0.065)
		
		for color_rect in get_tree().get_nodes_in_group("invertable_background"):
			if color_rect is ColorRect:
				color_rect.color = Color(0.102, 0.102, 0.102, 0.6)
		
func invert_theme(theme: Theme) -> Theme:
	var inverted_theme = theme.duplicate(true) # deep copy

	# Check all types and color names in the theme
	var types = inverted_theme.get_type_list()
	for type in types:
		var color_names = inverted_theme.get_color_list(type)
		for cname in color_names:
			var col = inverted_theme.get_color(cname, type)
			var inverted = Color(1.0 - col.r, 1.0 - col.g, 1.0 - col.b, col.a)
			inverted_theme.set_color(cname, type, inverted)

		var style_names = inverted_theme.get_stylebox_list(type)
		for sname in style_names:
			if type == "GraphEdit" and sname == "panel":
				continue
			var sb = inverted_theme.get_stylebox(sname, type)
			var new_sb = sb.duplicate()
			if new_sb is StyleBoxFlat:
				var col = new_sb.bg_color
				new_sb.bg_color = Color(1.0 - col.r, 1.0 - col.g, 1.0 - col.b, col.a)
			inverted_theme.set_stylebox(sname, type, new_sb)
	
	return inverted_theme

func swap_zoom_and_move(toggled: bool):
	if toggled:
		graph_edit.set_panning_scheme(1)
	else:
		graph_edit.set_panning_scheme(0)

func on_files_dropped(files):
	var mouse_pos = (graph_edit.get_local_mouse_position() + graph_edit.scroll_offset) / graph_edit.zoom
	
	#see if files were dropped on an input node
	var dropped_node
	for child in graph_edit.get_children():
		if child is GraphNode:
			if Rect2(child.position_offset, child.size).has_point(mouse_pos):
				dropped_node = child
				break
				
				
	#if they were dropped on a node and the first file in the array is a wav file replace the file in the input node
	if dropped_node and dropped_node.has_meta("command") and dropped_node.get_meta("command") == "inputfile":
		if files[0].get_extension().to_lower() == "wav":
			dropped_node.get_node("AudioPlayer")._on_file_selected(files[0])
	else:
		#else make a new input node at the mouse position and load it in
		if files[0].get_extension().to_lower() == "wav":
			var new_input_node = graph_edit._make_node("inputfile")
			new_input_node.position_offset = mouse_pos
			new_input_node.get_node("AudioPlayer")._on_file_selected(files[0])
	
	#remove first element from the array
	files.remove_at(0)
	
	#check if there are any other files
	if files.size() > 0:
		var position_plus_offset = Vector2(mouse_pos.x, mouse_pos.y + 250) #apply a vertical offset from the mouse position so nodes dont overlap
		for file in files:
			if file.get_extension().to_lower() == "wav":
				var new_input_node = graph_edit._make_node("inputfile")
				new_input_node.position_offset = position_plus_offset
				new_input_node.get_node("AudioPlayer")._on_file_selected(file)
				position_plus_offset.y = position_plus_offset.y + 250


func _on_fft_size_item_selected(index: int) -> void:
	var fft_size
	if index == 13:
		fft_size = 16380
	else:
		fft_size = 1 << (index + 1)
	run_thread.fft_size = fft_size



func _on_fft_overlap_item_selected(index: int) -> void:
	run_thread.fft_overlap = index + 1


func _on_undo_button_button_down() -> void:
	simulate_mouse_click()
	await get_tree().process_frame
	undo_redo.undo()
	graph_edit.force_hide_tooltips()
	

func _on_redo_button_button_down() -> void:
	simulate_mouse_click()
	await get_tree().process_frame
	undo_redo.redo()
	graph_edit.force_hide_tooltips()
