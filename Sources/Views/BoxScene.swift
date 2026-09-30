import SwiftUI
import RealityKit
import AppKit
import OSLog

/// Per-frame motion state for the 3D box. Not @Observable: it is mutated every frame.
@MainActor final class BoxMotion {
    private static let log = Logger(subsystem: "net.outofajam.SteamShelf", category: "BoxMotion")

    var yaw: Float = 0
    var pitch: Float = 0
    var yawVelocity: Float = 0
    var pitchVelocity: Float = 0
    var isDragging = false
    var time: Double = 0
    var targetYaw: Float?
    var subscription: EventSubscription?
    var backEntity: ModelEntity?
    /// Distance offset of the root along -Z (0 when the explicit camera is honoured).
    var rootZ: Float = 0
    var idleEnabled = false
    var springRate: Float = 8
    var lastTranslation: CGSize = .zero

    private var idleBlend: Float = 0
    private var frameCount = 0
    private var frameAccum: Float = 0

    var isFacingFront: Bool { cos(yaw) > 0 }
    var isSettled: Bool { targetYaw == nil && abs(yaw) < 0.02 && abs(pitch) < 0.02 && abs(yawVelocity) < 0.05 }

    func reset() {
        yaw = 0; pitch = 0; yawVelocity = 0; pitchVelocity = 0
        isDragging = false; targetYaw = nil; time = 0; idleBlend = 0; idleEnabled = false; springRate = 8
    }

    /// Turn to the back if showing the front, otherwise back to the front.
    func flip() {
        yawVelocity = 0
        let turn = 2 * Float.pi
        if isFacingFront {
            targetYaw = ((yaw - .pi) / turn).rounded() * turn + .pi
        } else {
            targetYaw = (yaw / turn).rounded() * turn
        }
    }

    func showBack() { if isFacingFront { flip() } }

    func rotate(by delta: Float) {
        yawVelocity = 0
        targetYaw = (targetYaw ?? yaw) + delta
    }

    func returnToFront() {
        yawVelocity = 0; pitchVelocity = 0
        let turn = 2 * Float.pi
        targetYaw = (yaw / turn).rounded() * turn
        springRate = 14
    }

    func step(dt rawDt: Float, root: Entity) {
        let dt = min(max(rawDt, 0), 0.05)
        time += Double(dt)
        #if DEBUG
        frameAccum += rawDt; frameCount += 1
        if frameAccum >= 2 {
            Self.log.debug("box fps ≈ \(Double(self.frameCount) / Double(self.frameAccum), format: .fixed(precision: 1), privacy: .public)")
            frameAccum = 0; frameCount = 0
        }
        #endif

        if !isDragging {
            if let target = targetYaw {
                yaw += (target - yaw) * min(1, dt * springRate)
                yawVelocity = 0
                if abs(target - yaw) < 0.002 { yaw = target; targetYaw = nil }
            } else {
                yaw += yawVelocity * dt
                yawVelocity *= pow(0.04, dt)
                if abs(yawVelocity) < 0.05 { yawVelocity = 0 }
            }
            pitch += pitchVelocity * dt
            pitchVelocity *= pow(0.04, dt)
            if abs(pitchVelocity) < 0.05 { pitchVelocity = 0 }
            pitch += (0 - pitch) * min(1, dt * 4)
        }
        pitch = min(max(pitch, -0.45), 0.45)

        let idleActive = idleEnabled && !isDragging && abs(yawVelocity) < 0.05 && targetYaw == nil
        idleBlend += ((idleActive ? 1 : 0) - idleBlend) * min(1, dt * 5)
        let t = Float(time)
        let bob = 0.006 * sin(2 * .pi * t / 3.2) * idleBlend
        let drift = (2.5 * Float.pi / 180) * sin(2 * .pi * t / 7) * idleBlend

        root.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw + drift, axis: [0, 1, 0])
        root.position = [0, bob, rootZ]
    }
}

@MainActor enum BoxBuilder {
    static let width: Float = 0.20, height: Float = 0.30, depth: Float = 0.044

    static func material(_ tex: TextureResource, roughness: Float, clearcoat: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(texture: .init(tex))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        if clearcoat > 0 { m.clearcoat = .init(floatLiteral: clearcoat) }
        return m
    }

