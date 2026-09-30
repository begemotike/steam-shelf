import SwiftUI
import AppKit

enum OpenPhase: Equatable { case closed, lifting, flying, presented, returning }

private struct BoxTextures {
    var front: SendableImage
    var back: SendableImage
    var spine: SendableImage
    var spineColor: Color
}

/// Overlay: dim backdrop, the 2D "flyer" copy of the tile, the 3D stage, toolbar and label editor.
/// Owns the open/close phase machine (DESIGN §7.1).
struct OpenBoxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: OpenPhase = .closed
    @State private var cover: ReadyCover?
    @State private var flyerRect: CGRect = .zero
    @State private var flyerScale: CGFloat = 1
    @State private var flyerShadow: CGFloat = 8
    @State private var flyerOpacity: Double = 1
    @State private var dim: Double = 0
    @State private var stageOpacity: Double = 0
    @State private var toolbarOpacity: Double = 0
    @State private var textures: BoxTextures?
    @State private var stageReady = false
    @State private var backVersion = 0
    @State private var motion = BoxMotion()
    @State private var generation = 0
    @State private var duScale: CGFloat = 1
    @State private var overlaySize: CGSize = .zero
    @State private var overlayOrigin: CGPoint = .zero
    @State private var backTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var entry: ShelfEntry? {
        guard let id = model.openedAppID else { return nil }
        return model.document.entries.first { $0.appID == id }
    }

    // MARK: Geometry

    private var stageSide: CGFloat { max(160, min(overlaySize.width - 360, overlaySize.height - 120)) }
    private var stageCenter: CGPoint {
        let reserved = model.isEditingLabel ? Theme.Metrics.editorPanelW + 40 : 0
        return CGPoint(x: (overlaySize.width - reserved) / 2, y: overlaySize.height / 2)
    }
    private var targetRect: CGRect {
        let h = Theme.Metrics.frontFaceFill * stageSide
        let w = h * 2 / 3
        // Flyer rects live in shelfSpace, so shift by the overlay origin.
        return CGRect(x: overlayOrigin.x + stageCenter.x - w / 2, y: overlayOrigin.y + stageCenter.y - h / 2, width: w, height: h)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            if phase != .closed {
                Color.black.opacity(0.7 * dim)
                    .contentShape(Rectangle())
                    .onTapGesture { if phase == .presented { beginClose() } }

                if let textures {
                    BoxStageView(front: textures.front, back: textures.back, spine: textures.spine,
                                 spineColor: textures.spineColor, backVersion: backVersion, motion: motion) {
                        stageReady = true
                    }
                    .frame(width: stageSide, height: stageSide)
                    .position(stageCenter)
                    .opacity(stageOpacity)
                    .animation(Theme.Motion.panel, value: model.isEditingLabel)
                    .id(generation)
                }

                flyer

                toolbar
                    .position(x: stageCenter.x,
                              y: stageCenter.y + Theme.Metrics.frontFaceFill * stageSide / 2 + 24 + 15)
                    .opacity(toolbarOpacity)
                    .allowsHitTesting(phase == .presented)
                    .animation(Theme.Motion.panel, value: model.isEditingLabel)

                if model.isEditingLabel, phase == .presented, let entry {
                    HStack {
                        Spacer()
                        LabelEditorPanel(appID: entry.appID)
                            .frame(width: Theme.Metrics.editorPanelW)
                            .frame(maxHeight: .infinity)
                            .padding(.vertical, 20)
                            .padding(.trailing, 20)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("shelfSpace")) } action: { frame in
            overlaySize = frame.size
            overlayOrigin = frame.origin
        }
        .allowsHitTesting(phase != .closed)
        .focusable(phase != .closed)
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.escape, .space, .leftArrow, .rightArrow]) { press in
            guard phase == .presented, press.modifiers.isEmpty else { return .ignored }
            switch press.key {
            case .escape: beginClose()
            case .space: motion.flip()
            case .leftArrow: motion.rotate(by: -.pi / 2)
            default: motion.rotate(by: .pi / 2)
            }
            return .handled
        }
        .onChange(of: model.openedAppID) { _, id in
            if id != nil, phase == .closed { begin() }
            else if id == nil, phase != .closed { hardReset() }
        }
        .onChange(of: entry) { _, new in
            if new != nil, phase != .closed { scheduleBackRender() }
        }
        .onChange(of: model.isEditingLabel) { _, editing in
            if editing { motion.showBack() } else if phase == .presented { focused = true }
        }
    }

    // MARK: Pieces

    private var flyer: some View {
        Group {
            if let cover {
                Image(decorative: cover.image, scale: 2)
                    .resizable()
                    .aspectRatio(2.0 / 3.0, contentMode: .fill)
                    .frame(width: max(1, flyerRect.width), height: max(1, flyerRect.height))
                    .clipShape(RoundedRectangle(cornerRadius: 2 * duScale))
                    .overlay(Theme.gloss.clipShape(RoundedRectangle(cornerRadius: 2 * duScale)).allowsHitTesting(false))
                    .shadow(color: .black.opacity(0.55), radius: flyerShadow * duScale, x: 3 * duScale, y: 6 * duScale)
                    .scaleEffect(flyerScale)
                    .position(x: flyerRect.midX - overlayOrigin.x, y: flyerRect.midY - overlayOrigin.y)
                    .opacity(flyerOpacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button("Flip") { motion.flip() }
                .buttonStyle(BrassPillButtonStyle())
            if model.source.isEditable {
                Button(model.isEditingLabel ? "Hide Label" : "Edit Label") {
                    withAnimation(Theme.Motion.panel) { model.isEditingLabel.toggle() }
                }
                .buttonStyle(BrassPillButtonStyle())
            }
            Button("Close") { beginClose() }
                .buttonStyle(BrassPillButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Textures

    @MainActor private func renderBack(_ entry: ShelfEntry, spineColor: Color) -> SendableImage? {
        let view = BackOfBoxView(entry: entry, ownerName: model.document.owner.displayName, spineColor: spineColor)
        return ArtGenerator.render(view, size: CGSize(width: Theme.Metrics.coverW, height: Theme.Metrics.coverH))
            .map { SendableImage(cgImage: $0) }
    }

    private func buildTextures(entry: ShelfEntry, cover: ReadyCover) -> BoxTextures? {
        guard let back = renderBack(entry, spineColor: cover.spine),
              let spine = ArtGenerator.render(SpineView(title: entry.title, color: cover.spine),
                                              size: CGSize(width: Theme.Metrics.spineW, height: Theme.Metrics.spineH)) else { return nil }
        return BoxTextures(front: SendableImage(cgImage: cover.image), back: back,
                           spine: SendableImage(cgImage: spine), spineColor: cover.spine)
    }

    /// Debounced (150 ms) re-render of the back label; `backVersion` only ever increases.
    private func scheduleBackRender() {
        backTask?.cancel()
        backTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let entry, let cover, textures != nil,
                  let image = renderBack(entry, spineColor: cover.spine) else { return }
            textures?.back = image
            backVersion += 1
        }
    }

    // MARK: Phase machine

    private func begin() {
        guard let entry else { return }
        generation += 1
        let gen = generation
        let from = model.openedFromFrame
        duScale = max(0.3, from.width / Theme.Metrics.boxW)
        let resolved = CoverLoader.recent[entry.appID]
            ?? ReadyCover(image: ArtGenerator.placeholderCover(title: entry.title, appID: entry.appID),
                          spine: CoverPalette.forApp(entry.appID).bottom)
        cover = resolved
        motion.reset()
        stageReady = false
        textures = nil
        backVersion = 0
        flyerOpacity = 1; stageOpacity = 0; toolbarOpacity = 0; dim = 0
        flyerScale = 1; flyerShadow = 8
        withTransaction(Transaction(animation: nil)) { flyerRect = from }

        Task { @MainActor in
            // Build every texture while the box lifts and flies.
            await Task.yield()
            guard gen == generation else { return }
            textures = buildTextures(entry: entry, cover: resolved)
        }

        Task { @MainActor in
            if reduceMotion {
                phase = .flying
                withTransaction(Transaction(animation: nil)) { flyerRect = targetRect }
                withAnimation(Theme.Motion.crossfade) { dim = 1 }
            } else {
                phase = .lifting
                withAnimation(Theme.Motion.lift) { flyerScale = 1.08; flyerShadow = 18 }
                try? await Task.sleep(for: .milliseconds(160))
                guard gen == generation else { return }
                phase = .flying
                withAnimation(Theme.Motion.fly) { flyerRect = targetRect; flyerScale = 1; flyerShadow = 14 }
                withAnimation(.easeInOut(duration: 0.45)) { dim = 1 }
                try? await Task.sleep(for: .milliseconds(450))
            }
            guard gen == generation else { return }
            await present(gen)
        }
    }

    private func present(_ gen: Int) async {
        // Wait for the RealityView to finish building (bounded).
        var waited = 0
        while !stageReady, waited < 200 {
            try? await Task.sleep(for: .milliseconds(20))
            waited += 1
            if gen != generation { return }
        }
        guard gen == generation else { return }
        motion.time = 0
        withAnimation(Theme.Motion.crossfade) { stageOpacity = 1; flyerOpacity = 0 }
        try? await Task.sleep(for: .milliseconds(150))
        guard gen == generation else { return }
        phase = .presented
        motion.idleEnabled = !reduceMotion
        focused = true
        withAnimation(.easeOut(duration: 0.2)) { toolbarOpacity = 1 }
        if let id = model.openedAppID {
            await model.refreshStats(for: id)
            await model.blurbIfNeeded(for: id)
        }
    }

    private func beginClose() {
        guard phase == .presented else { return }
        phase = .returning
        let gen = generation
        motion.idleEnabled = false
        backTask?.cancel()
        withAnimation(Theme.Motion.panel) { model.isEditingLabel = false }
        withAnimation(.easeOut(duration: 0.2)) { toolbarOpacity = 0 }
        motion.returnToFront()

        Task { @MainActor in
            // Spring back to yaw 0 / pitch 0 (bounded to 0.6 s).
            var waited = 0
            while !motion.isSettled, waited < 30 {
                try? await Task.sleep(for: .milliseconds(20))
                waited += 1
            }
            guard gen == generation else { return }
            withTransaction(Transaction(animation: nil)) { flyerRect = targetRect; flyerScale = 1; flyerShadow = 14 }
            withAnimation(.easeInOut(duration: 0.12)) { flyerOpacity = 1; stageOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(120))
            guard gen == generation else { return }
            if reduceMotion {
                withAnimation(Theme.Motion.crossfade) { dim = 0; flyerOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(150))
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                    flyerRect = model.openedFromFrame; flyerScale = 1.08; flyerShadow = 18
                }
                withAnimation(.easeInOut(duration: 0.38)) { dim = 0 }
                try? await Task.sleep(for: .milliseconds(380))
                guard gen == generation else { return }
                withAnimation(.easeOut(duration: 0.12)) { flyerScale = 1; flyerShadow = 8 }
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard gen == generation else { return }
            finish()
        }
    }

    private func finish() {
        model.close()
        reset()
    }

    /// The model closed the box from outside (e.g. leaving demo): drop everything immediately.
    private func hardReset() {
        generation += 1
        reset()
    }

    private func reset() {
        backTask?.cancel()
        phase = .closed
        textures = nil
        cover = nil
        motion.subscription?.cancel()
        motion.subscription = nil
        motion.backEntity = nil
        toolbarOpacity = 0; stageOpacity = 0; dim = 0
    }
}
