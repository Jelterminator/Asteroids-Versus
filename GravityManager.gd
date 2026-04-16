extends Node2D

@export var grid_size: int = PhysicsConfig.G_GRID_SIZE
@export var iterations: int = PhysicsConfig.G_ITERATIONS
@export var G_CONSTANT: float = PhysicsConfig.G_CONSTANT 
@export var curvature_sensitivity: float = PhysicsConfig.G_CURVATURE_SENSITIVITY

# OPTIMIZATION: Use PackedFloat32Arrays (contiguous memory channels) instead of an Array of Dictionaries.
# This results in massive speedups for loops and avoids dictionary hashing overhead.
var phi_grid: PackedFloat32Array
var mass_grid: PackedFloat32Array
var g_tt_grid: PackedFloat32Array

var screen_size = Vector2(PhysicsConfig.WORLD_SIZE, PhysicsConfig.WORLD_SIZE)

func _ready():
	z_as_relative = false
	z_index = -1024
	
	var total_cells = grid_size * grid_size
	phi_grid.resize(total_cells)
	mass_grid.resize(total_cells)
	g_tt_grid.resize(total_cells)
	
	phi_grid.fill(0.0)
	mass_grid.fill(0.0)
	g_tt_grid.fill(-1.0)

func _physics_process(_delta):
	# 1. Reset Mass (Fast primitive fill)
	mass_grid.fill(0.0)
	
	# 2. Bilinear Splat Mass
	var massives = get_tree().get_nodes_in_group("massives")
	for body in massives:
		if "m" in body and "pos" in body:
			var gx = (body.pos.x / screen_size.x) * grid_size
			var gy = (body.pos.y / screen_size.y) * grid_size
			var x0 = int(floor(gx))
			var y0 = int(floor(gy))
			var tx = gx - x0
			var ty = gy - y0
			
			_add_mass_wrapped(x0, y0, body.m * (1.0 - tx) * (1.0 - ty))
			_add_mass_wrapped(x0 + 1, y0, body.m * tx * (1.0 - ty))
			_add_mass_wrapped(x0, y0 + 1, body.m * (1.0 - tx) * ty)
			_add_mass_wrapped(x0 + 1, y0 + 1, body.m * tx * ty)

	# 3. Solve Potential (Poisson Relaxation)
	# Pre-caching constants for the loop
	var damp = 0.99
	var g_const_div_4 = G_CONSTANT / 4.0
	
	for i in range(iterations):
		for y in range(grid_size):
			var y_off = y * grid_size
			var y_up = posmod(y + 1, grid_size) * grid_size
			var y_dn = posmod(y - 1, grid_size) * grid_size
			
			for x in range(grid_size):
				var idx = y_off + x
				var x_rt = posmod(x + 1, grid_size)
				var x_lt = posmod(x - 1, grid_size)
				
				# Neighbor Potential Sum
				var n_sum = (
					phi_grid[y_dn + x] + phi_grid[y_up + x] + 
					phi_grid[y_off + x_lt] + phi_grid[y_off + x_rt]
				)
				
				# Relaxation Step
				phi_grid[idx] = ((n_sum / 4.0) - (mass_grid[idx] * g_const_div_4)) * damp

	# 4. Update Metric and Ground Potential
	var total_phi = 0.0
	for p in phi_grid: total_phi += p
	var avg_phi = total_phi / phi_grid.size()
	
	for i in range(phi_grid.size()):
		phi_grid[i] -= avg_phi 
		g_tt_grid[i] = -(1.0 + curvature_sensitivity * phi_grid[i])
	
	queue_redraw()

func _add_mass_wrapped(x: int, y: int, m_val: float):
	mass_grid[posmod(y, grid_size) * grid_size + posmod(x, grid_size)] += m_val

func _draw():
	var scale_distortion = PhysicsConfig.G_VISUAL_DISTORTION
	var margin = 4
	var step_x = screen_size.x / grid_size
	var step_y = screen_size.y / grid_size
	
	# Horizontal Lines
	for y in range(-margin, grid_size + margin + 1):
		var points = PackedVector2Array()
		for x in range(-margin, grid_size + margin + 1):
			var phi = phi_grid[posmod(y, grid_size) * grid_size + posmod(x, grid_size)]
			var p_raw = Vector2(x * step_x, y * step_y)
			points.append(p_raw + Vector2(-phi, -phi) * scale_distortion)
		draw_polyline(points, Color(0.63, 0.63, 0.63), 1.0)

	# Vertical Lines
	for x in range(-margin, grid_size + margin + 1):
		var points = PackedVector2Array()
		for y in range(-margin, grid_size + margin + 1):
			var phi = phi_grid[posmod(y, grid_size) * grid_size + posmod(x, grid_size)]
			var p_raw = Vector2(x * step_x, y * step_y)
			points.append(p_raw + Vector2(-phi, -phi) * scale_distortion)
		draw_polyline(points, Color(0.63, 0.63, 0.63), 1.0)

# Fast lookup for AI observation
func get_g_tt(x: int, y: int) -> float:
	return g_tt_grid[y * grid_size + x]

# Bilinear Interpolation for smooth gravity (Still used by Physics objects)
func sample_g_tt(pos: Vector2) -> float:
	var gx = (pos.x / screen_size.x) * grid_size
	var gy = (pos.y / screen_size.y) * grid_size
	var x0 = int(floor(gx))
	var y0 = int(floor(gy))
	var tx = gx - x0
	var ty = gy - y0
	
	var c00 = g_tt_grid[posmod(y0, grid_size) * grid_size + posmod(x0, grid_size)]
	var c10 = g_tt_grid[posmod(y0, grid_size) * grid_size + posmod(x0 + 1, grid_size)]
	var c01 = g_tt_grid[posmod(y0 + 1, grid_size) * grid_size + posmod(x0, grid_size)]
	var c11 = g_tt_grid[posmod(y0 + 1, grid_size) * grid_size + posmod(x0 + 1, grid_size)]
	
	return lerp(lerp(c00, c10, tx), lerp(c01, c11, tx), ty)
