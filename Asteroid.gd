extends CharacterBody2D

@export var pos = Vector2(250, 250)
@export var m = PhysicsConfig.ASTEROID_MASS_DEFAULT 
@export var p = Vector2(0, 0)

var type = "asteroid"
var invinciframe = 0
var is_exploding = false
var polygon_points = PackedVector2Array()

@onready var gravity = get_node("../../GravityManager")

# Using load() to avoid circular preload issues with the scene using this script
var _asteroid_scene = load("res://asteroid.tscn")

func _ready():
	add_to_group("massives")
	add_to_group("asteroids")
	self.position = pos
	self.scale = Vector2(1.0, 1.0)
	
	z_as_relative = false
	collision_layer = 2
	collision_mask = 2 # Merge only with asteroids
	
	if GameState.current_mode == GameState.GameMode.ONLINE:
		_setup_multiplayer_sync()
	
	generate_shape()

func _setup_multiplayer_sync():
	var synchronizer = MultiplayerSynchronizer.new()
	var config = SceneReplicationConfig.new()
	
	# Properties to sync from Host to Client
	config.add_property(^"pos")
	config.add_property(^"p")
	config.add_property(^"m")
	
	synchronizer.replication_config = config
	synchronizer.root_path = get_path()
	add_child(synchronizer)
	
	# Asteroids are ALWAYS owned by the host (Peer 1)
	synchronizer.set_multiplayer_authority(1)
	set_multiplayer_authority(1)

func generate_shape():
	polygon_points = PackedVector2Array()
	var num_points = 12
	var base_r = pow(m, 1.0/3.0) * 4.0 
	for i in range(num_points):
		var angle = (float(i) / num_points) * TAU
		var r = base_r * randf_range(0.8, 1.2)
		polygon_points.append(Vector2(cos(angle) * r, sin(angle) * r))
	
	var old_col = get_node_or_null("CollisionPolygon2D")
	if old_col: old_col.queue_free()
	
	var col = CollisionPolygon2D.new()
	col.name = "CollisionPolygon2D"
	col.polygon = polygon_points
	add_child(col)

func _physics_process(delta):
	if is_exploding: return
	
	# Only the authority (Host) processes physics for asteroids
	if GameState.current_mode == GameState.GameMode.ONLINE and not is_multiplayer_authority():
		# On client, we still need to update position from the synced 'pos'
		self.position = pos
		# We might also need to regenerate the shape if mass changed
		return

	if invinciframe > 0: invinciframe -= 1
	
	var p_mc = p.length() / (m * PhysicsConfig.C)
	var gamma = sqrt(1.0 + p_mc * p_mc)
	
	var g_tt = gravity.sample_g_tt(pos)
	var grav_dilation = sqrt(max(0.1, -g_tt))
	
	# Gravity Logic
	var eps = PhysicsConfig.ASTEROID_GRAVITY_EPS
	var g_l = gravity.sample_g_tt(pos + Vector2(-eps, 0))
	var g_r = gravity.sample_g_tt(pos + Vector2(eps, 0))
	var g_u = gravity.sample_g_tt(pos + Vector2(0, -eps))
	var g_d = gravity.sample_g_tt(pos + Vector2(0, eps))
	var accel = Vector2((g_r - g_l)/(2.0*eps), (g_d - g_u)/(2.0*eps))
	p += accel * PhysicsConfig.G_FORCE_SCALE * m * delta
	
	# Movement & Merging
	var velocity = (p / m) / gamma * grav_dilation
	var collision = move_and_collide(velocity * delta)
	
	if collision and invinciframe == 0:
		var c_obj = collision.get_collider()
		if c_obj != null and "type" in c_obj and c_obj.type == "asteroid":
			# Only merge if BOTH are not invincible
			if "invinciframe" in c_obj and c_obj.invinciframe == 0:
				if m >= c_obj.m:
					p += c_obj.p
					# Sync position to Center of Mass
					pos = (pos * m + c_obj.pos * c_obj.m) / (m + c_obj.m)
					m += c_obj.m
					generate_shape()
					c_obj.call_deferred("queue_free")
	
	# Move logical position
	pos = self.position
	
	# Robust Wrap
	pos.x = fposmod(pos.x, PhysicsConfig.WORLD_SIZE)
	pos.y = fposmod(pos.y, PhysicsConfig.WORLD_SIZE)
	
	self.position = pos
	z_index = int(pos.x + pos.y)
	queue_redraw()

