import SwiftUI
import MihoCore

/// A local, interactive animation review surface. It never substitutes fake audio for live capture.
struct DanceStudioView: View {
    @State private var selected: DanceMove = .twoStep
    @State private var mood: DanceMood = .groovy
    @State private var autoPlay = true
    private let started = Date()
    private let accent = Color(red: 0.02,green: 0.43,blue: 0.60)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading,spacing: 12) {
                Text("MIHO / DANCE STUDIO").font(.system(size: 10,weight: .bold,design: .monospaced)).tracking(2).foregroundStyle(accent)
                Text("你好，迷糊。").font(.system(size: 30,weight: .bold,design: .rounded))
                Text("墨镜一戴，跟着节拍。").font(.system(size: 12)).foregroundStyle(.secondary)
                TimelineView(.animation(minimumInterval: 1/30)) { context in
                    let elapsed = context.date.timeIntervalSince(started)
                    let moves = DanceMove.allCases
                    let move = autoPlay ? moves[Int(max(0,elapsed)/4) % moves.count] : selected
                    let previous = autoPlay ? moves[(Int(max(0,elapsed)/4)+moves.count-1) % moves.count] : selected
                    let phase = elapsed*2
                    let energy = mood == .dreamy ? 0.15 : mood == .groovy ? 0.5 : 0.9
                    let blend = min(1,elapsed.truncatingRemainder(dividingBy: 4)/0.4)
                    let pose = Choreographer.dance(move: previous,phase: phase,energy: energy)
                        .mixed(with: Choreographer.dance(move: move,phase: phase,energy: energy),by: blend*blend*(3-2*blend))
                    VStack(spacing: 0) {
                        CharacterView(pose: pose).frame(width: 320,height: 350)
                        Text(move.label).font(.system(size: 13,weight: .semibold)).foregroundStyle(accent)
                    }
                }
                Text("舞步预览 · 不需要播放音乐").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(28).frame(width: 350)
                .background(LinearGradient(colors: [Color(red: 0.91,green: 0.97,blue: 0.99),Color(red: 0.98,green: 0.98,blue: 0.96)],startPoint: .topLeading,endPoint: .bottomTrailing))
            VStack(alignment: .leading,spacing: 16) {
                Text("给 Miho 一点节奏").font(.system(size: 17,weight: .semibold))
                Text("桌面上的 Miho 会随真实声音跳舞。\n这里可以单独查看每种动作。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false,vertical: true)
                Toggle("自动轮换舞步",isOn: $autoPlay).toggleStyle(.switch).tint(accent).font(.system(size: 12))
                VStack(spacing: 6) {
                    ForEach(DanceMove.allCases,id: \.self) { move in
                        Button {
                            selected = move; autoPlay = false
                        } label: {
                            HStack {
                                Image(systemName: symbol(move)).frame(width: 24)
                                Text(move.label).font(.system(size: 12,weight: .medium))
                                Spacer()
                                if !autoPlay && selected == move { Image(systemName: "checkmark.circle.fill") }
                            }.padding(10).foregroundStyle(!autoPlay && selected == move ? .white : accent)
                                .background(!autoPlay && selected == move ? accent : accent.opacity(0.06),in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
                Text("动作力度").font(.system(size: 11,weight: .semibold)).foregroundStyle(.secondary)
                Picker("动作力度",selection: $mood) {
                    Text("轻柔").tag(DanceMood.dreamy)
                    Text("律动").tag(DanceMood.groovy)
                    Text("活力").tag(DanceMood.lively)
                }.pickerStyle(.segmented).labelsHidden()
                Text("实时模式依据声音强弱和音色调整状态，\n每八拍换一组动作。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(24).frame(width: 250)
        }.frame(width: 650,height: 620).background(Color(nsColor: .windowBackgroundColor))
    }
    private func symbol(_ move: DanceMove) -> String {
        switch move {
        case .twoStep: return "figure.dance"
        case .bodyRoll: return "waveform.path"
        case .armWave: return "waveform.path"
        case .pop: return "sparkles"
        case .heelToe: return "arrow.triangle.2.circlepath"
        case .happyHop: return "figure.jumprope"
        }
    }
}
