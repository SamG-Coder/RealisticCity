# Research notes: seed, address, time, and atomic dynamics

Research date: 21 September 2026. These are primary papers, not claims that ordinary 3D physics has a general closed-form solution. No claim about the fundamental discreteness of the real universe is needed for this software design.

Follow-up: finite-horizon memoization of nonlinear HPP collision regions is now implemented and measured in [REGION-CACHE.md](REGION-CACHE.md). This is a GPU region cache with exact causal halos, not the recursive HashLife algorithm.

## Papers with direct relevance

### Cristopher Moore — Quasi-Linear Cellular Automata

[Paper, arXiv submission 1997](https://arxiv.org/pdf/adap-org/9701001), particularly section 3 and its finite-ring polynomial scaling argument.

Additive cellular automata admit exact scaling identities. Certain broader algebraic rule families also support faster prediction. The paper distinguishes serial work from idealized parallel depth: logarithmic depth may use a number of processors that grows with the requested light cone. Our fixed finite ring uses the characteristic-two identity to apply one whole-grid pass per set time bit. That bound is derived for this implementation, not taken as a blanket guarantee for every CA in the paper.

### Cristopher Moore and Timofey Pnin — Predicting Non-linear Cellular Automata Quickly by Decomposing Them into Linear Ones

[Full paper](https://arxiv.org/pdf/patt-sol/9701008). The PDF names both authors, although some abstract/search metadata only names Moore. The arXiv submission is 1997; the served PDF prints a later 2018 date.

The authors give efficiently predictable nonlinear families using quasidirect decompositions and group structure. This is evidence that nonlinearity alone does not rule out shortcuts. It is not a general theorem about arbitrary nonlinear mechanics. Our local nonlinear relabelling is a simpler demonstration of cancellation under conjugacy, not a replication of those constructions. Implementing a genuinely non-Abelian example from this paper is a worthwhile separate experiment.

### R. Wm. Gosper — Exploiting Regularities in Large Cellular Spaces (1984)

[Publisher and DOI](https://doi.org/10.1016/0167-2789(84)90251-3) · [Full paper mirror](https://gwern.net/doc/cs/cellular-automaton/1984-gosper.pdf).

This is the closest conceptual match to random access in space and time. The algorithm compresses repeated spatial configurations and caches their evolution. It exploits structure rather than requiring an explicitly linear law. Previously computed equivalent subproblems can be reused exactly. This needs memory and useful repetition; it is not a universal constant-time predictor. A small seed generating high-entropy-looking states does not imply abundant repeated evolved blocks. We researched this route but have not implemented it in the prototype.

### Norman Margolus — Crystalline Computation (1998 preprint)

[Paper](https://arxiv.org/pdf/comp-gas/9811002), especially the four-channel HPP discussion around printed pages 20–22.

Finite-state local models can have exact invertibility and conservation laws. The paper explains particle streaming and head-on scattering, which directly motivates our HPP kernel. It also identifies the four-direction model's lack of isotropic hydrodynamics. Invertibility reconstructs previous states but does not establish fast-forwarding. Our wall bounce-back is an added fixed-boundary construction tested by exact inversion.

### Singh, Dhar, Spohn, and Kundu — Thermalization and Hydrodynamics in an Interacting Integrable System: The Case of Hard Rods (2024)

[Published paper](https://link.springer.com/article/10.1007/s10955-024-03282-z) · [Preprint](https://arxiv.org/abs/2310.18684).

The microscopic hard-rod mapping provides a concrete interacting physical example: remove rod spacing, represent equal-mass collision dynamics with noninteracting trajectories, and restore order/spacing. We use that mapping with reflecting boundaries and a restricted velocity set to produce exact integer-time position queries. The prototype does not implement the paper's hydrodynamic approximation or thermalization study. This route is stronger evidence for skipping actual collisions than a visual cellular pattern alone, but depends on the special one-dimensional equal-mass system.

### Aleksandar Donev — Asynchronous Event-Driven Particle Algorithms

[Author's paper](https://math.nyu.edu/inmemoriam/donev/DSMC/AED_Review.pdf).

Event-driven algorithms advance between changes rather than using uniform small timesteps. They can combine asynchronous and synchronous evolution. This is a practical fallback for interactions that lack algebraic shortcuts, not evidence that every intermediate collision can be eliminated. We used an elementary event-driven rod simulator as an independent correctness oracle, not a reproduction of Donev's framework.

## Translation into a building engine

Proposed query:

```text
evaluate(buildingSeed, stableObjectAddress, tick, rulesVersion, inputBranch)
```

1. Regenerate immutable structure and initial conditions from the stable address.
2. Use proven direct-time laws for independent or integrable motion.
3. Use exact algebraic jumps only for fields whose actual rules support them.
4. Reuse exact space-time blocks when initial state, rule, time phase, and causal boundary conditions match. Use full-key equality checks; a hash collision must never substitute another physical result.
5. Resolve remaining coupled events or ticks explicitly, retaining optional acceleration checkpoints.

If a boundary changes, invalidate every cached answer causally dependent on it. A wall, doorway, player action, or gravity field may invalidate the assumptions behind a shortcut. A shader must not use the jump rule outside those assumptions and merely call the result deterministic.

A complete building still requires connected geometry, a stable collision representation, a player controller, and persistence of external inputs. The original seed can determine all autonomous evolution; arbitrary later human actions require input records or an expanded description. Reversible dynamics can retain information in the evolving microstate, but a fixed small hash alone cannot encode an unlimited arbitrary input history losslessly.

## Most useful next research question

Can a finite room use exact memoized evolution for quiescent/repeated regions while a small active region handles novel interactions, without the memory and boundary-bookkeeping costs exceeding ordinary simulation?

Measure end-to-end work, memory, and correctness for sparse versus dense activity. Do not infer performance from seed size. Do not infer physically realistic gravity or rigid contacts merely from reversibility. The present experiments establish exact shortcuts in selected systems and a reversible collision substrate on CUDA; combining them into useful building physics remains open engineering work.
