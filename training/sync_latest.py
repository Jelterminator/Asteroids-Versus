import os
import json
import glob
import re
import torch
from stable_baselines3 import PPO

def get_latest_checkpoint(tier):
    checkpoint_dir = f"models/checkpoints/{tier}/"
    if not os.path.exists(checkpoint_dir):
        return None
    
    # Find all zip files in the checkpoint directory
    checkpoints = glob.glob(os.path.join(checkpoint_dir, "*.zip"))
    
    # Also check for the final tier model in the models folder
    final_model = f"models/asteroids_ai_{tier}.zip"
    if os.path.exists(final_model):
        checkpoints.append(final_model)
        
    if not checkpoints:
        return None
        
    # Sort by step count in filename (or use file modification time for the final model)
    def sort_key(f):
        # Extract numbers like '50000' from 'asteroids_1k_50000_steps.zip'
        match = re.search(r"(\d+)_steps", f)
        if match:
            return int(match.group(1))
        # If it's the final model, give it a very high score
        if "asteroids_ai_" in f:
            return 999999999 
        return 0

    checkpoints.sort(key=sort_key, reverse=True)
    return checkpoints[0]

def export_model(checkpoint_path, tier):
    print(f"Loading {checkpoint_path}...")
    model = PPO.load(checkpoint_path)
    state_dict = model.policy.state_dict()

    layers = []
    
    # Extract weights and biases for the actor network
    # Layer 0
    layers.append({
        "w": state_dict["mlp_extractor.policy_net.0.weight"].cpu().numpy().tolist(),
        "b": state_dict["mlp_extractor.policy_net.0.bias"].cpu().numpy().tolist(),
        "activation": "tanh"
    })
    
    # Layer 2
    layers.append({
        "w": state_dict["mlp_extractor.policy_net.2.weight"].cpu().numpy().tolist(),
        "b": state_dict["mlp_extractor.policy_net.2.bias"].cpu().numpy().tolist(),
        "activation": "tanh"
    })
    
    # Final Action Layer
    layers.append({
        "w": state_dict["action_net.weight"].cpu().numpy().tolist(),
        "b": state_dict["action_net.bias"].cpu().numpy().tolist(),
        "activation": "none" 
    })

    brain_data = {
        "name": tier,
        "layers": layers
    }

    output_path = f"models/brain_{tier}.json"
    with open(output_path, "w") as f:
        json.dump(brain_data, f)
    
    print(f"SUCCESS: Exported to {output_path}")

if __name__ == "__main__":
    # Ensure we are in project root
    if os.path.basename(os.getcwd()) == "training":
        os.chdir("..")
        
    for tier in ["1k", "10k", "100k"]:
        latest = get_latest_checkpoint(tier)
        if latest:
            print(f"--- Processing {tier} ---")
            export_model(latest, tier)
        else:
            print(f"No models found for tier {tier}")
