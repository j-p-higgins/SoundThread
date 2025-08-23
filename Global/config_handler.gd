extends Node

var config = ConfigFile.new()
const SETTINGS_FILE_PATH = "user://settings.ini"

func _ready():
	var file_exists = FileAccess.file_exists(SETTINGS_FILE_PATH)

	if file_exists:
		config.load(SETTINGS_FILE_PATH)

	# Set defaults only if not present
	ensure_setting("cdpprogs", "location", "no_location")
	ensure_setting("interface_settings", "disable_pvoc_warning", false)
	ensure_setting("interface_settings", "disable_progress_bar", false)
	ensure_setting("interface_settings", "auto_close_console", false)
	ensure_setting("interface_settings", "console_on_top", true)
	ensure_setting("interface_settings", "theme", 0)
	ensure_setting("interface_settings", "theme_custom_colour", "#865699")
	ensure_setting("interface_settings", "delete_intermediate", true)
	ensure_setting("interface_settings", "reuse_output_folder", true)
	ensure_setting("interface_settings", "ui_scale", 1.0)
	ensure_setting("interface_settings", "autoplay", true)
	ensure_setting("audio_settings", "device", "Default")

	# Only save if we added anything new
	if !file_exists or config_changed:
		config.save(SETTINGS_FILE_PATH)

# Internal tracker
var config_changed := false

func ensure_setting(section: String, key: String, default_value):
	if !config.has_section_key(section, key):
		config.set_value(section, key, default_value)
		config_changed = true
	

func save_cdpprogs_settings(location: String):
	config.set_value("cdpprogs", "location", location)
	config.save(SETTINGS_FILE_PATH)
	
func load_cdpprogs_settings():
	var cdpprogs_settings = {}
	for key in config.get_section_keys("cdpprogs"):
		cdpprogs_settings[key] = config.get_value("cdpprogs", key)
	return cdpprogs_settings

func save_interface_settings(key: String, value):
	config.set_value("interface_settings", key, value)
	config.save(SETTINGS_FILE_PATH)

func load_interface_settings():
	var interface_settings = {}
	for key in config.get_section_keys("interface_settings"):
		interface_settings[key] = config.get_value("interface_settings", key)
	return interface_settings
	
func save_audio_settings(key: String, device: String):
	config.set_value("audio_settings", key, device)
	config.save(SETTINGS_FILE_PATH)

func load_audio_settings():
	var audio_settings = {}
	for key in config.get_section_keys("audio_settings"):
		audio_settings[key] = config.get_value("audio_settings", key)
	return audio_settings
