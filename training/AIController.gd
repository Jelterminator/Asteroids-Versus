extends AIController2D

var ship = null
@export var target_player_name := "Player"
var player1 = null

var brain = null
@export var brain_name := "1k"

# Removed the strict ": RewardManager" typing so headless mode doesn't panic
var reward_manager 
var gravity_basis: Array = []

func _ready():
	add_to_group("AGENT")
	_find_ships()
	
	# Force training mode if we are in a headless environment
	if "--headless" in OS.get_cmdline_args() and control_mode == 1:
		control_mode = 2

	# 1. Setup local inference
	var nn_script = load("res://NeuralNet.gd")
	if nn_script:
		brain = nn_script.new()
		var path = "res://models/brain_" + brain_name + ".json"
		if brain.load_from_json(path):
			print("AIController: Local brain loaded. Inference mode active.")
		else:
			print("AIController: No brain found. Yielding to Python Training.")
			
	# 3. Initialize Gravity Basis LUT for performance
	_init_gravity_basis()
			
	# 2. Setup Reward Manager safely for headless mode
	if is_instance_valid(ship) and is_instance_valid(player1):
		# Adjust this path if RewardManager.gd is in a different folder!
		var rm_script = load("res://training/RewardManager.gd")
		if rm_script:
			reward_manager = rm_script.new(brain_name, ship, player1)

func _find_ships():
	var massives = get_tree().get_nodes_in_group("massives")
	for m in massives:
		if m.name == target_player_name:
			ship = m
		elif m.name != target_player_name and (m.name == "Player" or m.name == "Player2"):
			player1 = m

func _physics_process(_delta):
	# --- LOCAL PLAY MODE ONLY ---
	if not ship or not is_instance_valid(ship): return
		
	if brain and brain.is_loaded: 
		if not player1 or not is_instance_valid(player1): _find_ships()
			
		var obs = get_obs().get("obs", [])
		var prediction = brain.predict(obs)
		
		ship.ai_thrust = prediction[0] > 0.0
		ship.ai_rot_dir = (1.0 if prediction[2] > 0.0 else 0.0) - (1.0 if prediction[1] > 0.0 else 0.0)
		ship.ai_fire = prediction[3] > 0.0

# --- HELPERS FOR OBSERVATION ---
func get_global_harmonic_coords(pos: Vector2) -> Array:
	var tau_inv_size = TAU / PhysicsConfig.WORLD_SIZE
	return [
		cos(pos.x * tau_inv_size), sin(pos.x * tau_inv_size),
		cos(pos.y * tau_inv_size), sin(pos.y * tau_inv_size)
	]

func shortest_toroidal_distance(p1: Vector2, p2: Vector2) -> float:
	var dx = fposmod(p1.x - p2.x + PhysicsConfig.WORLD_HALF_SIZE, PhysicsConfig.WORLD_SIZE) - PhysicsConfig.WORLD_HALF_SIZE
	var dy = fposmod(p1.y - p2.y + PhysicsConfig.WORLD_HALF_SIZE, PhysicsConfig.WORLD_SIZE) - PhysicsConfig.WORLD_HALF_SIZE
	return Vector2(dx, dy).length()

