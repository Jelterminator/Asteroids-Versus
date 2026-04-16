extends RefCounted
class_name RewardManager

var brain_name: String
var ship: Node2D
var enemy: Node2D

func _init(_brain_name: String, _ship: Node2D, _enemy: Node2D):
	brain_name = _brain_name
	ship = _ship
	enemy = _enemy

func shortest_toroidal_distance(p1: Vector2, p2: Vector2) -> float:
	var dx = fposmod(p1.x - p2.x + PhysicsConfig.WORLD_HALF_SIZE, PhysicsConfig.WORLD_SIZE) - PhysicsConfig.WORLD_HALF_SIZE
	var dy = fposmod(p1.y - p2.y + PhysicsConfig.WORLD_HALF_SIZE, PhysicsConfig.WORLD_SIZE) - PhysicsConfig.WORLD_HALF_SIZE
	return Vector2(dx, dy).length()

func get_toroidal_direction(p_from: Vector2, p_to: Vector2) -> Vector2:
	var dx = fposmod(p_to.x - p_from.x + PhysicsConfig.WORLD_HALF_SIZE, PhysicsConfig.WORLD_SIZE) - PhysicsConfig.WORLD_HALF_SIZE
	var dy = fposmod(p_to.y - p_from.y + PhysicsConfig.WORLD_HALF_SIZE, PhysicsConfig.WORLD_SIZE) - PhysicsConfig.WORLD_HALF_SIZE
	return Vector2(dx, dy).normalized()

func compute_laser_rewards() -> Dictionary:
	var danger = 0.0
	var shot_quality = 0.0
	
	if not is_instance_valid(ship) or not is_instance_valid(enemy):
		return {"danger": 0.0, "shot_quality": 0.0}
	if not is_instance_valid(ship.get_tree()):
		return {"danger": 0.0, "shot_quality": 0.0}
	
	var lasers = ship.get_tree().get_nodes_in_group("lasers")
	for l in lasers:
		# LINEAR DANGER: Max penalty at 0 distance, scales to 0 at 150 units.
		var dist_to_ship = shortest_toroidal_distance(ship.position, l.position)
		if dist_to_ship < 150.0:
			danger += max(0.0, 1.0 - (dist_to_ship / 150.0))
		
		# LINEAR SHOT QUALITY
		if l.shooter == ship:
			var dist_to_enemy = shortest_toroidal_distance(enemy.position, l.position)
			if dist_to_enemy < 150.0:
				shot_quality += max(0.0, 1.0 - (dist_to_enemy / 150.0))
	
	return {"danger": danger, "shot_quality": shot_quality}

func compute_aim_quality() -> float:
	if not is_instance_valid(ship) or not is_instance_valid(enemy): return 0.0
	var dir_to_enemy = get_toroidal_direction(ship.position, enemy.position)
	var aim_dot = ship.orientation.dot(dir_to_enemy)
	return clamp((aim_dot - 0.5) / 0.5, 0.0, 1.0) # 0.0 to 1.0

func compute_step_reward(_delta: float) -> float:
	var reward = 0.0
	if not is_instance_valid(ship) or not is_instance_valid(enemy): return 0.0
	
	var aim_q = compute_aim_quality()
	var laser_data = compute_laser_rewards()
	
	match brain_name:
		"1k":
			# Aggressive Aggression: Must move, must aim, MUST shoot.
			# BREAK PACIFIST LOOP: Increased pressure to shoot and removed miss penalty.
			if ship.ai_thrust: reward += 0.01
			reward += 0.1 * aim_q # Doubled aim focus

			# Force decision: Penalty for NOT shooting is now much higher than any miss.
			if ship.laser_cooldown <= 0: reward -= 0.08
			
			if ship.ai_fire:
				if aim_q > 0.8:
					reward += 1.0 # HUGE bonus for firing while locked on
					ship.laser_cooldown = min(ship.laser_cooldown, 0.2) # Rapid fire when aimed
				elif aim_q > 0.2:
					reward += 0.1
				# Miss penalty removed for 1k to encourage exploration
					
			# Still penalize getting hit by lasers so it doesn't just ram them
			reward -= 0.1 * laser_data.danger

		"10k":

			# TACTICAL: Needs to actually hit the enemy and avoid being hit.
			reward -= 1.0 * laser_data.danger
			reward += 1.0 * laser_data.shot_quality
			
			# Mild encouragement to shoot if lined up (helps discover the shot_quality reward)
			if ship.ai_fire and aim_q > 0.8:
				reward += 0.1
				
			reward -= 0.01 # Time penalty
			
		"100k":
			# MONSTER: Mostly terminal rewards, strict dynamic laser avoidance.
			reward -= 1.0 * laser_data.danger
			reward += 0.5 * laser_data.shot_quality
			reward -= 0.01 # Time penalty
	
	return reward

func compute_game_over_reward(winner_name: String) -> float:
	if winner_name == ship.p_name:
		return 10.0 # Clear positive signal
	elif winner_name == "TIMEOUT_DRAW":
		return -50.0 # Severe punishment for stalemate
	else:
		return -1.0 # Slight punishment for loss - makes combat risk-positive

func notify_collision(collider: Node) -> float:
	if collider.is_in_group("asteroids"):
		if brain_name == "1k": return -5.0
		if brain_name == "10k": return -1.0
		if brain_name == "100k": return -0.1
	return 0.0