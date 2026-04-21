extends Control

@onready var main_buttons = $VBoxContainer
@onready var difficulty_menu = $DifficultyMenu

var button_texts = {}

func _ready():
	# Configure ALL buttons in the menu
	var all_buttons = []
	all_buttons.append_array(main_buttons.get_children())
	all_buttons.append_array(difficulty_menu.get_children())
	
	for btn in all_buttons:
		if btn is Button:
			button_texts[btn] = btn.text
			btn.text = "" # Fix double letters by clearing the node's text
			btn.flat = true
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	$VBoxContainer/BtnLocal.pressed.connect(_on_btn_local_pressed)
	$VBoxContainer/BtnOnline.pressed.connect(_on_btn_online_pressed)
	$VBoxContainer/BtnAI.pressed.connect(_on_btn_ai_pressed)
	$VBoxContainer/BtnScreensaver.pressed.connect(_on_btn_screensaver_pressed)
	
	$DifficultyMenu/BtnEasy.pressed.connect(func(): _start_ai_game(1))
	$DifficultyMenu/BtnNormal.pressed.connect(func(): _start_ai_game(2))
	$DifficultyMenu/BtnHard.pressed.connect(func(): _start_ai_game(3))
	$DifficultyMenu/BtnBack.pressed.connect(_on_btn_back_pressed)

func _on_btn_local_pressed():
	GameState.start_game(GameState.GameMode.LOCAL)

func _on_btn_online_pressed():
	get_tree().change_scene_to_file("res://multiplayer/Lobby.tscn")

func _on_btn_ai_pressed():
	main_buttons.visible = false
	difficulty_menu.visible = true

func _on_btn_screensaver_pressed():
	GameState.randomize_screensaver_brains()
	GameState.start_game(GameState.GameMode.SCREENSAVER)

func _on_btn_back_pressed():
	main_buttons.visible = true
	difficulty_menu.visible = false

func _start_ai_game(difficulty: int):
	GameState.start_game(GameState.GameMode.AI, difficulty)
