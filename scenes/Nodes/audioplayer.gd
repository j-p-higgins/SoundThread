extends Control

@onready var audio_player = $AudioStreamPlayer
@onready var file_dialog = $FileDialog
@onready var waveform_display = $WaveformPreview
var outfile_path = "not_loaded"
var temp_dir = "user://temp_soundthread"

var rect_focus = false
var mouse_pos_x

#Used for waveform preview
var voice_preview_generator : Node = null
var stream : AudioStreamWAV = null

var autoplay

signal setnodetitle

func _ready():
	#Setup file dialogue to access system files and only accept wav files
	#get_window().files_dropped.connect(_on_files_dropped)
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = ["*.wav ; WAV audio files"]
	file_dialog.connect("file_selected", Callable(self, "_on_file_selected"))
	audio_player.connect("finished", Callable(self, "_on_audio_finished"))
	
	if get_meta("loadenable") == false:
		#$PlayButton.size.x = 192
		#$PlayButton.position.x = 208
		$PlayButton.size.x = $Panel.size.x
		$PlayButton.position.x = $LoadButton.position.x
		$LoadButton.hide()
		$RecycleButton.hide()
	#else:
		#$Autoplay.hide()
	
	$WavError.hide()
	
	# Load the voice preview generator for waveform visualization
	voice_preview_generator = preload("res://addons/audio_preview/voice_preview_generator.tscn").instantiate()
	add_child(voice_preview_generator)
	voice_preview_generator.texture_ready.connect(_on_texture_ready)
	
	#setup meta to say the player is empty and no trim points have been set
	set_meta("trimfile", false)

#func _on_files_dropped(files):
	#if files[0].get_extension() == "wav" or files[0].get_extension() == "WAV":
		#audio_player.stream = AudioStreamWAV.load_from_file(files[0])
		#if audio_player.stream.stereo == true: #checks if stream is stereo, not sure what this will do with a surround sound file
			#audio_player.stream = null #empties audio stream so stereo audio cant be played back
			#$WavError.show()
		#else:
			#voice_preview_generator.generate_preview(audio_player.stream) #this generates the waveform graphic
			#Global.infile = files[0] #this sets the global infile variable to the audio file path
			#print(Global.infile)
	#else:
		#$WavError.show()

func _on_close_button_button_down() -> void:
	$WavError.hide()

func _on_load_button_button_down() -> void:
	file_dialog.popup_centered()

func _on_file_selected(path: String):
	audio_player.stream = AudioStreamWAV.load_from_file(path, {
		"compress/mode" = 0,
		"edit/loop_mode" = 1})
	voice_preview_generator.generate_preview(audio_player.stream)
	if audio_player.stream != null:
		var length = convert_length(audio_player.stream.get_length())
		$EndLabel.text = length
		setnodetitle.emit(path.get_file())
	else:
		$EndLabel.text = "00:00.00"
	# If the selected filename contains non-ASCII bytes, copy it once to a safe
	# temporary location (absolute filesystem path) and store that path instead.
	var final_path = path
	if typeof(path) == TYPE_STRING and FileAccess.file_exists(path) and contains_non_ascii(path):
		final_path = copy_file_to_temp(path)
		print("Copied input to temporary path: " + final_path)
	set_meta("inputfile", final_path)
	reset_playback()
	
	#output signal that the input has loaded and it is safe to continue with running thread
	#Used for preview nodes in run_thread to avoid deleting the input file before it is done loading
	
	
func reset_playback():
	$LoopRegion.size.x = 0
	$Playhead.position.x = 0
	$PlayButton.text = "Play"
	$Timer.stop()
	if get_meta("loadenable") == true:
		set_meta("timefile", false)
	
	
func play_outfile(path: String):
	outfile_path = path
	audio_player.stream = AudioStreamWAV.load_from_file(path, {
		"compress/mode" = 0,
		"edit/loop_mode" = 1})
	print(audio_player.stream)
	if audio_player.stream == null:
		voice_preview_generator._reset_to_blank()
		reset_playback()
		return
	await voice_preview_generator.generate_preview(audio_player.stream)
	if audio_player.stream != null:
		var length = convert_length(audio_player.stream.get_length())
		$EndLabel.text = length
	else:
		$EndLabel.text = "00:00.00"
	reset_playback()
	if autoplay == true:
		_on_play_button_button_down()

	
func recycle_outfile():
	print("recycle pressed")
	print(Global.cdpoutput)
	if Global.cdpoutput != "no_file":
		_on_file_selected(Global.cdpoutput)


func _on_play_button_button_down() -> void:
	var playhead_position
	#check if trim markers are set and set playhead position to correct location
	if $LoopRegion.size.x == 0:
		playhead_position = 0
	else:
		playhead_position = $LoopRegion.position.x
	
	$Playhead.position.x = playhead_position
	
	#check if audio is playing, to decide if this is a play or stop button
	if audio_player.stream:
		if audio_player.playing:
			audio_player.stop()
			$Timer.stop()
			$PlayButton.text = "Play"
		else:
			$PlayButton.text = "Stop"
			if $LoopRegion.size.x == 0: #loop position is not set, play from start of file
				audio_player.play()
			else:
				var length = $AudioStreamPlayer.stream.get_length()
				var pixel_to_time = length / 399
				audio_player.play(pixel_to_time * $LoopRegion.position.x)
				if $LoopRegion.position.x + $LoopRegion.size.x < 399:
					$Timer.start(pixel_to_time * $LoopRegion.size.x)
				

