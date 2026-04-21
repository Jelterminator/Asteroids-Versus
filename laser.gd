extends CharacterBody2D

var pos = Vector2(100, 100)
var p = Vector2(1, 0) # Direction unit vector
var type = "laser"

var C_SPEED = PhysicsConfig.LASER_SPEED 
var energy = PhysicsConfig.LASER_ENERGY_DEFAULT # High energy, but not "instant disappearance" high
var shooter = null # Who fired this laser

var trail_pos = []
var trail_time = []
var TRAIL_LIFETIME = PhysicsConfig.LASER_TRAIL_LIFETIME

@onready var gravity = get_node("../GravityManager")

func _ready():
	add_to_group("lasers")
	self.position = pos
	self.scale = Vector2(1.0, 1.0)
	z_as_relative = false
	

	# Layer 4 (Laser), Mask 2 & 4 (Asteroid & Player)
	collision_layer = 8 
	collision_mask = 2 | 4 
	
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 1.5 
	col.shape = shape
	add_child(col)

func get_energy_color() -> Color:
	# Calculate gravitational redshift/blueshift based on local metric
	var g_tt = gravity.sample_g_tt(pos)
	var shift_ratio = 1.0 / sqrt(max(0.1, -g_tt)) 
	
	# shift_ratio is exactly 1.0 in empty space.
	var deviation = (shift_ratio - 1.0)
	var hue = clamp(0.33 + deviation, 0.0, 0.66) 
	
	var col = Color.from_hsv(hue, 1.0, 1.0)
	return col.lerp(Color.WHITE, 0.10) # Always maintain 10% pure white for brightness

func _physics_process(delta):
	if GameState.current_mode == GameState.GameMode.ONLINE and not is_multiplayer_authority():
		self.position = pos
		# Update trail for remote visual smoothness
		trail_pos.append(pos)
		trail_time.append(Time.get_ticks_msec() / 1000.0)
		var current_time = Time.get_ticks_msec() / 1000.0
		while trail_time.size() > 0 and current_time - trail_time[0] > TRAIL_LIFETIME:
			trail_pos.pop_front()
			trail_time.pop_front()
		queue_redraw()
		return

	# 1. Gravity Deflection
	var eps = PhysicsConfig.LASER_GRAVITY_EPS
	var g_l = gravity.sample_g_tt(pos + Vector2(-eps, 0))
	var g_r = gravity.sample_g_tt(pos + Vector2(eps, 0))
	var g_u = gravity.sample_g_tt(pos + Vector2(0, -eps))
	var g_d = gravity.sample_g_tt(pos + Vector2(0, eps))
	var grad = Vector2((g_r - g_l)/(2.0*eps), (g_d - g_u)/(2.0*eps))
	
	# Update direction p based on local potential gradient
	p += grad * PhysicsConfig.LASER_GRAVITY_DEFLECTION_SCALE * delta 
	p = p.normalized()

	# 2. Local C
	var g_tt = gravity.sample_g_tt(pos)
	var local_c = C_SPEED * sqrt(max(0.1, -g_tt))
	var velocity = p * local_c
	
	# 2. Movement & Collision (Ghostly)
	# Using 'test_only=true' to prevent blocking, but detecting hits on BOTH Players and Asteroids
	var collision = move_and_collide(velocity * delta, true)
	if collision:
		var hit_obj = collision.get_collider()
		if hit_obj.has_method("hit_by_laser"):
			hit_obj.hit_by_laser(energy, shooter)
		queue_free()
		return

	# Update logical position
	pos += velocity * delta
	
	# Robust Wrap
	pos.x = fposmod(pos.x, PhysicsConfig.WORLD_SIZE)
	pos.y = fposmod(pos.y, PhysicsConfig.WORLD_SIZE)
	
	self.position = pos
	z_index = int(pos.x + pos.y)
	
	# Update trail
	trail_pos.append(pos)
	trail_time.append(Time.get_ticks_msec() / 1000.0)
	
	var current_time = Time.get_ticks_msec() / 1000.0
	while trail_time.size() > 0 and current_time - trail_time[0] > TRAIL_LIFETIME:
		trail_pos.pop_front()
		trail_time.pop_front()
		
	queue_redraw()

func _draw():
	# Edge-Triggered Ghosting: Only draw ghosts if we are actually crossing a boundary.
	# Lasers are small, so drawing ghosts is cheap and ensures they don't pop out at edges.
	var margin = 10.0
	var draw_offsets = [Vector2.ZERO]
	
	if pos.x < margin: draw_offsets.append(Vector2(PhysicsConfig.WORLD_SIZE, 0))
	elif pos.x > PhysicsConfig.WORLD_SIZE - margin: draw_offsets.append(Vector2(-PhysicsConfig.WORLD_SIZE, 0))
	
	if pos.y < margin: draw_offsets.append(Vector2(0, PhysicsConfig.WORLD_SIZE))
	elif pos.y > PhysicsConfig.WORLD_SIZE - margin: draw_offsets.append(Vector2(0, -PhysicsConfig.WORLD_SIZE))
	
	# Handles corners
	if pos.x < margin and pos.y < margin: draw_offsets.append(Vector2(PhysicsConfig.WORLD_SIZE, PhysicsConfig.WORLD_SIZE))
	if pos.x < margin and pos.y > PhysicsConfig.WORLD_SIZE - margin: draw_offsets.append(Vector2(PhysicsConfig.WORLD_SIZE, -PhysicsConfig.WORLD_SIZE))
	if pos.x > PhysicsConfig.WORLD_SIZE - margin and pos.y < margin: draw_offsets.append(Vector2(-PhysicsConfig.WORLD_SIZE, PhysicsConfig.WORLD_SIZE))
	if pos.x > PhysicsConfig.WORLD_SIZE - margin and pos.y > PhysicsConfig.WORLD_SIZE - margin: draw_offsets.append(Vector2(-PhysicsConfig.WORLD_SIZE,-PhysicsConfig.WORLD_SIZE))

	for offset in draw_offsets:
		# Draw Trail Segments
		for i in range(1, trail_pos.size()):
			var p1 = trail_pos[i-1]
			var p2 = trail_pos[i]
			
			# Skip segments that wrap around the screen
			if p1.distance_to(p2) > PhysicsConfig.WORLD_HALF_SIZE:
				continue
				
			var alpha = float(i) / trail_pos.size()
			var color = get_energy_color()
			color.a = alpha * 0.8 # More opaque for better visibility
			
			var width = alpha * 6.0 # Thinner trail
			draw_line(p1 - pos + offset, p2 - pos + offset, color, width)

		# Draw the laser head (Isometric billboarding to remain circular)
		draw_set_transform(offset, -0.785398, Vector2(1.0, 2.0))
		draw_line(Vector2(-4, 0), Vector2(4, 0), Color.WHITE, 2.0)
		draw_line(Vector2(0, -4), Vector2(0, 4), Color.WHITE, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


