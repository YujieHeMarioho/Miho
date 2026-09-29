import SwiftUI

@available(macOS 14.2, *)
struct PetView: View {
    @ObservedObject var model: CompanionModel
    private let ink = Color(red: 0.31, green: 0.23, blue: 0.25)
    private let cream = Color(red: 1, green: 0.96, blue: 0.86)
    private let peach = Color(red: 1, green: 0.69, blue: 0.64)

    var body: some View {
        let m = model.motion
        let sway = sin(m.phase) * (2 + m.energy * 13)
        let bounce = m.bounce * (8 + m.energy * 16)
        let breath = sin(m.time * 2.2) * 0.015
        let blink = m.time.truncatingRemainder(dividingBy: 4.3) > 4.12
        ZStack {
            Ellipse()
                .fill(ink.opacity(0.12))
                .frame(width: 88 - bounce * 0.7, height: 12)
                .blur(radius: 3)
                .offset(y: 74)
            ZStack {
                // Tiny feet and waving arms sit behind the marshmallow body.
                Capsule().fill(ink).frame(width: 24, height: 14)
                    .rotationEffect(.degrees(-12 - sway)).offset(x: -28, y: 58)
                Capsule().fill(ink).frame(width: 24, height: 14)
                    .rotationEffect(.degrees(12 - sway)).offset(x: 28, y: 58)
                arm(angle: -35 - sway * 2 - m.bounce * 35).offset(x: -60, y: 20)
                arm(angle: 35 - sway * 2 + m.bounce * 35).offset(x: 60, y: 20)
                Ellipse()
                    .fill(LinearGradient(colors: [.white, cream], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Ellipse().stroke(ink, lineWidth: 2.5))
                    .frame(width: 112, height: 105)
                    .shadow(color: peach.opacity(0.18), radius: 5, y: 3)
                // A little green sprout gives Miho a recognizable silhouette.
                Capsule().fill(ink).frame(width: 3, height: 17).offset(y: -57)
                Ellipse().fill(Color(red: 0.62, green: 0.78, blue: 0.51))
                    .overlay(Ellipse().stroke(ink, lineWidth: 2))
                    .frame(width: 24, height: 13)
                    .rotationEffect(.degrees(-28 + sway * 0.5)).offset(x: 9, y: -66)
                HStack(spacing: 25) {
                    eye(blink: blink)
                    eye(blink: blink)
                }.offset(y: -5)
                HStack(spacing: 49) {
                    Ellipse().fill(peach.opacity(0.7)).frame(width: 18, height: 10)
                    Ellipse().fill(peach.opacity(0.7)).frame(width: 18, height: 10)
                }.offset(y: 12)
                if m.energy > 0.12 {
                    Ellipse().fill(ink).frame(width: 12, height: 10 + m.energy * 5).offset(y: 15)
                } else {
                    Smile().stroke(ink, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                        .frame(width: 12, height: 7).offset(y: 14)
                }
                Ellipse().fill(.white.opacity(0.75)).frame(width: 22, height: 9)
                    .rotationEffect(.degrees(-30)).offset(x: -27, y: -30)
            }
            .scaleEffect(x: 1 + breath - m.bounce * 0.06,
                         y: 1 - breath + m.bounce * 0.09, anchor: .bottom)
            .rotationEffect(.degrees(sway), anchor: .bottom)
            .offset(x: sin(m.phase * 0.5) * m.energy * 5, y: 6 - bounce)
            if m.energy > 0.08 {
                Text("♪").font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(peach)
                    .rotationEffect(.degrees(-15))
                    .offset(x: -76, y: -36 - sin(m.phase) * 5)
                    .opacity(min(1, m.energy * 3))
                Text("♫").font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.62, green: 0.72, blue: 0.52))
                    .offset(x: 76, y: -52 + sin(m.phase) * 5)
                    .opacity(min(1, m.energy * 3))
            }
        }
        .frame(width: 200, height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Miho 迷糊，桌面音乐精灵")
        .accessibilityValue(model.status)
        .help("拖动 Miho 换位置 · 点击菜单栏的小精灵调整设置")
    }

    private func eye(blink: Bool) -> some View {
        Capsule().fill(ink).frame(width: 7, height: blink ? 2 : 13)
    }
    private func arm(angle: Double) -> some View {
        Capsule().fill(cream).overlay(Capsule().stroke(ink, lineWidth: 2.5))
            .frame(width: 15, height: 30).rotationEffect(.degrees(angle))
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.maxY * 1.8))
        return path
    }
}
