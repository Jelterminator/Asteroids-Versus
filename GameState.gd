extends Node

enum GameMode { LOCAL, ONLINE, AI, SCREENSAVER }
var current_mode: GameMode = GameMode.LOCAL
var selected_ai_difficulty: int = 1 

var p1_brain_name: String = "1k"
var p2_brain_name: String = "1k"

var player_name: String = "Pilot"
var current_streak: int = 0

signal game_over(winner_name, is_match_over)
signal score_changed(p1_wins, p2_wins)

var p1_wins = 0
var p2_wins = 0
var winner = "" # Current round winner
const WINS_TO_WIN_MATCH = 3

func start_game(mode: GameMode, difficulty: int = 1):
	reset_match_state()
	current_mode = mode
	selected_ai_difficulty = difficulty
	get_tree().change_scene_to_file("res://main.tscn")

func notify_death(player_name: String):
	if winner != "": return # Already ended this round
	
	if player_name == "TIMEOUT_DRAW":
		winner = "TIMEOUT_DRAW"
	else:
		winner = "Player 2" if player_name == "Player 1" else "Player 1"
		
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
		else:
			current_streak = 0
			print("GameState: Win streak reset")
			
	game_over.emit(winner, is_match_over)

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
