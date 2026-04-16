extends Control

@onready var main_menu = get_parent()
var btn_font: Font

func _ready():
	# Load the new Silkscreen pixel font
	btn_font = load("res://fonts/Silkscreen-Regular.ttf")
	if btn_font == null:
		printerr("MenuOverlay: Failed to load Silkscreen font!")
	
	# Make sure mouse events pass through to buttons
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta):
	queue_redraw()

func _draw():
	if not main_menu: return
	
	# Title
	var title_text = "ASTEROIDS VERSUS"
	var title_size = 64
	
	# Fallback font handling
	var draw_font = btn_font
	if not draw_font or not is_instance_valid(draw_font):
		# Try to grab the font from the control's theme or use standard fallback
		draw_font = get_theme_font("font")
	
	if draw_font and is_instance_valid(draw_font):
		draw_string(draw_font, Vector2(0, 100), title_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, title_size, Color.WHITE)
	else:
		# Final fallback: use internal engine default drawing if possible, or skip to avoid crash
		# In Godot 4, draw_string REQUIRES a font.
		pass
	
	# Draw Boxes around buttons
	var vbox_list = [main_menu.get_node_or_null("VBoxContainer"), main_menu.get_node_or_null("DifficultyMenu")]
	
	for vbox in vbox_list:
		if not vbox or not vbox.visible: continue
		
		for btn in vbox.get_children():
			if btn is Button:
				var rect = btn.get_global_rect()
				rect.position -= global_position
				
				var border_color = Color(0.88, 0.88, 0.88)
				if btn.is_hovered():
					border_color = Color(1, 1, 1)
					draw_rect(rect, Color(0.2, 0.2, 0.2), true)
				
				draw_rect(rect, border_color, false, 2.0)
				
				# Button Label
				var font_size = 16 if btn.name == "BtnBack" else 24
				var label = main_menu.button_texts.get(btn, "")
				var label_pos = rect.position + Vector2(20, rect.size.y / 2 + 8)
				
				if draw_font and is_instance_valid(draw_font):
					draw_string(draw_font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, border_color)
