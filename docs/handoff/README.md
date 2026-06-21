# Handoff Prompts

Each file in this directory is a **session starter prompt** for implementing a phase.
Copy the file contents into a fresh Devin session to begin work.

## Usage

1. Start a new Devin session (fresh context).
2. Paste the contents of the relevant handoff file as your first message.
3. The agent reads the docs, invokes the right skills, and starts picking off issues.

## Files

| File | Phase | When to use |
|------|-------|-------------|
| `phase-0-start.md` | Phase 0 — Platform Foundation | Starting the project skeleton + tooling |
| `phase-1-start.md` | Phase 1 — ES + MX Vertical Slice | After Phase 0 issues are merged |
| `phase-2-start.md` | Phase 2 — Resilience & Production Hardening | After Phase 1 issues are merged |

## Creating future handoffs

Copy `phase-0-start.md` as a template. Update:
- The "Read these first" section (add any new docs created during the phase)
- The "Skills to use" section (add any new skills that became relevant)
- The "Key decisions already made" section (append decisions from the just-completed phase)
- The "Start" section (point to the right milestone/issues)
