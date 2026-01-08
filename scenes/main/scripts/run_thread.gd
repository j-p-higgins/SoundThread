extends Node
var control_script

var progress_label
var progress_bar
var graph_edit
var console_output
var progress_window
var console_window
var process_successful #tracks if the last run process was successful
var process_info = {} #tracks the data of the currently running process
var process_running := false #tracks if a process is currently running
var process_cancelled = false #checks if the currently running process has been cancelled
var final_output_dir
var fft_size = 1024 #tracks the fft size for the thread set in the main window
var fft_overlap = 3 #tracks the fft overlap for the thread set in the main window

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


func init(main_node: Node, progresswindow: Window, progresslabel: Label, progressbar: ProgressBar, graphedit: GraphEdit, consolewindow: Window, consoleoutput: RichTextLabel) -> void:
	control_script = main_node
	progress_window = progresswindow
	progress_label = progresslabel
	progress_bar = progressbar
	graph_edit = graphedit
	console_window = consolewindow
	console_output = consoleoutput


	
func run_thread_with_branches():
	process_cancelled = false
	process_successful = true
	progress_bar.value = 0
	progress_label.text = "Initialising Inputs"
	console_window.find_child("KillProcess").disabled = false
	# Detect platform: Determine if the OS is Windows
	var is_windows := OS.get_name() == "Windows"
	
	# Choose appropriate commands based on OS
	var delete_cmd = "del" if is_windows else "rm"
	var rename_cmd = "ren" if is_windows else "mv"

	# Get all node connections in the GraphEdit
	var connections = graph_edit.get_connection_list()

	# Prepare data structures for graph traversal
	var graph = {}          # forward adjacency list
	var reverse_graph = {}  # reverse adjacency list (for input lookup)
	var indegree = {}       # used for topological sort
	var all_nodes = {}      # map of node name -> GraphNode reference
	
	#store input nodes for sample rate and stereo matching
	var input_nodes = []
	var nodes_with_sample_rates = []
	var processing_sample_rate = 0 #sample rate that processing is being done at after input file is normalised, if this stays at 0 only synthesis exists in thread and highest value from that should be used
	var processing_bit_depth = 1 #stores the file type and bit-depth in the format used by the copysfx cdp function 1: 16-bit 2: 32-bit int 3: 32-bit float 4: 24-bit
	var intermediate_files = [] # Files to delete later
	var breakfiles = [] #breakfiles to delete later

	log_console("Mapping thread.", true)
	await get_tree().process_frame  # Let UI update

	#Step 0: check thread is valid
	var is_valid = path_exists_through_all_nodes()
	if is_valid == false:
		log_console("[color=#9c2828][b]Error: Valid Thread not found[/b][/color]", true)
		log_console("Threads must contain at least one processing node and a valid path from the Input File or Synthesis node to the Output File.", true)
		await get_tree().process_frame  # Let UI update
		if progress_window.visible:
			progress_window.hide()
		if !console_window.visible:
			console_window.popup_centered()
		return
	else:
		log_console("[color=#638382][b]Valid Thread found[/b][/color]", true)
		await get_tree().process_frame  # Let UI update
		
	# Step 1: Gather nodes from the GraphEdit
	var inputcount = 0 # used for tracking the number of input nodes and trims on input files for progress bar
	for child in graph_edit.get_children():
		if child is GraphNode:
			var includenode = true
			var name = str(child.name)
			all_nodes[name] = child
			if child.has_meta("utility"):
				includenode = false
			else:
				#check if node has inputs
				if child.get_input_port_count() > 0:
					#if it does scan through those inputs
					for i in range(child.get_input_port_count()):
						#check if it can find any valid connections
						var connected = false
						for conn in connections:
							if conn["to_node"] == name and conn["to_port"] == i:
								connected = true
								break
						#if no valid connections are found break the for loop to skip checking other inputs and set include to false
						if connected == false:
							log_console(name + " input is not connected, skipping node.", true)
							includenode = false
							break
				#check if node has outputs
				if child.get_output_port_count() > 0:
					#if it does scan through those outputs
					for i in range(child.get_output_port_count()):
						#check if it can find any valid connections
						var connected = false
						for conn in connections:
							if conn["from_node"] == name and conn["from_port"] == i:
								connected = true
								break
						#if no valid connections are found break the for loop to skip checking other inputs and set include to false
						if connected == false:
							log_console(name + " output is not connected, skipping node.", true)
							includenode = false
							break
								
			if includenode == true:
				graph[name] = []
				reverse_graph[name] = []
				indegree[name] = 0  # Start with zero incoming edges
				if child.get_meta("command") == "inputfile":
					inputcount -= 1
					input_nodes.append(child)
					if child.get_node("AudioPlayer").get_meta("trimfile"):
						inputcount += 1
				#check if node has internal sample rate, e.g. synthesis nodes and add to array for checking if this is set correctly
				if child.has_meta("node_sets_sample_rate") and child.get_meta("node_sets_sample_rate") == true:
					nodes_with_sample_rates.append(child)
	#do calculations for progress bar
	var progress_step
	progress_step = 100 / (graph.size() + 3 + inputcount)

	#check if input file sample rates and bit depths match
	if input_nodes.size() > 1:
		var match_input_files = await match_input_file_sample_rates_and_bit_depths(input_nodes)
		if control_script.delete_intermediate_outputs:
			for f in match_input_files[0]:
				intermediate_files.append(f)
		processing_sample_rate = match_input_files[1]
		processing_bit_depth = match_input_files[2]
	elif input_nodes.size() == 1:
		#reset upsampled if it has previously been set on this node
		input_nodes[0].get_node("AudioPlayer").set_meta("upsampled", false)
		#get sample rate and bit-depth so that any synthesis nodes can have the correct sample rate set
		processing_sample_rate = input_nodes[0].get_node("AudioPlayer").get_meta("sample_rate")
		var soundfile_properties = get_soundfile_properties(input_nodes[0].get_node("AudioPlayer").get_meta("inputfile"))
		processing_bit_depth = classify_format(soundfile_properties["format"], soundfile_properties["bitdepth"])
	
	
	#check if the sample rate of synthesis nodes match and if they match any files in the input file nodes
	if (nodes_with_sample_rates.size() > 0 and input_nodes.size() > 0) or nodes_with_sample_rates.size() > 1:
		var sythesis_sample_rates = []
		var highest_synthesis_sample_rate
		var final_synthesis_sample_rate
		var change_synthesis_sample_rate
		
		for node in nodes_with_sample_rates:
			#get the sample rate from the meta and add to an array
			var sample_rate_option_button = node.get_node("samplerate")
			sythesis_sample_rates.append(int(sample_rate_option_button.get_item_text(sample_rate_option_button.selected)))
		
		#Check if all sample rates are the same
		if sythesis_sample_rates.all(func(v): return v == sythesis_sample_rates[0]):
			highest_synthesis_sample_rate = sythesis_sample_rates[0]
			if processing_sample_rate != 0 and processing_sample_rate != highest_synthesis_sample_rate:
				change_synthesis_sample_rate = true
				final_synthesis_sample_rate = processing_sample_rate
		else:
			#if not find the highest sample rate
			change_synthesis_sample_rate = true
			highest_synthesis_sample_rate = sythesis_sample_rates.max()
			if processing_sample_rate != 0 and processing_sample_rate != highest_synthesis_sample_rate:
				final_synthesis_sample_rate = processing_sample_rate
			else:
				final_synthesis_sample_rate = highest_synthesis_sample_rate
		
		if change_synthesis_sample_rate:
			log_console("Sample rate in synthesis nodes do not match the rest of the thread. Adjusting values to " + str(final_synthesis_sample_rate) + "Hz", true)
			for node in nodes_with_sample_rates:
				#get the sample rate from the meta and add to an array
				node.get_node("samplerate").set_meta("adjusted_sample_rate", true)
				node.get_node("samplerate").set_meta("new_sample_rate", final_synthesis_sample_rate)
			
	# Step 2: Build graph relationships from connections
	if process_cancelled:
		progress_label.text = "Thread Stopped"
		log_console("[b]Thread Stopped[/b]", true)
		return
	else:
		progress_label.text = "Building Thread"
	for conn in connections:
		var from = str(conn["from_node"])
		var to = str(conn["to_node"])
		if graph.has(from) and graph.has(to):
			graph[from].append(to)
			reverse_graph[to].append(from)
			indegree[to] += 1  # Count incoming edges
			
	# check for loops
	var has_cycle := detect_cycles(graph, {})  # pass loop_nodes list later
	if has_cycle:
		log_console("[color=#9c2828][b]Error: Thread not valid, Threads cannot contain loops.[/b][/color]", true)
		if progress_window.visible:
			progress_window.hide()
		if !console_window.visible:
			console_window.popup_centered()
		return
		
	# Step 3: Topological sort to get execution order
	var sorted = []  # Sorted list of node names
	var queue = []   # Queue of nodes with 0 indegree

	for node in graph.keys():
		if indegree[node] == 0:
			queue.append(node)

	while not queue.is_empty():
		var current = queue.pop_front()
		sorted.append(current)
		for neighbor in graph[current]:
			indegree[neighbor] -= 1
			if indegree[neighbor] == 0:
				queue.append(neighbor)

	# If not all nodes were processed, there's a cycle
	#if sorted.size() != graph.size():
		#log_console("[color=#9c2828][b]Error: Thread not valid[/b][/color]", true)
		#log_console("Threads cannot contain loops.", true)
		#return
	progress_bar.value = progress_step
	# Step 4: Start processing audio

	# Dictionary to keep track of each node's output file
	var output_files = {}
	var process_count = 0

	#var current_infile

	# Iterate over the processing nodes in topological order
	for node_name in sorted:
		var node = all_nodes[node_name]
		if process_cancelled:
			progress_label.text = "Thread Stopped"
			log_console("[b]Thread Stopped[/b]", true)
			break
		else:
			progress_label.text = "Running process: " + node.get_title()
		# Find upstream nodes connected to the current node
		# Build an array of all inlet connections
		var input_connections := []
		for conn in connections:
			if conn["to_node"] == node_name:
				input_connections.append(conn)
		input_connections.sort_custom(func(a, b): return a["to_port"] < b["to_port"])
		
		#build a dictionary with all inputs sorted by inlet number
		var inlet_inputs = {}

		for conn in input_connections:
			var inlet_idx = conn["to_port"]
			var upstream_node = conn["from_node"]
			if output_files.has(upstream_node):
				if not inlet_inputs.has(inlet_idx):
					inlet_inputs[inlet_idx] = []
				inlet_inputs[inlet_idx].append(output_files[upstream_node])

		# Merge inputs if inlet has more than one input and build infile dictionary
		var current_infiles = {} #dictionary to store input files by inlet number

		for inlet_idx in inlet_inputs.keys():
			var files = inlet_inputs[inlet_idx]
			if files.size() > 1: #if more than one file mix them together
				var runmerge = await merge_many_files(inlet_idx, process_count, files)
				var merge_output = runmerge[0] #mixed output file name
				var converted_files = runmerge[1] #intermediate files created from merge

				current_infiles[inlet_idx] = merge_output #input filename added to dictionary sorted by inlet number
				
				#add intermediate files to delete list if toggled
				if control_script.delete_intermediate_outputs:
					intermediate_files.append(merge_output)
					for f in converted_files:
						intermediate_files.append(f)
			elif files.size() == 1:
				current_infiles[inlet_idx] = files[0] #only one file, do not merge add to dictionary
		
		#if the dictionary has more than one entry there is more than one inlet and files need to be matched
		#however this should only be done to nodes with audio files rather than pvoc nodes
		if current_infiles.size() > 1 and node.get_slot_type_left(0) == 0:
			#check all files in dictionary have the same sample rate and channel count and fix if not
			var all_files = current_infiles.values()
			
			var match_channels = await match_file_channels(0, process_count, all_files)
			var matched_files = match_channels[0]
			
			#add intermediate files
			if control_script.delete_intermediate_outputs:
				for f in match_channels[1]:
					intermediate_files.append(f)
			
			#replace files in dictionary with matched files
			var idx = 0
			for key in current_infiles.keys():
				current_infiles[key] = matched_files[idx]
				idx += 1
		
		#check if node is some form of input node
		if node.get_input_port_count() == 0:
			if node.get_meta("command") == "inputfile":
				var loadedfile
				#get the inputfile from the nodes meta
				if node.get_node("AudioPlayer").get_meta("upsampled"):
					loadedfile = node.get_node("AudioPlayer").get_meta("upsampled_file")
				else:
					loadedfile = node.get_node("AudioPlayer").get_meta("inputfile")
					
				#check if input file has any invalid characters in path/name
				var check_invalid_characters = Global.check_for_invalid_chars(loadedfile)
				
				if check_invalid_characters["contains_invalid_characters"] == true:
					log_console("Special characters found in input file path/name, creating copy without special characters", true)
					#get just the output folder by giving the outfile and extension and the running get base dir
					var output_folder_location = Global.outfile + ".wav"
					output_folder_location = output_folder_location.get_base_dir()
					#make a unigue name for this file
					var input_file_copy_name = Global.outfile.get_basename() + "_input_file_copy_" + str(process_count) + "." + loadedfile.get_extension()
					if is_windows:
						loadedfile = loadedfile.replace("/", "\\")
						output_folder_location = output_folder_location.replace("/", "\\")
						input_file_copy_name = input_file_copy_name.replace("/", "\\")
						await run_command("copy", [loadedfile, output_folder_location])
						await run_command(rename_cmd, [output_folder_location + "\\" + loadedfile.get_file(), input_file_copy_name.get_file()])
					else:
						await run_command("cp", [loadedfile, output_folder_location])
						await run_command(rename_cmd, [output_folder_location + "/" + loadedfile.get_file(), input_file_copy_name])
					
					loadedfile = input_file_copy_name
					
					if control_script.delete_intermediate_outputs:
						intermediate_files.append(input_file_copy_name)
						
					
				#get wether trim has been enabled
				var trimfile = node.get_node("AudioPlayer").get_meta("trimfile")
				
				#if trim is enabled trim the file
				if trimfile == true:
					#get the start and end points
					var start = node.get_node("AudioPlayer").get_meta("trimpoints")[0]
					var end = node.get_node("AudioPlayer").get_meta("trimpoints")[1]
					
					if process_cancelled:
						#exit out of process if cancelled
						progress_label.text = "Thread Stopped"
						log_console("[b]Thread Stopped[/b]", true)
						return
					else:
						progress_label.text = "Trimming input audio"
					await run_command(control_script.cdpprogs_location + "/sfedit", ["cut", "1", loadedfile, "%s_%d_input_trim.wav" % [Global.outfile, process_count], str(start), str(end)])
					
					output_files[node_name] =  "%s_%d_input_trim.wav" % [Global.outfile, process_count]
					
					# Mark trimmed file for cleanup if needed
					if control_script.delete_intermediate_outputs:
						intermediate_files.append("%s_%d_input_trim.wav" % [Global.outfile, process_count])
					progress_bar.value += progress_step
				else:
					#if trim not enabled pass the loaded file
					output_files[node_name] =  loadedfile
					
				process_count += 1
			else: #not an audio file must be synthesis
				var slider_data = _get_slider_values_ordered(node)
				var makeprocess = make_process(node, process_count, [], slider_data)
				# run the command
				await run_command(makeprocess[0], makeprocess[3])
				await get_tree().process_frame
				var output_file = makeprocess[1]
				
				#check if bitdepth matches other files in thread and convert if needed
				var soundfile_properties = get_soundfile_properties(output_file)
				if processing_bit_depth != classify_format(soundfile_properties["format"], soundfile_properties["bitdepth"]):
					var bit_convert_output = output_file.get_basename() + "_bit_depth_convert.wav"
					await run_command(control_script.cdpprogs_location + "/copysfx", ["-h0", "-s" + str(processing_bit_depth), output_file, bit_convert_output])
					#store converted output file path for this node
					output_files[node_name] = bit_convert_output
					#mark for cleanup if needed
					if control_script.delete_intermediate_outputs:
						intermediate_files.append(bit_convert_output)
				else:
					# Store original output file path for this node
					output_files[node_name] = output_file

				# Mark file for cleanup if needed
				if control_script.delete_intermediate_outputs:
					for file in makeprocess[2]:
						breakfiles.append(file)
					intermediate_files.append(output_file)
					
				process_count += 1
				
		#elif node.has_meta("bypassed") and node.get_meta("bypassed"):
			#check if node is bypassed and skip processing
			
		else:
			# Build the command for the current node's audio processing
			var slider_data = _get_slider_values_ordered(node)
			
			if node.get_slot_type_right(0) == 1: #detect if process outputs pvoc data
				if is_pvoc_stereo(current_infiles): #check if infiles contain an array meaning at least one input pvoc process has be processed in dual mono mode
					var split_files = await process_dual_mono_pvoc(current_infiles, node, process_count, slider_data)
					var pvoc_stereo_files = split_files[0]
								
					# Mark file for cleanup if needed
					if control_script.delete_intermediate_outputs:
						for file in split_files[1]:
							breakfiles.append(file)
						for file in pvoc_stereo_files:
							intermediate_files.append(file)
							
					process_count += 1
						
					output_files[node_name] = pvoc_stereo_files
				else:
					var input_stereo = is_stereo(current_infiles.values()[0])
					if input_stereo == true: 
						#audio file is stereo and needs to be split for pvoc processing
						var pvoc_stereo_files = []

						##Split stereo to c1/c2 and process
						var split_files = await stereo_split_and_process(current_infiles.values(), node, process_count, slider_data)
						pvoc_stereo_files = split_files[0]
							
						# Mark file for cleanup if needed
						if control_script.delete_intermediate_outputs:
							for file in split_files[1]:
								breakfiles.append(file)
							for file in pvoc_stereo_files:
								intermediate_files.append(file)
						
						#Delete c1 and c2 because they can be in the wrong folder and if the same infile is used more than once
						#with this stereo process CDP will throw errors in the console even though its fine
						var files_to_delete = split_files[2] + split_files[3]
						for file in files_to_delete:
							if is_windows:
								file = file.replace("/", "\\")
							await run_command(delete_cmd, [file])
						
						#advance process count to match the advancement in the stereo_split_and_process function
						process_count += 1
						
						# Store output file path for this node
						output_files[node_name] = pvoc_stereo_files
						
					else: 
						#input file is mono run through process
						var makeprocess = make_process(node, process_count, current_infiles.values(), slider_data)
						# run the command
						await run_command(makeprocess[0], makeprocess[3])
						await get_tree().process_frame
						var output_file = makeprocess[1]

						# Store output file path for this node
						output_files[node_name] = output_file

						# Mark file for cleanup if needed
						if control_script.delete_intermediate_outputs:
							for file in makeprocess[2]:
								breakfiles.append(file)
							intermediate_files.append(output_file)

			# Increase the process step count
				process_count += 1
				
			else: 
				#Process outputs audio
				#check if this is the last pvoc process in a stereo processing chain and check if infile is an array meaning that the last pvoc process was run in dual mono mode
				if node.get_meta("command") == "pvoc_synth" and is_pvoc_stereo(current_infiles):
					var split_files = await process_dual_mono_pvoc(current_infiles, node, process_count, slider_data)
					var pvoc_stereo_files = split_files[0]
								
					# Mark file for cleanup if needed
					if control_script.delete_intermediate_outputs:
						for file in split_files[1]:
							breakfiles.append(file)
						for file in pvoc_stereo_files:
							intermediate_files.append(file)
							
					process_count += 1
						
						
					#interleave left and right
					var output_file = Global.outfile.get_basename() + str(process_count) + "_interleaved.wav"
					await run_command(control_script.cdpprogs_location + "/submix", ["interleave", pvoc_stereo_files[0], pvoc_stereo_files[1], output_file])
					# Store output file path for this node
					output_files[node_name] = output_file
					
					# Mark file for cleanup if needed
					if control_script.delete_intermediate_outputs:
						intermediate_files.append(output_file)
				elif node.get_meta("command") == "preview":
					var preview_audioplayer = node.get_child(1)
					var preview_file = current_infiles.values()[0]
					preview_audioplayer._on_file_selected(preview_file)
					if preview_file in intermediate_files:
						intermediate_files.erase(preview_file)
				else:
					#Detect if input file is mono or stereo
					var input_stereo = is_stereo(current_infiles.values()[0])
					#var input_stereo = true #bypassing stereo check just for testing need to reimplement
					if input_stereo == true:
						if node.get_meta("stereo_input") == true: #audio file is stereo and process is stereo, run file through process
							#current_infile = current_infiles.values()
							var makeprocess = make_process(node, process_count, current_infiles.values(), slider_data)
							# run the command
							await run_command(makeprocess[0], makeprocess[3])
							await get_tree().process_frame
							var output_file = makeprocess[1]
							
							# Store output file path for this node
							output_files[node_name] = output_file

							# Mark file for cleanup if needed
							if control_script.delete_intermediate_outputs:
								for file in makeprocess[2]:
									breakfiles.append(file)
								intermediate_files.append(output_file)

						else: #audio file is stereo and process is mono, split stereo, process and recombine
							##Split stereo to c1/c2 and process
							var split_files = await stereo_split_and_process(current_infiles.values(), node, process_count, slider_data)
							var dual_mono_output = split_files[0]
								
							# Mark file for cleanup if needed
							if control_script.delete_intermediate_outputs:
								for file in split_files[1]:
									breakfiles.append(file)
								for file in dual_mono_output:
									intermediate_files.append(file)
							
							#Delete c1 and c2 because they can be in the wrong folder and if the same infile is used more than once
							#with this stereo process CDP will throw errors in the console even though its fine
							var files_to_delete = split_files[2] + split_files[3]
							for file in files_to_delete:
								if is_windows:
									file = file.replace("/", "\\")
								await run_command(delete_cmd, [file])
							
							#advance process count to match the advancement in the stereo_split_and_process function
							process_count += 1
							
							
							var output_file = Global.outfile.get_basename() + str(process_count) + "_interleaved.wav"
							await run_command(control_script.cdpprogs_location + "/submix", ["interleave", dual_mono_output[0], dual_mono_output[1], output_file])
							
							# Store output file path for this node
							output_files[node_name] = output_file

							# Mark file for cleanup if needed
							if control_script.delete_intermediate_outputs:
								intermediate_files.append(output_file)

					else: #audio file is mono, run through the process
						var makeprocess = make_process(node, process_count, current_infiles.values(), slider_data)
						# run the command
						await run_command(makeprocess[0], makeprocess[3])
						await get_tree().process_frame
						var output_file = makeprocess[1]
						

						# Store output file path for this node
						output_files[node_name] = output_file

						# Mark file for cleanup if needed
						if control_script.delete_intermediate_outputs:
							for file in makeprocess[2]:
								breakfiles.append(file)
							intermediate_files.append(output_file)

				# Increase the process step count
				process_count += 1
			progress_bar.value += progress_step
	# FINAL OUTPUT STAGE

	# Collect all nodes that are connected to the outputfile node
	if process_cancelled:
		progress_label.text = "Thread Stopped"
		log_console("[b]Thread Stopped[/b]", true)
		return
	else:
		progress_label.text = "Finalising output"
	var output_inputs := []
	for conn in connections:
		var to_node = str(conn["to_node"])
		if all_nodes.has(to_node) and all_nodes[to_node].get_meta("command") == "outputfile":
			output_inputs.append(str(conn["from_node"]))

	# List to hold the final output files to be merged (if needed)
	var final_outputs := []
	for node_name in output_inputs:
		if output_files.has(node_name):
			final_outputs.append(output_files[node_name])

	# If multiple outputs go to the outputfile node, merge them
	if final_outputs.size() > 1:
		var runmerge = await merge_many_files(0, process_count, final_outputs)
		final_output_dir = runmerge[0]
		var converted_files = runmerge[1]
		
		if control_script.delete_intermediate_outputs:
			for f in converted_files:
				intermediate_files.append(f)


	# Only one output, no merge needed
	elif final_outputs.size() == 1:
		var single_output = final_outputs[0]
		final_output_dir = single_output
		intermediate_files.erase(single_output)
	progress_bar.value += progress_step
	# CLEANUP: Delete intermediate files after processing, rename final output and reset upsampling meta
	if process_cancelled:
		progress_label.text = "Thread Stopped"
		log_console("[b]Thread Stopped[/b]", true)
		return
	else:
		log_console("Cleaning up intermediate files.", true)
		progress_label.text = "Cleaning up"
	for file_path in intermediate_files:
		# Adjust file path format for Windows if needed
		var fixed_path = file_path
		if is_windows:
			fixed_path = fixed_path.replace("/", "\\")
		await run_command(delete_cmd, [fixed_path])
		await get_tree().process_frame
	#delete break files 
	for file_path in breakfiles:
		# Adjust file path format for Windows if needed
		var fixed_path = file_path
		if is_windows:
			fixed_path = fixed_path.replace("/", "\\")
		await run_command(delete_cmd, [fixed_path])
		await get_tree().process_frame
		
		
	var final_filename = "%s.wav" % Global.outfile
	var final_output_dir_fixed_path = final_output_dir
	if is_windows:
		final_output_dir_fixed_path = final_output_dir_fixed_path.replace("/", "\\")
		await run_command(rename_cmd, [final_output_dir_fixed_path, final_filename.get_file()])
	else:
		await run_command(rename_cmd, [final_output_dir_fixed_path, "%s.wav" % Global.outfile])
	final_output_dir = Global.outfile + ".wav"
	
	control_script.output_audio_player.play_outfile(final_output_dir)
	Global.cdpoutput = final_output_dir
	progress_bar.value = 100.0
	var interface_settings = ConfigHandler.load_interface_settings() #checks if close console is enabled and closes console on a success
	progress_window.hide()
	progress_bar.value = 0
	progress_label.text = ""
	console_window.find_child("KillProcess").disabled = true
	if interface_settings.auto_close_console and process_successful == true:
		console_window.hide()

