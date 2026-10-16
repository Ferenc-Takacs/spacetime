# Spacetime Simulation under Curvature-Dependent Cosmological Constant

A high-performance **Rust** and **WebGPU (WGSL)** simulation environment designed to numerically integrate a modified version of Einstein's field equations at the sub-Planckian scale. This framework treats the cosmological constant not as an immutable background value, but as a dynamic scalar field \(\Lambda(K, C^2)\) coupled directly to local geometric tension.

## 🌌 Theoretical Framework

The core engine integrates the modified field equations presented in Ferenc Takács (2026), *A Version of Einstein's Equations Valid for the Entire Universe* (IJAA):

\[R_{\mu\nu} - \frac{1}{2}R g_{\mu\nu} + \Lambda(K, C^2) g_{\mu\nu} = \frac{8\pi G}{c^4} T_{\mu\nu}\]

Where the dynamic cosmological feedback loop is defined at the sub-atomic boundary via fixed geometric couplings (γ = 2/3, δ = 3/2) and scale-corrected by the Planck length (\(\ell_P^2 = 0.01\)):

\[\phi = \ell_P^2 \left( \frac{2}{3}K + \frac{3}{2}C^2 \right)\]

*   **K (Kretschmann Scalar):** Measures localized Ricci-driven energy and tidal stresses, preventing gravitational singularities.
*   **C² (Weyl Conformal Invariant Square):** Maps long-range non-local tidal shear and rotational vacuum feszültség.

---

## ⚡ Numerical Architecture & WebGPU Engine

To handle the **41 orders of magnitude discrepancy** between gravitational and electromagnetic scales without numerical divergence, the simulator implements a highly optimized parallelized pipeline on a 113³ spatial grid:

1. **Local Self-Regulated Timestepping (`local_dt`):** The code dynamically extracts the lapse function \(\alpha = \sqrt{\max(10^{-8}, -g_{00})}\) point-by-point. Simulation time automatically slows down in high-curvature domains, maximizing stability near the core event horizon.
2. **Conformal Stabilization:** Energy contributions from \(T_{em}\) are attenuated via a `stabilization_factor = 1.0 / (1.0 + phi)`, providing a physical saturation barrier against infinite density.
3. **Soft-Clipping Operators:** To suppress high-frequency numerical grid noise, the source terms and Weyl metrics are routed through non-linear asymptotic capping functions (e.g., `source_term / (1.0 + abs(source_term / 35.0))`).
4. **Pure GPU Compute Pipeline:** The simulation runs entirely within parallelized WGSL compute shaders, leaving the CPU completely free.

---

## 🚀 Building and Running

Ensure you have a Rust toolchain and a WebGPU-compatible driver installed.

```bash
# Clone the repository
git clone https://github.com/Ferenc-Takacs/spacetime.git
cd spacetime

# Run the simulation with release optimizations
cargo run --release
```

### Data Visualization
The application exports the entire 4D metric tensor state into structured CSV snapshots every 10,000 steps. 
* Use `draw_webp.py` to compile the snapshot logs into compressed, high-fidelity WebP animations.
* Extended diagnostic tracking can be conducted using the integrated graphical analysis suites.

## 🧪 Simulation Results (At 50,000 Iterations)

Starting from a modified, central-smoothed (non-singular) Schwarzschild initial metric metric, the 4D manifold undergoes **spontaneous symmetry breaking** and topologico-hydrodynamic self-regulation:

* **The Almond Remnant:** A stable, non-spherical, almond-shaped core forms at the center, surrounded by a slowly expanding, high-intensity shell of K and C² geometric tension.
* **The Recirculation Loop:** A closed topological flow cell emerges. Spacetime continuously streams from the rear to the front of the almond structure. Below the expanding tension crust, a distinct counter-current forms, evacuating energy away from the leading edge and establishing an asymptotic equilibrium.
* **Metric Torsion and Vector Cancellation:** 
  * *The Outer Regime:* Inflowing coordinates remain structurally flat, displaying sharp metric twist (torsion) only upon hitting the high-gradient boundary shell, tracked via line discolouration.
  * *The Inner Regime:* The deep core is permanently discoloured, indicating uniform, maximal metric shear. Crucially, neighboring lattice points twist in alternating directions, causing a local cancellation of rotational vectors. As a direct consequence, the core fluid flow remains **perfectly rectilinear (straight)** instead of collapsing into a macroscopic classical torus.

---

