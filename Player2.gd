extends CharacterBody2D

signal collided(collider)

@export var pos = Vector2(125, 125)
@export var m = PhysicsConfig.PLAYER_DEFAULT_MASS
@export var p = Vector2(0, 0)
@export var orientation = Vector2(1, 1)

var F_jet = PhysicsConfig.PLAYER_THRUST
var v_rot = PhysicsConfig.PLAYER_ROT_SPEED
var p_laser = PhysicsConfig.PLAYER_LASER_RECOIL_MOMENTUM
var laser_cooldown = 0.0
var spawn_timer = PhysicsConfig.PLAYER_SPAWN_TIMER
var type = "player"
var is_local = true
var p_name = "Player 2"
var is_exploding = false

# Inputs for AI/Network
var ai_thrust = false
var ai_rot_dir = 0.0
var ai_fire = false
var laser_scene = preload("res://laser.tscn")
@onready var gravity = get_node("../../GravityManager")

# Shape
var ship_points = [
	Vector2(4, 2),   # Nose
	Vector2(0, 0),   # Wingtip L
	Vector2(1, 2),   # Inset 
	Vector2(0, 4),   # Wingtip R
]
var ship_center = Vector2(1.5, 2) 

func _ready():
	add_to_group("massives")
	self.position = pos
	self.scale = Vector2(1.0, 1.0)
	
	z_as_relative = false
	collision_layer = 4
	collision_mask = 2 | 4
	
	# Collision
	var col = CollisionPolygon2D.new()
	var transformed_points = []
	for p_raw in ship_points:
		var p_rel = (p_raw - ship_center) * 4.0
		transformed_points.append(p_rel)
	col.polygon = PackedVector2Array(transformed_points)
	add_child(col)
	
	# Thruster
	var p_emit = CPUParticles2D.new()
	p_emit.name = "ThrusterParticles"
	p_emit.amount = 80
	p_emit.lifetime = 0.5
	p_emit.spread = 20.0
	p_emit.gravity = Vector2.ZERO
	p_emit.initial_velocity_min = 80.0
	p_emit.scale_amount_min = 2.0
	p_emit.scale_amount_max = 2.0
	
	var g = Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.add_point(0.0, Color(1, 1, 1, 1))   # White
	g.add_point(0.1, Color(1, 1, 0, 1))   # Yellow
	g.add_point(0.4, Color(1, 0.5, 0, 1)) # Orange
	g.add_point(0.8, Color(1, 0, 0, 0))   # Fade out
	p_emit.color_ramp = g
	
	p_emit.emitting = false
	p_emit.direction = Vector2(-1, 0)
	p_emit.position = (Vector2(1, 2) - ship_center) * 4.0
	add_child(p_emit)

func _physics_process(delta):
	var p_mc = p.length() / (m * PhysicsConfig.C)
	var gamma = sqrt(1.0 + p_mc * p_mc)
	
	var g_tt = gravity.sample_g_tt(pos)
	var grav_dilation = sqrt(max(0.1, -g_tt))
	var delta_proper = delta * grav_dilation / gamma
	
	# 1. Controls
	var rot_dir = 0.0
	var thrusting = false
	var firing = false
	
	
	
	if is_local and not has_meta("is_ai"):
		rot_dir = float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		thrusting = Input.is_physical_key_pressed(KEY_UP)
		firing = Input.is_physical_key_pressed(KEY_DOWN)
	else:
		rot_dir = ai_rot_dir
		thrusting = ai_thrust
		firing = ai_fire

	orientation = orientation.rotated(v_rot * rot_dir * delta_proper)
	self.rotation = orientation.angle()
	
	if thrusting:
		p += F_jet * orientation * delta
		get_node("ThrusterParticles").emitting = true
	else:
		get_node("ThrusterParticles").emitting = false
	
	if spawn_timer > 0: spawn_timer -= delta_proper
	if laser_cooldown > 0: laser_cooldown -= delta_proper
	if firing and laser_cooldown <= 0 and spawn_timer <= 0:
		p -= orientation * p_laser # Recoil
		var l = laser_scene.instantiate()
		l.pos = pos + orientation * 20
		l.p = orientation
		l.energy = p_laser * l.C_SPEED
		l.shooter = self
		get_node("../..").add_child(l)
		laser_cooldown = PhysicsConfig.PLAYER_LASER_COOLDOWN

	# 2. Gravity
	var eps = PhysicsConfig.PLAYER_GRAVITY_EPS
	var g_l = gravity.sample_g_tt(pos + Vector2(-eps, 0))
	var g_r = gravity.sample_g_tt(pos + Vector2(eps, 0))
	var g_u = gravity.sample_g_tt(pos + Vector2(0, -eps))
	var g_d = gravity.sample_g_tt(pos + Vector2(0, eps))
	var accel = Vector2((g_r - g_l)/(2.0*eps), (g_d - g_u)/(2.0*eps))
	p += accel * PhysicsConfig.G_FORCE_SCALE * m * delta
	
	# 3. Movement
	var velocity = (p / m) / gamma * grav_dilation
	var collision = move_and_collide(velocity * delta)
	
	if collision:
		var c_obj = collision.get_collider()
		if "m" in c_obj and "p" in c_obj:
			var n = collision.get_normal()
			var v1 = p / m
			var v2 = c_obj.p / c_obj.m
			var rel_v = v1 - v2
			var v_along_n = rel_v.dot(n)
			
			# Only resolve if they are moving towards each other
			if v_along_n < 0:
				var j = -2.0 * v_along_n / (1.0/m + 1.0/c_obj.m)
				var impulse = j * n
				p += impulse
				c_obj.p -= impulse
				collided.emit(c_obj)
			
	pos = self.position
	
	pos.x = fposmod(pos.x, PhysicsConfig.WORLD_SIZE)
	pos.y = fposmod(pos.y, PhysicsConfig.WORLD_SIZE)
	
	self.position = pos
	z_index = int(pos.x + pos.y)
	
	if is_exploding:
		pass
		
	queue_redraw()

