extends Node2D

@onready var massives_container = $GameContainer/GameViewport/Level/Massives
@onready var game_viewport = $GameContainer/GameViewport
@onready var tiled_display = $IsometricBox/WorldRotation/TiledDisplay
@onready var game_over_ui = $GameOverUI
@onready var winner_label = $GameOverUI/VBoxContainer/WinnerLabel
@onready var btn_restart = $GameOverUI/VBoxContainer/BtnRestart
@onready var btn_menu = $GameOverUI/VBoxContainer/BtnMenu
@onready var p1_score_label = $HUD/P1Score
@onready var p2_score_label = $HUD/P2Score
@onready var pause_btn = $HUD/PauseButton
@onready var hud_menu_btn = $HUD/MenuButton

var asteroid_scene: PackedScene

func _ready():
	# Configure tiled display
	tiled_display.texture = game_viewport.get_texture()
	asteroid_scene = load("res://asteroid.tscn")
	seed(Time.get_ticks_msec())
	GameState.reset_win_state()
	GameState.score_changed.connect(_on_score_changed)
	pause_btn.pressed.connect(_on_pause_pressed)
	hud_menu_btn.pressed.connect(_on_menu_pressed)
	_on_score_changed(GameState.p1_wins, GameState.p2_wins)
	
	# Connect Game Over
	GameState.game_over.connect(_on_game_over)
	btn_restart.pressed.connect(_on_restart_pressed)
	btn_menu.pressed.connect(_on_menu_pressed)
	
	# Handle Player Initialization based on Mode
	if GameState.current_mode == GameState.GameMode.AI:
		call_deferred("_setup_ai")

	elif GameState.current_mode == GameState.GameMode.SCREENSAVER:
		call_deferred("_setup_screensaver")

	elif GameState.current_mode == GameState.GameMode.ONLINE:
		call_deferred("_setup_online")

	if GameState.current_mode != GameState.GameMode.ONLINE or multiplayer.get_unique_id() == 1:
		spawn_initial_asteroids()

func _setup_ai():
	print("Main: Initializing AI Challenge...")
	var ai_controller_script = load("res://AIController.gd")
	var ai = Node2D.new()
	ai.set_script(ai_controller_script)
	ai.name = "AIController2"
	ai.target_player_name = "Player2"
	
	# Map difficulty to brain
	var difficulty_map = {1: "1k", 2: "10k", 3: "100k"}
	ai.brain_name = difficulty_map.get(GameState.selected_ai_difficulty, "1k")
	
	add_child(ai)
	
	# Ensure Player 2 knows it's AI
	var p2 = massives_container.get_node_or_null("Player2")
	if p2:
		p2.set_meta("is_ai", true)
		print("Main: Player 2 assigned AI control (", ai.brain_name, ")")

func _setup_screensaver():
	print("Main: Initializing Screensaver Mode (", GameState.p1_brain_name, " vs ", GameState.p2_brain_name, ")...")
	var ai_controller_script = load("res://AIController.gd")
	
	# P1 AI
	var ai1 = Node2D.new()
	ai1.set_script(ai_controller_script)
	ai1.name = "AIController1"
	ai1.target_player_name = "Player"
	ai1.brain_name = GameState.p1_brain_name
	add_child(ai1)
	
	# P2 AI
	var ai2 = Node2D.new()
	ai2.set_script(ai_controller_script)
	ai2.name = "AIController2"
	ai2.target_player_name = "Player2"
	ai2.brain_name = GameState.p2_brain_name
	add_child(ai2)
	
	# Mark ships as AI
	var p1 = massives_container.get_node_or_null("Player")
	var p2 = massives_container.get_node_or_null("Player2")
	if p1: p1.set_meta("is_ai", true)
	if p2: p2.set_meta("is_ai", true)

func _setup_online():
	print("Main: Initializing Online Mode...")
	var p1 = massives_container.get_node_or_null("Player")
	var p2 = massives_container.get_node_or_null("Player2")
	if p1 and p2:
		var my_id = multiplayer.get_unique_id()
		var peers = multiplayer.get_peers()
		var other_id = peers[0] if peers.size() > 0 else 2
		
		var host_id = 1
		# The client is not guaranteed to be ID 2 in WebRTC Mesh. They get a huge random int.
		var client_id = my_id if my_id != 1 else other_id

		# Peer 1 (Host) owns Player 1, Peer X (Client) owns Player 2
		p1.set_multiplayer_authority(host_id)
		p2.set_multiplayer_authority(client_id)
		
		# Set is_local based on actual mesh IDs
		p1.is_local = (my_id == host_id)
		p2.is_local = (my_id == client_id)
		
		print("Main: Multiplayer authority assigned. Local ID: ", multiplayer.get_unique_id())
		_show_role_indicator()

	# Set up MultiplayerSpawner to sync dynamic objects (asteroids, lasers)
	var spawner = MultiplayerSpawner.new()
	spawner.spawn_path = massives_container.get_path()
	# Add the scenes that can be spawned
	spawner.add_spawnable_scene("res://asteroid.tscn")
	spawner.add_spawnable_scene("res://laser.tscn")
	add_child(spawner)

