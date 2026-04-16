extends Node2D

@onready var massives_container = $Massives
var asteroid_scene: PackedScene
var match_ticks = 0
const MAX_MATCH_TICKS = 1200 # 5 seconds @ 240Hz for hyper-aggressive signal assignment
# Note: At 100x speedup, this will pass in ~1 second of real time.

func _ready():
	print("TRAINING: Initializing persistent environment...")
	asteroid_scene = load("res://asteroid.tscn")	# Initial setup (Clean Room for 1k)
	var args = OS.get_cmdline_args()
	var brain_name = "1k"
	for arg in args:
		if arg.begins_with("--brain_name="):
			brain_name = arg.split("=")[1]
	
	if brain_name != "1k":
		call_deferred("spawn_initial_asteroids")
	
	GameState.game_over.connect(_on_game_over)
	
	var p1 = massives_container.get_node_or_null("Player")
	var p2 = massives_container.get_node_or_null("Player2")
	if p1: p1.set_meta("is_ai", true)
	if p2: p2.set_meta("is_ai", true)
	
	# Initial setup
	call_deferred("spawn_initial_asteroids")

func _physics_process(_delta):
	match_ticks += 1
	if match_ticks >= MAX_MATCH_TICKS:
		if GameState.winner == "":
			print("MATCH TIMEOUT: Enforcing Draw Reset...")
			GameState.notify_death("TIMEOUT_DRAW")

func _on_game_over(winner_name, is_match_over = false):
	var reason = "KILL"
	if winner_name == "TIMEOUT_DRAW": reason = "TIMEOUT"
	
	print(">>> MATCH RESULT: [", reason, "] | Winner: ", winner_name, " | Score: ", GameState.p1_wins, "-", GameState.p2_wins)
	
	# If we are training (headless), STOP HERE. 
	# Python needs a fraction of a second to register the death and will call reset_match() through the AIController.
	if "--headless" in OS.get_cmdline_args():
		return
		
	# If we are playing normally, do whatever UI/Reset logic you want
	reset_match(is_match_over)

func reset_match(is_match_over = false):
	match_ticks = 0
	
	if is_match_over:
		GameState.reset_match_state() # Reset wins to 0-0
	else:
		GameState.reset_win_state() # Just clear current round winner
	
	# 1. Clear Debris
	get_tree().call_group("lasers", "queue_free")
	get_tree().call_group("asteroids", "queue_free")
	
	# 2. Reset Players
	var p1 = massives_container.get_node_or_null("Player")
	var p2 = massives_container.get_node_or_null("Player2")
	
	# Add Spawn Jitter to break corner-circling local optima
	var jitter = Vector2(randf_range(-50, 50), randf_range(-50, 50))
	
	if p1:
		p1.pos = Vector2(PhysicsConfig.WORLD_HALF_SIZE - 50.0, PhysicsConfig.WORLD_HALF_SIZE - 50.0) + jitter
		p1.p = Vector2.ZERO
		p1.orientation = Vector2(1, 1).normalized()
		p1.spawn_timer = 1.0 
		p1.laser_cooldown = 0.0 
	if p2:
		p2.pos = Vector2(PhysicsConfig.WORLD_HALF_SIZE + 50.0, PhysicsConfig.WORLD_HALF_SIZE + 50.0) - jitter
		p2.p = Vector2.ZERO
		p2.orientation = Vector2(-1, -1).normalized()
		p2.spawn_timer = 1.0 
		p2.laser_cooldown = 0.0
		
	# 3. Regenerate Asteroids (Clean Room for 1k)
	var args_reset = OS.get_cmdline_args()
	var is_1k = false
	for arg in args_reset:
		if arg == "--brain_name=1k": is_1k = true
	
	if not is_1k:
		call_deferred("spawn_initial_asteroids")

func spawn_initial_asteroids():
	var num_asteroids = randi_range(5, 15)
	var total_target_mass = 1200.0
	
	var p1 = massives_container.get_node_or_null("Player")
	var p2 = massives_container.get_node_or_null("Player2")
	
	# Middle Asteroid
	if p1 and p2:
		var midpoint = (p1.pos + p2.pos) / 2.0
		spawn_asteroid(400.0, midpoint)
		total_target_mass -= 400.0
	
	# Random Asteroids
	for i in range(num_asteroids):
		spawn_asteroid(total_target_mass / num_asteroids)

func spawn_asteroid(m_val, forced_pos = null):
	var spawn_pos = forced_pos if forced_pos != null else Vector2(randf_range(50, 460), randf_range(50, 460))
	var a = asteroid_scene.instantiate()
	a.m = m_val
	a.pos = spawn_pos
	a.p = Vector2(randf_range(-5, 5), randf_range(-5, 5)) * m_val
	massives_container.add_child(a)
