extends Node
class_name NeuralNet

# We pre-process the JSON into highly optimized packed arrays upon loading.
var _processed_layers: Array[Dictionary] = []
var is_loaded: bool = false

func load_from_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		printerr("NeuralNet: Brain file not found at ", path)
		return false
	
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	var data = JSON.parse_string(content)
	
	if typeof(data) != TYPE_DICTIONARY or not data.has("layers"):
		printerr("NeuralNet: Invalid JSON format in ", path)
		return false
	
	_processed_layers.clear()
	
	# Pre-allocate and type-cast everything during load to save frame-time during prediction
	for layer_data in data.layers:
		var processed_layer = {
			"weights": [], # Will hold an Array of PackedFloat32Arrays
			"biases": PackedFloat32Array(layer_data.b),
			"activation": layer_data.get("activation", "linear") # Fallback to linear if omitted
		}
		
		# Convert each row of weights into a contiguous block of floats
		for row in layer_data.w:
			processed_layer.weights.append(PackedFloat32Array(row))
			
		_processed_layers.append(processed_layer)
		
	is_loaded = true
	print("NeuralNet: Loaded brain '", data.get("name", "Unknown"), "' with ", _processed_layers.size(), " layers.")
	return true

func predict(input_array: Array) -> Array:
	if not is_loaded: 
		return []
	
	# Cast the initial generic Array into a strict float array
	var current_vec := PackedFloat32Array(input_array)
	
	for layer in _processed_layers:
		# Static typing here ensures the GDScript VM doesn't waste time checking types
		var weights: Array = layer.weights
		var biases: PackedFloat32Array = layer.biases
		var activation: String = layer.activation
		var out_size: int = biases.size()
		var in_size: int = current_vec.size()
		
		# Pre-allocate the exact size needed for the next layer
		var next_vec := PackedFloat32Array()
		next_vec.resize(out_size)
		
		for i in range(out_size):
			var node_sum: float = biases[i]
			var row: PackedFloat32Array = weights[i]
			
			if row.size() != in_size:
				printerr("NeuralNet: Dimension mismatch! Expected ", row.size(), " but got ", in_size)
				return Array(current_vec) # Fail gracefully
			
			# --- CRITICAL INNER LOOP ---
			# Because both 'row' and 'current_vec' are PackedFloat32Array, 
			# this multiplication is incredibly fast.
			for j in range(in_size):
				node_sum += row[j] * current_vec[j]
			
			# Activation Functions
			if activation == "tanh":
				node_sum = tanh(node_sum)
			elif activation == "relu":
				node_sum = maxf(0.0, node_sum) # Use maxf for typed floats in Godot 4
			# "linear" does nothing
			
			next_vec[i] = node_sum
			
		current_vec = next_vec
		
	# Cast back to a generic Array for the rest of your game logic
	return Array(current_vec)