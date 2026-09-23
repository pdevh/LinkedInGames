# Patches

Build with `./build.sh`. Open LinkedInGames.app and choose Zip or Patches from the library. Both games
use one window; Games (Command–0) returns to the library, Command–1 opens Zip,
and Command–2 opens Patches. Progress and model training remain separate. Existing Zip save files remain compatible.

Draw a rectangle from either corner to its opposite corner. Every rectangle must
contain exactly one clue. A number specifies its area; square, tall and wide
badges specify its proportions. A diamond permits any rectangle. A dot omits
the area constraint. Fill the grid without overlap to win.

Click a patch to remove it. Drawing a new patch around the same clue replaces the
old one if it does not overlap another patch. Undo restores the previous layout,
including after a reset or hint. Invalid attempts preserve the existing layout.
Arrow keys move the cursor; Space or Return selects each corner; Delete removes
the patch under the cursor; Escape cancels a selection.

Hints unlock after 30 seconds of active play, with a 30-second cooldown and a
three-hint limit. A hint removes one incorrect rectangle or places one correct
rectangle. Each hint is reversible and is recorded as assistance.

The timer starts on Play and pauses on window/app inactivity, an explicit pause,
or 30 seconds without input. Resume explicitly to continue. This idle cutoff can
exclude long periods of genuine thinking; active time is an estimate. Progress,
undo history, hint allowance and timing persist independently for each difficulty.
Completed boards stay visible. New puzzle starts another board.

## Generation and learning

Seeded recursive partitions produce a complete tiling. An exact-cover solver
checks uniqueness, with a bounded node budget. Ambiguous partitions are refined;
budget exhaustion is never accepted as proof. Removing area or shape clues is
allowed only when the result remains uniquely solvable.

A pool of 18 candidates spans all three board sizes. Patches has its own seven
regression coefficients: intercept, cell count, clue density, candidate ambiguity,
missing constraints, largest patch fraction, and an ambiguity interaction. A
regularized fit learns observed effort rather than the selected difficulty label.
Effort uses active time per cell, corrected cells, pauses between edits, hints and
resets. Valid completed records are deduplicated and limited to the latest 200;
recency has a 60-game half-life, and hinted examples receive lower weight.

Outcome estimates use leave-one-out residuals weighted by structural similarity,
with a broad weak prior. Selection reuses Zip's conservative Easy utility and
qualification thresholds. Without data, structural distance selects the board;
no cold-start confidence is claimed. If no candidate qualifies, the best available
candidate is used. These estimates require real-player validation, and are not
guaranteed difficulty match rates. Assessments use frozen pre-play boundaries.

Easy generation attempts to omit up to four area or shape constraints, accepting
an omission only if the tiling stays unique. Fresh Easy selection favors 5×5 boards
with at least one omitted constraint and at least two clues that permit multiple
individual rectangles. During the first seven valid solves, selection targets
moderate predicted effort instead of the lowest possible effort. If at least three
of the latest 12 valid Easy solves average effort of 0.8 or more, Easy can draw from
the full pool and prioritize easier outcomes. This retains a gentler path for
players who need it.

Statistics show solved count, median active time, unassisted solves and observed
difficulty matches. History is saved in the existing atomic snapshot and backup;
the optional Patches field preserves compatibility with earlier Zip snapshots.

## Validation

`LinkedInGames.app/Contents/MacOS/LinkedInGames --self-test` runs both games' regression suites.
Patches checks 120 deterministic generated boards with an independent cell-first
tiling oracle; ambiguous/impossible fixtures; budget exhaustion; shape/area and
overlap rules; reproducibility; learning direction, recency, assistance, invalid
records, deduplication, forecast normalization and cold-start uncertainty; and
save compatibility and round trips. Synthetic tests verify behavior, not human
predictive accuracy.

Rules reference: https://www.linkedin.com/help/linkedin/answer/a10314037

## Pointer tolerance and app identity

Patches previews snap only to locally legal rectangles within 22% of a cell of
the pointer. Small edge overshoots and diagonal wobbles keep the last valid preview;
releasing just outside the board also works. Moving farther abandons that preview.
Near-equal alternatives are not guessed, overlap remains forbidden, and snapping
never reads the stored solution. The highlighted rectangle is the one committed.
Keyboard selection remains exact. Regression tests cover reverse drags, outer edges,
corner wobble, deliberate changes, and blocked rectangles.

The app bundle, executable, menus, Dock icon and initial screen are LinkedInGames.
The previous bundle identifier and Application Support/Zip save location are kept
for compatibility with existing progress and preferences. Build renames the prior
Zip.app bundle when needed. The library gives both games equal access; Patches has
an illustrated welcome/resume screen instead of an empty grid.