func stereo_split_and_process(files: Array, node: Node, process_count: int, slider_data: Array) -> Array:
	var dual_mono_output:= []
	var left:= []
	var right:= []
	var intermediate_files:= []
	
	for file in files:
		await run_command(control_script.cdpprogs_location + "/housekeep",["chans", "2", file])
		left.append(file.get_basename() + "_%s.%s" % ["c1", file.get_extension()])
		right.append(file.get_basename() + "_%s.%s" % ["c2", file.get_extension()])
	
	#loop through the left and right arrays and make and run the process for each of them
	for channel in [left, right]:
		var makeprocess = make_process(node, process_count, channel, slider_data)
		# run the command
		await run_command(makeprocess[0], makeprocess[3])
		await get_tree().process_frame
		var output_file = makeprocess[1]
		dual_mono_output.append(output_file)
		for file in makeprocess[2]:
			intermediate_files.append(file)
		
		#advance process count to maintain unique file names
		process_count += 1
		
	#return the two output files, any breakfiles generated and the split files for deletion
	return [dual_mono_output, intermediate_files, left, right]
	
func process_dual_mono_pvoc(current_infiles: Dictionary, node: Node, process_count: int, slider_data: Array) -> Array:
	match_pvoc_channels(current_infiles) #normalise dictionary to ensure that all entries are dual mono (any mono only processes are duplicated to both left and right)
	
	var infiles_left = []
	var infiles_right = []
	var pvoc_stereo_files = []
	var intermediate_files = []
	
	# extract left and right infiles from dictionary
	for value in current_infiles.values():
		infiles_left.append(value[0])
		infiles_right.append(value[1])
		
	for infiles in [infiles_left, infiles_right]:
		var makeprocess = make_process(node, process_count, infiles, slider_data)
		# run the command
		await run_command(makeprocess[0], makeprocess[3])
		await get_tree().process_frame
		var output_file = makeprocess[1]
		pvoc_stereo_files.append(output_file)
		for file in makeprocess[2]:
			intermediate_files.append(file)
		
		#advance process count to maintain unique file names
		process_count += 1
		
	return [pvoc_stereo_files, intermediate_files]
	
