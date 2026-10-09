extends HSplitContainer

signal value_changed(value)

@onready var slider = $HSlider
@onready var value_box = $LineEdit

var min_value = 0
var max_value = 1
var exponential = false
var step_amount = 0.01
var init_value = 0

func _ready() -> void:
	slider.min_value = min_value
	slider.max_value = max_value
	slider.exp_edit = exponential
	slider.step = step_amount
	slider.value = init_value

func _on_h_slider_value_changed(value: float) -> void:
	value_box.text = str(value)
	value_changed.emit(value)


func _on_line_edit_focus_exited() -> void:
	var new_value = value_box.text
	var old_value = slider.value
	
	if new_value.is_valid_float():
		new_value = new_value.to_float()
		if new_value != old_value:
			if new_value > max_value:
				slider.value = max_value
				value_box.text = str(max_value)
			elif new_value < min_value:
				slider.value = min_value
				value_box.text = str(min_value)
			else:
				slider.set_value_no_signal(new_value)
				value_changed.emit(new_value)
	else:
		value_box.text = str(old_value)


func _on_line_edit_text_submitted(new_text: String) -> void:
	_on_line_edit_focus_exited()