func _draw():
	var transformed_points = []
	for p_raw in ship_points:
		var p_rel = (p_raw - ship_center) * 4.0
		transformed_points.append(p_rel)
	
	# Edge-Triggered Ghosting: Only draw ghosts if we are actually crossing a boundary.
	# This eliminates "clones" in neighboring tiles while maintaining seamless wrapping.
	var margin = 32.0
	var draw_offsets = [Vector2.ZERO]
	
	if pos.x < margin: draw_offsets.append(Vector2(PhysicsConfig.WORLD_SIZE, 0))
	elif pos.x > PhysicsConfig.WORLD_SIZE - margin: draw_offsets.append(Vector2(-PhysicsConfig.WORLD_SIZE, 0))
	
	if pos.y < margin: draw_offsets.append(Vector2(0, PhysicsConfig.WORLD_SIZE))
	elif pos.y > PhysicsConfig.WORLD_SIZE - margin: draw_offsets.append(Vector2(0, -PhysicsConfig.WORLD_SIZE))
	
	# Handles corners
	if pos.x < margin and pos.y < margin: draw_offsets.append(Vector2(PhysicsConfig.WORLD_SIZE, PhysicsConfig.WORLD_SIZE))
	if pos.x < margin and pos.y > PhysicsConfig.WORLD_SIZE - margin: draw_offsets.append(Vector2(PhysicsConfig.WORLD_SIZE, -PhysicsConfig.WORLD_SIZE))
	if pos.x > PhysicsConfig.WORLD_SIZE - margin and pos.y < margin: draw_offsets.append(Vector2(-PhysicsConfig.WORLD_SIZE, PhysicsConfig.WORLD_SIZE))
	if pos.x > PhysicsConfig.WORLD_SIZE - margin and pos.y > PhysicsConfig.WORLD_SIZE - margin: draw_offsets.append(Vector2(-PhysicsConfig.WORLD_SIZE, -PhysicsConfig.WORLD_SIZE))

	# Calculate Lorentz contraction
	var p_mc = p.length() / (m * PhysicsConfig.C)
	var gamma = sqrt(1.0 + p_mc * p_mc)
	var contraction = 1.0 / gamma
	
	var p_local_angle = p.rotated(-self.rotation).angle()
	var rot_forward = Transform2D().rotated(p_local_angle)
	var rot_back = Transform2D().rotated(-p_local_angle)
	var scale_tr = Transform2D().scaled(Vector2(contraction, 1.0))
	var contract_tr = rot_forward * scale_tr * rot_back

	for offset in draw_offsets:
		var offset_tr = Transform2D(0, offset.rotated(-self.rotation))
		draw_set_transform_matrix(offset_tr * contract_tr)
		draw_colored_polygon(PackedVector2Array(transformed_points), Color(0.88, 0.88, 0.88)) # Off-White
		
		# Status Indicator (Red Pixel)
		var current_timer = spawn_timer if spawn_timer > 0 else laser_cooldown
		if current_timer <= 0:
			draw_circle(Vector2.ZERO, 2, Color.RED)
		elif current_timer <= 1.2:
			if (int(Time.get_ticks_msec() / 100) % 2) == 0:
				draw_circle(Vector2.ZERO, 2, Color.RED)

func spawn_explosion():
	var parent_node = get_parent()
	if not parent_node: return
	
	var expl = CPUParticles2D.new()
	expl.position = pos
	expl.amount = 60
	expl.explosiveness = 1.0
	expl.one_shot = true
	expl.lifetime = 1.0
	expl.spread = 180.0
	expl.gravity = Vector2.ZERO
	expl.initial_velocity_min = 60.0
	expl.initial_velocity_max = 150.0
	expl.scale_amount_min = 2.0
	expl.scale_amount_max = 2.0
	
	var g = Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.add_point(0.0, Color(1, 1, 1, 1))
	g.add_point(0.3, Color(1, 0.2, 0, 1)) # Red for P2
	g.add_point(0.8, Color(1, 0, 0, 0))
	expl.color_ramp = g
	
	parent_node.add_child(expl)
	get_tree().create_timer(expl.lifetime).timeout.connect(expl.queue_free)
	expl.emitting = true

func hit_by_laser(_energy, _shooter = null):
	if is_exploding: return
	is_exploding = true
	GameState.notify_death(p_name)
	spawn_explosion()
	
	if not has_meta("is_ai") and GameState.current_mode != GameState.GameMode.AI:
		queue_free()

func reset_player(new_pos: Vector2):
	pos = new_pos
	self.position = pos
	p = Vector2.ZERO
	spawn_timer = PhysicsConfig.PLAYER_SPAWN_TIMER
	laser_cooldown = 0.0
	is_exploding = false
	visible = true
