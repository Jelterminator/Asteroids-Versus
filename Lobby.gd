extends Control

var ws := WebSocketPeer.new()
var rtc_mp := WebRTCMultiplayerPeer.new()
var joined := false

@onready var status_label = $StatusLabel
@onready var btn_cancel = $BtnCancel

# --- API CONFIG ---
var signaling_url = "wss://asteroids-versus.onrender.com" 
var supabase_url = "https://gonistzmzzmtzrcdqpud.supabase.co"
var supabase_key = "sb_publishable_WYhmYscnjsP9zgl6js_wJg_RGkzudbV"

# --- UI NODES (Created in code to keep .tscn simple) ---
var name_input: LineEdit
var leaderboard_container: VBoxContainer
var btn_join: Button
var http_fetch: HTTPRequest
var http_save: HTTPRequest

func _ready():
	_setup_ui()
	_load_local_name()
	
	btn_cancel.pressed.connect(_on_cancel_pressed)
	
	# Set up HTTP for Supabase
	http_fetch = HTTPRequest.new()
	add_child(http_fetch)
	http_fetch.request_completed.connect(_on_leaderboard_fetched)
	
	http_save = HTTPRequest.new()
	add_child(http_save)
	
	# Initial fetch
	_fetch_leaderboard()
	
	# Set up RTC Peer signals
	rtc_mp.peer_connected.connect(_on_peer_connected)
	rtc_mp.peer_disconnected.connect(_on_peer_disconnected)

func _setup_ui():
	# Name Input
	name_input = LineEdit.new()
	name_input.placeholder_text = "ENTER YOUR PILOT NAME..."
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	name_input.offset_top = 50
	name_input.custom_minimum_size = Vector2(250, 40)
	add_child(name_input)
	
	# Join Button
	btn_join = Button.new()
	btn_join.text = "JOIN MATCHMAKING"
	btn_join.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	btn_join.offset_top = 100
	btn_join.custom_minimum_size = Vector2(200, 40)
	btn_join.pressed.connect(_on_join_pressed)
	add_child(btn_join)
	
	# Leaderboard Title
	var lb_title = Label.new()
	lb_title.text = "🏆 TOP 10 PILOT STREAKS 🏆"
	lb_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lb_title.offset_bottom = -250
	lb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lb_title)
	
	# Leaderboard Container
	leaderboard_container = VBoxContainer.new()
	leaderboard_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	leaderboard_container.offset_bottom = -50
	leaderboard_container.custom_minimum_size = Vector2(400, 200)
	add_child(leaderboard_container)

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
	var err = ws.connect_to_url(signaling_url)
	if err != OK:
		status_label.text = "CANNOT CONNECT TO SIGNALING SERVER"
	else:
		status_label.text = "CONNECTING..."

func _process(_delta):
	ws.poll()
	var state = ws.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not joined:
			ws.send_text(JSON.stringify({
				"type": "join",
				"name": GameState.player_name
			}))
			joined = true
			status_label.text = "JOINING MATCHMAKING..."
			
		while ws.get_available_packet_count() > 0:
			var packet = ws.get_packet()
			_handle_signaling_data(JSON.parse_string(packet.get_string_from_utf8()))
	elif state == WebSocketPeer.STATE_CLOSED and joined:
		status_label.text = "SIGNALING CONNECTION CLOSED"

func _handle_signaling_data(data):
	if typeof(data) != TYPE_DICTIONARY: return
	
	match data.get("type"):
		"waiting":
			status_label.text = "SEARCHING FOR MATCH..."
		"match_found":
			status_label.text = "MATCH FOUND! HANDSHAKING..."
			_start_rtc(data["is_host"])
		"partner_disconnected":
			status_label.text = "PARTNER DISCONNECTED"
			multiplayer.multiplayer_peer = null
		"candidate":
			var my_peer_id = multiplayer.get_unique_id()
			var partner_id = 2 if my_peer_id == 1 else 1
			if rtc_mp.has_peer(partner_id):
				rtc_mp.get_peer(partner_id).connection.add_ice_candidate(data["mid"], data["index"], data["sdp"])
		"offer":
			var my_peer_id = multiplayer.get_unique_id()
			var partner_id = 2 if my_peer_id == 1 else 1
			if rtc_mp.has_peer(partner_id):
				rtc_mp.get_peer(partner_id).connection.set_remote_description("offer", data["sdp"])
		"answer":
			var my_peer_id = multiplayer.get_unique_id()
			var partner_id = 2 if my_peer_id == 1 else 1
			if rtc_mp.has_peer(partner_id):
				rtc_mp.get_peer(partner_id).connection.set_remote_description("answer", data["sdp"])

func _start_rtc(is_host: bool):
	rtc_mp.create_mesh(1 if is_host else 2)
	multiplayer.multiplayer_peer = rtc_mp
	
	var partner_id = 2 if is_host else 1
	var rtc_peer: WebRTCPeerConnection = rtc_mp.get_peer(partner_id).connection
	rtc_peer.ice_candidate_created.connect(_on_ice_candidate)
	rtc_peer.session_description_created.connect(_on_session_description)
	
	if is_host:
		rtc_peer.create_offer()

func _on_ice_candidate(mid, index, sdp):
	ws.send_text(JSON.stringify({
		"type": "candidate",
		"mid": mid,
		"index": index,
		"sdp": sdp
	}))

func _on_session_description(type, sdp):
	var my_peer_id = multiplayer.get_unique_id()
	var partner_id = 2 if my_peer_id == 1 else 1
	rtc_mp.get_peer(partner_id).connection.set_local_description(type, sdp)
	
	ws.send_text(JSON.stringify({
		"type": type,
		"sdp": sdp
	}))

func _on_peer_connected(id):
	status_label.text = "PEER CONNECTED! STARTING GAME..."
	# Before starting, if we have a streak, report it (in case we didn't before)
	if GameState.current_streak > 0:
		_save_streak(GameState.player_name, GameState.current_streak)
		
	await get_tree().create_timer(1.0).timeout
	GameState.start_game(GameState.GameMode.ONLINE)

func _on_peer_disconnected(id):
	status_label.text = "PEER DISCONNECTED"
	multiplayer.multiplayer_peer = null

func _on_cancel_pressed():
	ws.close()
	get_tree().change_scene_to_file("res://MainMenu.tscn")

# --- SUPABASE LOGIC ---
func _fetch_leaderboard():
	var url = supabase_url + "/rest/v1/high_scores?select=name,streak&order=streak.desc&limit=10"
	var headers = [
		"apikey: " + supabase_key,
		"Authorization: Bearer " + supabase_key
	]
	http_fetch.request(url, headers, HTTPClient.METHOD_GET)

func _on_leaderboard_fetched(_result, response_code, _headers, body):
	if response_code != 200:
		print("Supabase: Fetch failed, code: ", response_code)
		return
	
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) == TYPE_ARRAY:
		# Clear existing
		for child in leaderboard_container.get_children():
			child.queue_free()
		
		for i in range(data.size()):
			var entry = data[i]
			var label = Label.new()
			label.text = "%d. %s — Streak: %d" % [i + 1, entry["name"], entry["streak"]]
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			leaderboard_container.add_child(label)

func _save_streak(p_name, streak):
	var url = supabase_url + "/rest/v1/high_scores"
	var headers = [
		"apikey: " + supabase_key,
		"Authorization: Bearer " + supabase_key,
		"Content-Type: application/json",
		"Prefer: return=minimal"
	]
	var body = JSON.stringify({
		"name": p_name,
		"streak": streak
	})
	http_save.request(url, headers, HTTPClient.METHOD_POST, body)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ws.close()