    static func edgeMaterial(_ color: Color) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: NSColor(color))
        m.roughness = .init(floatLiteral: 0.7)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    /// Six single-sided planes. Plane meshes face +Z; each is rotated so its front faces outward.
    static func makeBox(front: TextureResource, back: TextureResource, spine: TextureResource, edge: RealityKit.Material) -> Entity {
        let W = width, H = height, D = depth
        let box = Entity()
        box.name = "box"

        func face(_ name: String, w: Float, h: Float, position: SIMD3<Float>, rotation: simd_quatf, material: RealityKit.Material) -> ModelEntity {
            let e = ModelEntity(mesh: .generatePlane(width: w, height: h), materials: [material])
            e.name = name
            e.position = position
            e.orientation = rotation
            box.addChild(e)
            return e
        }
        let identity = simd_quatf(angle: 0, axis: [0, 1, 0])
        _ = face("front", w: W, h: H, position: [0, 0, D / 2], rotation: identity,
                 material: material(front, roughness: 0.35, clearcoat: 0.6))
        _ = face("back", w: W, h: H, position: [0, 0, -D / 2], rotation: simd_quatf(angle: .pi, axis: [0, 1, 0]),
                 material: material(back, roughness: 0.6))
        _ = face("right", w: D, h: H, position: [W / 2, 0, 0], rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]),
                 material: material(spine, roughness: 0.5))
        _ = face("left", w: D, h: H, position: [-W / 2, 0, 0], rotation: simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]),
                 material: material(spine, roughness: 0.5))
        _ = face("top", w: W, h: D, position: [0, H / 2, 0], rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]), material: edge)
        _ = face("bottom", w: W, h: D, position: [0, -H / 2, 0], rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]), material: edge)
        return box
    }
}

/// Wraps the RealityView. Textures are built by the caller before presentation.
struct BoxStageView: View {
    let front: SendableImage
    let back: SendableImage
    let spine: SendableImage
    let spineColor: Color
    let backVersion: Int
    let motion: BoxMotion
    let onReady: @MainActor () -> Void

    private static let log = Logger(subsystem: "net.outofajam.SteamShelf", category: "BoxStage")

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "boxRoot"
            content.add(root)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 30
            camera.position = [0, 0, 0.85]
            content.add(camera)

            let key = DirectionalLight()
            key.light.intensity = 2800
            key.look(at: .zero, from: [-0.5, 0.7, 1.0], relativeTo: nil)
            content.add(key)
            let fill = DirectionalLight()
            fill.light.intensity = 900
            fill.look(at: .zero, from: [0.8, -0.1, 0.6], relativeTo: nil)
            content.add(fill)

            do {
                var options = TextureResource.CreateOptions(semantic: .color)
                options.mipmapsMode = .allocateAndGenerateAll
                let frontTex = try await TextureResource(image: front.cgImage, options: options)
                let backTex = try await TextureResource(image: back.cgImage, options: options)
                let spineTex = try await TextureResource(image: spine.cgImage, options: options)
                let box = BoxBuilder.makeBox(front: frontTex, back: backTex, spine: spineTex,
                                             edge: BoxBuilder.edgeMaterial(spineColor))
                motion.backEntity = box.findEntity(named: "back") as? ModelEntity
                root.addChild(box)
            } catch {
                Self.log.error("Texture creation failed: \(String(describing: error), privacy: .public)")
            }

            motion.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                motion.step(dt: Float(event.deltaTime), root: root)
            }
            onReady()
        } update: { _ in
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !motion.isDragging {
                        motion.isDragging = true
                        motion.targetYaw = nil
                        motion.yawVelocity = 0; motion.pitchVelocity = 0
                        motion.lastTranslation = .zero
                    }
                    let dx = Float(value.translation.width - motion.lastTranslation.width)
                    let dy = Float(value.translation.height - motion.lastTranslation.height)
                    motion.lastTranslation = value.translation
                    motion.yaw += dx * 0.012
                    motion.pitch = min(max(motion.pitch + dy * 0.008, -0.45), 0.45)
                }
                .onEnded { value in
                    motion.isDragging = false
                    motion.yawVelocity = Float(value.velocity.width) * 0.012
                    motion.pitchVelocity = Float(value.velocity.height) * 0.008
                    motion.lastTranslation = .zero
                }
        )
        .task(id: backVersion) {
            guard backVersion > 0, let entity = motion.backEntity else { return }
            var options = TextureResource.CreateOptions(semantic: .color)
            options.mipmapsMode = .allocateAndGenerateAll
            guard let tex = try? await TextureResource(image: back.cgImage, options: options), !Task.isCancelled else { return }
            entity.model?.materials = [BoxBuilder.material(tex, roughness: 0.6)]
        }
        .onDisappear {
            motion.subscription?.cancel()
            motion.subscription = nil
        }
    }
}
