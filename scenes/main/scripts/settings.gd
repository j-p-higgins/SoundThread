extends Window
signal open_cdp_location
signal console_on_top
var interface_settings

# helper to format a float to 2 decimal places without using round(x, ndigits)
func _format_two_decimals(v: float) -> String:
	var scaled = float(int(v * 100.0 + 0.5)) / 100.0
	return str(scaled)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


func _on_change_cdp_button_down() -> void:
	self.hide()
	open_cdp_location.emit()
	

func _on_close_requested() -> void:
	self.hide()


func _on_about_to_popup() -> void:
	interface_settings = ConfigHandler.load_interface_settings()
	$VBoxContainer/HBoxContainer5/ThemeList.select(interface_settings.theme, true)
	$VBoxContainer/HBoxContainer/CustomColourPicker.color = Color(interface_settings.theme_custom_colour)
	$VBoxContainer/HBoxContainer2/PvocWarning.button_pressed = interface_settings.disable_pvoc_warning
	$VBoxContainer/HBoxContainer6/ProgressBar.button_pressed = interface_settings.disable_progress_bar
	$VBoxContainer/HBoxContainer3/AutoCloseConsole.button_pressed = interface_settings.auto_close_console
	$VBoxContainer/HBoxContainer4/ConsoleAlwaysOnTop.button_pressed = interface_settings.console_on_top
	# ui scale control (added for hidpi/manual scaling)
	if interface_settings.has("ui_scale"):
		$VBoxContainer/HBoxContainer7/UIScaleLabel.text = str(interface_settings.ui_scale)
	else:
		$VBoxContainer/HBoxContainer7/UIScaleLabel.text = "1.0"
	

func _on_pvoc_warning_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("disable_pvoc_warning", toggled_on)

func _on_progress_bar_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("disable_progress_bar", toggled_on)



func _on_auto_close_console_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("auto_close_console", toggled_on)
	

func _on_console_always_on_top_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("console_on_top", toggled_on)
	console_on_top.emit(toggled_on)


func _on_theme_list_item_selected(index: int) -> void:
	ConfigHandler.save_interface_settings("theme", index)
	match index:
		0:
			RenderingServer.set_default_clear_color(Color("#2f4f4e"))
		1:
			RenderingServer.set_default_clear_color(Color("#000807"))
		2:
			RenderingServer.set_default_clear_color(Color("#98d4d2"))
		3:
			RenderingServer.set_default_clear_color(Color(interface_settings.theme_custom_colour))

func _on_ui_scale_decrease_button_down() -> void:
	var v = float($VBoxContainer/HBoxContainer7/UIScaleLabel.text)
	v = clamp(v - 0.1, 0.5, 4.0)
	$VBoxContainer/HBoxContainer7/UIScaleLabel.text = _format_two_decimals(v)

	ConfigHandler.save_interface_settings("ui_scale", v)
	# inform main control to reapply
	get_tree().get_root().call_deferred("apply_user_ui_scale")

func _on_ui_scale_increase_button_down() -> void:
	var v = float($VBoxContainer/HBoxContainer7/UIScaleLabel.text)
	v = clamp(v + 0.1, 0.5, 4.0)
	$VBoxContainer/HBoxContainer7/UIScaleLabel.text = _format_two_decimals(v)
	ConfigHandler.save_interface_settings("ui_scale", v)
	get_tree().get_root().call_deferred("apply_user_ui_scale")

func _on_ui_scale_reset_button_down() -> void:
	$VBoxContainer/HBoxContainer7/UIScaleLabel.text = "1.0"
	ConfigHandler.save_interface_settings("ui_scale", 1.0)
	get_tree().get_root().call_deferred("apply_user_ui_scale")


func _on_custom_colour_picker_color_changed(color: Color) -> void:
	ConfigHandler.save_interface_settings("theme_custom_colour", color.to_html(false))
	if $VBoxContainer/HBoxContainer5/ThemeList.is_selected(3):
		RenderingServer.set_default_clear_color(color)