#timer for ending playback at end of loop
func _on_timer_timeout() -> void:
	_on_play_button_button_down() #"press" stop button

func _on_audio_finished():
	$PlayButton.text = "Play"


# This function will be called when the waveform texture is ready
func _on_texture_ready(image_texture: ImageTexture):
	# Set the generated texture to the TextureRect (waveform display node)
	waveform_display.texture = image_texture
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if $AudioStreamPlayer.playing:
		var length = $AudioStreamPlayer.stream.get_length()
		var total_distance = 399.0
		var speed = total_distance / length
		$Playhead.position.x += speed * delta
		if $Playhead.position.x >= 399:
			$Playhead.position.x = 0
	
	if rect_focus == true:
		if get_local_mouse_position().x > mouse_pos_x:
			$LoopRegion.size.x = clamp(get_local_mouse_position().x - mouse_pos_x, 0, $Panel.size.x - (mouse_pos_x - $Panel.position.x))
		else:
			$LoopRegion.size.x = clamp(mouse_pos_x - get_local_mouse_position().x, 0, (mouse_pos_x - $Panel.position.x))
			$LoopRegion.position.x = clamp(get_local_mouse_position().x, $Panel.position.x, $Panel.position.x + $Panel.size.x)

#func _on_recycle_button_button_down() -> void:
	#if outfile_path != "not_loaded":
		#recycle_outfile_trigger.emit(outfile_path)
	



	

func _on_button_button_down() -> void:
	if audio_player.stream:
		if audio_player.playing: #if audio is playing allow user to skip around the sound file
			$Timer.stop()
			var length = $AudioStreamPlayer.stream.get_length()
			var pixel_to_time = length / 399
			$Playhead.position.x = get_local_mouse_position().x
			if $LoopRegion.size.x == 0 or get_local_mouse_position().x > $LoopRegion.position.x + $LoopRegion.size.x: #loop position is not set or click is after loop position, play to end of file
				audio_player.seek(pixel_to_time * get_local_mouse_position().x)
			else: #if click position is before the loop position play from there and stop at the end of the loop position
				audio_player.seek(pixel_to_time * get_local_mouse_position().x)
				if $LoopRegion.position.x + $LoopRegion.size.x < 399:
					$Timer.start(pixel_to_time * ($LoopRegion.position.x + $LoopRegion.size.x - get_local_mouse_position().x))
		else:
			mouse_pos_x = get_local_mouse_position().x
			$LoopRegion.position.x = mouse_pos_x
			rect_focus = true


func _on_button_button_up() -> void:
	rect_focus = false
	if get_meta("loadenable") == true:
		if $LoopRegion.size.x > 0:
			set_meta("trimfile", true)
			var length = $AudioStreamPlayer.stream.get_length()
			var pixel_to_time = length / 399
			var start = pixel_to_time * $LoopRegion.position.x
			var starttime = convert_length(start)
			$StartLabel.text = starttime
			var end = start + (pixel_to_time * $LoopRegion.size.x)
			var endtime = convert_length(end)
			$EndLabel.text = endtime
			set_meta("trimpoints", [start, end])
		else:
			set_meta("trimfile", false)
			$StartLabel.text = "00:00.00"
			var end = convert_length($AudioStreamPlayer.stream.get_length())
			$EndLabel.text = end
			

func convert_length(reportedseconds: float) -> String:
	var converted_length = reportedseconds
	var hours
	var minutes
	var seconds = int(reportedseconds) % 60
	seconds = seconds + (reportedseconds - int(reportedseconds))
	
	if reportedseconds > 3600:
		hours = reportedseconds / 3600
		minutes = (int(reportedseconds) % 3600) / 60
		converted_length = "%.0f:%02.0f:%05.2f" % [hours, minutes, seconds, 0.01]
	else:
		minutes = int((int(reportedseconds) % 3600) / 60)
		converted_length = "%02.0f:%05.2f" % [minutes, seconds]
	
	return converted_length


func contains_non_ascii(s: String) -> bool:
	# quick check for bytes outside 0-127 using UTF-8 bytes
	var buf = s.to_utf8_buffer()
	for i in range(buf.size()):
		if buf[i] > 127:
			return true
	return false


func ensure_temp_dir() -> void:
	var da = DirAccess.open("user://")
	if da:
		if not da.dir_exists("temp_soundthread"):
			da.make_dir_recursive("temp_soundthread")


func copy_file_to_temp(src_path: String) -> String:
	if not FileAccess.file_exists(src_path):
		return src_path
	ensure_temp_dir()
	var basename = src_path.get_file()
	var uniq = str(randi())
	var dest = temp_dir + "/safe_" + uniq + "_" + basename
	var abs_dest = ProjectSettings.globalize_path(dest)
	var src = FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		return src_path
	var data = src.get_buffer(src.get_length())
	src.close()
	var dst = FileAccess.open(abs_dest, FileAccess.WRITE)
	if dst == null:
		return src_path
	dst.store_buffer(data)
	dst.close()
	return abs_dest
