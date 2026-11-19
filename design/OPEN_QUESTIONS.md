# Open questions

All resolved by owner decisions during the v1 specification blitz (2026-11-19). See `DECISIONS.md` and the specification (`docs/superpowers/specs/2026-11-19-no-halla-v1-spec.md`).

- **Grace range.** RESOLVED (D24): config and slider use 0–120 s, default 5 s. Deviates from the mockup's 0–60 s; owner-approved and recorded in `DECISIONS.md`.
- **Cancel during grace.** RESOLVED (D25): Cancel triggers an immediate re-check → `checking`, with no hidden indefinite bypass; if the IP is still disallowed the countdown restarts.
- **Repository link.** RESOLVED (D26): the About Repository row is hidden until a real repository URL exists; `ui.repository` is unused.

Additional builder-check decisions: reachability of `disabled` → D27 (master Protection toggle); unverifiable IPv6 policy → D28 (unknown, lattice composition); missing/parameterized strings → D22 (additive copy.json); language switch without relaunch → D12; Esc in MenuBarExtra → D23 (best-effort).