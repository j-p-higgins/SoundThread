extends Node
class_name MIDIParser

func midi_to_brk(file: String, convert_to_hz: bool) -> Dictionary:
	var midi_file_properties = {
		"format": 0,
		"ntrks": 0,
		"division": 0,
		"tracks": []
	}
	
	#open the audio file
	var f = FileAccess.open(file, FileAccess.READ)
	if f == null:
		return midi_file_properties  # couldn't open
	
	f.big_endian = true
	
	if f.get_buffer(4).get_string_from_ascii().to_lower() != "mthd":
		#not a midi file
		return midi_file_properties
	else:
		f.seek(8) #skip past the size
		midi_file_properties["format"] = f.get_16()
		midi_file_properties["ntrks"] = f.get_16()
		midi_file_properties["division"] = f.get_16()
		
		#print(midi_file_properties)
		
		var track_number = 0
		while f.get_position() < f.get_length():
			var chunk_type = f.get_buffer(4).get_string_from_ascii().to_lower()
			var chunk_length = f.get_32()
			var end_of_chunk = f.get_position() + chunk_length
			
			
			if chunk_type == "mtrk":
				track_number += 1
				var track_data = {
					"track_number": track_number,
					"track_name": "Track " + str(track_number),
					"brk": []
				}
				
				#print("found data chunk")
				
				var message_type
				var midi_channel
				
				var current_tick = 0
				var previous_tick = 0
				var break_file = []
				var held_notes = []
				
				while f.get_position() < end_of_chunk:
					
					var delta_time = get_variable_length_quantity(f)
					
					current_tick += delta_time
					if current_tick != previous_tick and held_notes.size() != 0:
						#moved to the next tick, write the last pressed note to the array
						break_file.append(Vector2(previous_tick, held_notes[held_notes.size() - 1]))
					
					#print("\n Delta Time: " + str(delta_time))
					
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
							#print("note off")
							var note = f.get_8()
							var velocity = f.get_8()
							#print(note)
							#print(velocity)
							
							held_notes.erase(note)
							previous_tick = current_tick
						9:
							#note on
							#print("note on")
							var note = f.get_8()
							var velocity = f.get_8()
							#print("Note: " + str(note))
							#print("Velocity: " + str(velocity))
							
							if velocity != 0:
								held_notes.append(note)
								#if previous_tick == current_tick and break_file.size() != 0:
									#break_file[break_file.size() - 1] = Vector2(current_tick, note)
								#else:
									#break_file.append(Vector2(current_tick, note))
								previous_tick = current_tick
							else:
								held_notes.erase(note)
								#if held_notes.size() > 0:
									#var last_held_note = held_notes[held_notes.size() - 1]
									#break_file.append(Vector2(current_tick, last_held_note))
								previous_tick = current_tick
						10:
							#polyphonic aftertouch
							#print("aftertouch")
							f.seek(f.get_position() + 2)
						11:
							#cc change
							#print("cc change")
							f.seek(f.get_position() + 2)
						12:
							#program change
							#print("program change")
							f.seek(f.get_position() + 1)
						13:
							#channel pressure
							#print("channel pressure")
							f.seek(f.get_position() + 1)
						14:
							#pitch bend
							#print("pitch bend")
							f.seek(f.get_position() + 2)
						15:
							#sysex or meta
							if midi_channel == 0 or midi_channel == 7:
								#print("sysex")
								var data_length = get_variable_length_quantity(f)
								f.seek(f.get_position() + data_length)
							else:
								var type = f.get_8()
								#print("Meta, type: " + str(type))
								var data_length = get_variable_length_quantity(f)
								match type:
									0:
										#print("Sequence Number")
										f.seek(f.get_position() + data_length)
									1:
										#print("Text Event")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										#print(meta_text)
									2:
										#print("Copyright Notice")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										#print(meta_text)
									3:
										#print("Sequence/Track Name")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										track_data["track_name"] = meta_text
										#print(meta_text)
									4:
										#print("Instrument Name")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										#print(meta_text)
									5:
										#print("Lyric")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										#print(meta_text)
									6:
										#print("Marker")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										#print(meta_text)
									7:
										#print("Cue Point")
										var meta_text = f.get_buffer(data_length).get_string_from_ascii()
										#print(meta_text)
									32:
										#print("Midi Channel Prefix")
										f.seek(f.get_position() + data_length)
									47:
										#print("End of Track")
										#add a point for 100% if the file ends after the end of the last midi note
										if break_file.size() != 0 and current_tick != previous_tick:
											var last_value = break_file[break_file.size() - 1].y
											break_file.append(Vector2(current_tick, last_value))
										f.seek(f.get_position() + data_length)
									81:
										#print("Set Tempo")
										f.seek(f.get_position() + data_length)
									84:
										#print("SMTPE Offset")
										f.seek(f.get_position() + data_length)
									88:
										#print("Time Signature")
										f.seek(f.get_position() + data_length)
									89:
										#print("Key Signature")
										f.seek(f.get_position() + data_length)
									_:
										#print("unknown meta")
										f.seek(f.get_position() + data_length)
									
				#done parsing track cleanup breakfile info
				#don't check last value as it should be the same as the previous but clean up all other duplicates
				if break_file.size() > 1:
					for i in range(break_file.size() - 2, 0, -1):
						if break_file[i].y == break_file[i - 1].y:
							break_file.remove_at(i)
							
					if break_file[0].x != 0:
						#if the first point isnt at 0 move it to preserve other timings on scaling
						break_file[0].x = 0
						
					#scale timing from 0-100%
					var max_ticks = break_file[break_file.size() - 1].x
					for i in range(break_file.size()):
						break_file[i].x = remap(break_file[i].x, 0, max_ticks, 0, 100)
						
					#add note hold
					for i in range(break_file.size() - 3, -1, -1):
						var x = break_file[i + 1].x - 0.1
						var y = break_file[i].y
						
						break_file.insert(i + 1, Vector2(x, y))
					if convert_to_hz:
						for i in range(break_file.size()):
							break_file[i].y = convert_midi_to_hz(break_file[i].y)
						
					track_data["brk"] = break_file
					midi_file_properties["tracks"].append(track_data)
					
				
				#f.seek(end_of_chunk)
			else:
				f.seek(end_of_chunk)
	
	
	
	f.close()
	print("File Closed")
	print(midi_file_properties)
	return midi_file_properties

func get_variable_length_quantity(f: FileAccess) -> int:
	#Variable Length Quantities
	#The variable-length quantity provides a convenient means of representing arbitrarily large integers,
	#without creating needlessly large fixed-width integers.
	
	#A variable-length quantity is a represented as a series of 7-bit values, from most-significant to least-significant. 
	#where the last byte of the series bit 7 (the most significant bit) set to 0, and the preceding bytes have bit 7 set to 1.
	#from: https://www.personal.kent.edu/~sbirch/Music_Production/MP-II/MIDI/midi_file_format.htm#vlq
	
	var value = 0
	while true:
		#get the next byte in the file
		var vlq_byte = f.get_8()
		#multiply existing value by 128 by shifting it 7 bits
		#extract the vlq value by masking
		#add it to the now multiplied value
		value = (value << 7) | (vlq_byte & 0x7f)
		
		if vlq_byte & 0x80 == 0:
			#this is the last byte in the value break the loop
			break
	
	return value

#on its own in case it might be useful for something later
func convert_midi_to_hz(note: int) -> float:
	return 440.0 * pow(2, (note - 69) / 12.0)
