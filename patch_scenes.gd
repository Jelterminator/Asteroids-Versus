extends SceneTree

func _init():
	print("Patching asteroid.tscn and laser.tscn...")

	for scene_path in ["res://asteroid.tscn", "res://laser.tscn"]:
		var pk = load(scene_path)
		var scn: Node = pk.instantiate()
		
		# Ensure we don't duplicate
		if scn.has_node("MultiplayerSynchronizer"):
			print("Already has sync node: " + scene_path)
			continue
			
		var sync_node = MultiplayerSynchronizer.new()
		sync_node.name = "MultiplayerSynchronizer"
		
		var config = SceneReplicationConfig.new()
		if "Asteroid" in scn.name:
			config.add_property(NodePath(".:pos"))
			config.property_set_spawn(NodePath(".:pos"), true)
			config.property_set_replication_mode(NodePath(".:pos"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
			
			config.add_property(NodePath(".:p"))
			config.property_set_spawn(NodePath(".:p"), true)
			config.property_set_replication_mode(NodePath(".:p"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
			
			config.add_property(NodePath(".:m"))
			config.property_set_spawn(NodePath(".:m"), true)
			config.property_set_replication_mode(NodePath(".:m"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
			
			config.add_property(NodePath(".:is_exploding"))
			config.property_set_spawn(NodePath(".:is_exploding"), true)
			config.property_set_replication_mode(NodePath(".:is_exploding"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
			
		elif "Laser" in scn.name:
			config.add_property(NodePath(".:pos"))
			config.property_set_spawn(NodePath(".:pos"), true)
			config.property_set_replication_mode(NodePath(".:pos"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
			
			config.add_property(NodePath(".:p"))
			config.property_set_spawn(NodePath(".:p"), true)
			config.property_set_replication_mode(NodePath(".:p"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
			
		sync_node.replication_config = config
		scn.add_child(sync_node)
		sync_node.owner = scn
		
		var new_pk = PackedScene.new()
		new_pk.pack(scn)
		ResourceSaver.save(new_pk, scene_path)
		print("Successfully patched " + scene_path)
	
	quit()