func _show_role_indicator():
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	
	var label = Label.new()
	var my_id = multiplayer.get_unique_id()
	label.text = "YOU ARE PLAYER " + str(my_id)
	
	# Color based on player
	var p_color = Color(0, 0.5, 1) if my_id == 1 else Color(1, 0.2, 0)
	label.add_theme_color_override("font_color", p_color)
	label.add_theme_font_size_override("font_size", 48)
	
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(label)
	
	# Fade out animation using Tween
	var tween = get_tree().create_tween()
	# Wait 0.4s then fade over 0.6s to reach 1.0s total
	tween.tween_interval(0.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.finished.connect(canvas.queue_free)

func spawn_initial_asteroids():
	var num_asteroids = randi_range(5, 15)
	var total_target_mass = PhysicsConfig.ASTEROID_INITIAL_WEIGHT_TOTAL
	
	var player1 = massives_container.get_node_or_null("Player")
	var player2 = massives_container.get_node_or_null("Player2")
	if player1 and player2:
		var midpoint = (player1.position + player2.position) / 2.0
		var intervening_mass = 400.0
		spawn_asteroid(intervening_mass, midpoint)
		total_target_mass -= intervening_mass
	
	var masses = []
	var total_random_weight = 0.0
	for i in range(num_asteroids):
		var weight = randf_range(0.1, 1.0)
		masses.append(weight)
		total_random_weight += weight
	
	for i in range(num_asteroids):
		var asteroid_mass = (masses[i] / total_random_weight) * total_target_mass
		spawn_asteroid(asteroid_mass)



func spawn_asteroid(m_val, forced_pos = null):
	var max_attempts = 150
	var success = false
	var spawn_pos = Vector2.ZERO
	var radius = pow(m_val, 1.0/3.0) * 4.0
	
	if forced_pos != null:
		spawn_pos = forced_pos
		success = true
	else:
		for attempt in range(max_attempts):
			spawn_pos = Vector2(randf_range(PhysicsConfig.WORLD_SPAWN_MARGIN, PhysicsConfig.WORLD_SIZE - PhysicsConfig.WORLD_SPAWN_MARGIN), randf_range(PhysicsConfig.WORLD_SPAWN_MARGIN, PhysicsConfig.WORLD_SIZE - PhysicsConfig.WORLD_SPAWN_MARGIN))
			if is_valid_pos(spawn_pos, radius):
				success = true
				break
	
	if success:
		var a = asteroid_scene.instantiate()
		a.m = m_val
		a.pos = spawn_pos
		var drift_speed = randf_range(1.0, 5.0)
		a.p = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * drift_speed * m_val
		massives_container.add_child(a)

func is_valid_pos(pos, radius):
	var buffer = 10.0
	for node in get_tree().get_nodes_in_group("massives"):
		if not node is Node2D: continue
		var other_m = node.m if "m" in node else PhysicsConfig.PLAYER_DEFAULT_MASS
		var other_radius = pow(other_m, 1.0/3.0) * 4.0
		if pos.distance_to(node.position) < (radius + other_radius + buffer):
			return false
	return true

func _on_score_changed(p1, p2):
	p1_score_label.text = "P1: %d" % p1
	p2_score_label.text = "P2: %d" % p2

func _on_pause_pressed():
	get_tree().paused = !get_tree().paused
	pause_btn.text = "RESUME" if get_tree().paused else "PAUSE"
	hud_menu_btn.visible = get_tree().paused

func _on_game_over(winner_name, is_match_over):
	if is_match_over:
		winner_label.text = "MATCH WINNER: " + winner_name
		btn_restart.text = "NEW MATCH"
		btn_restart.visible = true
		btn_menu.visible = true
		game_over_ui.visible = true
	else:
		winner_label.text = winner_name + " WINS THE ROUND!"
		btn_restart.visible = false
		btn_menu.visible = false
		game_over_ui.visible = true
		
		# Auto-restart after 3 seconds
		await get_tree().create_timer(3.0).timeout
		if game_over_ui.visible: # Ensure we didn't exit to menu
			_on_restart_pressed()

func _on_restart_pressed():
	get_tree().paused = false
	# Check for match completion
	if GameState.p1_wins >= GameState.WINS_TO_WIN_MATCH or GameState.p2_wins >= GameState.WINS_TO_WIN_MATCH:
		if GameState.current_mode == GameState.GameMode.SCREENSAVER:
			GameState.randomize_screensaver_brains()
		GameState.reset_match_state()
	else:
		GameState.reset_win_state() # Just reset current round winner
	get_tree().reload_current_scene()

func _on_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://MainMenu.tscn")
