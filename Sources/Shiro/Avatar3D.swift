import SwiftUI
import AppKit
import SceneKit
import SceneKit.ModelIO
import ModelIO
import ShiroCore

struct Avatar3D: NSViewRepresentable {
    let bot: Bot
    var size: CGFloat
    var active = false
    func makeNSView(context: Context) -> AvatarSceneView { AvatarSceneView() }
    func updateNSView(_ view: AvatarSceneView, context: Context) { view.configure(bot: bot, size: size, active: active) }
}

/// Orthographic, unlit geometry: a flat cartoon at rest, with depth only in motion.
final class AvatarSceneView: SCNView {
    private var identity = ""
    private var currentBot = Bot(name: "Shiro")
    private var bodyMotion = SCNNode()
    private var head = SCNNode()
    private var eyes: [SCNNode] = []
    private var monitor: Any?
    private var cursorTimer: Timer?
    private var followsMouse = true
    private var lastPointer = NSPoint(x: -10000, y: -10000)
    private var lastMovement = Date.distantPast
    private var resting = true
    private var restTilt: CGFloat = 0
    private let ink = NSColor(srgbRed: 0.055, green: 0.065, blue: 0.07, alpha: 1)

    init() {
        super.init(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        backgroundColor = .clear; antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 24; allowsCameraControl = false; autoenablesDefaultLighting = false
        setAccessibilityElement(true); setAccessibilityRole(.image)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self, self.followsMouse, event.window === self.window, let window = self.window else { return event }
            self.aim(event.locationInWindow, in: window); return event
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    deinit { cursorTimer?.invalidate(); if let monitor { NSEvent.removeMonitor(monitor) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); window?.acceptsMouseMovedEvents = true
        cursorTimer?.invalidate()
        guard window != nil else { return }
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.followsMouse, let window = self.window, window.isVisible, !self.visibleRect.isEmpty else { return }
            let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            if window.contentView?.bounds.contains(point) == true { self.aim(point, in: window) }
            else { self.returnToRest() }
        }
    }
    func configure(bot: Bot, size: CGFloat, active: Bool) {
        currentBot = bot
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let motion = bot.animateAvatar != false && !reduced
        followsMouse = bot.avatarMouseTracking != false && !reduced
        setAccessibilityLabel(bot.name + " animated character")
        let key = [bot.id.uuidString, bot.avatarFamily, bot.avatarTint, bot.avatarModelPath ?? "", String(motion), String(active), String(followsMouse)].joined(separator: "|")
        guard identity != key else { return }; identity = key
        let world = SCNScene(); world.background.contents = NSColor.clear
        world.lightingEnvironment.intensity = 0
        scene = world; bodyMotion = SCNNode(); head = SCNNode(); eyes = []
        world.rootNode.addChildNode(bodyMotion); bodyMotion.addChildNode(head)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 0.9
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
        camera.position = SCNVector3(0, 0, 5); world.rootNode.addChildNode(camera); pointOfView = camera
        restTilt = CGFloat(Int(bot.id.uuidString.utf8.first ?? 0) % 5 - 2) * 0.045
        let coat = flatMaterial(Self.coatColor(for: bot))
        if let path = bot.avatarModelPath, bot.avatarKind == "custom", loadCustom(path) { head = bodyMotion }
        else { buildCharacter(family: bot.avatarFamily, coat: coat) }
        head.eulerAngles.z = restTilt; resting = true; lastPointer = NSPoint(x: -10000, y: -10000)
        if motion {
            for eye in eyes {
                let blink = SCNAction.sequence([.wait(duration: 4.2 + Double(bot.id.uuidString.utf8.first ?? 0) / 100), .scaleY(to: 0.12, duration: 0.08), .scaleY(to: 1, duration: 0.12)])
                eye.runAction(.repeatForever(blink))
            }
            if active { bodyMotion.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.028, z: 0, duration: 0.8), .moveBy(x: 0, y: -0.028, z: 0, duration: 0.8)]))) }
        }
        isPlaying = motion; rendersContinuously = motion; needsDisplay = true
    }
    private func flatMaterial(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = NSColor.black; material.emission.contents = color
        material.ambient.contents = NSColor.black; material.specular.contents = NSColor.black
        material.reflective.contents = NSColor.black; material.metalness.contents = 0; material.roughness.contents = 1
        material.isDoubleSided = true
        return material
    }
    static func coatColor(for bot: Bot) -> NSColor {
        let tint = bot.avatarTint
        if tint.hasPrefix("#"), tint.count == 7, let value = UInt64(tint.dropFirst(), radix: 16) {
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
        let colors: [String: (CGFloat, CGFloat, CGFloat)] = ["cream": (0.90, 0.89, 0.83), "blue": (0.10, 0.51, 1), "purple": (0.62, 0.44, 0.98), "teal": (0.07, 0.72, 0.66), "orange": (1, 0.59, 0.28), "pink": (0.97, 0.16, 0.58), "graphite": (0.53, 0.59, 0.65)]
        let rgb = colors[tint] ?? colors["blue"]!
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }
    private func buildCharacter(family: String, coat: SCNMaterial) {
        let geometry: SCNGeometry
        if family == "robot" {
            geometry = SCNBox(width: 1.32, height: 1.28, length: 0.32, chamferRadius: 0.16)
        } else {
            let path = NSBezierPath(); path.flatness = 0.002
            if family == "circle" {
                path.appendOval(in: NSRect(x: -0.66, y: -0.66, width: 1.32, height: 1.32))
            } else if family == "capsule" {
                path.appendRoundedRect(NSRect(x: -0.48, y: -0.72, width: 0.96, height: 1.44), xRadius: 0.48, yRadius: 0.48)
            } else if ["diamond", "hexagon", "star"].contains(family) {
                let count = family == "star" ? 10 : family == "hexagon" ? 6 : 4
                for i in 0..<count {
                    let angle = CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(count)
                    let radius: CGFloat = family == "star" && i % 2 == 1 ? 0.49 : 0.76
                    let point = NSPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                    if i == 0 { path.move(to: point) } else { path.line(to: point) }
                }
            } else if family == "cloud" {
                path.move(to: NSPoint(x: -0.62, y: -0.4))
                path.curve(to: NSPoint(x: -0.52, y: 0.33), controlPoint1: NSPoint(x: -0.98, y: -0.15), controlPoint2: NSPoint(x: -0.85, y: 0.36))
                path.curve(to: NSPoint(x: 0.26, y: 0.5), controlPoint1: NSPoint(x: -0.64, y: 0.91), controlPoint2: NSPoint(x: 0.13, y: 0.96))
                path.curve(to: NSPoint(x: 0.62, y: -0.4), controlPoint1: NSPoint(x: 0.91, y: 0.62), controlPoint2: NSPoint(x: 1.02, y: -0.25))
                path.curve(to: NSPoint(x: -0.62, y: -0.4), controlPoint1: NSPoint(x: 0.3, y: -0.66), controlPoint2: NSPoint(x: -0.3, y: -0.66))
            } else if family == "orb" {
                path.move(to: NSPoint(x: -0.28, y: 0.69))
                path.curve(to: NSPoint(x: 0.45, y: 0.55), controlPoint1: NSPoint(x: -0.1, y: 0.78), controlPoint2: NSPoint(x: 0.3, y: 0.64))
                path.curve(to: NSPoint(x: 0.69, y: -0.18), controlPoint1: NSPoint(x: 0.65, y: 0.47), controlPoint2: NSPoint(x: 0.73, y: 0.05))
                path.curve(to: NSPoint(x: 0.12, y: -0.67), controlPoint1: NSPoint(x: 0.67, y: -0.36), controlPoint2: NSPoint(x: 0.34, y: -0.65))
                path.curve(to: NSPoint(x: -0.57, y: -0.4), controlPoint1: NSPoint(x: -0.1, y: -0.75), controlPoint2: NSPoint(x: -0.44, y: -0.58))
                path.curve(to: NSPoint(x: -0.66, y: 0.28), controlPoint1: NSPoint(x: -0.7, y: -0.22), controlPoint2: NSPoint(x: -0.77, y: 0.1))
                path.curve(to: NSPoint(x: -0.28, y: 0.69), controlPoint1: NSPoint(x: -0.59, y: 0.45), controlPoint2: NSPoint(x: -0.4, y: 0.61))
            } else { path.appendRoundedRect(NSRect(x: -0.65, y: -0.61, width: 1.3, height: 1.22), xRadius: 0.48, yRadius: 0.48) }
            path.close(); let shape = SCNShape(path: path, extrusionDepth: 0.32); shape.chamferRadius = 0.025; geometry = shape
        }
        let body = SCNNode(geometry: geometry); geometry.materials = [coat]; body.castsShadow = false
        if family != "robot" { body.position.z = -0.16 }; head.addChildNode(body)
        for sign: CGFloat in [-1, 1] {
            let geometry = SCNCapsule(capRadius: 0.075, height: 0.32)
            geometry.radialSegmentCount = 16; geometry.firstMaterial = flatMaterial(ink)
            let eye = SCNNode(geometry: geometry); eye.position = SCNVector3(sign * 0.18, -0.015, 0.20); eye.eulerAngles.z = -0.07
            head.addChildNode(eye); eyes.append(eye)
        }
    }
    static func validateModel(_ url: URL) -> Bool {
        let scene: SCNScene
        if ["scn", "dae"].contains(url.pathExtension.lowercased()) {
            guard let result = try? SCNScene(url: url, options: [.checkConsistency: true]) else { return false }; scene = result
        } else { scene = SCNScene(mdlAsset: MDLAsset(url: url)) }
        let (min, max) = scene.rootNode.boundingBox
        let extent = Swift.max(max.x-min.x, Swift.max(max.y-min.y, max.z-min.z))
        return extent.isFinite && extent > 0.0001
    }
    private func loadCustom(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true, (values.fileSize ?? 0) <= 50 * 1024 * 1024 else { return false }
        let imported: SCNScene
        if ["scn", "dae"].contains(url.pathExtension.lowercased()) {
            guard let loaded = try? SCNScene(url: url, options: [.checkConsistency: true]) else { return false }; imported = loaded
        } else { imported = SCNScene(mdlAsset: MDLAsset(url: url)) }
        let model = SCNNode(); for node in imported.rootNode.childNodes { model.addChildNode(node) }
        let (min, max) = model.boundingBox; let extent = Swift.max(max.x-min.x, Swift.max(max.y-min.y, max.z-min.z))
        guard extent.isFinite, extent > 0.0001 else { return false }
        let factor: CGFloat = 1.8 / extent
        model.scale = SCNVector3(factor, factor, factor); model.position = SCNVector3(-(min.x+max.x)*factor/2, -(min.y+max.y)*factor/2, -(min.z+max.z)*factor/2)
        model.enumerateChildNodes { node, _ in
            node.light = nil; node.camera = nil; node.castsShadow = false
            if let geometry = node.geometry {
                geometry.materials = geometry.materials.map { source in
                    self.flatMaterial((source.name ?? "").lowercased().contains("eye") ? self.ink : Self.coatColor(for: self.currentBot))
                }
            }
        }
        bodyMotion.addChildNode(model); return true
    }
    private func aim(_ point: NSPoint, in window: NSWindow) {
        guard scene != nil else { return }
        if abs(point.x-lastPointer.x) + abs(point.y-lastPointer.y) < 3 {
            if Date().timeIntervalSince(lastMovement) > 1.2 { returnToRest() }; return
        }
        lastPointer = point; lastMovement = Date(); resting = false
        let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        let x = CGFloat(max(-1, min(1, (point.x-center.x) / max(250, window.frame.width * 0.45))))
        let y = CGFloat(max(-1, min(1, (point.y-center.y) / max(200, window.frame.height * 0.45))))
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.18
        head.eulerAngles = SCNVector3(-y * 0.16, x * 0.26, restTilt - x * 0.045)
        for (i, eye) in eyes.enumerated() { eye.position.x = (i == 0 ? -0.18 : 0.18) + x * 0.025; eye.position.y = -0.015 + y * 0.025 }
        SCNTransaction.commit(); needsDisplay = true
    }
    private func returnToRest() {
        guard !resting else { return }; resting = true
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.3
        head.eulerAngles = SCNVector3(0, 0, restTilt)
        for (i, eye) in eyes.enumerated() { eye.position.x = i == 0 ? -0.18 : 0.18; eye.position.y = -0.015 }
        SCNTransaction.commit(); needsDisplay = true
    }
}

private extension SCNAction {
    static func scaleY(to target: CGFloat, duration: TimeInterval) -> SCNAction {
        .customAction(duration: duration) { node, elapsed in
            // The start/end scales are fixed for these short blink strokes.
            let t = min(1, CGFloat(elapsed) / max(0.001, CGFloat(duration)))
            node.scale.y = target < 1 ? 1 - t * 0.88 : 0.12 + t * 0.88
        }
    }
}
