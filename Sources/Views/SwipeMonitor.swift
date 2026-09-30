import AppKit

/// Turns horizontal trackpad / Magic Mouse swipes into page turns.
///
/// Two paths, matching the "Swipe between pages" system preference:
/// - scroll-based swipes (two fingers / one finger on Magic Mouse) arrive as `scrollWheel` events with
///   gesture phases; we accumulate `scrollingDeltaX` and fire once when it passes the threshold;
/// - three-finger swipes arrive as `.swipe` events with `deltaX` of ±1.
@MainActor final class SwipeMonitor {
    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private var firedThisGesture = false
    private let threshold: CGFloat = 60

    /// `handler(+1)` = next page (fingers moved left), `handler(-1)` = previous page.
    func start(in window: @escaping @MainActor () -> NSWindow?, enabled: @escaping @MainActor () -> Bool, handler: @escaping @MainActor (Int) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
            guard let self, let target = window(), event.window === target, enabled() else { return event }
            switch event.type {
            case .swipe:
                if event.deltaX > 0 { handler(-1) } else if event.deltaX < 0 { handler(+1) }
                return event
            case .scrollWheel:
                // Only gesture-phased events (trackpad, Magic Mouse); a wheel mouse has no phases.
                let phase = event.phase, momentum = event.momentumPhase
                if phase.contains(.began) { accumulated = 0; firedThisGesture = false }
                if phase.contains(.changed) || momentum.contains(.changed) {
                    // Ignore mostly-vertical scrolling.
                    guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                    accumulated += event.scrollingDeltaX
                    if !firedThisGesture, abs(accumulated) >= threshold {
                        firedThisGesture = true
                        handler(accumulated < 0 ? +1 : -1)
                    }
                }
                if phase.contains(.ended) || phase.contains(.cancelled) { accumulated = 0 }
                if momentum.contains(.ended) { accumulated = 0; firedThisGesture = false }
                return event
            default:
                return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
