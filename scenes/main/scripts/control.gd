extends Control

var mainmenu_visible : bool = false #used to test if mainmenu is open
var effect_position = Vector2(40,40) #tracks mouse position for node placement offset
@onready var graph_edit = $GraphEdit
var cdpprogs_location #stores the cdp programs location from user prefs for easy access
var delete_intermediate_outputs # tracks state of delete intermediate outputs toggle
@onready var console_output: RichTextLabel = $Console/ConsoleOutput
var undo_redo := UndoRedo.new() 
var output_audio_player #tracks the node that is the current output player for linking
var input_audio_player #tracks node that is the current input player for linking
var currentfile = "none" #tracks dir of currently loaded file for saving
var changesmade = false #tracks if user has made changes to the currently loaded save file
var savestate # tracks what the user is trying to do when savechangespopup is called
var helpfile #tracks which help file the user was trying to load when savechangespopup is called
var outfilename #links to the user name for outputfile field
var foldertoggle #links to the reuse folder button
var lastoutputfolder = "none" #tracks last output folder, this can in future be used to replace global.outfile but i cba right now
var uiscale = 1.0 #tracks scaling for retina screens
var use_anyway #used to store the folder selected for cdprogs when it appears the wrong folder is selected but the user wants to use it anyway
var ui_scale_setting := 1.0 # user UI scale preference


#scripts
var open_help
var run_thread
var save_load