func _draw():
	if is_exploding: return
	
	# Edge-Triggered Ghosting: Only draw ghosts if we are actually crossing a boundary.
	# This eliminates "clones" in neighboring tiles while maintaining seamless wrapping.
	var margin = 80.0
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
	
	var p_angle = p.angle()
	var rot_forward = Transform2D().rotated(p_angle)
	var rot_back = Transform2D().rotated(-p_angle)
	var scale_tr = Transform2D().scaled(Vector2(contraction, 1.0))
	var contract_tr = rot_forward * scale_tr * rot_back

	for offset in draw_offsets:
		# Apply both the wrapped offset and the isometric billboarding transform
		# Isometric Billboarding: Counter-act parent's Rotation (45) and Scale (1, 0.5)
		var iso_tr = Transform2D(-0.785398, offset).scaled_local(Vector2(1.0, 2.0))
		draw_set_transform_matrix(iso_tr * contract_tr)
		
		draw_colored_polygon(polygon_points, Color.BLACK)
		var line_points = polygon_points.duplicate()
		line_points.append(line_points[0])
		draw_polyline(line_points, Color(0.88, 0.88, 0.88), 1.0)

func spawn_explosion():
	var parent_node = get_parent()
	if not parent_node: return
	
	var expl = CPUParticles2D.new()
	expl.position = pos
	expl.amount = clamp(int(m), 20, 150)
	expl.explosiveness = 1.0
	expl.one_shot = true
	expl.lifetime = 1.0
	expl.spread = 180.0
	expl.gravity = Vector2.ZERO
	expl.initial_velocity_min = 40.0
	expl.initial_velocity_max = 120.0
	expl.scale_amount_min = 2.0
	expl.scale_amount_max = 2.0
	
	var g = Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.add_point(0.0, Color(0.9, 0.9, 0.9, 1)) # Light Grey
	g.add_point(0.4, Color(0.5, 0.5, 0.5, 1)) # Grey
	g.add_point(0.8, Color(0.3, 0.3, 0.3, 0)) # Fade
	expl.color_ramp = g
	
	parent_node.add_child(expl)
	get_tree().create_timer(expl.lifetime).timeout.connect(expl.queue_free)
	expl.emitting = true

func hit_by_laser(laser_energy, shooter = null):
	if is_exploding: return
	
	# Capture parent before we start the deletion process
	var parent_node = get_parent()
	if not parent_node: return
	
	# Only the authority (Host) handles destruction and splintering
	if GameState.current_mode == GameState.GameMode.ONLINE and not is_multiplayer_authority():
		return
		
	spawn_explosion()
	is_exploding = true
	
	var num_pieces = int(randf_range(2, 5))
	var pieces_data = []
	var total_random_mass = 0.0
	
	# Ensure m is at least something sensible
	var current_m = max(m, 0.5)
	
	for i in range(num_pieces):
		var temp_m = randf_range(0.2, 1.0)
		pieces_data.append({"m": temp_m, "v": Vector2.ZERO})
		total_random_mass += temp_m
	
	for piece in pieces_data:
		# Distribute current mass, but keep pieces visible
		piece.m = max((piece.m / total_random_mass) * current_m, 0.1)
	
	var net_momentum = Vector2.ZERO
	for piece in pieces_data:
		piece.v = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(PhysicsConfig.ASTEROID_SHATTER_VEL_MIN, PhysicsConfig.ASTEROID_SHATTER_VEL_MAX)
		net_momentum += piece.v * piece.m
		
	var v_shift = net_momentum / current_m
	var internal_ke = 0.0
	for piece in pieces_data:
		piece.v -= v_shift
		internal_ke += 0.5 * piece.m * piece.v.length_squared()
	
	# Cap explosion scale to prevent fragments from vanishing instantly
	var explosion_scale = clamp(sqrt(laser_energy / max(internal_ke, 1.0)), 1.0, 15.0)
	var base_vel = p / current_m
	
	for piece in pieces_data:
		var a = _asteroid_scene.instantiate()
		a.m = piece.m
		a.p = piece.m * (base_vel + piece.v * explosion_scale)
		# Tighter shatter radius
		a.pos = pos + piece.v.normalized() * PhysicsConfig.ASTEROID_SHATTER_RADIUS
		a.invinciframe = PhysicsConfig.ASTEROID_INVINCIBILITY_FRAMES 
		
		# Add to parent using the captured reference
		parent_node.call_deferred("add_child", a)
	
	call_deferred("queue_free")
