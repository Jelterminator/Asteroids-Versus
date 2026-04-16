extends Control

var ws := WebSocketPeer.new()
var rtc_mp := WebRTCMultiplayerPeer.new()
var sealed := false

@onready var status_label = $StatusLabel
@onready var btn_cancel = $BtnCancel

# Update with your deployed Fly.io/Heroku URL
var signaling_url = "ws://localhost:8080" 

func _ready():
	btn_cancel.pressed.connect(_on_cancel_pressed)
	var err = ws.connect_to_url(signaling_url)
	if err != OK:
		status_label.text = "CANNOT CONNECT TO SIGNALING SERVER"
	
	# Set up RTC Peer
	rtc_mp.peer_connected.connect(_on_peer_connected)
	rtc_mp.peer_disconnected.connect(_on_peer_disconnected)

func _process(_delta):
	ws.poll()
	var state = ws.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var packet = ws.get_packet()
			_handle_signaling_data(JSON.parse_string(packet.get_string_from_utf8()))
	elif state == WebSocketPeer.STATE_CLOSED:
		status_label.text = "SIGNALING CONNECTION CLOSED"

func _handle_signaling_data(data):
	if typeof(data) != TYPE_DICTIONARY: return
	
	match data.get("type"):
		"waiting":
			status_label.text = "SEARCHING FOR MATCH..."
		"match_found":
			status_label.text = "MATCH FOUND! HANDSHAKING..."
			_start_rtc(data["is_host"])
		"candidate":
			rtc_mp.get_peer(1).connection.add_ice_candidate(data["mid"], data["index"], data["sdp"])
		"offer":
			rtc_mp.get_peer(1).connection.set_remote_description("offer", data["sdp"])
		"answer":
			rtc_mp.get_peer(1).connection.set_remote_description("answer", data["sdp"])

func _start_rtc(is_host: bool):
	# In a 2-player setup, host is 1, peer is 2 (simplified for this demo)
	# But in RTC Multi, we usually use mesh. 
	# Here we create a connection to the other peer (id 1 in the signaling context, but let's use 1 as host)
	rtc_mp.create_mesh(1 if is_host else 2)
	multiplayer.multiplayer_peer = rtc_mp
	
	var rtc_peer: WebRTCPeerConnection = rtc_mp.get_peer(1 if not is_host else 2).connection
	rtc_peer.ice_candidate_created.connect(_on_ice_candidate.bind(1))
	rtc_peer.session_description_created.connect(_on_session_description.bind(1))
	
	if is_host:
		rtc_peer.create_offer()

func _on_ice_candidate(mid, index, sdp, _peer_id):
	ws.send_text(JSON.stringify({
		"type": "candidate",
		"mid": mid,
		"index": index,
		"sdp": sdp
	}))

func _on_session_description(type, sdp, _peer_id):
	rtc_mp.get_peer(1).connection.set_local_description(type, sdp)
	ws.send_text(JSON.stringify({
		"type": type,
		"sdp": sdp
	}))

func _on_peer_connected(id):
	status_label.text = "PEER CONNECTED! STARTING GAME..."
	GameState.start_game(GameState.GameMode.ONLINE)

func _on_peer_disconnected(id):
	status_label.text = "PEER DISCONNECTED"
	multiplayer.multiplayer_peer = null

func _on_cancel_pressed():
	ws.close()
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ws.close()
