# SwipeMonitor

Path: [`Sources/Views/SwipeMonitor.swift`](../../Sources/Views/SwipeMonitor.swift) (50 lines)

Turns horizontal trackpad and Magic Mouse swipes into page turns using an AppKit local event monitor, because SwiftUI has no first-class API for the "Swipe between pages" gesture. It handles the two paths macOS provides, matching the system preference: scroll-wheel events with gesture phases (two-finger swipe, one finger on Magic Mouse), and three-finger `.swipe` events.

## Depends on / used by

- Depends on: AppKit.
- Used by: [ShelfView](ShelfView.md) (`@State swipes`, started in `.onAppear`, stopped in `.onDisappear`).

## `SwipeMonitor`

`@MainActor final class SwipeMonitor`; private state `monitor: Any?`, `accumulated: CGFloat`, `firedThisGesture: Bool`, constant `threshold = 60`.

| Signature | Behaviour |
|---|---|
| `func start(in window: @escaping @MainActor () -> NSWindow?, enabled: @escaping @MainActor () -> Bool, handler: @escaping @MainActor (Int) -> Void)` | Calls `stop()` then installs `NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe])`. Events are ignored (returned untouched) unless the event's window is the target window and `enabled()` is true. `handler(+1)` means next page (fingers moved left), `handler(-1)` previous. All events are returned, never swallowed. |
| `func stop()` | Removes the monitor. |

Event logic:

- `.swipe`: `deltaX > 0` gives `-1`, `deltaX < 0` gives `+1`.
- `.scrollWheel`: only gesture-phased events count (wheel mice have no phases). On `.began` the accumulator and fired flag reset. On `.changed` (or momentum `.changed`), mostly vertical movement is ignored (`|deltaX| > |deltaY|` required); the horizontal delta accumulates and, the first time its magnitude reaches 60 within the gesture, the handler fires once (negative accumulation means next). `.ended`/`.cancelled` zero the accumulator; momentum `.ended` also clears the fired flag, so momentum scrolling after the finger lifts cannot fire a second page.

## Gotchas

- A local monitor sees events before they are dispatched, so returning the event keeps normal scrolling behaviour elsewhere.
- Not started in tests mode.
- Because `ShelfView` disables it while a box is open (`enabled: { model.openedAppID == nil }`), swipes do nothing in the open-box overlay.

## See also

[Shelf rendering](../architecture/shelf-rendering.md).