func is_stereo(file: String) -> bool:
	var soundfile_properties = get_soundfile_properties(file)
	if soundfile_properties["channels"] == 2:
		return true
	else:
		return false

func is_pvoc_stereo(current_infiles: Dictionary) -> bool:
	for value in current_infiles.values():
		if value is Array:
			return true
	return false

## Returns properties of a WAV file as a Dictionary:
## {
##   "format": 1 or 3,
##   "channels": number of channels,
##   "samplerate": sample rate in Hz,
##   "bitdepth": bits per sample,
##   "duration": length in seconds
## }
func get_soundfile_properties(file: String) -> Dictionary:
	var soundfile_properties:= {
		"format": 0,
		"channels": 0,
		"samplerate": 0,
		"bitdepth": 0,
		"duration": 0.0
	}
	
	#open the audio file
	var f = FileAccess.open(file, FileAccess.READ)
	if f == null:
		log_console("Could not find file: " + file, true)
		return soundfile_properties  # couldn't open
	
	#Skip the RIFF header (12 bytes: "RIFF", file size, "WAVE")
	f.seek(12)
	
	var audio_chunk_size = 0
	
	#read through file until end of file if needed
	while f.get_position() + 8 <= f.get_length():
		#read the 4 byte chunk id to identify what this chunk is
		var chunk_id = f.get_buffer(4).get_string_from_ascii() 
		#read how big this chunk is
		var chunk_size = f.get_32()
		
		if chunk_id == "fmt ":
			#found the format chunk
			#fmt chunk layout:
			#2 bytes: Audio format (1 = PCM, 3 = IEEE float, etc.)
			#2 bytes: Number of channels (1 = mono, 2 = stereo, ...)
			#4 bytes: Sample rate
			#4 bytes: Byte rate
			#2 bytes: Block align
			#2 bytes: Bits per sample
			#potentially misc other stuff depending on format
			soundfile_properties["format"] = f.get_16() #format 2 bytes: 1 = int PCM, 3 = float
			soundfile_properties["channels"] = f.get_16() #num of channels 2 bytes
			soundfile_properties["samplerate"] = f.get_32() #sample rate 4 bytes
			f.seek(f.get_position() + 6)
			soundfile_properties["bitdepth"] = f.get_16() #bitdepth 2 bytes
			
			#check if we have already found the data chunk (not likely) and break the loop
			if audio_chunk_size > 0:
				f.close()
				break
			#skip to the end of the fmt chunk - max protects against skipping weirdly if wav is malformed and we have already moved too far into the file
			f.seek(f.get_position() + (max(chunk_size - 16, 0)))
		elif chunk_id == "data":
			#this is where the audio is stored
			audio_chunk_size = chunk_size
			#check if we have already found the fmt chunk and break loop
			if soundfile_properties["format"] > 0:
				f.close()
				break
			#skip the rest of the chunk
			f.seek(f.get_position() + chunk_size)
		else:
			#don't care about any other data in the file skip it
			f.seek(f.get_position() + chunk_size)
			
	#close the file
	f.close()
	
	if audio_chunk_size > 0 and soundfile_properties["channels"] > 0 and soundfile_properties["bitdepth"] > 0 and soundfile_properties["samplerate"] > 0:
		#(channels * bitdepth) / 8 - div 8 to convet bits to bytes
		var block_align = int((soundfile_properties["channels"] * soundfile_properties["bitdepth"]) / 8)
		#number of frames = size of audio chunk / block size in bytes
		var num_frames = int(audio_chunk_size / block_align)
		#length in seconds = number of frames / sample rate
		soundfile_properties.duration = (num_frames) / soundfile_properties["samplerate"]
	else:
		#something = 0 and something has gone wrong
		log_console("No valid fmt chunk found in wav file, unable to establish, format, channel count, samplerate or bit-depth", true)
		for key in soundfile_properties:
			#normalise dictionary to 0 so code can detect errors later even if some values have ended up in the dictionary
			soundfile_properties[key] = 0
		return soundfile_properties #no fmt chunk found, invalid wav file
		
	return soundfile_properties