func get_obs() -> Dictionary:
	if not ship or not is_instance_valid(ship): 
		var arr = []; arr.resize(48); arr.fill(0.1) # Use 0.1 for visibility in obs
		return {"obs": arr}

	var obs = []

	# 1. SELF (9 vars)
	var beta_x = ship.p.x / (ship.m * PhysicsConfig.C)
	var beta_y = ship.p.y / (ship.m * PhysicsConfig.C)
	var time_until_laser = max(0.0, max(ship.laser_cooldown, ship.spawn_timer)) / PhysicsConfig.PLAYER_LASER_COOLDOWN
	obs.append_array(get_global_harmonic_coords(ship.pos))
	obs.append_array([beta_x, beta_y, cos(ship.rotation), sin(ship.rotation), time_until_laser])
	
	# 2. ENEMY (8 vars)
	if is_instance_valid(player1):
		var e_beta_x = player1.p.x / (player1.m * PhysicsConfig.C)
		var e_beta_y = player1.p.y / (player1.m * PhysicsConfig.C)
		obs.append_array(get_global_harmonic_coords(player1.pos))
		obs.append_array([e_beta_x, e_beta_y, cos(player1.rotation), sin(player1.rotation)])
	else:
		obs.append_array([1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])

	# 3. LASERS (12 vars)
	var lasers = get_tree().get_nodes_in_group("lasers")
	lasers.sort_custom(func(a, b): return shortest_toroidal_distance(ship.pos, a.pos) < shortest_toroidal_distance(ship.pos, b.pos))
	for i in range(2):
		if i < lasers.size():
			var l = lasers[i]
			var l_angle = l.p.angle()
			obs.append_array(get_global_harmonic_coords(l.pos))
			obs.append_array([cos(l_angle), sin(l_angle)])
		else:
			obs.append_array([1.0, 0.0, 1.0, 0.0, 1.0, 0.0])

	# 4. GRAVITY HARMONICS (12 vars) - Low-res 4x4 sampled
	var gm = get_parent().get_node_or_null("GravityManager")
	if gm:
		obs.append_array(get_gravity_harmonics(gm))
	else:
		var pad = []; pad.resize(12); pad.fill(0.0)
		obs.append_array(pad)

	# 5. CLOSEST ASTEROID (7 vars)
	# (We still collect asteroids to find the closest one)
	var asteroids = get_tree().get_nodes_in_group("asteroids")
	var valid_asteroids = []
	for a in asteroids:
		if is_instance_valid(a) and not a.is_exploding: valid_asteroids.append(a)

	if valid_asteroids.size() > 0:
		valid_asteroids.sort_custom(func(a, b): return shortest_toroidal_distance(ship.pos, a.pos) < shortest_toroidal_distance(ship.pos, b.pos))
		var a = valid_asteroids[0]
		var a_beta_x = a.p.x / (a.m * PhysicsConfig.C)
		var a_beta_y = a.p.y / (a.m * PhysicsConfig.C)
		var a_m_norm = a.m / PhysicsConfig.ASTEROID_INITIAL_WEIGHT_TOTAL
		obs.append_array(get_global_harmonic_coords(a.pos))
		obs.append_array([a_beta_x, a_beta_y, a_m_norm])
	else:
		obs.append_array([1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0])

	return {"obs": obs}

func get_gravity_harmonics(gravity_manager) -> Array:
	if gravity_basis.is_empty(): _init_gravity_basis()
	
	var harmonics = []
	var grid = gravity_manager.g_tt_grid
	var steps = [0, 4, 8, 12] # 4x4 sample points
	
	for basis in gravity_basis:
		var real_sum: float = 0.0
		var imag_sum: float = 0.0
		var s_idx = 0
		
		# Sample the 4x4 grid
		for sy in steps:
			var y_off = sy * 16
			for sx in steps:
				var g_tt = grid[y_off + sx]
				
				# Dot product with pre-calculated basis
				real_sum += g_tt * basis[0][s_idx]
				imag_sum += g_tt * basis[1][s_idx]
				s_idx += 1
		
		harmonics.append(tanh(real_sum * 2.0))
		harmonics.append(tanh(imag_sum * 2.0))
		
	return harmonics

func _init_gravity_basis():
	gravity_basis.clear()
	# Reduced to top 6 frequency pairs (12 vars total)
	var frequencies = [
		Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), 
		Vector2(2, 0), Vector2(0, 2), Vector2(2, 1)
	]
	var steps = [0, 4, 8, 12]
	const INV_N_TAU = -TAU / 16.0
	
	for uv in frequencies:
		var r_coeffs = []
		var i_coeffs = []
		for sy in steps:
			for sx in steps:
				var angle = (uv.x * sx + uv.y * sy) * INV_N_TAU
				r_coeffs.append(cos(angle))
				i_coeffs.append(sin(angle))
		gravity_basis.append([r_coeffs, i_coeffs])

# ==========================================
# GODOT RL TRAINING HOOKS
# ==========================================
func get_action_space() -> Dictionary:
	return {
		"thrust": {"size": 1, "action_type": "continuous"},
		"rot_left": {"size": 1, "action_type": "continuous"},
		"rot_right": {"size": 1, "action_type": "continuous"},
		"fire": {"size": 1, "action_type": "continuous"}
	}

func set_action(action: Dictionary):
	if not ship or not is_instance_valid(ship): return
	ship.ai_thrust = action["thrust"][0] > 0.0
	ship.ai_rot_dir = (1.0 if action["rot_right"][0] > 0.0 else 0.0) - (1.0 if action["rot_left"][0] > 0.0 else 0.0)
	ship.ai_fire = action["fire"][0] > 0.0

func get_reward() -> float:
	if not reward_manager: return 0.0
	var step_rew = reward_manager.compute_step_reward(get_physics_process_delta_time())
	if get_done():
		step_rew += reward_manager.compute_game_over_reward(GameState.winner)
	return step_rew

func get_done() -> bool:
	if not ship or not is_instance_valid(ship): return true
	return ship.is_exploding or GameState.winner != ""

func reset():
	var main = get_node_or_null("/root/Main") # Make sure this matches your scene root name!
	if main and main.has_method("reset_match"):
		var is_match_over = (GameState.p1_wins >= GameState.WINS_TO_WIN_MATCH or GameState.p2_wins >= GameState.WINS_TO_WIN_MATCH)
		main.reset_match(is_match_over)