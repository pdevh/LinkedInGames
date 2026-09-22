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
telemetry before fitting. Compatible stored puzzle features are reused. Historical records remain readable.

## Outcome probabilities and choosing boards

Classifier version 3 retains the effort regression and adds a conditional outcome
forecast. It estimates Easy/Medium/Hard probabilities by comparing predicted effort
plus historical leave-one-out regression residuals with the pre-play assessment
boundaries. Similar puzzle structures receive more weight; the same recency and
assistance weights used for fitting also apply to these residuals. Smoothing scales
with the player's target spacing. A broad weak prior prevents sparse or unfamiliar
structures from receiving unwarranted certainty. These are model estimates; their
calibration must be evaluated on future games.

Generate the original 18 candidates across all three grid sizes. Select across the
whole pool by outcome probability, rather than constraining each button to one
third. Easy prioritizes its Easy probability and penalizes Hard surprises three
fold. A candidate qualifies for Easy at estimated P(Easy) >= 85% and P(Hard) <= 5%.
Medium and Hard use 70% for their requested outcome. Qualifying candidates outrank
nonqualifying candidates, then expected utility decides among them.

When the initial pool does not qualify, generate up to three additional batches of
six candidates. For Easy these are 5×5 boards with maximum checkpoint gaps of 4,
3, then 2, and respectively 25%, 50%, then 75% of remaining off-solution edges
blocked. Added clues retain existing checkpoints in order. Both changes only add
constraints, preserving the base puzzle's unique solution. Generator version is 4.
Medium and Hard expand with additional boards of their respective generator preset.
Previously played paths remain excluded.

The search is bounded at 36 candidates in normal operation. If no candidate
qualifies, return the candidate with the best utility; do not claim that its target
was met. New structures require real play before their probabilities can be
validated. Every completed, valid game updates subsequent fits automatically.

Each new game stores its predicted outcome probabilities and its pre-play targets.
The post-solve toast uses those saved targets even after a restart or playing other
levels. The effort formula is unchanged. Older games without saved targets retain
the previous fallback assessment behavior. Skipped games remain excluded from fit.

## Performance

Historical optimized-build medians for classifier version 2 (not version 3):

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
permitting deterministic tests. Those measurements used generator version 3 and classifier version 2.

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

## Version 3 validation

New regression coverage checks probability normalization, uncertainty with no data,
reliable versus mixed outcomes, recent skill changes, forecast persistence, frozen
pre-play assessment boundaries, and guided-board uniqueness using the independent
reference solver. Synthetic success is not evidence of a real-player match rate.

A chronological replay of the available 83 valid solves, with the first 20 used
as initial history, provides an offline prediction check. It cannot establish the
match rate of newly generated guided boards: those boards have not yet been played.
The 85% Easy and 5% Hard thresholds are selection targets, not measured achievements.
