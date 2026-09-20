# Exact CUDA region cache: implementation and findings

Implemented and measured on 21 September 2026. The cache is correct in the tested collision model. It reduces computation dramatically on recurring states, but lookup/boundary/storage costs limit speedup. Irregular activity runs faster with uncached temporal blocking.

## Run

```powershell
cd D:\RealisticCity\experiments\atomic-time
.\build-regions.ps1
# Rerun checks without benchmarks:
.\build\region_cache.exe --validate-only
```

`region_cache.cu` is a separate native CUDA executable. It does not modify the original experiments. C++ initializes inputs, launches kernels, checks outputs, and reports timings. The cache, hashing, full-key comparison, collision evolution, writer election, and result publication all run on the GPU. There is no JavaScript. The CMake target is supplied but the tested build path is PowerShell/nvcc.

## Exactness contract

Each output tile is 16 by 16 cells. To advance it K ticks, load a square input patch of width 16 + 2K. The HPP rule transports a particle at most one cell per tick, so this halo contains every possible cause of the tile's state after K ticks, including fixed wall reflections. On a miss, shrink the valid patch by one cell on each side at each substep, and publish only the central tile. Adjacent outputs therefore join exactly without assuming independent rooms.

The key contains every input particle bit and wall bit in the patch plus the horizon. The rule version participates in hashing; the rule is immutable within this executable/cache lifetime. Matching hashes only select a candidate: all patch contents and the horizon must match before reuse. Coordinates and the initial seed are intentionally absent because the local rule is translation invariant and the full current causal state is provided. Identical states in different places can share an entry.

The domain is periodic at its outer coordinate boundary. Room scenarios explicitly encode outer walls, internal walls, and doorways; the synthetic periodic control has no walls. Dimensions must be positive multiples of 16. The current horizon supports 1 through 8 ticks, with shorter final intervals supported.

No input, door, or wall may change during a cached interval. Apply edits at an interval boundary, or split the interval at the edit tick. The next full-state lookup then naturally rejects affected entries; it cannot reuse a result based on the old halo. This is a content-addressed cache, so global invalidation after every local change is unnecessary.

## Race-free cache lifecycle

1. Every tile reads the cache as an immutable snapshot for this batch.
2. Exact hits copy the stored result. Misses compute the shrinking patch.
3. Misses nominate the lowest tile index as writer for their direct-map slot using `atomicMin`.
4. A second kernel publishes one complete key and result per elected slot.
5. The next batch runs after publication in the same CUDA stream.

No tile spins waiting for another block. No block reads an entry while another block overwrites it. Direct-map collisions affect performance, not correctness. Equal misses in the same batch currently compute independently; only subsequent batches can reuse the published entry. This is intentionally simpler than same-batch deduplication or a recursive HashLife tree.

## Benchmarks

RTX 5080, 512 by 512 cells, 256 ticks, K=8, 4,096 direct-map entries. Five repetitions after warmup; medians below are uninstrumented. Every result from every repetition was compared bit-for-bit to ordinary CUDA stepping.

| Scenario | Ordinary stepping | Uncached blocked CUDA | Cache, initially empty | Replay with retained cache | Cold-run hit rate |
|---|---:|---:|---:|---:|---:|
| Quiet rooms | 1.7363 ms | 0.9264 ms | 0.8234 ms | 0.7911 ms | 96.875% |
| Sparse particles in rooms | 1.8719 ms | 0.9266 ms | 1.1391 ms | 1.1102 ms | 37.958% |
| Repeated initial particle pattern in rooms | 1.8324 ms | 0.9262 ms | 1.2752 ms | 1.2619 ms | 0% |
| Dense seeded particles in rooms | 1.6857 ms | 0.9254 ms | 1.3216 ms | 1.3236 ms | 0% |
| Periodic head-on collisions, no walls | 1.8058 ms | 0.9259 ms | 0.7781 ms | 0.8204 ms | 96.875% |

See `region-results.csv` for the machine-readable measurements, update counts, and memory. Replay starts from the same initial world while retaining the cache from the previous trajectory, not a saved final frame. Direct-map replacement means the cache does not necessarily retain every earlier result. Differences of a few hundredths of a millisecond should not be treated as robust trends.

