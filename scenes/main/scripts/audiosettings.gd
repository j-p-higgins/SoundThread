extends Window

@onready var item_list = $VBoxContainer/ItemList
@onready var device_timer = $DevicePollTimer
var last_known_devices = []


func _on_item_list_item_selected(index: int) -> void:
	var device = item_list.get_item_text(index)
	AudioServer.set_output_device(device)
	ConfigHandler.save_audio_settings("device", device)


func _on_about_to_popup() -> void:
	$VBoxContainer/DeviceInfo.text = "Current Device: " + AudioServer.get_output_device()
	
	update_device_list()  # Initial fetch
	device_timer.start()
	


func _on_close_requested() -> void:
	device_timer.stop()
	hide()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		device_timer.stop()
		hide()
		get_viewport().set_input_as_handled()


func update_device_list():
	var audio_settings = ConfigHandler.load_audio_settings()
	var last_selected_device = audio_settings.device
	var devices = AudioServer.get_output_device_list()
	var device = AudioServer.get_output_device()
	
	item_list.clear()
	last_known_devices = devices
	for item in AudioServer.get_output_device_list():
		item_list.add_item(item)
	
	#check if the users last selected device has now become available if not set to default to reset audio server to default so it reports properly
	if device != last_selected_device and devices.has(last_selected_device):
		AudioServer.set_output_device("Default") #hacky fix because the audio server doesn't work properly when hot swapping outputs
		await get_tree().create_timer(0.1).timeout  # Wait 100 ms
		AudioServer.set_output_device(last_selected_device)
	elif !devices.has(last_selected_device):
		AudioServer.set_output_device("Default")
		
	await get_tree().create_timer(0.1).timeout  # Wait 100 ms
	device = AudioServer.get_output_device()
	#highlight the currently selected device
	for i in range(item_list.get_item_count()):
		if device == item_list.get_item_text(i):
			item_list.select(i)
			break


func _on_device_poll_timer_timeout() -> void:
	var current_devices = AudioServer.get_output_device_list()
	if current_devices != last_known_devices:
		last_known_devices = current_devices
		update_device_list()
		
	$VBoxContainer/DeviceInfo.text = "Current Device: " + AudioServer.get_output_device()
