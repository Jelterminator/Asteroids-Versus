import os
import re
import json
import glob
import torch
import numpy as np
from stable_baselines3 import PPO

def get_latest_checkpoint(name):
    checkpoint_dir = f"models/checkpoints/{name}"
    if not os.path.exists(checkpoint_dir): 
        return None
    
    checkpoints = glob.glob(os.path.join(checkpoint_dir, "*.zip"))
    if not checkpoints: 
        return None
        
    # Sort by step count: {name}_model_{steps}_steps.zip
    def extract_steps(filepath):
        match = re.search(r"_(\d+)_steps\.zip", filepath)
        return int(match.group(1)) if match else 0
        
    checkpoints.sort(key=extract_steps, reverse=True)
    return checkpoints[0]

def export_model(name):
    model_path = f"models/asteroids_ai_{name}.zip"
    
    selected_path = None
    if os.path.exists(model_path):
        selected_path = model_path
        print(f">>> Found FINAL model for {name}: {selected_path}")
    else:
        selected_path = get_latest_checkpoint(name)
        if selected_path:
            print(f">>> Final model not found. Using LATEST CHECKPOINT for {name}: {selected_path}")
        else:
            print(f"!!! Error: No model or checkpoints found for {name}. Skipping.")
            return

    print(f"Exporting weights from {selected_path}...")
    model = PPO.load(selected_path)
    state_dict = model.policy.state_dict()

    # Extract policy network (actor)
    # Layer indices depend on the SB3 version/PPO defaults, 
    # but 0 and 2 are usually the hidden layers for MlpPolicy.
    layers = []
    
    try:
        # Layer 0
        layers.append({
            "w": state_dict["mlp_extractor.policy_net.0.weight"].detach().cpu().numpy().tolist(),
            "b": state_dict["mlp_extractor.policy_net.0.bias"].detach().cpu().numpy().tolist(),
            "activation": "tanh"
        })
        
        # Layer 2
        layers.append({
            "w": state_dict["mlp_extractor.policy_net.2.weight"].detach().cpu().numpy().tolist(),
            "b": state_dict["mlp_extractor.policy_net.2.bias"].detach().cpu().numpy().tolist(),
            "activation": "tanh"
        })
        
        # Final Action Layer
        layers.append({
            "w": state_dict["action_net.weight"].detach().cpu().numpy().tolist(),
            "b": state_dict["action_net.bias"].detach().cpu().numpy().tolist(),
            "activation": "none" 
        })

        brain_data = {
            "name": name,
            "layers": layers
        }

        output_path = f"models/brain_{name}.json"
        with open(output_path, "w") as f:
            json.dump(brain_data, f)
        
        print(f"SUCCESS: Exported {name} to {output_path}")
    except KeyError as e:
        print(f"!!! ERROR: Could not find key {e} in state_dict. Model architecture might differ.")

if __name__ == "__main__":
    # Change working directory to project root
    if os.path.basename(os.getcwd()) == "training":
        os.chdir("..")
    
    os.makedirs("models", exist_ok=True)
    
    for tier in ["1k", "10k", "100k"]:
        export_model(tier)