func get_analysis_file_properties(file: String) -> Dictionary:
	var analysis_file_properties:= {
		"windowsize": 0,
		"windowcount": 0,
		"decimationfactor": 0
	}
	
	#open the audio file
	var f = FileAccess.open(file, FileAccess.READ)
	if f == null:
		log_console("Could not find file: " + file, true)
		return analysis_file_properties  # couldn't open
	
	#Skip the RIFF header (12 bytes: "RIFF", file size, "WAVE")
	f.seek(12)
	
	var data_chunk_size = 0
	
	#read through file until end of file if needed
	while f.get_position() + 8 <= f.get_length():
		#read the 4 byte chunk id to identify what this chunk is
		var chunk_id = f.get_buffer(4).get_string_from_ascii() 
		#read how big this chunk is
		var chunk_size = f.get_32()
		
		#if chunk_id == "LIST":
			#f.seek(f.get_position() + 4) # skip first four bits of data - list type "adtl"
			#var list_end = f.get_position() + chunk_size
			#while f.get_position() <= list_end:
				#var sub_chunk_id = f.get_buffer(4).get_string_from_ascii() 
				#var sub_chunk_size = f.get_32()
				#
				#if sub_chunk_id == "note":
					#var note_bytes = f.get_buffer(sub_chunk_size)
					#var note_text = ""
					#for b in note_bytes:
						#note_text += char(b)
					#var pvoc_header_data = note_text.split("\n", false)
					#var i = 0
					#for entry in pvoc_header_data:
						#if entry == "analwinlen":
							#analysis_file_properties["windowsize"] = hex_string_to_int_le(pvoc_header_data[i+1])
						#elif entry == "decfactor":
							#analysis_file_properties["decimationfactor"] =  hex_string_to_int_le(pvoc_header_data[i+1])
						#i += 1
					#break
			##check if we have already found the data chunk (not likely) and break the loop
			#if data_chunk_size > 0:
				#f.close()
				#break
		if chunk_id == "data":
			#this is where the audio is stored
			data_chunk_size = chunk_size
			break
		else:
			#don't care about any other data in the file skip it
			f.seek(f.get_position() + chunk_size)
			
	#close the file
	f.close()
	
	#set window size to size from thread, not ideal but will change when move to using pvocex, see pvocex branch for proper implementation
	analysis_file_properties["windowsize"] = fft_size
	
	if analysis_file_properties["windowsize"] != 0 and data_chunk_size != 0:
		var bytes_per_frame = (analysis_file_properties["windowsize"] + 2) * 4
		analysis_file_properties["windowcount"] = int(data_chunk_size / bytes_per_frame)
	else:
		log_console("Error: Could not get information from analysis file", true)
		
	print(analysis_file_properties)
	return analysis_file_properties
	