The periodic control is a synthetic active best case: every site alternates between a horizontal and vertical colliding pair. It is not representative of room activity. The repeated initial pattern is another useful control: spatial repetition does not guarantee recurring space-time keys as walls and interactions evolve. This cache also does not deduplicate identical misses within the same batch.

Timing includes host launches, region lookups, computations, claims reset, result publication, and final synchronization. It excludes allocation, world uploads/downloads, and clearing the entire cache before a cold run. Both tiled and cached kernels include the same diagnostic counters; the uncached path skips hashing and key comparison. Ordinary stepping is one launch per tick. Blocked CUDA performs eight ticks per region launch without any cache, so it is the important baseline for isolating the benefit of memoization. These are whole-run timings, not per-tick timings or rendering frame rates.

## Work and memory

Each missed K=8 query computes 4,400 local cell updates, including shrinking halo overhead, to produce 256 final cells. A full uncached blocked run computes 144,179,200 cell updates, compared with 67,108,864 for global single-step evolution. Blocking trades redundant halo work for fewer launches and local shared-memory accesses.

Quiet and periodic cached runs compute only 4,505,600 cell updates, a 96.875% reduction relative to uncached blocking. Sparse activity computes 89,452,000. Repeated/dense runs compute all 144,179,200 plus cache overhead. Avoiding collision arithmetic does not avoid reading, hashing, comparing, and writing region data.

The fixed cache and its bookkeeping occupy 21,049,392 bytes (about 20.07 MiB), allocated even when few entries are useful. Two world buffers add 2 MiB. Each cache entry uses 5,132 bytes: a maximum 1,024-cell key, a 256-cell result, and three metadata words. Local values use 32-bit words even though five bits suffice; packing could reduce storage. Reported memory excludes driver allocations, code, shared memory, and CPU reference vectors.

Cold cache versus blocked CUDA is about 1.13x faster for quiet rooms and 1.19x faster for the synthetic periodic gas. Sparse/repeated/dense cases are slower. The experiment does not show a general speedup from memoizing atomic interactions. An analytic empty-region shortcut may also beat a generic cache on the quiet case; that optimization is not implemented here.

## Correctness checks

- 36 combinations of scene, horizon, and capacity, each checked both initially and after particle/geometry edits against an independent CPU scatter implementation.
- Capacities of 1, 17, and 1,024 entries exercise eviction and heavy slot collisions.
- A particle starting outside a tile crosses into it during the skipped interval; the result must replace the previously cached empty future.
- Deliberately corrupted cache keys retaining their original hashes exercise full-key rejection.
- Zero ticks and changing horizons with retained entries.
- Eight additional random obstacle masks, including boundaries and tile edges, checked against CPU stepping for both blocked and cached CUDA.
- Particle conservation and exact benchmark-output comparison on every repetition.

NVIDIA Compute Sanitizer completed the validation suite successfully with both tools:

```text
memcheck:  ERROR SUMMARY: 0 errors
racecheck: RACECHECK SUMMARY: 0 hazards displayed (0 errors, 0 warnings)
```

These instrumented checks used `--validate-only`; benchmark timings above came from the separate uninstrumented run. Logs are in `build/region-memcheck.log` and `build/region-racecheck.log`. The prototype was tested on one GPU; cross-device testing has not been performed.

The cache supports forward evolution only. It has no gravity, player controller, moving-wall substeps, or rendered building. It provides finite-horizon exact memoization, not arbitrary-time access to a nonlinear world. Time cost still scales with the number of eight-tick batches; there is no recursive composition of large time intervals yet.

## Implication for the building

Use temporal blocking as the current collision baseline. Treat a region cache as optional acceleration for measured recurrence. A future adaptive implementation could avoid cache work in regions that consistently miss, while keeping exact reuse for periodic systems. Neither that policy nor recursive space-time caching is implemented here.

The next research step should address same-batch duplicate queries and cache storage efficiency before attempting longer horizons: a larger halo increases both key size and miss work. This experiment establishes correct causal boundaries and exposes where time savings disappear, which is the prerequisite for evaluating those extensions honestly.
