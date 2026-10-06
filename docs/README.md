# Steam Shelf — documentation map

Steam Shelf is a native macOS app that shows a Steam library as game boxes on a skeuomorphic wooden bookcase.
Click a box and it lifts off the shelf as a 3D object you can spin; the back carries your rating, hours,
achievements, a note, and (optionally) AI-written "Shelf-Keeper" notes drawn from the game's own save files.

This folder is written for an engineer or an AI reviewer who has never seen the project. Read top-down:
each level links to the next.

## 1. Start here
| Page | What it answers |
|---|---|
| [overview/product.md](overview/product.md) | What the app does, feature by feature, and what it deliberately does not do yet |
| [overview/build-and-run.md](overview/build-and-run.md) | Toolchain, `make` targets, demo mode, tests, how to ship a release |
| [overview/how-it-was-built.md](overview/how-it-was-built.md) | The process (plan → implement → review), the timeline, and how to keep working this way |

## 2. Architecture (one page per subsystem)
Start with [architecture/overview.md](architecture/overview.md); it gives the module map and a reading order.

| Page | Subsystem |
|---|---|
| [architecture/overview.md](architecture/overview.md) | Module map, launch modes, where state lives, the main-actor rule |
| [architecture/app-and-state.md](architecture/app-and-state.md) | `AppModel`, the `ShelfDocument` schema, pagination, arrangement, persistence, export/import |
| [architecture/shelf-rendering.md](architecture/shelf-rendering.md) | The bookcase: layout math, textures, lights, handles, swipes, drag-to-reorder |
| [architecture/open-box.md](architecture/open-box.md) | The opened box: flight animation, RealityKit box, back label, editor, Play/Install |
| [architecture/steam.md](architecture/steam.md) | Steam Web API client, cover art CDN paths, image cache |
| [architecture/personalizer.md](architecture/personalizer.md) | Per-game save-file readers (Baldur's Gate 3), Larian formats, folder access, time zone |
| [architecture/ai-writer.md](architecture/ai-writer.md) | The Shelf-Keeper: prompts, two wire formats, provider presets, model listing, cost |
| [architecture/distribution.md](architecture/distribution.md) | Signing, sandbox entitlements, Sparkle updates, the release script, the icon |

## 3. Reference (one page per source file)
[reference/](reference/) holds a page for every Swift file under `Sources/`, plus `Tests.md`, `scripts.md` and
`tools-bg3.md`. Each lists every type and function with its signature, isolation and gotchas. Architecture pages link
to the reference pages they cover, and vice versa.

## 4. Design
| Page | |
|---|---|
| [design/DESIGN.md](design/DESIGN.md) | The visual and interaction spec: palette, geometry, shadows, motion, back label, settings. Sections marked as superseded point at the later decision. |

## 5. Decisions
| Page | |
|---|---|
| [decisions/DECISIONS.md](decisions/DECISIONS.md) | The consolidated decision log: what was chosen, why, and what it would cost to change |
| [decisions/OPEN_QUESTIONS.md](decisions/OPEN_QUESTIONS.md) | The running log kept during development: 23 pinned questions with their defaults, plus dated implementation notes per feature |
| [decisions/steam-shelf-questions.xlsx](decisions/steam-shelf-questions.xlsx) | The same questions as a worksheet with dropdowns (and a `.csv` twin) |

## 6. History (original plans, kept verbatim)
These were written before or during implementation and are **partly superseded**; the architecture pages describe
the code as it is. They are kept because they explain the reasoning at the time.

| Page | |
|---|---|
| [history/RESEARCH.md](history/RESEARCH.md) | Steam API verification, CDN art paths, engine choice research |
| [history/ARCHITECTURE-v1-plan.md](history/ARCHITECTURE-v1-plan.md) | The first architecture plan (file list, types, project.yml) |
| [history/IMPLEMENTATION_PLAN.md](history/IMPLEMENTATION_PLAN.md) | Phase A/B work packages with acceptance criteria |
| [history/PHASE_C-full-bleed-case.md](history/PHASE_C-full-bleed-case.md) | The "window is the bookcase" redesign spec |
| [history/PERSONALIZER-spec.md](history/PERSONALIZER-spec.md) | The Shelf-Keeper notes spec the implementation was built from |

## Conventions
- Paths in docs are relative to the repository root unless they start with `../`.
- "du" in the design spec means design units at the reference box height of 180 pt; everything scales with `shelfScale`.
- Never commit real save data, Steam IDs or keys. The repository is public.