func hex_string_to_int_le(hex_string: String) -> int:
	# Ensure the string is 8 characters (4 bytes)
	if hex_string.length() != 8:
		push_error("Invalid hex string length: " + hex_string)
		return 0
	var le_string = ""
	for i in [6, 4, 2, 0]: #flip the order of the bytes as ana format uses little endian
		le_string += hex_string.substr(i, 2)
	
	return le_string.hex_to_int()

func merge_many_files(inlet_id: int, process_count: int, input_files: Array) -> Array:
	var merge_output = "%s_merge_%d_%d.wav" % [Global.outfile.get_basename(), inlet_id, process_count]
	var converted_files := []  # Track any mono->stereo converted files or upsampled files
	
	#check if there are a mix of mono and stereo files and interleave mono files if required
	var match_channels = await match_file_channels(inlet_id, process_count, input_files)
	input_files = match_channels[0]
	converted_files += match_channels[1]

	# Merge all input files (converted or original)
	log_console("Mixing files to combined input.", true)
	var command := ["mergemany"]
	command += input_files
	command.append(merge_output)
	await run_command(control_script.cdpprogs_location + "/submix", command)
	
	if process_successful == false:
		log_console("Failed to merge files to" + merge_output, true)
	
	return [merge_output, converted_files]
	
