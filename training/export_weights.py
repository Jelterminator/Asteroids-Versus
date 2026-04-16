import os
import json
import torch
import numpy as np
from stable_baselines3 import PPO

def export_model(name):
    model_path = f"models/asteroids_ai_{name}.zip"
    if not os.path.exists(model_path):
        print(f"Model {model_path} not found.")
        return

    print(f"Exporting {name}...")
    model = PPO.load(model_path)
    state_dict = model.policy.state_dict()

    # We extract the policy network (actor)
    # Layer 0: Linear(8, X)
    # Layer 1: Tanh
    # Layer 2: Linear(X, X)
    # Layer 3: Tanh
    # Action Net: Linear(X, 4)

    layers = []
    
    # Layer 0
    layers.append({
        "w": state_dict["mlp_extractor.policy_net.0.weight"].numpy().tolist(),
        "b": state_dict["mlp_extractor.policy_net.0.bias"].numpy().tolist(),
        "activation": "tanh"
    })
    
    # Layer 2
    layers.append({
        "w": state_dict["mlp_extractor.policy_net.2.weight"].numpy().tolist(),
        "b": state_dict["mlp_extractor.policy_net.2.bias"].numpy().tolist(),
        "activation": "tanh"
    })
    
    # Final Action Layer
    layers.append({
        "w": state_dict["action_net.weight"].numpy().tolist(),
        "b": state_dict["action_net.bias"].numpy().tolist(),
        "activation": "none" # Action mean
    })

    brain_data = {
        "name": name,
        "layers": layers
    }

    with open(f"models/brain_{name}.json", "w") as f:
        json.dump(brain_data, f)
    
    print(f"Exported to models/brain_{name}.json")

if __name__ == "__main__":
	# CRITICAL: Change working directory to project root so we can find models/ folder
	os.chdir("..")
	
	export_model("1k")
	export_model("10k")
	export_model("100k")
