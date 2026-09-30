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
                Text("MIHO / LIVE BEAT").font(.system(size: 10,weight: .bold,design: .monospaced)).tracking(2).foregroundStyle(accent)
                Text(model.appearance.displayName).font(.system(size: 30,weight: .bold,design: .rounded))
                Text("跟着唱腔，自由地跳。").font(.system(size: 12)).foregroundStyle(.secondary)
                LiveDancePreview(animation: model.animation)
                Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false,vertical: true)
            }.padding(28).frame(width: 350)
                .background(LinearGradient(colors: [Color(red: 0.91,green: 0.97,blue: 0.99),Color(red: 0.98,green: 0.98,blue: 0.96)],startPoint: .topLeading,endPoint: .bottomTrailing))
            VStack(alignment: .leading,spacing: 16) {
                Text("跟随主唱").font(.system(size: 20,weight: .bold,design: .rounded))
                Label(!model.enabled ? "人声分析已暂停" : model.separationReady ? "本机人声分离已连接" : "人声分离未连接",systemImage: "waveform")
                    .font(.system(size: 11)).foregroundStyle(accent)
                VStack(alignment: .leading,spacing: 16) {
                    Label("唱腔上扬，身体抬起",systemImage: "arrow.up.right")
                    Label("长音持续，姿态保持",systemImage: "pause")
                    Label("收句回落，顺势放松",systemImage: "arrow.down.right")
                    Label("人声重音，加一点力度",systemImage: "bolt")
                }.font(.system(size: 12)).padding(.vertical,16)
                HStack {
                    Text("动作幅度").font(.system(size: 12,weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1f×",model.motionIntensity)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Slider(value: $model.motionIntensity,in: 0.5...1.5,step: 0.1).accessibilityLabel("动作幅度")
                Text("动作连续跟随人声的力度和音高，不再循环播放固定舞步。伴奏鼓点轻轻带过长音。")
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
                    meter("鼓点",value: frame.rhythm.drumEnergy)
                    meter("延音",value: frame.rhythm.vocalSustain)
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