func match_input_file_sample_rates_and_bit_depths(input_nodes: Array) -> Array:
	var sample_rates := []
	var input_files := [] #used to track input files so that the same file is not upsampled more than once should it be loaded into more than one input node
	var converted_files := []
	var highest_sample_rate
	var bit_depths:= []
	var file_types:= []
	var highest_bit_depth
	var int_float
	var final_format
	
	#get the sample rate, bit depth and file type (int/float) for each file and add to arrays
	for node in input_nodes:
		var soundfile_props = get_soundfile_properties(node.get_node("AudioPlayer").get_meta("inputfile"))
		file_types.append(soundfile_props["format"])
		sample_rates.append(soundfile_props["samplerate"])
		bit_depths.append(soundfile_props["bitdepth"])
		#set upsampled meta to false to allow for repeat runs of thread
		node.get_node("AudioPlayer").set_meta("upsampled", false)
	
	#Check if all sample rates are the same
	if sample_rates.all(func(v): return v == sample_rates[0]):
		highest_sample_rate = sample_rates[0]
		pass
	else:
		#if not find the highest sample rate
		highest_sample_rate = sample_rates.max()
		log_console("Different sample rates found in input files, upsampling files to match highest sample rate (" + str(highest_sample_rate) + "Hz) before processing.", true)
		#move through all input files and compare match their index to the sample_rate array
		for node in input_nodes:
			#check if sample rate of current node is less than the highest sample rate
			if node.get_node("AudioPlayer").get_meta("sample_rate") < highest_sample_rate:
				var input_file = node.get_node("AudioPlayer").get_meta("inputfile")
				#up sample it to the highest sample rate if so
				var upsample_output = Global.outfile + "_" + input_file.get_file().get_slice(".wav", 0) + "_" + str(highest_sample_rate) + ".wav"
				#check if file has previously been upsampled and if not upsample it
				if !input_files.has(input_file):
					input_files.append(input_file)
					await run_command(control_script.cdpprogs_location + "/housekeep", ["respec", "1", input_file, upsample_output, str(highest_sample_rate)])
					#add to converted files for cleanup if needed
					converted_files.append(upsample_output)
				node.get_node("AudioPlayer").set_meta("upsampled", true)
				node.get_node("AudioPlayer").set_meta("upsampled_file", upsample_output)
				
	input_files = [] #clear input files array for reuse with bitdepths
	
	#check if all file types and bit-depths are the same
	if file_types.all(func(v): return v == file_types[0]) and bit_depths.all(func(v): return v == bit_depths[0]):
		highest_bit_depth = bit_depths[0]
		int_float = file_types[0]
		#convert this to the value cdp uses in copysfx for potential use with synthesis nodes later
		final_format = classify_format(int_float, highest_bit_depth)
	else:
		highest_bit_depth = bit_depths.max()
		int_float = file_types.max()
		#convert this to the value cdp needs to convert file types using copysfx
		final_format = classify_format(int_float, highest_bit_depth)
		log_console("Different bit-depths found in input files, converting files to match highest bit-depth (" + str(highest_bit_depth) + "-bit) before processing.", true)
		#move through all input file nodes and compare them to the highest bit depth and file type
		var index = 0
		for node in input_nodes:
			if classify_format(file_types[index], bit_depths[index]) != final_format:
				var input_file
				#check if input file has already been upsampled and respec that file instead
				if node.get_node("AudioPlayer").get_meta("upsampled") == true:
					input_file = node.get_node("AudioPlayer").get_meta("upsampled_file")
				else:
					input_file = node.get_node("AudioPlayer").get_meta("inputfile")
				#build unique output name
				var bit_convert_output = Global.outfile + "_" + input_file.get_file().get_slice(".wav", 0) + "_" + str(highest_bit_depth) + "-bit" + ".wav"
				#check if this file has already been respeced (two input nodes with the same file loaded for some reason)
				if !input_files.has(input_file):
					input_files.append(input_file)
					await run_command(control_script.cdpprogs_location + "/copysfx", ["-h0", "-s" + str(final_format), input_file, bit_convert_output])
					#add to converted files for cleanup if needed
					converted_files.append(bit_convert_output)
				node.get_node("AudioPlayer").set_meta("upsampled", true)
				node.get_node("AudioPlayer").set_meta("upsampled_file", bit_convert_output)
			index += 1
	
	return [converted_files, highest_sample_rate, final_format]

func classify_format(file_type: int, bit_depth: int) -> int:
	#takes the bitdepth and file type (int/float) of a wav file and outputs a number that can be used by the cdp process copysfx to respec a files bit-depth
	match [file_type, bit_depth]:
		[1, 16]:
			return 1
		[1, 32]:
			return 2
		[3, 32]:
			return 3
		[1, 24]:
			return 4
		_:
			return -1

	
func match_file_channels(inlet_id: int, process_count: int, input_files: Array) -> Array:
	var converted_files := []
	var channel_counts := []
	
	# Check each file's channel count and build channel count array
	for f in input_files:
		var stereo = is_stereo(f)
		channel_counts.append(stereo)

	# Check if there is a mix of mono and stereo files
	if channel_counts.has(true) and channel_counts.has(false):
		log_console("Mix of mono and stereo files found, interleaving mono files to stereo before mixing.", true)
		var index = 0
		for f in input_files:
			if channel_counts[index] == false: #file is mono
				var stereo_file = Global.outfile + "_" + str(inlet_id) + "_" + str(process_count) + f.get_file().get_slice(".wav", 0) + "_stereo.wav"
				await run_command(control_script.cdpprogs_location + "/submix", ["interleave", f, f, stereo_file])
				if process_successful == false:
					log_console("Failed to interleave mono file: %s" % f, true)
				else:
					converted_files.append(stereo_file)
					input_files[index] = stereo_file
			index += 1

	return [input_files, converted_files]
	
func match_pvoc_channels(dict: Dictionary) -> void:
	#work through dictionary of files and make all entries dual arrays for stereo pvoc processing
	for key in dict.keys():
		var value = dict[key]
		if value is String:
			dict[key] = [value, value]
			
func _get_slider_values_ordered(node: Node) -> Array:
	var results := []
	if node.has_meta("command") and node.get_meta("command") == "pvoc_anal_1":
		results.append(["slider", "-c", fft_size, false, [], 2, 16380, false, false])
		results.append(["slider", "-o", fft_overlap, false, [], 1, 4, false, false])
		return results
	for child in node.get_children():
		if child is Range:
			var flag = child.get_meta("flag") if child.has_meta("flag") else ""
			var time = child.get_meta("time")
			var brk_data = []
			var min_slider = child.min_value
			var max_slider = child.max_value
			var exponential = child.exp_edit
			var fftwindowsize = child.get_meta("fftwindowsize")
			var fftwindowcount = child.get_meta("fftwindowcount")
			var value = child.value
			
			if child.has_meta("brk_data"):
				brk_data = child.get_meta("brk_data")
			#if this slider is a percentage of the fft size just calulate this here as fft size is a global value
			if fftwindowsize == true:
				if value == 100:
					value = fft_size
				else:
					value = max(int(fft_size * (value/100)), 1)
				min_slider = max(int(fft_size * (min_slider/100)), 1)
				max_slider = int(fft_size * (max_slider/100))
			results.append(["slider", flag, value, time, brk_data, min_slider, max_slider, exponential, fftwindowcount])
		elif child is CheckButton:
			var flag = child.get_meta("flag") if child.has_meta("flag") else ""
			results.append(["checkbutton", flag, child.button_pressed])
		elif child is OptionButton:
			var flag = child.get_meta("flag") if child.has_meta("flag") else ""
			var value = child.get_item_text(child.selected)
			#check if there has been a sample rate mismatch in the thread and adjust the this parameter to match the threads sample rate
			if child.has_meta("adjusted_sample_rate") and child.get_meta("adjusted_sample_rate"):
				value = str(child.get_meta("new_sample_rate"))
				child.set_meta("adjusted_sample_rate", false)
			results.append(["optionbutton", flag, value])
		#call this function recursively to find any nested sliders in scenes
		if child.get_child_count() > 0:
			var nested := _get_slider_values_ordered(child)
			results.append_array(nested)
	return results



