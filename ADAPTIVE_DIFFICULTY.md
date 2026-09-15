# Automatic personalized difficulty

Playing is the only input required. Completed games are archived locally, then a
background fit updates the model. The next generated board uses the latest history.
The model is reconstructed from saved telemetry on launch, so adaptation survives
restarts. Existing in-progress boards are not replaced when the fit changes.

## What is learned

The requested Easy/Medium/Hard label is never the training target. The target is
observed effort: active time per cell, backtracked cells, pause count and duration,
hints, and resets. Fast, unassisted solves with little hesitation receive low effort
labels, regardless of which button originally produced the board. Hints increase
effort while reducing that example's confidence, because assistance changes play.
Elapsed time while inactive or paused is excluded. A recorded pause is a proxy for
hesitation, not proof that the player was thinking about the puzzle.

The original ten coefficients (intercept plus nine normalized structural features)
are retained, with three additional interactions:

- Solution turns × junction cells.
- Maximum checkpoint gap × checkpoint detour.
- Walls × clues.

Thirteen coefficients fit a regularized regression of effort relative to the initial
structural prior. A direct Cholesky solve replaces 250 gradient-descent passes.
The prior fades into the fitted prediction over the first eight valid solves.
Recent evidence has a half-life of 60 valid games; at most 200 valid games are used.
Skipped games, incomplete telemetry, invalid numeric data, and duplicate record IDs
do not become training examples. Stored summary values are recalculated from raw
telemetry before fitting. Compatible stored puzzle features are reused.

## Choosing boards

Generate 18 unique-solution candidates across all three grid sizes using three
workers. Score the candidates once and sort them. Easy uses the lowest third,
Medium the middle third, and Hard the highest third. Within each band, choose the
candidate nearest the player's recent effort target (15th/50th/85th percentile).
Targets gradually become personal over 20 valid games. Previously played solution
paths in the existing exclusion list are filtered out.

The bands separate predictions within a candidate batch. They cannot guarantee
actual difficulty across independently generated batches. Players differ, features
omit some relevant puzzle properties, and all available candidates may be easy for
an experienced player. Learned predictions should improve with representative play;
perfect difficulty classification requires evidence from real play and is not
promised. Skips are deliberately not interpreted as difficulty: a skip alone does
not reveal whether a board was too easy, too hard, or interrupted.

## Performance

Local optimized-build medians measured during this change:

| Operation | Before | After |
| --- | ---: | ---: |
| Fit 200 records | ~8.5–9 ms | ~0.54 ms |
| Predict one board | ~0.038 ms | ~0.009 ms |
| Select among 18 candidates | ~25.8 ms | ~6.4 ms |

These are microbenchmarks, not UI latency guarantees. Baseline fitting used repeated
examples with the old model; final fitting used 200 distinct record IDs across 30
boards. Candidate generation is random. The final parallel selection was also
compared with the same implementation run serially (~12.1 ms).

Connectivity features now check four neighbors per cell. Uniqueness searches use
bitsets without per-node frontier arrays. Each puzzle uses a local random generator
seeded once from system randomness, avoiding thousands of system-random calls and
permitting deterministic tests. Generator version is 3; classifier version is 2.

## Validation

Run:

```sh
./build.sh
Zip.app/Contents/MacOS/Zip --self-test
```

The suite covers 512 wall configurations against the original uniqueness solver,
including exhausted budgets; 30 reproducible seeded puzzles checked by the original
solver; feature equivalence; 300 generated-puzzle and persistence checks; observed
effort overriding requested labels in both directions; first-solve learning; recent
skill changes; hints; invalid/duplicate/incomplete data; skipped-record filtering;
restart persistence; candidate ordering; and the direct solve's optimality.
Synthetic telemetry checks establish algorithm behavior, not real-player predictive
accuracy. No changes to real player history are made by the tests.

## Post-solve assessment

After solving, an in-app toast reports “This puzzle was easy/medium/hard for you”
for six seconds. The assessment compares measured effort with the midpoints between
the model's pre-solve targets. The requested difficulty and original prediction do
not determine this verdict. It is saved with the completed record. Incomplete or
invalid telemetry receives an honest “Still learning” message instead of a guessed
rating. The toast does not block proceeding, respects Reduce Motion, and announces
its message to assistive technology.
