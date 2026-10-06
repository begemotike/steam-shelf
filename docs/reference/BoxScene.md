# BoxScene

Path: [`Sources/Views/BoxScene.swift`](../../Sources/Views/BoxScene.swift) (237 lines)

The 3D box. It is not a SceneKit scene (SceneKit is soft-deprecated); it is a small RealityKit scene shown through `RealityView`. The file holds the per-frame motion state (`BoxMotion`), the builder that turns three textures into a six-plane box (`BoxBuilder`), and the SwiftUI wrapper that creates the scene, lights, camera, drag gesture and back-texture hot swap (`BoxStageView`). `OpenBoxView` supplies the textures and drives `BoxMotion`.

## Depends on / used by

- Depends on: RealityKit, SwiftUI, AppKit, OSLog, [ArtGenerator](ArtGenerator.md) (`SendableImage`).
- Used by: [OpenBoxView](OpenBoxView.md) (creates `BoxMotion`, embeds `BoxStageView`).

## `BoxMotion`

`@MainActor final class BoxMotion`; deliberately **not** `@Observable` because it is mutated every frame and no view should re-render from it.

| Property | Meaning |
|---|---|
| `yaw`, `pitch`, `yawVelocity`, `pitchVelocity` (`Float`) | Current rotation (radians) and drag-release inertia. |
| `isDragging`, `lastTranslation` | Drag bookkeeping (`lastTranslation` is the previous cumulative drag translation, used to compute per-event deltas). |
| `time: Double` | Seconds since presentation; drives the idle bob/drift. |
| `targetYaw: Float?` | When set, yaw springs toward it (flip, arrow keys, return to front). |
| `subscription: EventSubscription?` | The `SceneEvents.Update` subscription. |
| `backEntity: ModelEntity?` | The back-face entity, kept so its texture can be swapped. |
| `rootZ`, `idleEnabled`, `springRate` | Root offset along -Z (0, because the explicit camera is honoured), idle on/off (off under Reduce Motion), spring rate (8, 14 when returning). |

| Member | Behaviour |
|---|---|
| `isFacingFront` | `cos(yaw) > 0`. |
| `isSettled` | No target, `|yaw| < 0.02`, `|pitch| < 0.02`, `|yawVelocity| < 0.05`. `OpenBoxView` polls it (up to 0.6 s) before the return animation. |
| `reset()` | Zeroes motion, clears target, idle off, spring rate 8. |
| `flip()` | Zeroes velocity and sets `targetYaw` to the nearest "back" angle (`pi` plus a multiple of 2 pi) if facing front, else the nearest front angle. |
| `showBack()` | Flip only if currently facing front (used when opening the editor or notes). |
| `rotate(by:)` | Adds `delta` to the target (or current yaw); used by the left/right arrows (quarter turns). |
| `returnToFront()` | Target nearest multiple of 2 pi, spring rate 14. |
| `step(dt:root:)` | Per frame (dt clamped to 0.05 s): if not dragging, spring yaw toward `targetYaw` (snap within 0.002), else integrate velocity with decay `0.04^dt`; pitch has the same decay and a restoring pull toward 0; pitch clamped to +-0.45. Idle: blend-in factor `idleBlend` (rate 5) gives a 6 mm vertical bob (period 3.2 s) and 2.5 degree yaw drift (period 7 s) only when idle is enabled, not dragging, no velocity and no target. Writes `root.orientation = pitch(x) * (yaw + drift)(y)` and `root.position`. DEBUG logs an fps estimate every 2 s. |

## `BoxBuilder`

`@MainActor enum BoxBuilder` (RealityKit entity APIs are main-actor isolated in the macOS 26 SDK).

| Member | Behaviour |
|---|---|
| `width`, `height`, `depth` | 0.20, 0.30, 0.044 metres; the depth is 22% of the width, a chunky collector's box (Q15). |
| `material(_:roughness:clearcoat:) -> PhysicallyBasedMaterial` | Base colour from a texture, metallic 0, given roughness, optional clearcoat. |
| `edgeMaterial(_ color: Color)` | Tinted PBR, roughness 0.7. Used for top and bottom faces (spine colour). |
| `makeBox(front:back:spine:edge:) -> Entity` | Six single-sided planes (plane meshes face +Z; each is rotated to face outward): `front` at +D/2 (roughness 0.35, clearcoat 0.6, the "shrink-wrap" look), `back` at -D/2 rotated pi about Y (roughness 0.6), `right` and `left` (width D, rotated +-pi/2 about Y, the spine texture), `top` and `bottom` (rotated -pi/2 and +pi/2 about X, edge material). Entities are named `front`, `back`, ... so the back can be found later. |

## `BoxStageView`

`struct BoxStageView: View` with `front`, `back`, `spine: SendableImage`, `spineColor: Color`, `backVersion: Int`, `motion: BoxMotion`, `onReady: @MainActor () -> Void`.

| Aspect | Behaviour |
|---|---|
| Scene build (`RealityView` make closure) | Root entity `boxRoot`; `PerspectiveCamera` field of view 30 degrees at (0, 0, 0.85); key `DirectionalLight` intensity 2800 from (-0.5, 0.7, 1.0); fill light 900 from (0.8, -0.1, 0.6). Textures are created with `TextureResource(image:options:)` (colour semantic, mipmaps `.allocateAndGenerateAll`); a failure is logged and the stage stays empty. `motion.backEntity` is set, the box added, `SceneEvents.Update` subscribed to `motion.step`, then `onReady()` is called (OpenBoxView waits for it before cross-fading from the flyer). |
| Drag | `DragGesture(minimumDistance: 2)`: on first change sets `isDragging`, clears target and velocity; each change adds `dx * 0.012` to yaw and `dy * 0.008` to pitch (clamped); on end stores release velocity (`velocity * 0.012` and `* 0.008`) for inertia. |
| `.task(id: backVersion)` | When `backVersion > 0`, rebuilds a `TextureResource` from the *current* `back` image and replaces the back entity's material. This is how label edits appear on the 3D box without rebuilding the scene. |
| `.onDisappear` | Cancels the subscription. |

## Concurrency

Everything is `@MainActor`. `SendableImage` crosses from the caller into texture creation. `BoxMotion.step` is called on the main actor from the scene update event, so no locking is needed.

## Gotchas

- On macOS 26, RealityKit honoured the explicit `PerspectiveCamera` and composited transparently over SwiftUI; the fallbacks considered in the plan (root at z, backdrop) were not needed ([Phase B notes](../decisions/OPEN_QUESTIONS.md#implementation-notes-phase-b)).
- `Theme.Metrics.frontFaceFill` (0.628) is the measured size of the front face for these camera values; changing the camera or box size requires re-measuring it.
- The `update:` closure of `RealityView` is intentionally empty; all changes are applied through `motion` and `.task`.

## See also

[Open box](../architecture/open-box.md), [Design spec](../design/DESIGN.md) (section 7.3).
