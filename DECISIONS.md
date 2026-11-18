# Decisions

Log of deviations and ambiguous design/implementation decisions with their rationale (per `AGENTS.md`).

## 2026-11-19 — Design brief: dark-first native brand shell

**Decision.** Rework `docs/DESIGN_BRIEF.md` away from strict native minimalism toward a **dark-first native brand shell**, following the system appearance. The established fjord/bronze/gate world is expanded into the UI, not replaced.

**Why.** The previous brief confined the brand (fjord/bronze/bone) to the icon, illustrations and About, while the app UI itself was stock neutral gray (dark bg `#1b1e25`). The product did not feel Norse in use. The owner asked for a less minimalist brief with an accent on the dark theme.

**Approach chosen (owner-approved).**

- Brand layer inside a native frame: native controls (`Form`/`List`/`MenuBarExtra`), status clarity and accessibility stay intact.
- Follow system appearance, **dark-first**: dark is the primary design target and the reference for mockups; light is a full adaptation. Dark is not forced.

**What changed in the brief.**

- Dark shell is fjord-tinted, not neutral gray: bg `#0E1F26`, surface `#1C333D`, chrome `#14252D`, control `#24404B`, separator `#2E4A52`.
- Bronze enters the UI as an identity accent (header gate-line, status-pill rim, selected-tab indicator, frozen-row "waiting" rim). It is never used for text, status meaning, or the primary button.
- Primary action stays the project action blue (`#1B5EC4` light / `#2865C6` dark); semantic status colors use contrast-safe dark tonal variants (`#88DDB1` / `#FFC784` / `#FFA1AF`).
- Gradient ban relaxed: soft tonal fjord gradient allowed on the shell and onboarding/About hero illustrations and the icon metal; never on controls, statuses or text. No neon/glow/glassmorphism.
- Richer hero moments: onboarding step 1 and About get a larger fjord gate illustration and a 22–24 pt SF Pro Display hero title; empty states get a small illustration; the 24-tick ornament recurs as a divider.
- Sections revised: intro, §3, §4, §7, §10 (visual language + new shell tokens), §11, §12, §13, §14, §15.

**What stays (product truth).** Scope, IA, state model, interactions, copy keys, EN/RU, native controls, one-click `Resume all`, semantic color redundancy, and all accessibility requirements (4.5:1 text, 3:1 non-text, 28 pt targets, keyboard, VoiceOver, Increase Contrast / Reduce Transparency / Reduce Motion).

**Contrast verified.** Proposed dark tokens were checked: text/bg 15.5:1, muted/surface 6.5:1, bronze/bg 7.4:1, control-line/control 3.26:1, white/action 5.6:1, semantic variants ≥6.9:1 on surface.

**Follow-up (completed).** The [Doop canvas](http://localhost:4300/c/2lgrE5QsCb?page=VhQCHx-t4F), the 15 offline HTML references, `DESIGN.md` and the handoff now use the dark-first shell. Light status fills use 4% tint to keep the bronze rim at 3:1 or better. Settings rails use the control boundary token at 28 pt hit height. Four app rows fit before internal scrolling. All 280 Doop prototype interactions were preserved.
