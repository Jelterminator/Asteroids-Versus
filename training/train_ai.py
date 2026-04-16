import os
import re
import time
import glob
import subprocess
import atexit
import signal
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback
from stable_baselines3.common.vec_env import VecNormalize
from godot_rl.wrappers.sbg_single_obs_wrapper import SBGSingleObsEnv
from godot_rl.core.godot_env import GodotEnv
import psutil

PID_FILE = "live_godot_pids.txt"

def cleanup_live_procs():
    """Nuclear kill for all tracked Godot processes."""
    if os.path.exists(PID_FILE):
        try:
            with open(PID_FILE, "r") as f:
                pids = f.readlines()
            for pid_str in pids:
                try:
                    pid = int(pid_str.strip())
                    proc = psutil.Process(pid)
                    print(f"Cleanup: Killing process {pid}")
                    for child in proc.children(recursive=True): child.kill()
                    proc.kill()
                except: pass
            os.remove(PID_FILE)
        except: pass
    
    # Global fallback
    for proc in psutil.process_iter(['name', 'pid']):
        try:
            if "godot" in proc.info['name'].lower():
                print(f"Cleanup: Killing lingering Godot {proc.info['pid']}")
                proc.kill()
        except: pass

def nuclear_preflight():
    print(">>> PRE-FLIGHT CHECK: Cleaning up ports and zombies...")
    cleanup_live_procs()
    for conn in psutil.net_connections():
        if conn.laddr.port in range(11008, 11018) and conn.status == 'LISTEN':
            if conn.pid and conn.pid != os.getpid():
                try:
                    p = psutil.Process(conn.pid)
                    print(f"Pre-flight: Killing port-holder {p.name()} (PID {p.pid}) on {conn.laddr.port}")
                    p.kill()
                except: pass
    time.sleep(2)

atexit.register(cleanup_live_procs)
signal.signal(signal.SIGINT, lambda s, f: (cleanup_live_procs(), os._exit(0)))

# --- ROBUST MONKEY PATCHING ---
# We patch GodotEnv GLOBALLY to handle scene paths and PID tracking correctly on Windows.
_ORIG_LAUNCH = GodotEnv._launch_env

def patched_launch(self, env_path, port, show_window, framerate, seed, action_repeat, speedup, **kwargs):
    from godot_rl.core.utils import convert_macos_path
    from sys import platform
    path = convert_macos_path(env_path) if platform == "darwin" else env_path
    
    # Base command
    launch_cmd = [path, f"--port={port}", f"--env_seed={seed}"]
    if not show_window: launch_cmd += ["--disable-render-loop", "--headless"]
    if speedup: launch_cmd += [f"--speedup={speedup}"]
    if action_repeat: launch_cmd += [f"--action_repeat={action_repeat}"]
    
    # Custom Curriculum Support (passed via kwargs usually)
    brain_name = kwargs.pop("brain_name", "1k")
    launch_cmd += [f"--brain_name={brain_name}"]
    
    # ADD SCENE PATH AS POSITIONAL ARGUMENT (CRITICAL FIX)
    scene_path = kwargs.pop("scene_path", None)
    if scene_path: launch_cmd.append(scene_path)
    
    for k, v in kwargs.items(): launch_cmd.append(f"--{k}={v}")
    
    print(f" --- [LAUNCH] Port {port} Command: {' '.join(launch_cmd)}")
    self.proc = subprocess.Popen(launch_cmd)
    with open(PID_FILE, "a") as f: f.write(f"{self.proc.pid}\n")

GodotEnv._launch_env = patched_launch

def train_difficulty(name, arch, total_timesteps, env_params):
    print(f"\n=== TRAINING TIER: {name} ===")
    
    # SBGSingleObsEnv is ALREADY a VecEnv. We do NOT use SubprocVecEnv.
    # This avoids all multiprocessing/EOFError issues on Windows.
    raw_env = SBGSingleObsEnv(brain_name=name, **env_params)
    env = VecNormalize(raw_env, norm_obs=False, norm_reward=True)
    
    try:
        model_path = f"models/asteroids_ai_{name}"
        checkpoint_dir = f"models/checkpoints/{name}"
        os.makedirs(checkpoint_dir, exist_ok=True)
        
        load_path = None
        if os.path.exists(model_path + ".zip"):
            load_path = model_path
        else:
            checkpoints = glob.glob(os.path.join(checkpoint_dir, "*.zip"))
            if checkpoints:
                checkpoints.sort(key=os.path.getmtime)
                load_path = checkpoints[-1].replace(".zip", "")

        if load_path:
            print(f">>> Resuming {name} from {load_path}")
            model = PPO.load(load_path, env=env)
        else:
            print(f">>> Fresh start for {name}")
            model = PPO("MlpPolicy", env, verbose=1, policy_kwargs=dict(net_arch=arch))

        checkpoint_callback = CheckpointCallback(save_freq=10000, save_path=checkpoint_dir, name_prefix=f"{name}_model")
        model.learn(total_timesteps=total_timesteps, callback=[checkpoint_callback], reset_num_timesteps=not load_path)
        model.save(model_path)
    finally:
        env.close()

if __name__ == "__main__":
    nuclear_preflight()
    os.makedirs("models", exist_ok=True)
    if os.path.basename(os.getcwd()) == "training": os.chdir("..")
    
    env_params = {
        "env_path": r"C:\Users\jelte\Godot\Godot_v4.6.2-stable_win64_console.exe",
        "show_window": False,
        "scene_path": "training/training_scene.tscn",
        "speedup": 80.0,
        "n_parallel": 5 # Using 5 instances
    }

    train_difficulty("1k", dict(pi=[32, 32], vf=[32, 32]), 1_000_000, env_params)
    train_difficulty("10k", dict(pi=[64, 64], vf=[64, 64]), 5_000_000, env_params)
    train_difficulty("100k", dict(pi=[128, 128], vf=[128, 128]), 10_000_000, env_params)