# add a key binding (with optional ctrl/meta modifiers)
func _add_key(action: String, scancode: int, ctrl: bool=false, meta: bool=false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = scancode
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.meta_pressed = meta
	InputMap.action_add_event(action, ev)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Nodes.hide()
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
	
	get_tree().set_auto_accept_quit(false) #disable closing the app with the x and instead handle it internally
	
	load_scripts()
	make_signal_connections()
	check_user_preferences()
	hidpi_adjustment()
	ensure_zoom_actions()
	apply_user_ui_scale()
	new_patch()
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
	get_node("mainmenu").make_node.connect(graph_edit._make_node)
	get_node("mainmenu").open_help.connect(open_help.show_help_for_node)
	get_node("Settings").open_cdp_location.connect(show_cdp_location)
	get_node("Settings").console_on_top.connect(change_console_settings)
	
func hidpi_adjustment():
	#checks if display is hidpi and scales ui accordingly hidpi - 144
	if DisplayServer.screen_get_dpi(0) >= 144:
		uiscale = 2.0
		get_window().content_scale_factor = uiscale
		#goes through popup_windows group and scales all popups and resizes them
		for window in get_tree().get_nodes_in_group("popup_windows"):
			# store a base size so repeated adjustments are idempotent
			if not window.has_meta("base_size"):
				window.set_meta("base_size", window.size)
			var base = window.get_meta("base_size")
			window.size = base * uiscale
			window.content_scale_factor = uiscale

func apply_user_ui_scale():
	# Apply saved UI scale combined with hidpi scaling
	var _interface_settings = ConfigHandler.load_interface_settings()
	if _interface_settings.has("ui_scale"):
		ui_scale_setting = float(_interface_settings.get("ui_scale"))
	else:
		ui_scale_setting = 1.0
	# combined scale
	var final_scale = uiscale * ui_scale_setting
	get_window().content_scale_factor = final_scale
	# scale popup windows to match final scale
	for window in get_tree().get_nodes_in_group("popup_windows"):
		if not window.has_meta("base_size"):
			window.set_meta("base_size", window.size)
		var base = window.get_meta("base_size")
		window.size = base * final_scale
		window.content_scale_factor = final_scale


func ensure_zoom_actions() -> void:
	# Ensure zoom input actions exist
	if not InputMap.has_action("zoom_in"):
		InputMap.add_action("zoom_in")
	if not InputMap.has_action("zoom_out"):
		InputMap.add_action("zoom_out")
	if not InputMap.has_action("zoom_reset"):
		InputMap.add_action("zoom_reset")

	# add common combinations (Ctrl or Cmd +/-, Ctrl/Cmd 0)
	_add_key("zoom_in", KEY_PLUS, true, false)
	_add_key("zoom_in", KEY_EQUAL, true, false)
	_add_key("zoom_in", KEY_PLUS, false, true)
	_add_key("zoom_in", KEY_EQUAL, false, true)
	_add_key("zoom_out", KEY_MINUS, true, false)
	_add_key("zoom_out", KEY_MINUS, false, true)
	_add_key("zoom_reset", KEY_0, true, false)
	_add_key("zoom_reset", KEY_0, false, true)

func save_user_ui_scale(scale_val: float) -> void:
	# hide transient tooltips/windows then save/apply new scale
	simulate_mouse_click()

	ui_scale_setting = clamp(scale_val, 0.5, 4.0)
	ConfigHandler.save_interface_settings("ui_scale", ui_scale_setting)
	apply_user_ui_scale()

func load_from_filesystem():
	#checks if user has opened a file from the system file menu and loads it
	var args = OS.get_cmdline_args()
	for arg in args:
		var path = arg.strip_edges()
		if FileAccess.file_exists(path) and path.get_extension().to_lower() == "thd":
			save_load.load_graph_edit(path)
			break

func new_patch():
	#clear old patch
	graph_edit.clear_connections()

	for node in graph_edit.get_children():
		if node is GraphNode:
			node.queue_free()
	
	await get_tree().process_frame  # Wait for nodes to actually be removed
	
	graph_edit.scroll_offset = Vector2(0, 0)
	
		#Generate input and output nodes
	var effect: GraphNode = Nodes.get_node(NodePath("inputfile")).duplicate()
	effect.name = "inputfile"
	get_node("GraphEdit").add_child(effect, true)
	effect.connect("open_help", Callable(open_help, "show_help_for_node"))
	effect.position_offset = Vector2(20,80)
	
	effect = Nodes.get_node(NodePath("outputfile")).duplicate()
	effect.name = "outputfile"
	get_node("GraphEdit").add_child(effect, true)
	effect.init() #initialise ui from user prefs
	effect.connect("open_help", Callable(open_help, "show_help_for_node"))
	effect.position_offset = Vector2((DisplayServer.screen_get_size().x - 480) / uiscale, 80)
	graph_edit._register_node_movement() #link nodes for tracking position changes for changes tracking
	
	changesmade = false #so it stops trying to save unchanged empty files
	get_window().title = "SoundThread"
	link_output()
	
	
func link_output():
	#links various buttons and function in the input nodes - this is called after they are created so that it still works on new and loading files
	for control in get_tree().get_nodes_in_group("outputnode"): #check all items in outputnode group
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
	elif event.is_action_pressed("redo"):
		undo_redo.redo()
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
	elif event.is_action_pressed("zoom_in"):
		save_user_ui_scale(ui_scale_setting + 0.1)
	elif event.is_action_pressed("zoom_out"):
		save_user_ui_scale(ui_scale_setting - 0.1)
	elif event.is_action_pressed("zoom_reset"):
		save_user_ui_scale(1.0)
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
	for node in graph_edit.get_children():
		if node.get_meta("command") == "inputfile" and node.get_node("AudioPlayer").has_meta("inputfile") == false:
			$NoInputPopup.popup_centered()
			return
	#check if the reuse folder toggle is set and a folder has been previously chosen
	if foldertoggle.button_pressed == true and lastoutputfolder != "none":
		_on_file_dialog_dir_selected(lastoutputfolder)
	else:
		$FileDialog.show()
			

func _on_file_dialog_dir_selected(dir: String) -> void:
	lastoutputfolder = dir
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
	run_thread.log_console("Output directory and file name(s):" + Global.outfile, true)
	await get_tree().process_frame
	
	run_thread.run_thread_with_branches()

func _toggle_delete(toggled_on: bool):
	delete_intermediate_outputs = toggled_on
	print(toggled_on)

func _on_console_close_requested() -> void:
	$Console.hide()



func _on_console_open_folder_button_down() -> void:
	$Console.hide()
	OS.shell_open(Global.outfile.get_base_dir())


func _on_ok_button_2_button_down() -> void:
	$NoInputPopup.hide()


func _on_ok_button_3_button_down() -> void:
	$MultipleConnectionsPopup.hide()



func _on_settings_button_index_pressed(index: int) -> void:
	var interface_settings = ConfigHandler.load_interface_settings()
	
	match index:
		0:
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
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/getting_started.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/getting_started.thd")
		2:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/navigating.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/navigating.thd")
		3:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/building_a_thread.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/building_a_thread.thd")
		4:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/frequency_domain.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/frequency_domain.thd")
		5:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/automation.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/automation.thd")
		6:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/trimming.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/trimming.thd")
		7:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/multiple_inputs.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/multiple_inputs.thd")
		8:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/preview_nodes.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/preview_nodes.thd")
		9:
			pass
		10:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/wetdry.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/wetdry.thd")
		11:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/resonant_filters.thd"
				$SaveChangesPopup.popup_centered()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				save_load.load_graph_edit("res://examples/resonant_filters.thd")
		12:
			pass
		13:
			OS.shell_open("https://www.composersdesktop.com/docs/html/ccdpndex.htm")
		14:
			OS.shell_open("https://github.com/j-p-higgins/SoundThread/issues")

#func _recycle_outfile():
	#if outfile != "no file":
		#input_audio_player.recycle_outfile(outfile)



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
			get_tree().quit() # default behavior
			
func _open_output_folder():
	if lastoutputfolder != "none":
		OS.shell_open(lastoutputfolder)
		

func _on_rich_text_label_meta_clicked(meta: Variant) -> void:
	print(str(meta))
	OS.shell_open(str(meta))


func _on_graph_edit_popup_request(at_position: Vector2) -> void:

	effect_position = graph_edit.get_local_mouse_position()

	#get the mouse position in screen coordinates
	var mouse_screen_pos = DisplayServer.mouse_get_position()  
	#get the window position in screen coordinates
	var window_screen_pos = get_window().position
	#get the window size relative to its scaling for retina displays
	var window_size = get_window().size * DisplayServer.screen_get_scale()

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
