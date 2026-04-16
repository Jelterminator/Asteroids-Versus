extends Node

enum GameMode { LOCAL, ONLINE, AI }
var current_mode: GameMode = GameMode.LOCAL
var selected_ai_difficulty: int = 1 

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
	game_over.emit(winner, is_match_over)

func reset_win_state():
	winner = ""

func reset_match_state():
	p1_wins = 0
	p2_wins = 0
	winner = ""
	score_changed.emit(p1_wins, p2_wins)
