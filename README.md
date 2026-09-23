# LinkedInGames

A native macOS puzzle collection with Zip and Patches, a shared game library,
trackpad haptics, persistent progress, and personalized difficulty.

- **Zip:** connect the numbered checkpoints in order and visit every square.
- **Patches:** fill the board with rectangles that match each clue's area and shape.
- **Personalization:** separate game histories learn from active play time,
  corrections, hesitation and assistance. Difficulty forecasts are estimates.
- **Controls:** drag to play; Patches tolerates small pointer overshoots. Undo,
  reset, keyboard selection, pause/resume and timed hints are available.

## Run

Download and unzip the macOS app from Releases, then open `LinkedInGames.app`.
The provided build is for Apple Silicon and requires macOS 13 or later. It is
ad-hoc signed, not Apple-notarized. Updater-enabled releases check GitHub
Releases and prompt before installing new signed versions. See
[update and release instructions](UPDATES.md).

## Build and test

With the Xcode command-line tools installed:

```sh
./build.sh
LinkedInGames.app/Contents/MacOS/LinkedInGames --self-test
open LinkedInGames.app
```

The build uses Swift, AppKit, and the pinned Sparkle updater framework.
Releases are built and uploaded manually; no CI/CD is configured.

Command–0 opens the game library, Command–1 opens Zip, and Command–2 opens Patches.
Both games run in one window. Existing Zip progress remains compatible: the
original bundle identifier and `Application Support/Zip/progress.json` location
are retained.

See [Patches implementation and controls](PATCHES.md) and
[Zip's adaptive difficulty model](ADAPTIVE_DIFFICULTY.md) for details.

This is an independent implementation, not an official LinkedIn app.
