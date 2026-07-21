# RDC Window Qualification

## Current policy

The RDC scan first intersects the enabled patterns and then finds the longest
contiguous run of passing sampled tap points for each DQ.

The current RTL parameters are:

```text
P_MIN_WINDOW_POINTS = 4
P_VERIFY_REPEAT     = 3
```

`P_MIN_WINDOW_POINTS` counts scan samples, not physical tap units. With a scan
step of 2, four consecutive samples cover eight tap units. A DQ with no valid
run, or with only 1-3 consecutive samples, is reported in `fail_mask`.

## Center verification

After all enabled DQs have a qualified window, the engine temporarily loads
each selected midpoint and performs fresh MRR/capture reads:

1. Verify the first pattern three times.
2. If dual-pattern mode is enabled, verify the second pattern three times.
3. OR the error bitmap across the repetitions.
4. Any error rejects the candidate and restores the delay values saved before
   the training run.
5. A clean result keeps the midpoint when `apply_best` is enabled; otherwise
   the saved values are restored after verification.

This is a real new capture for every repetition. It does not reuse the prior
scan bitmap and does not change the existing read capture window, beat offset,
WCK timing, or PHY clock structure.

`lpddr5_init` now leaves the initialization wait state unless both
`rdc_train_done` and `rdc_train_pass_all` are asserted. A failed or
unqualified training run therefore cannot be presented as a completed init.

## Simulation coverage

`sim/rdc_train/tb_rdc_train_dual_pattern.v` checks:

- dual and single pattern scans;
- transient scan errors and persistent holes;
- one error during center verification, followed by delay restoration;
- a three-point contiguous window rejected by the four-point minimum.