func make_process(node: Node, process_count: int, current_infile: Array, slider_data: Array) -> Array:
	var args:= []
	var command
	var cleanup = []
	
	# Determine output extension: .wav or .ana based on the node's slot type
	var extension = ".wav" if node.get_slot_type_right(0) == 0 else ".ana"

	# Construct output filename for this step
	var output_file = "%s_%d%s" % [Global.outfile.get_basename(), process_count, extension]
	
	#special case for morph glide as it requires spec grab to have been run first
	if node.get_meta("command") == "morph_glide":
		#get slider values nothing else needed
		var window1 = slider_data[0][2]
		var window2 = slider_data[1][2]
		var duration = slider_data[2][2]
		
		#get length of the two input files
		var soundfile_1_props = get_soundfile_properties(current_infile[0])
		var infile_1_length = soundfile_1_props["duration"]
		var soundfile_2_props = get_soundfile_properties(current_infile[1])
		var infile_2_length = soundfile_2_props["duration"]
		if window1 == 100:
			#if slider is set to 100% default to 10 milliseconds before the end of the file to stop cdp moaning about rounding errors
			window1 = infile_1_length - 0.1
		else:
			window1 = infile_1_length * (window1 / 100) #calculate percentage time of the input file
		if window2 == 100:
			#if slider is set to 100% default to 10 milliseconds before the end of the file to stop cdp moaning about rounding errors
			window2 = infile_2_length - 0.1
		else:
			window2 = infile_2_length * (window2 / 100) #calculate percentage time of the input file
			
		#run spec grab to extract the chosen windows
		var window1_outfile = "%s_%d_%s%s" % [Global.outfile.get_basename(), process_count, "window1", extension]
		run_command("%s/%s" %[control_script.cdpprogs_location, "spec"], ["grab", current_infile[0], window1_outfile, str(window1)])
		cleanup.append(window1_outfile)
		var window2_outfile = "%s_%d_%s%s" % [Global.outfile.get_basename(), process_count, "window2", extension]
		run_command("%s/%s" %[control_script.cdpprogs_location, "spec"], ["grab", current_infile[1], window2_outfile, str(window2)])
		cleanup.append(window2_outfile)
		
		#build actual glide command
		command = "%s/%s" %[control_script.cdpprogs_location, "morph"]
		args = ["glide", window1_outfile, window2_outfile, output_file, duration]
	else:
		# Normal node process as usual 
		# Get the command name from metadata
		var command_name = str(node.get_meta("command"))
		if command_name.find("_") != -1:
			command_name = command_name.split("_", true, 1)
			command = "%s/%s" %[control_script.cdpprogs_location, command_name[0]]
			args = command_name[1].split("_", true, 1)
		else:
			command = "%s/%s" %[control_script.cdpprogs_location, command_name]
			
		if current_infile.size() > 0:
			#check if input is empty, e.g. synthesis nodes, otherwise append input file to arguments
			for file in current_infile:
				args.append(file)
		args.append(output_file)
		
		

		# Append parameter values from the sliders, include flags if present
		var slider_count = 0
		for entry in slider_data:
			if entry[0] == "slider":
				var flag = entry[1]
				var value = entry[2]
				#if value == int(value):
					#value = int(value)
				var time = entry[3] #checks if slider is a time percentage slider
				var brk_data = entry[4]
				var min_slider = entry[5]
				var max_slider = entry[6]
				var exponential = entry[7]
				var fftwindowcount = entry[8]
				var window_count
				if fftwindowcount == true:
					var analysis_file_data = get_analysis_file_properties(current_infile[0])
					window_count = analysis_file_data["windowcount"]
					min_slider = int(max(window_count * (min_slider / 100), 1))
					max_slider = int(window_count * (max_slider / 100))
				
				if brk_data.size() > 0: #if breakpoint data is present on slider
					#Sort all points by time
					var sorted_brk_data = []
					sorted_brk_data = brk_data.duplicate()
					sorted_brk_data.sort_custom(sort_points)
					
					var calculated_brk = []
					
					#get length of input file in seconds
					var infile_length = 1 #set infile length to dummy value just incase it does get used where it shouldn't to avoid crashes
					if current_infile.size() > 0:
						var soundfile_props = get_soundfile_properties(current_infile[0])
						infile_length = soundfile_props["duration"]
					
					#scale values from automation window to the right length for file and correct slider values
					#if node has an output duration then breakpoint files should be x = outputduration y= slider value else x=input duration, y=value
					if node.has_meta("outputduration"):
						for i in range(sorted_brk_data.size()):
							var point = sorted_brk_data[i]
							var new_x = float(node.get_meta("outputduration")) * (point.x / 700) #output time
							if i == sorted_brk_data.size() - 1: #check if this is last automation point
								new_x = float(node.get_meta("outputduration")) + 0.1  # force last point's x to infile_length + 100ms to make sure the file is defo over
							var new_y
							#check if slider is exponential and scale automation
							if exponential:
								new_y = remap_y_to_log_scale(point.y, 0.0, 255.0, min_slider, max_slider)
							else:
								new_y = remap(point.y, 255, 0, min_slider, max_slider) #slider value
							if time: #check if this is a time slider and convert to percentage of input file
								new_y = infile_length * (new_y / 100)
							calculated_brk.append(Vector2(new_x, new_y))
					else:
						for i in range(sorted_brk_data.size()):
							var point = sorted_brk_data[i]
							var new_x = infile_length * (point.x / 700) #time
							if i == sorted_brk_data.size() - 1: #check if this is last automation point
								new_x = infile_length + 0.1  # force last point's x to infile_length + 100ms to make sure the file is defo over
							var new_y
							#check if slider is exponential and scale automation
							if exponential:
								new_y = remap_y_to_log_scale(point.y, 0.0, 255.0, min_slider, max_slider)
							else:
								new_y = remap(point.y, 255, 0, min_slider, max_slider) #slider value
							calculated_brk.append(Vector2(new_x, new_y))
						
					#make text file
					var brk_file_path = output_file.get_basename() + "_" + str(slider_count) + ".txt"
					write_breakfile(calculated_brk, brk_file_path)
					
					#add breakfile to cleanup before adding flag
					cleanup.append(brk_file_path)
					
					#append text file in place of value
					#include flag if this param has a flag
					if flag.begins_with("-"):
						brk_file_path = flag + brk_file_path
					args.append(brk_file_path)
					
					
				else: #no break file append slider value
					if time == true:
						var soundfile_props = get_soundfile_properties(current_infile[0])
						var infile_length = soundfile_props["duration"]
						if value == 100:
							#if slider is set to 100% default to a millisecond before the end of the file to stop cdp moaning about rounding errors
							value = infile_length - 0.1
						else:
							value = infile_length * (value / 100) #calculate percentage time of the input file
					if fftwindowcount == true:
						if value == 100:
							value = window_count
						else:
							value = int(window_count * (value / 100))
					args.append(("%s%.2f " % [flag, value]) if flag.begins_with("-") else str(value))
					
			elif entry[0] == "checkbutton":
				var flag = entry[1]
				var value = entry[2]
				#if button is pressed add the flag to the arguments list
				if value == true:
					args.append(flag)
					
			elif entry[0] == "optionbutton":
				var flag = entry[1]
				var value = entry[2]
				args.append(("%s%.2f " % [flag, value]) if flag.begins_with("-") else str(value))
				
			slider_count += 1
	return [command, output_file, cleanup, args]
	#return [line.strip_edges(), output_file, cleanup]

func remap_y_to_log_scale(y: float, min_y: float, max_y: float, min_val: float, max_val: float) -> float:
	var t = clamp((y - min_y) / (max_y - min_y), 0.0, 1.0)
	# Since y goes top-down (0 = top, 255 = bottom), we invert t
	t = 1.0 - t
	var log_min = log(min_val) / log(10)
	var log_max = log(max_val) / log(10)
	var log_val = lerp(log_min, log_max, t)
	return pow(10.0, log_val)


func sort_points(a, b):
	return a.x < b.x
	
