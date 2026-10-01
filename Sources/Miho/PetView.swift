import SwiftUI
import SceneKit
import MihoCore

@available(macOS 14.2, *)
struct PetView: View {
    static let desktopSize = CGSize(width: 220,height: 260)
    @ObservedObject var model: CompanionModel
    var body: some View {
        AnimatedCharacterView(animation: model.animation)
            .frame(width: Self.desktopSize.width, height: Self.desktopSize.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.appearance.displayName)，3D 桌面音乐精灵")
            .accessibilityValue(model.status)
            .help("拖动旋转 · ⌥ 拖动移动 · 双击回正 · 右键自定义角色")
    }
}

private struct AnimatedCharacterView: View {
    @ObservedObject var animation: CharacterAnimation
    var body: some View {
        ZStack {
            AudioReactiveField(frame: animation.frame.soundField).padding(8)
            CharacterView(pose: animation.frame.pose,rotation: animation.frame.rotation,appearance: animation.frame.appearance)
        }
    }
}

/// SwiftUI owns controls; SceneKit owns a persistent Metal scene and its joint animations.
struct CharacterView: NSViewRepresentable {
    var pose: DancePose
    var rotation = Rotation3()
    var appearance = CharacterAppearance()
    var animated = true
    final class Coordinator { let rig = CharacterScene() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = context.coordinator.rig.scene
        view.pointOfView = context.coordinator.rig.camera
        view.backgroundColor = .clear
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.antialiasingMode = .multisampling8X
        view.allowsCameraControl = false
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.rig.setAppearance(appearance)
        context.coordinator.rig.apply(pose, duration: animated ? 1/120 : 0)
        context.coordinator.rig.setInteractionRotation(rotation,duration: animated ? 1/60 : 0)
    }
    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) { view.isPlaying = false; view.scene = nil }
}
