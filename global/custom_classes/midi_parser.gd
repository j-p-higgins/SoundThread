extends Node
class_name MIDIParser

func midi_to_brk(file: String) -> Array:
	var brk = []
	var midi_file_properties = {
		"format": 0,
		"ntrks": 0,
		"division": 0
	}
	
	#open the audio file
	var f = FileAccess.open(file, FileAccess.READ)
	if f == null:
		return brk  # couldn't open
	
	f.big_endian = true
	
	if f.get_buffer(4).get_string_from_ascii().to_lower() != "mthd":
		#not a midi file
		return brk
	else:
		f.seek(8) #skip past the size
		midi_file_properties["format"] = f.get_16()
		midi_file_properties["ntrks"] = f.get_16()
		midi_file_properties["division"] = f.get_16()
		
		print(midi_file_properties)
		
		while f.get_position() < f.get_length():
			var chunk_type = f.get_buffer(4).get_string_from_ascii().to_lower()
			var chunk_length = f.get_32()
			var end_of_chunk = f.get_position() + chunk_length
			
			if chunk_type == "mtrk":
				print("found data chunk")
				
				var message_type
				var midi_channel
				
				while f.get_position() < end_of_chunk:
					var delta_time = get_variable_length_quantity(f)
					
					print("\n Delta Time: " + str(delta_time))
					
					var first_message_byte = f.get_8()
					if first_message_byte >= 0x80:
						#this is a status byte dictating what the message is
						message_type = first_message_byte >> 4
						midi_channel = first_message_byte & 0x0F
					else:
						#no status byte, using running status
						#use previous status and treat this as data
						f.seek(f.get_position() - 1)
					match message_type:
						8:
							#note off
							print("note off")
							var note = f.get_8()
							var velocity = f.get_8()
							print(note)
							print(velocity)
						9:
							#note on
							print("note on")
							var note = f.get_8()
							var velocity = f.get_8()
							print("Note: " + str(note))
							print("Velocity: " + str(velocity))
						10:
							#polyphonic aftertouch
							print("aftertouch")
							f.seek(f.get_position() + 2)
						11:
							#cc change
							print("cc change")
							f.seek(f.get_position() + 2)
						12:
							#program change
							print("program change")
							f.seek(f.get_position() + 1)
						13:
							#channel pressure
							print("channel pressure")
							f.seek(f.get_position() + 1)
						14:
							#pitch bend
							print("pitch bend")
							f.seek(f.get_position() + 2)
						15:
							#sysex or meta
							if midi_channel == 0 or midi_channel == 7:
								print("sysex")
								var data_length = get_variable_length_quantity(f)
								f.seek(f.get_position() + data_length)
							else:
								var type = f.get_8()
								print("Meta, type: " + str(type))
								var data_length = get_variable_length_quantity(f)
								#if type != 0:
									#data_length = get_variable_length_quantity(f)
								#else:
									#data_length = 2
								match type:
									0:
										print("Sequence Number")
										f.seek(f.get_position() + data_length)
									1:
										print("Text Event")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										print(meta_text)
									2:
										print("Copyright Notice")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										print(meta_text)
									3:
										print("Sequence/Track Name")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										print(meta_text)
									4:
										print("Instrument Name")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										print(meta_text)
									5:
										print("Lyric")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										print(meta_text)
									6:
										print("Marker")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										print(meta_text)
									7:
										print("Cue Point")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										print(meta_text)
									32:
										print("Midi Channel Prefix")
										f.seek(f.get_position() + data_length)
									47:
										print("End of Track")
										f.seek(f.get_position() + data_length)
									81:
										print("Set Tempo")
										f.seek(f.get_position() + data_length)
									84:
										print("SMTPE Offset")
										f.seek(f.get_position() + data_length)
									88:
										print("Time Signature")
										f.seek(f.get_position() + data_length)
									89:
										print("Key Signature")
										f.seek(f.get_position() + data_length)
									_:
										print("unknown meta")
										f.seek(f.get_position() + data_length)
									

									
					
				
				#f.seek(end_of_chunk)
			else:
				f.seek(end_of_chunk)
	
	
	
	f.close()
	print("File Closed")
	return brk

func get_variable_length_quantity(f: FileAccess) -> int:
	var value = 0
	while true:
		var vlq_byte = f.get_8()
		value = (value << 7) | (vlq_byte & 0x7f)
		
		if vlq_byte & 0x80 == 0:
			break
	
	return value
