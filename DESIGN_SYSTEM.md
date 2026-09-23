# Game screen design system

Use `GameUIStyle` for shared AppKit chrome. Each game owns its board artwork and rules.

## Shell

- One 660-point-wide window with a transparent, full-size title bar.
- Background: neutral 0.965 white. Title: 22-point bold at the same left inset.
- Header order: compact back chevron, game title, difficulty picker. Back and title share a vertical center.
- Keep Patches instructions in its clue artwork: proportions indicate shape; four edge tabs indicate any rectangle. Below the board: live status and elapsed time.
- Bottom controls share one baseline: Reset, Undo, Hint on the left; Statistics, New puzzle aligned right. Patches adds a compact Pause/Resume icon at the start of the same row. Keep learning diagnostics in Statistics.
- Statistics opens inside the same window. Use a back control, summary cards, and concise explanations; keep each game's data separate.

## Controls

- Shared actions use `GameUIStyle.button`: 34-point height, 10-point corner radius, 14-point semibold text, white fill and dark ink.
- `New puzzle` uses the shared red accent. Disabled actions retain their position.
- Difficulty uses `DifficultyPicker` in both games. Timer uses monospaced digits.
- Use the same words for identical actions, including `New puzzle`.

## Future additions

Add common controls and colors to `GameUIStyle` first, then use them in both screens. Keep board colors and puzzle-specific guidance local to the game.
