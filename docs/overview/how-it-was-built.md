# How it was built

Steam Shelf was built almost entirely by AI models under a human owner's direction, in about a week of sessions,
as a deliberately fully automated experiment. This page records the process so it can be repeated or judged.

## Roles
| Role | Who | What |
|---|---|---|
| Owner | Michael (MSP/IT consultant) | Set the brief, made every taste call ("the whole window should be the bookcase", "hilarious edging on roast"), ran the outward-facing steps (GitHub repo, notarization credentials, releases) |
| Research and design lead | Claude Opus 5.5 | Verified the Steam API live, chose the engine, wrote `history/RESEARCH.md`, `history/ARCHITECTURE-v1-plan.md`, `design/DESIGN.md`, `history/IMPLEMENTATION_PLAN.md`, pinned 18 open questions |
| Implementer | Claude Sonnet 5.5 | Wrote the code in phases from the plans and later specs, running `make` after every package and taking screenshots of the running app to check its own work |
| Reviewer, integrator, later features | Claude Fable 5.1 | Reviewed each hand-back, drove the app with synthetic clicks/drags/swipes to verify behaviour, fixed defects, wrote later specs (`history/PHASE_C…`, `history/PERSONALIZER-spec.md`), implemented the smaller features directly, tuned prompts live against real data |

The owner's standing instruction was: decide everything yourself, pin anything worth revisiting as a question,
build only what is needed. The pinned questions became `decisions/OPEN_QUESTIONS.md` and the worksheet.

## Timeline
| Date | Milestone |
|---|---|
| 2026-09-29 | Plan written; Phase A (models, Steam client, persistence, settings, demo) and Phase B (bookcase, 3D box, label, editor, export) landed the same day; Phase C made the window the bookcase; icon; Sparkle + Developer ID signing; **0.1.0** notarized and published |
| 2026-09-30 | Drag-to-reorder (**0.2.0**); Play/Install with direct launch and trackpad swipes (**0.2.1**); shelf lights tuned over three rounds against reference photos (**0.2.2**); boxes stand behind the plank edge (**0.2.3**) |
| 2026-10-01 | Debug builds signed with Developer ID to stop Keychain prompts; Shelf-Keeper notes: Larian save-file readers, BG3 personalizer, Notes panel, Anthropic client; then any AI service |
| 2026-10-04 | Voice rewritten around comedy craft and tested live; Sonnet 5.5 made the default; app-counted facts so models stop miscounting; save time zone setting after a travelling Mac shifted every clock time |

## What worked
- **Specs with acceptance criteria and gotchas** per work package. Sonnet rarely strayed when the spec said what
  "done" looked like and named the traps (strict concurrency, RealityKit fallbacks, grep under pipefail).
- **Making the implementer look.** Requiring screenshots of the running app, read back as images, caught layout
  problems before review. The reviewer then re-verified with synthesized input (CGEvent clicks, drags, phased
  scroll gestures) and screenshots at several window sizes.
- **Reference implementations in Python first.** The Larian format readers were prototyped and verified against
  118 real saves in Python, then ported to Swift against synthetic fixtures; the port matched the reference on the
  real data in 0.11 s.
- **Testing prompts on real data, checking every claim.** Each prompt revision was run live and every number in the
  output was checked against the extracted data. Two kinds of error showed up and were fixed structurally: a model
  guessing what a player-typed word meant (now a rule), and models miscounting (now the app counts).

## What to watch for
- Timestamps follow the Mac's time zone; save files carry none. A travelling Mac silently moved every save by two
  hours until a setting was added.
- The auto-mode safety classifier blocks some outward-facing or security-relevant actions for the AI (creating public
  repos, running the release script, removing the sandbox). Those steps are documented for the owner to run.
- Sandbox + Sparkle + Developer ID has several traps (nested helper signing, XPC entitlements, hardened runtime and
  test injection). They are all captured in `architecture/distribution.md`.

## Continuing the work
1. Read `architecture/overview.md`, then the page for the subsystem you are changing, then its reference pages.
2. Check `decisions/OPEN_QUESTIONS.md` for the decision behind what you are about to change.
3. Keep `make` green with zero warnings; add a test for pure logic; never commit real save data or keys.
4. Record the decision and its date in `decisions/OPEN_QUESTIONS.md`; update the affected architecture page.
5. Ship with `scripts/release.sh X.Y.Z`.
