# Atomic time: native CUDA research prototype

This experiment asks whether an interacting procedural world can be queried at a distant time without replaying every tick. It implements three separate models. Their guarantees must not be combined into a claim of general-purpose fast-forward physics.

The follow-up [exact CUDA region-cache experiment](REGION-CACHE.md) is now implemented separately. Run `./build-regions.ps1` to validate and benchmark finite-horizon memoization of the collision model in quiet, sparse, repeated, dense, and periodic scenarios.

No JavaScript, browser runtime, external assets, or CUDA-to-WGSL translation is used. This is a command-line research executable, not an enterable building or rendered demo. CUDA runs the experimental dynamics; C++ hosts the kernels, validation, and measurements.

## Build and run

On Windows with the NVIDIA CUDA toolkit and Visual Studio C++ tools:

```powershell
cd D:\RealisticCity\experiments\atomic-time
.\build.ps1
```

This builds `build/atomic_time.exe`, runs validation and benchmarks, and writes `results.json` in the working directory. `-arch=native` targets the installed GPU. To rerun without compiling, run `./build/atomic_time.exe` from this directory.

Alternatively, configure the supplied CMake project in an environment with a working CUDA/C++ toolchain, build, and run CTest. The PowerShell/nvcc route was exercised on this machine; the CMake route is supplied but has not been exercised.

## 1. Exact jump-ahead cellular automaton

Start with three independent binary fields on a periodic ring. Each field follows Rule 90:

```text
F(x)[i] = x[i-1] XOR x[i+1]
```

Over arithmetic modulo two, cross terms cancel. For commuting left and right shift operators L and R:

```text
(L + R)^(2^k) = L^(2^k) + R^(2^k)
```

Therefore a jump of 2^k ticks is just a neighbor query at distance 2^k. Compose the jumps for the set bits of T. On a ring of N cells this takes `popcount(T)` full-grid passes, O(N log T) total work in the worst case, and O(N) resident state. There is no growing history or jump table. CPU launch overhead and GPU bandwidth still matter; parallel depth is not constant wall-clock time on finite hardware.

To test a nonlinear visible rule, store each cell through an invertible local mapping:

```text
h(a,b,c) = (a,b,c XOR (a AND b))
G = h F h
G^T = h F^T h
```

The encoded one-tick rule includes cross products between neighboring bits. However, it is deliberately conjugate to a linear rule. This is an illustrative construction, not an implementation of the full Moore/Pnin quasidirect-product algorithm, nor a model of mechanical collision or conservation. Rule 90 is not generally reversible on the finite ring.

`jumpKernel` reads two cells and writes one. Each jump is a separate launch with distinct input/output buffers; a block barrier cannot replace the required global ordering. CPU reference tests use the expanded nonlinear truth rule rather than the GPU's decode/XOR/encode implementation.

There is also a direct seed-and-address oracle using the odd binomial coefficients. It needs 2^popcount(T) initial samples before accounting for possible ring coincidences, so a sparse-bit time is cheap but an arbitrary dense-bit time may be expensive. The oracle refuses more than 20 set bits. This is not a universal constant-cost seed lookup.

## 2. Reversible atomic collisions

An HPP lattice gas uses four occupancy bits per cell: east, north, west, south. Each tick streams particles, then scatters an isolated opposing pair by 90 degrees. Other occupancies pass through unchanged.

Two tests run: a periodic domain, and two enclosed rooms connected by a doorway. Fixed walls reflect particles. The inverse first undoes the collision and then undoes streaming. The CPU oracle scatters data while the GPU gathers it, providing different indexing implementations.

Validation checks forward agreement, particle-count conservation, periodic-domain momentum conservation, and exact return to the initial microstate after 257 inverse steps. Walls exchange momentum with the gas, so gas momentum is not asserted conserved in the room case. Since all particles have the same speed, particle count also fixes the model's kinetic energy.

This recovers history without stored frames but still takes one pass per tick forward or backward. No general jump-ahead algorithm for this collision model is implemented. HPP is anisotropic and is not a realistic room-air or rigid-body solver. There is no gravity in this prototype.

## 3. Exact colliding hard rods at arbitrary time

For identical rods in one dimension with elastic collisions, subtract the mandatory spacing: `y_i = x_i - i*d`. The compressed domain contains point particles. Equal-mass collisions exchange velocities, allowing independent ghost trajectories to represent the unordered positions. Fold those trajectories at reflecting walls, rank their positions, and restore spacing with `x_i = sorted(y)_i + i*d`.

`rodsAtTime` evaluates this directly on CUDA. The test uses 32 rods, equal mass and diameter, integer initial coordinates, velocities +/-1, and fixed reflecting endpoints. A separate CPU event-driven implementation actually processes the wall and rod collisions in physical coordinates. Seven times through 16,384 ticks are compared exactly. A UINT64_MAX query is compared using the independently known trajectory period.

The GPU's simple pairwise ranking costs O(N^2), independent of elapsed tick count. It is adequate for this proof; a production implementation would use sorting. This kernel returns positions, not a complete velocity/contact-state API. At coincident ghost positions a stable index tie-break produces unique writes. This exact restricted mechanics does not extend automatically to unequal masses, friction, gravity, rotation, arbitrary 3D contacts, or moving walls.

## Validation and measurement

- 162 CA cases against independent CPU stepping, including zero time, several seeds, singleton/two-cell rings, power-of-two and odd domain sizes.
- GPU seed generation agrees with CPU generation.
- Sparse distant-time queries are checked against the binomial/submask seed oracle.
- Large-time composition, the 64-bit maximum time, and an explicit nonlinear witness are checked.
- HPP checks described above and hard-rod/event-driven comparisons all run before reporting PASS.
- Benchmark: 65,521 cells, 8,191 ticks, five repetitions after warmup; medians include host launch overhead and final synchronization. Allocation, initial upload, and final download are excluded from timing. Both paths compute identical outputs on the same GPU.
- The step baseline is intentionally simple: one CUDA launch per tick. The measured ratio includes the reduction in launches and is not a comparison against every optimized persistent-kernel implementation.
- The huge-time result is checked through the mathematical derivation, sparse-time independent oracle, and composition tests. It is not independently stepped through 10^18 ticks.

Results are observations on one device/run, not a performance guarantee. The ring is finite and periodic; these tests do not establish cheap queries for an infinite random field.

## Research and next building experiment

See [RESEARCH.md](RESEARCH.md) for the papers, exact correspondences, and proposed building architecture. The bounded collision-region experiment has been completed in [REGION-CACHE.md](REGION-CACHE.md), including causal halos, exact comparisons, cache hit rates, and memory accounting. We have not implemented recursive HashLife, gravity, an interactive player, or the building renderer.
