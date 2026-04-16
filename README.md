# Asteroids Duel: Reinforcement Learning Edition

An isometric, gravity-fueled Asteroids clone built in Godot 4, featuring an autonomous self-play reinforcement learning pipeline.

## 🚀 Key Features

- **Isometric Physics**: A custom 2D isometric world with persistent gravity management.
- **Decoupled AI Driver Architecture**: AI agents are separated from ship lifecycles, ensuring stable training sessions even as ships are destroyed and respawned.
- **Self-Play Pipeline**: Integrated with `godot-rl` for high-speed PPO training (Stable Baselines3).
- **Soft Reset System**: Optimized match loop that resets the environment in a single frame without scene reloads, preserving TCP connections.
- **Multi-Mode Gameplay**: Support for Local, Online, and AI vs AI Challenge modes.

## 🛠️ Tech Stack

- **Game Engine**: [Godot 4.6+](https://godotengine.org/)
- **RL Framework**: [Godot RL Agents](https://github.com/edbeeching/godot-rl-agents)
- **Learning Library**: [Stable Baselines3](https://github.com/DLR-RM/stable-baselines3) / PPO
- **Environment**: Python 3.12+

## 📥 Installation

### 1. Godot Setup
- Clone this repository.
- Open `project.godot` in Godot 4.6+.
- Ensure the `godot_rl_agents` plugin is enabled in Project Settings.

### 2. Python Setup
Create a virtual environment and install dependencies:
```bash
python -m venv venv
source venv/Scripts/activate  # Windows: .\venv\Scripts\activate
pip install -r requirements.txt
```

## 🧠 Training the IA

To start a self-play training session:

1. **Start Python Server**:
   ```bash
   python train_ai.py
   ```
2. **Launch Godot**: Press **Play** in the Godot Editor.
3. **Trigger Training**: In the Main Menu, click **AI CHALLENGE**.

The simulation will run at `10x` speed. Checkpoints and ONNX models are saved to the `models/` directory.

## 🎮 How to Play

- **W/A/S/D**: Player 1 Controls (Thrust, Rotate, Fire)
- **Arrows**: Player 2 Controls
- **Objective**: Use gravity and your laser to destroy the opponent while navigating the asteroid field.
