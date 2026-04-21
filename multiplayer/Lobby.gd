extends Control

var client := preload("res://multiplayer/multiplayer_client.gd").new()
var joined := false

@onready var status_label = %StatusLabel
@onready var btn_cancel = %BtnCancel
@onready var name_input = %NameInput
@onready var lb_col_1 = %LBCol1
@onready var lb_col_2 = %LBCol2
@onready var btn_join = %BtnJoin

# --- API CONFIG ---
var signaling_url = "wss://asteroids-versus.onrender.com" # "ws://localhost:8081"

# --- UI NODES ---
var http_fetch: HTTPRequest

func _ready():
	_load_local_name()
	_prefill_leaderboard()
	
	btn_cancel.pressed.connect(_on_cancel_pressed)
	btn_join.pressed.connect(_on_join_pressed)
	
	# Set up HTTP for Supabase
	http_fetch = HTTPRequest.new()
	add_child(http_fetch)
	http_fetch.request_completed.connect(_on_leaderboard_fetched)
	
	# Initial fetch
	_fetch_leaderboard()
	
	# Set up MultiplayerClient hooks
	add_child(client)
	client.connected.connect(_on_connected)
	client.lobby_joined.connect(_on_lobby_joined)
	client.lobby_sealed.connect(_on_lobby_sealed)
	client.peer_connected.connect(_on_peer_connected)
	client.peer_disconnected.connect(_on_peer_disconnected)
	client.disconnected.connect(_on_disconnected)

func _prefill_leaderboard():
	for col in [lb_col_1, lb_col_2]:
		for child in col.get_children():
			child.queue_free()
	
	for i in range(10):
		var label = Label.new()
		label.text = "%d. ---" % (i + 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		
		if i < 5:
			lb_col_1.add_child(label)
		else:
			lb_col_2.add_child(label)

func _load_local_name():
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	if err == OK:
		GameState.player_name = config.get_value("Player", "name", "Pilot")
		name_input.text = GameState.player_name

func _save_local_name(new_name):
	var config = ConfigFile.new()
	config.set_value("Player", "name", new_name)
	config.save("user://settings.cfg")
	GameState.player_name = new_name

func _on_join_pressed():
	if name_input.text.strip_edges() == "":
		status_label.text = "PLEASE ENTER A NAME"
		return
	
	_save_local_name(name_input.text)
	name_input.editable = false
	btn_join.disabled = true
	
	_connect_to_signaling()

func _connect_to_signaling():
	status_label.text = "CONNECTING..."
	# Request implicit 1v1 matchmaking utilizing empty lobby "" and mesh network true
	client.start(signaling_url, "", true)

func _on_connected(id: int, use_mesh: bool):
	pass

func _on_lobby_joined(lobby: String):
	status_label.text = "SEARCHING FOR MATCH..."

func _on_lobby_sealed():
	pass

func _on_peer_connected(id: int):
	status_label.text = "PEER CONNECTED! STARTING GAME..."
	
	# Host forces a seal immediately to lock matchmaking lobby size at 2
	if multiplayer.get_unique_id() == 1:
		client.seal_lobby()
		
	await get_tree().create_timer(1.0).timeout
	GameState.start_game(GameState.GameMode.ONLINE)

func _on_peer_disconnected(id: int):
	status_label.text = "PEER DISCONNECTED"
	multiplayer.multiplayer_peer = null
	btn_join.disabled = false
	name_input.editable = true
	client.stop()

func _on_disconnected():
	status_label.text = "SIGNALING CONNECTION CLOSED"
	multiplayer.multiplayer_peer = null
	btn_join.disabled = false
	name_input.editable = true

func _on_cancel_pressed():
	client.stop()
	get_tree().change_scene_to_file("res://MainMenu.tscn")

# --- SUPABASE LOGIC ---
func _fetch_leaderboard():
	var url = GameState.supabase_url + "/rest/v1/high_scores?select=name,streak&order=streak.desc&limit=10"
	var headers = [
		"apikey: " + GameState.supabase_key,
		"Authorization: Bearer " + GameState.supabase_key
	]
	http_fetch.request(url, headers, HTTPClient.METHOD_GET)

func _on_leaderboard_fetched(_result, response_code, _headers, body):
	if response_code != 200:
		print("Supabase: Fetch failed, code: ", response_code)
		return
	
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) == TYPE_ARRAY:
		for col in [lb_col_1, lb_col_2]:
			for child in col.get_children():
				child.queue_free()
		
		for i in range(10):
			var label = Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			
			if i < data.size():
				var entry = data[i]
				label.text = "%d. %-12s STR:%d" % [i + 1, entry["name"].left(12), entry["streak"]]
				# Stylize top 3
				match i:
					0: label.add_theme_color_override("font_color", Color(1, 0.84, 0)) # Gold
					1: label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75)) # Silver
					2: label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.2)) # Bronze
					_: label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			else:
				label.text = "%d. ---" % (i + 1)
				label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			
			if i < 5:
				lb_col_1.add_child(label)
			else:
				lb_col_2.add_child(label)

# Note: _save_streak is now handled by GameState.gd singleton

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		client.stop()