func write_breakfile(points: Array, path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		for point in points:
			var line = str(point.x) + " " + str(point.y) + "\n"
			file.store_string(line)
		file.close()
	else:
		log_console("Failed to open file to write breakfile", true)

func _on_kill_process_button_down() -> void:
	if process_running and process_info.has("pid"):
		progress_window.hide()
		# Terminate the process by PID
		OS.kill(process_info["pid"])
		process_running = false
		process_cancelled = true

func path_exists_through_all_nodes() -> bool:
	var graph = {}
	var input_node_names = []
	var output_node_name = ""

	# Gather nodes and initialize adjacency list
	for child in graph_edit.get_children():
		if child is GraphNode:
			var name = str(child.name)
			var command = child.get_meta("command")
			var input = child.get_meta("input")

			if input:
				input_node_names.append(name)
			elif command == "outputfile":
				output_node_name = name

			graph[name] = []

	# Add edges
	for conn in graph_edit.get_connection_list():
		var from_node = str(conn["from_node"])
		var to_node = str(conn["to_node"])
		if graph.has(from_node):
			graph[from_node].append(to_node)

	# BFS from each input node
	for input_node in input_node_names:
		var queue = [[input_node]]  # store paths, not just nodes
		while queue.size() > 0:
			var path = queue.pop_front()
			var current = path[-1]

			if current == output_node_name:
				# Candidate path found; validate multi-inlets
				if validate_path_inlets(path, graph, input_node_names):
					return true  # fully valid path found

			for neighbor in graph.get(current, []):
				if neighbor in path:
					continue  # avoid cycles
				var new_path = path.duplicate()
				new_path.append(neighbor)
				queue.append(new_path)

	return false


# Validate all nodes along a candidate path for multi-inlets
func validate_path_inlets(path: Array, graph: Dictionary, input_node_names: Array) -> bool:
	for node_name in path:
		var child = graph_edit.get_node(node_name)
		var input_count = child.get_input_port_count()
		if input_count <= 1:
			continue  # single-inlet nodes are trivially valid

		# Check each inlet
		for i in range(input_count):
			var inlet_valid = false
			for conn in graph_edit.get_connection_list():
				if str(conn["to_node"]) == node_name and conn["to_port"] == i:
					var src_node = str(conn["from_node"])
					if path_has_input(src_node, graph, input_node_names):
						inlet_valid = true
						break
			if not inlet_valid:
				return false  # this inlet cannot reach any input
	return true


# Step backwards from a node to see if a path exists to any input node
func path_has_input(current: String, graph: Dictionary, input_node_names: Array, visited: Dictionary = {}) -> bool:
	if current in input_node_names:
		return true
	if current in visited:
		return false
	visited[current] = true

	# Check all nodes that lead to current
	for conn in graph_edit.get_connection_list():
		if str(conn["to_node"]) == current:
			var src_node = str(conn["from_node"])
			if path_has_input(src_node, graph, input_node_names, visited.duplicate()):
				return true
	return false

#func path_exists_through_all_nodes() -> bool:
	#var graph = {}
	#var input_node_names = []
	#var output_node_name = ""
#
	## Gather nodes and build empty graph
	#for child in graph_edit.get_children():
		#if child is GraphNode:
			#var name = str(child.name)
			#var command = child.get_meta("command")
			#var input = child.get_meta("input")
#
			#if input:
				#input_node_names.append(name)
			#elif command == "outputfile":
				#output_node_name = name
#
			#graph[name] = []  # Initialize adjacency list
#
	## Add connections (edges)
	#for conn in graph_edit.get_connection_list():
		#var from = str(conn["from_node"])
		#var to = str(conn["to_node"])
		#if graph.has(from):
			#graph[from].append(to)
#
	## BFS to check if any input node reaches the output
	#for input_node in input_node_names:
		#var visited = {}
		#var queue = [input_node]
#
		#while queue.size() > 0:
			#var current = queue.pop_front()
#
			#if current == output_node_name:
				#return true  # Path found
#
			#if current in visited:
				#continue
			#visited[current] = true
#
			#for neighbor in graph.get(current, []):
				#queue.append(neighbor)
#
	## No path from any input node to output
	#return false
	
func log_console(text: String, update: bool) -> void:
	console_output.append_text(text + "\n \n")
	console_output.scroll_to_line(console_output.get_line_count() - 1)
	if update == true:
		await get_tree().process_frame  # Optional: ensure UI updates

func run_command(command: String, args: Array) -> String:
	var is_windows = OS.get_name() == "Windows"

	console_output.append_text(command + " " + " ".join(args) + "\n")
	console_output.scroll_to_line(console_output.get_line_count() - 1)
	await get_tree().process_frame
	
	if is_windows and (command == "del" or command == "ren" or command =="copy"): #checks if the command is a windows system command and runs it through cmd.exe
		args.insert(0, command)
		args.insert(0, "/C")
		process_info = OS.execute_with_pipe("cmd.exe", args, false)
	else:
		process_info = OS.execute_with_pipe(command, args, false)
	# Check if the process was successfully started
	if !process_info.has("pid"):
		log_console("Failed to start process", true)
		return ""
	
	process_running = true
	
	# Start monitoring the process output and status
	return await monitor_process(process_info["pid"], process_info["stdio"], process_info["stderr"])

func monitor_process(pid: int, stdout: FileAccess, stderr: FileAccess) -> String:
	var output := ""
	
	while OS.is_process_running(pid):
		await get_tree().process_frame
		
		while stdout.get_position() < stdout.get_length():
			var line = stdout.get_line()
			output += line
			console_output.append_text(line + "\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
		while stderr.get_position() < stderr.get_length():
			var line = stderr.get_line()
			output += line
			console_output.append_text(line + "\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
	
	var exit_code = OS.get_process_exit_code(pid)
	if exit_code == 0:
		if output.contains("ERROR:"): #checks if CDP reported an error but passed exit code 0 anyway
			console_output.append_text("[color=#9c2828][b]Processes failed[/b][/color]\n\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
			process_successful = false
			if process_cancelled == false:
				progress_window.hide()
				if !console_window.visible:
					console_window.popup_centered()
		else:
			console_output.append_text("[color=#638382]Processes ran successfully[/color]\n\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
	else:
		console_output.append_text("[color=#9c2828][b]Processes failed with exit code: %d[/b][/color]\n" % exit_code + "\n")
		console_output.scroll_to_line(console_output.get_line_count() - 1)
		process_successful = false
		if process_cancelled == false:
			progress_window.hide()
			if !console_window.visible:
				console_window.popup_centered()
		if output.contains("as an internal or external command"): #check for cdprogs location error on windows
			console_output.append_text("[color=#9c2828][b]Please make sure your cdprogs folder is set to the correct location in the Settings menu. The default location is C:\\CDPR8\\_cdp\\_cdprogs[/b][/color]\n\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
		if output.contains("command not found"): #check for cdprogs location error on unix systems
			console_output.append_text("[color=#9c2828][b]Please make sure your cdprogs folder is set to the correct location in the Settings menu. The default location is ~/cdpr8/_cdp/_cdprogs[/b][/color]\n\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
			
	process_running = false
	return output

# Main cycle detection
func detect_cycles(graph: Dictionary, loop_nodes: Dictionary) -> bool:
	var visited := {}
	var stack := {}

	for node in graph.keys():
		if _dfs_cycle(node, graph, visited, stack, loop_nodes):
			return true
	return false
	
func _dfs_cycle(node: String, graph: Dictionary, visited: Dictionary, stack: Dictionary, loop_nodes: Dictionary) -> bool:
	if not visited.has(node):
		visited[node] = true
		stack[node] = true

		for neighbor in graph[node]:
			# If neighbor hasn't been visited, recurse
			if not visited.has(neighbor):
				if _dfs_cycle(neighbor, graph, visited, stack, loop_nodes):
					# Cycle found down this path
					if not (loop_nodes.has(node) or loop_nodes.has(neighbor)):
						return true
			elif stack.has(neighbor):
				# Back edge found → cycle
				if not (loop_nodes.has(node) or loop_nodes.has(neighbor)):
					return true

	# Done exploring this node
	stack.erase(node)
	return false
