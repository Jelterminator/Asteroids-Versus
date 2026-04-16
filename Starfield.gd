extends Node2D

var stars = []
var num_stars = 1000

func _ready():
	var view_size = get_viewport_rect().size
	
	# Generate Organic "Milky Way" Starfield
	# Uses a Gaussian-weighted distribution along a central diagonal band
	for i in range(num_stars):
		# Point along the diagonal axis
		var t = randf()
		var center_x = t * view_size.x
		var center_y = t * view_size.y
		
		# Organic Gaussian-ish spread
		# We use randfn() for natural clusters
		var sx = posmod(center_x + randfn(0, view_size.x * 0.15), view_size.x)
		var sy = posmod(center_y + randfn(0, view_size.y * 0.15), view_size.y)
		
		var brightness = randf()
		# Grey (#707070) or Dark Grey (#404040)
		var color = Color(0.44, 0.44, 0.44) if brightness > 0.6 else Color(0.25, 0.25, 0.25)
		
		stars.append({"pos": Vector2(sx, sy), "color": color})
	
	queue_redraw()

func _draw():
	for star in stars:
		# Draw single pixel
		draw_rect(Rect2(star.pos.x, star.pos.y, 1, 1), star.color)
