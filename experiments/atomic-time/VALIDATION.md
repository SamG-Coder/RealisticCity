# Validation record

Run on 21 September 2026, Windows, NVIDIA GeForce RTX 5080 (compute capability 12.0), driver 616.64, CUDA 13.3, MSVC 14.51.

`./build.ps1` completed successfully. The native executable passed 162 CPU-reference CA comparisons, GPU/CPU seeded initialization, a nonlinear-rule witness, sparse distant-time queries, large-time composition, UINT64_MAX time handling, HPP forward/inverse/conservation checks in periodic and walled domains, and exact hard-rod comparisons against an independent event-driven CPU oracle.

Uninstrumented benchmark medians over five repetitions:

| Case | Full-grid CUDA passes | Time |
|---|---:|---:|
| 65,521 cells, 8,191 ticks, explicit stepping | 8,191 | 47.0214 ms |
| Same input and final time, exact jump | 13 | 0.0828 ms |
| Same cell count, tick 1,152,921,504,730,303,765 | 17 | 0.0914 ms |

The first two outputs were compared exactly on every benchmark repetition. Their observed ratio is approximately 568x. Both paths use the same simple CUDA stencil, with a launch per step or per jump; this includes the benefit from fewer launches. It does not compare against an optimized persistent stepper or include allocation/uploads/downloads.

The distant-time measurement is for the conjugated linear CA, not the HPP collision solver. It is not validated by stepping 10^18 times. See README for the independent oracle and composition checks.

CUDA memory validation also passed:

```text
compute-sanitizer --tool memcheck --error-exitcode 9 --log-file memcheck.log ./atomic_time.exe
========= COMPUTE-SANITIZER
========= ERROR SUMMARY: 0 errors
```

The sanitizer was run from the build directory; its instrumented timings are separate from the uninstrumented results above. This was a memory check, not a claim of cross-device numerical validation or a full performance profile. The CMake build route was not exercised.
