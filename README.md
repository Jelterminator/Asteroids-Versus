# ☄️ Asteroids Versus ☄️

🚀 **[Play it Live Here Data-Free!](https://jelterminator.github.io/Asteroids-Versus)**

An over-engineered, peer-to-peer multiplayer Asteroids engine written in Godot 4. Instead of basic arcade physics, it simulates actual astrophysics—integrating both **Special Relativity (SR)** and **General Relativity (GR)** to dictate how mass, movement, and time operate in a 2D Toroidal Spacetime topology. 

If you travel near $`c`$, you squish. If you fall into a gravity well, your internal cooldowns slow down. Period.

<br>

---

## 🕹️ How to Play

Survive the relativistic sandbox! Dodge asteroids, utilize gravity wells to slingshot your ship, and obliterate the enemy.

**Controls:**
- **[W]** - Thrust Forward
- **[A] / [D]** - Rotate Left / Right
- **[S]** - Fire Relativistic Laser

*Pro-tip: Firing your laser generates massive recoil. Use it to brake or radically alter your momentum in emergencies.*

---

## 🚀 Physics & Simulation Math

### Special Relativity & Lorentian Mechanics
Instead of tracking raw velocity, the engine natively tracks relativistic Momentum ($\vec{p}$) and Rest Mass ($m_{0}$). 
- **The Speed Limit**: The calculation of coordinate velocity factors in the Lorentz factor ($\gamma$), meaning the classic arcade thrust inherently approaches but never surpasses the configurable speed of light ($C$).
  ```math
  \gamma = \sqrt{1 + \left( \frac{|p|}{mc} \right)^2} \quad | \quad \vec{v} = \frac{\vec{p} / m}{\gamma}
  ```
- **Time Dilation (Proper Time vs Coordinate Time)**: Player actions such as rotation and weapon cooldowns run entirely on Proper Time ($\Delta \tau$), whereas momentum is modified linearly in Coordinate Time.
- **Lorentz Contraction**: Rendering uses custom Transform matrices rotated in the direction of local momentum to manually compress the polygon vertices by $\frac{1}{\gamma}$. Ships deform dynamically at high speeds.

### General Relativity & Gravity
A custom `GravityManager.gd` utilizes continuous **Poisson Relaxation** to compute a persistent scalar field solving for the temporal metric tensor component ($g_{tt}$).
- Mass is bilinearly splatted into a spatial grid every physics frame. Grid relaxation converges on a gravitational potential $\Phi$.
- Spatial gradients are sampled smoothly (using bilinear interpolation) at object coordinates $x,y$ to pull bodies towards mass distributions.
- **Gravitational Time Dilation**: Deep gravity wells dynamically stretch the local passage of time by a factor of $\sqrt{-g_{tt}}$. 
- **Geodesic Mapping**: Realtime visual grids distort using the gravitational well calculations, directly mapping the curvature of the spacetime field onto the background rendering.

### Toroidal Topological Wrapping
To simulate classic "edge-wrapping" without stuttering, the spacetime topology operates as a seamless 2D Torus. 
- Using modulo wrapping (`fposmod`), positions loop mathematically.
- Visually, objects use **Edge-Triggered Ghosting**: Objects calculate their proximity to boundaries and actively render up to 3 clone representations (offsets of `WORLD_SIZE`) to cross the torus seamlessly.

### Rigorous Momentum Conservation
When a laser hits an asteroid, it vaporizes it into fragments. To ensure the $n-$body simulation doesn't break, the destruction logic injects internal Kinetic Energy relative to the size of the explosion while shifting the fragmentation velocity vectors perfectly against the Center of Mass. The output maintains exact absolute momentum conservation ($\sum p_{before} = \sum p_{after}$). You can merge asteroids, blast them, or bounce them, and the simulation remains fully intact.

---

## 🌐 Networking

### Asymmetric Dual-Synchronizer Architecture
Asteroids Versus implements a high-fidelity, peer-to-peer synchronization model designed specifically for the low-latency demands of relativistic physics. 

- **Host-Authoritative State Replication**: The Host maintains the absolute truth of the gravitational field, asteroid positions, and projectile trajectories. High-frequency state snapshots are serialized and pushed to peers, ensuring perfect synchronization across the torus.
- **Client Input Replication**: To minimize perceived input lag, Clients replicate only raw input vectors (Thrust/Fire) to the Host. The Host then processes these inputs within its local simulation and reconciles the resulting delta back to the Client.
- **WebRTC Mesh Messaging**: Instead of archaic client-server polling, the game utilizes the `WebRTCDataChannel`. Packets are optimized for MTU limits, preventing fragmentation and ensuring that relativistic state updates arrive within single-digit millisecond windows.
- **Express Signaling & Isolation**: A dedicated Node.js signaling server handles 1v1 matchmaking and P2P handshakes via WebSockets. The delivery pipeline enforces **Cross-Origin Isolation** (COOP/COEP) headers, enabling the Godot engine to leverage **SharedArrayBuffers** for multi-threaded physics calculations in-browser.

## 🧠 Godot RL & Embedded Neuro-Inference

What's the point of building a mathematically sound spacetime topology if you aren't training AI to exploit it?
- **Embedded GDScript Inference**: The codebase includes a bespoke Multi-Layer Perceptron (`NeuralNet.gd`) that calculates forward passes inside the Godot VM without external dependencies. By pre-allocating contiguous memory (`PackedFloat32Array`), matrix-vector multiplication handles continuous framerates effortlessly. 
- **Toroidal Harmonic Encodings**: Because the world wraps like a torus, the AI isn't fed raw $X,Y$ coordinates. Positions are parsed through global scale $sin$/$cos$ harmonics to prevent discontinuities at the map boundaries.
- **Gravity Field Discretization**: Standard ray-casts don't work natively in curved spacetime. Instead, the AI Controller observes gravity by calculating an 8x8 Fast-Fourier-style dot product against the $g_{tt}$ potential grid, giving the neural net a localized sense of spacetime curvature.
- **Seamless Godot-RL Integration**: Native hook mappings for action-spaces and reward callbacks enable remote Python environments (`Ray`, `StableBaselines3`) to train agents completely headless before serializing the brain back into a `.json` for the client.

---

*This is not your dad's arcade game.*
