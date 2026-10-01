import SwiftUI
import MihoCore

/// The desktop and this preview observe exactly the same live motion frame.
/// There is no separate metronome, demo audio, or free-running dance loop.
struct DanceStudioView: View {
    @ObservedObject var model: CompanionModel
    private let accent = Color(red: 0.02,green: 0.43,blue: 0.60)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading,spacing: 12) {
                Text("MIHO / LIVE VOICE").font(.system(size: 10,weight: .bold,design: .monospaced)).tracking(2).foregroundStyle(accent)
                Text(model.appearance.displayName).font(.system(size: 30,weight: .bold,design: .rounded))
                Text("跟着歌手的声音，舒展和摆动。").font(.system(size: 12)).foregroundStyle(.secondary)
                LiveDancePreview(animation: model.animation)
                Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false,vertical: true)
            }.padding(28).frame(width: 350)
                .background(LinearGradient(colors: [Color(red: 0.91,green: 0.97,blue: 0.99),Color(red: 0.98,green: 0.98,blue: 0.96)],startPoint: .topLeading,endPoint: .bottomTrailing))
            VStack(alignment: .leading,spacing: 16) {
                Text("人声领舞").font(.system(size: 20,weight: .bold,design: .rounded))
                Label(!model.enabled ? "律动已暂停" : model.separationReady ? "正在本机跟随人声" : "音频分析未连接",systemImage: "waveform")
                    .font(.system(size: 11)).foregroundStyle(accent)
                VStack(alignment: .leading,spacing: 16) {
                    Label("短句起落，跟着声音摆动",systemImage: "music.note")
                    Label("长音舒展，延音保持姿态",systemImage: "arrow.left.and.right")
                    Label("唱腔上扬，随收句放松",systemImage: "arrow.up.right")
                    Label("人声重音加力，鼓点轻轻补充",systemImage: "bolt")
                }.font(.system(size: 12)).padding(.vertical,16)
                HStack {
                    Text("动作幅度").font(.system(size: 12,weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1f×",model.motionIntensity)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Slider(value: $model.motionIntensity,in: 0.5...1.5,step: 0.1).accessibilityLabel("动作幅度")
                Text("人声决定主要动作，延音保持舒展。唱句和换气期间不让鼓点带跑；无人声时，伴奏才轻轻摇动。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    .fixedSize(horizontal: false,vertical: true)
                Button(model.enabled ? "暂停律动" : "开始律动") { model.setEnabled(!model.enabled) }
                    .buttonStyle(.bordered).controlSize(.small)
            }.padding(24).frame(width: 250)
        }.frame(width: 650,height: 620).background(Color(nsColor: .windowBackgroundColor))
    }

}

private struct LiveDancePreview: View {
    @ObservedObject var animation: CharacterAnimation
    private let accent = Color(red: 0.02,green: 0.43,blue: 0.60)
    var body: some View {
        let frame = animation.frame
        VStack(spacing: 12) {
            CharacterView(pose: frame.pose,appearance: frame.appearance).frame(width: 320,height: 335)
            Text(frame.gesture.label).font(.system(size: 13,weight: .semibold)).foregroundStyle(accent)
            HStack(spacing: 12) {
                VStack(alignment: .leading,spacing: 5) {
                    meter("人声",value: frame.rhythm.vocalEnergy*frame.rhythm.vocalPresence)
                    meter("延音",value: frame.rhythm.vocalSustain)
                    meter("鼓点",value: frame.rhythm.drumEnergy)
                }
                Spacer()
                VStack(spacing: 4) {
                    Circle().fill(accent.opacity(0.12+min(1,frame.impact)*0.88))
                        .frame(width: 24,height: 24).scaleEffect(1+min(1,frame.impact)*0.20)
                    Text("重音").font(.system(size: 10)).foregroundStyle(.secondary)
                }.accessibilityElement(children: .ignore)
                    .accessibilityLabel("重音响应").accessibilityValue(frame.impact > 0.15 ? "重音来了" : "等待重音")
            }.padding(.horizontal,16)
        }
    }
    private func meter(_ label: String,value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Capsule().fill(accent.opacity(0.08)).frame(width: 130,height: 5)
                .overlay(alignment: .leading) {
                    Capsule().fill(accent).frame(width: max(2,130*min(1,max(0,value))),height: 5)
                }
        }
    }
}
