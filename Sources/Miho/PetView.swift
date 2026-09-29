import SwiftUI
import SceneKit
import MihoCore

@available(macOS 14.2, *)
struct PetView: View {
    @ObservedObject var model: CompanionModel
    var body: some View {
        CharacterView(pose: model.motion.pose)
            .frame(width: 260, height: 300)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Miho 迷糊，3D 桌面音乐精灵")
            .accessibilityValue(model.status)
            .help("拖动 Miho 换位置 · 右键调整律动与预览舞步")
    }
}

/// SwiftUI owns controls; SceneKit owns a persistent Metal scene and its joint animations.
struct CharacterView: NSViewRepresentable {
    var pose: DancePose
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
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.rig.apply(pose, duration: animated ? 1/30 : 0)
    }
    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) { view.isPlaying = false; view.scene = nil }
}
