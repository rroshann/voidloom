# Polish Turn 1 — Launcher row refinement

## Inspection (two lenses)

**CEO / Jobs lens (launcher):**
- Every workspace row shows a **permanently bright-red trash icon** — destructive
  action shouting ambiently. Premium apps keep row actions quiet until intent.
- Pencil + trash are **always visible** on every row → clutter; the eye is pulled
  to the red, not the workspace name.
- Row click target is **ambiguous** (clicking a row can hit rename; no "open"
  affordance).

**Power-user lens:**
- No hover feedback on rows; no clear open affordance.
- (Deferred to a later turn: full keyboard navigation ↑/↓/Enter.)

## Spec (this turn)

1. **Hover-reveal actions.** Pencil + trash fade in only when the row is hovered
   (they stay mounted for accessibility, just at ~0 opacity otherwise).
2. **Restrained delete.** Trash is a muted gray by default; it turns red only on
   its own hover — destructive intent, not ambient alarm.
3. **Open affordance.** On row hover the background lifts slightly and a chevron
   appears on the right, signalling "opens on click".
4. Keep all existing behavior: rename inline, delete confirm, open on row tap.

## Verify
- App builds; launcher screenshot shows clean rows (no ambient red), actions on
  hover, chevron affordance.
