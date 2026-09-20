# Stratum — One building

A browser FPS walkthrough of address-seeded buildings using [SamG-Coder/cuda-webshader](https://github.com/SamG-Coder/cuda-webshader). CUDA source supplies building generation, ray queries, procedural materials, lighting, the acceleration structure, gravity, stair stepping, and player collision. JavaScript supplies browser input, dispatch, residency scheduling, and the interface.

## Run

Requires Node.js 20+ and a browser with working WebGPU. Tested with Microsoft Edge on an NVIDIA Blackwell adapter.

```powershell
git clone --recurse-submodules https://github.com/SamG-Coder/RealisticCity.git
cd RealisticCity
npm install
npm run build
npm start
```

Open http://127.0.0.1:8787 and click **Walk inside**. `START.ps1` is also supplied. No native CUDA toolkit is required. Generated WGSL comes from `kernels/building.cu` through the user's compiler.

If you cloned without submodules, run `git submodule update --init --recursive` before building. Generated shader artifacts are rebuilt locally. This repository does not configure GitHub Pages or a deployment workflow.

## Address and residency

World seed + integer lot X/Z derive a 32-bit building key. Independent channels determine residential/workspace/mixed use, footprint, two to four floors, individual storey heights, flat/pitched/stepped roofs, facade palette, per-floor room partitions, and furnishings. Each floor currently has four rooms around a connected corridor and stair core. Room dimensions and contents vary; this is a constrained architectural grammar.

The same `emitBuilding()` function enumerates every exterior. The neighboring version does not substitute a proxy facade, roof, or simplified window assembly. This follows the shared-geometry principle in the current Stratum reference. Material coordinates are anchored to each lot, so rebasing does not slide the brick and wood patterns.

The current GPU residency window contains **25 exteriors and at most one detailed interior**. Walking across a 40m lot boundary recenters the window. The camera rebases to local coordinates while preserving its position in the addressed world. Nearby interiors load; distant interiors are omitted on reconstruction. An 8m load / 11m unload threshold around a conservative building envelope avoids boundary churn. Returning regenerates the same geometry from the same address.

This permits traversal across many addresses without retaining every visited room. It is **not yet the reference's citywide analytic query renderer**: exteriors are enumerated into a fixed buffer inside a 5×5 window, and geometry outside that window is not rendered. Windows into nonresident interiors can reveal the absence of furnishings. Exact distant interior visibility requires an on-demand query path. The current implementation does not claim pixel-identical interior views across residency transitions or thousands of simultaneously visible buildings.

Geometry and BVH allocation are fixed at 32,768 feature slots (about 4.25 MiB combined geometry, BVH, and sort buffers; frame buffers are additional). Eviction overwrites reusable slots; it does not continually allocate buffers. World seeds accept 0–16,777,215; lot coordinates accept −1,000,000–1,000,000. A 32-bit key can repeat at different addresses; it is a deterministic variation key, not a unique address encoding. Save the world seed, address, and generator version for reproducibility.

## Walkthrough

- Walk through door openings and furnished lounges, kitchens, dining rooms, studies, and bedrooms.
- Ascend and descend two-flight stairs with intermediate landings and real slab openings.
- Gravity, jumping, wall/furniture blocking, and automatic stair stepping use the same solid shapes as rendering.
- Procedural brick joints, timber, fabric, plaster, window frames, glazing, trim, books, lights, and plants.
- 1280, 1920, and 2560 render widths; sun shadows, local lights, contact lighting, and stationary accumulation.
- PNG export at the actual render resolution.

WASD moves, mouse looks, Shift runs, Space jumps, Esc releases the pointer or pauses fallback controls, R returns to the current entrance, and H hides the interface. World seed and lot address fields let you visit a specific building directly.

## Source and validation

`kernels/building.cu` is the world implementation. `src/engine.js` uses upstream `GpuRuntime`, `src/app.js` handles the browser, and `tools/compile.mjs` produces `generated/`. Upstream is pinned at `d1abd25c32b93d40ce13c7757fccdd0ce6e2f01a`; its MIT license remains in `vendor/cuda-webshader/LICENSE`. Upstream source is unmodified.

```powershell
npm test
```

The Playwright test launches Edge, walks room entrances and stairs at several positive and negative addresses, checks jumping and facade collision, verifies deterministic regeneration, eviction, return, fixed allocation, and matching exterior geometry when a neighboring building becomes the active address. It tests pointer lock, WASD, Escape, Ultra resolution, and stationary accumulation. Full-resolution images and reports are written below `captures/`.

This is a playable procedural architecture prototype with approximate lighting and static furnishings. It is not a full rigid-body simulator. Doors are placed open. Interactive object changes are not persisted. Earlier time/cache experiments remain in `experiments/atomic-time`; their HPP rules have not been applied to FPS gravity. The native draft is archived in `experiments/native-draft`.

If the browser declines mouse capture, walking remains available: use WASD and hold the left mouse button while dragging to look. Escape pauses; clicking the scene resumes. Pointer capture is requested directly from the entry click before GPU work. Run `npm run test:controls` to verify real capture, promise rejection, legacy error events, synchronous rejection, drag looking, input-field focus, pause, and resume in Edge.
