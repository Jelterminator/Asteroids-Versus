extends Node

enum GameMode { LOCAL, ONLINE, AI, SCREENSAVER }
var current_mode: GameMode = GameMode.LOCAL
var selected_ai_difficulty: int = 1 

var p1_brain_name: String = "1k"
var p2_brain_name: String = "1k"

var player_name: String = "Pilot"
var current_streak: int = 0

# --- API CONFIG ---
var supabase_url = "https://gonistzmzzmtzrcdqpud.supabase.co"
var supabase_key = "sb_publishable_WYhmYscnjsP9zgl6js_wJg_RGkzudbV"

signal game_over(winner_name, is_match_over)
signal score_changed(p1_wins, p2_wins)
signal streak_updated(new_streak)

var http_save: HTTPRequest

var p1_wins = 0
var p2_wins = 0
var winner = "" # Current round winner
const WINS_TO_WIN_MATCH = 3

func _ready():
	load_persistence()
	
	http_save = HTTPRequest.new()
	add_child(http_save)

func start_game(mode: GameMode, difficulty: int = 1):
	reset_match_state()
	current_mode = mode
	selected_ai_difficulty = difficulty
	get_tree().change_scene_to_file("res://main.tscn")

@rpc("any_peer", "call_local", "reliable")
func notify_death(p_killed_name: String):
	if winner != "": return # Already ended this round
	
	if p_killed_name == "TIMEOUT_DRAW":
		winner = "TIMEOUT_DRAW"
	else:
		winner = "Player 2" if p_killed_name == "Player 1" else "Player 1"
		
		if winner == "Player 1":
			p1_wins += 1
		elif winner == "Player 2":
			p2_wins += 1
		
	score_changed.emit(p1_wins, p2_wins)
	
	var is_match_over = (p1_wins >= WINS_TO_WIN_MATCH or p2_wins >= WINS_TO_WIN_MATCH)
	
	if is_match_over and current_mode == GameMode.ONLINE:
		var my_id = multiplayer.get_unique_id()
		var i_won = (winner == "Player 1" and my_id == 1) or (winner == "Player 2" and my_id == 2)
		if i_won:
			current_streak += 1
			print("GameState: Win streak increased to ", current_streak)
			_save_streak(player_name, current_streak) # Immediate upload
		else:
			current_streak = 0
			print("GameState: Win streak reset")
		
		save_persistence()
		streak_updated.emit(current_streak)
		
		# SEVER CONNECTION: Per requirement, online matches disconnect immediately after finishing
		# We wait a tiny bit to ensure signals have finished processing on all menus
		call_deferred("_sever_online_connection")
			
	game_over.emit(winner, is_match_over)

func _sever_online_connection():
	if multiplayer.multiplayer_peer != null:
		print("GameState: Severing online connection after match completion.")
		multiplayer.multiplayer_peer = null

func reset_win_state():
	winner = ""

func reset_match_state():
	p1_wins = 0
	p2_wins = 0
	winner = ""
	score_changed.emit(p1_wins, p2_wins)

func randomize_screensaver_brains():
	var brains = []
	var dir = DirAccess.open("res://models/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.begins_with("brain_") and file_name.ends_with(".json"):
				var b_name = file_name.trim_prefix("brain_").trim_suffix(".json")
				brains.append(b_name)
			file_name = dir.get_next()
	
	if brains.size() > 0:
		p1_brain_name = brains[randi() % brains.size()]
		p2_brain_name = brains[randi() % brains.size()]
		print("GameState: Screensaver brains randomized: ", p1_brain_name, " vs ", p2_brain_name)
	else:
		p1_brain_name = "1k"
		p2_brain_name = "1k"
		print("GameState: No brains found in models/, defaulting to 1k")

func save_persistence():
	var config = ConfigFile.new()
	# Load existing to not overwrite other settings (like name)
	config.load("user://settings.cfg")
	config.set_value("Player", "streak", current_streak)
	config.save("user://settings.cfg")
	print("GameState: Persistence saved (streak=", current_streak, ")")

func load_persistence():
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	if err == OK:
		current_streak = config.get_value("Player", "streak", 0)
		print("GameState: Persistence loaded (streak=", current_streak, ")")

func _save_streak(p_name, streak):
	if streak <= 0: return # Only save positive streaks
	
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
	print("GameState: Uploading win streak to Supabase (", p_name, ": ", streak, ")")
