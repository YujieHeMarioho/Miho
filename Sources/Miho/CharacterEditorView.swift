import SwiftUI
import MihoCore

@available(macOS 14.2, *)
struct CharacterEditorView: View {
    @ObservedObject var model: CompanionModel
    var onDone: () -> Void
    @State private var rotation = Rotation3()
    @State private var dragStart: Rotation3?
    private let accent = Color(red: 0.02,green: 0.43,blue: 0.60)
    private let colorNames = ["天空蓝","薄荷绿","丁香紫","樱花粉","蜂蜜黄","珊瑚橙","奶油白","雾蓝","可可棕","石墨黑"]

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 18) {
                Text("MEET YOUR MIHO").font(.system(size: 10,weight: .bold,design: .monospaced)).tracking(2).foregroundStyle(accent)
                Text(model.appearance.displayName).font(.system(size: 34,weight: .bold,design: .rounded))
                CharacterView(pose: DancePose(),rotation: rotation,appearance: model.appearance)
                    .frame(width: 320,height: 350)
                    .overlay {
                        Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil { dragStart = rotation }
                                rotation.y = (dragStart?.y ?? 0)+value.translation.width*0.015
                                rotation.x = min(0.55,max(-0.55,(dragStart?.x ?? 0)+value.translation.height*0.010))
                            }.onEnded { _ in dragStart = nil })
                    }.accessibilityLabel("角色 3D 预览")
                Text("拖动看看侧面与背面").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Button("回到正面") { rotation = Rotation3() }
                    Button("随机搭配") { randomize() }
                }.controlSize(.small)
                Spacer(minLength: 0)
                Text("你的搭配会自动保存，\n也会立即出现在桌面上。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            }.padding(26).frame(width: 360)
                .background(LinearGradient(colors: [Color(red: 0.91,green: 0.97,blue: 0.99),Color(red: 0.98,green: 0.98,blue: 0.96)],startPoint: .topLeading,endPoint: .bottomTrailing))
            VStack(alignment: .leading,spacing: 0) {
                HStack {
                    VStack(alignment: .leading,spacing: 5) {
                        Text("创造你的伙伴").font(.system(size: 24,weight: .semibold,design: .rounded))
                        Text("从形态到小配饰，都由你来选。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("完成",action: onDone).buttonStyle(.borderedProminent).tint(accent)
                }.padding(24)
                Divider()
                ScrollView {
                    VStack(alignment: .leading,spacing: 20) {
                        section("名字") {
                            TextField("给它取个名字",text: $model.appearance.name).textFieldStyle(.roundedBorder)
                                .onChange(of: model.appearance.name) { _, value in
                                    if value.count > 24 { model.appearance.name = String(value.prefix(24)) }
                                }.accessibilityLabel("角色名字")
                        }
                        section("形态") {
                            Picker("形态",selection: $model.appearance.shape) {
                                ForEach(BodyShape.allCases,id: \.self) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                            Picker("耳朵",selection: $model.appearance.ears) {
                                ForEach(EarStyle.allCases,id: \.self) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                        section("颜色") {
                            swatches($model.appearance.bodyColor,label: "身体")
                            Picker("质感",selection: $model.appearance.surface) {
                                ForEach(SurfaceStyle.allCases,id: \.self) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                        section("眼睛") {
                            Picker("眼睛",selection: $model.appearance.eyes) {
                                ForEach(EyeStyle.allCases,id: \.self) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                            if model.appearance.glasses == .sunglasses {
                                Text("摘下墨镜，就能看到眼睛啦。")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        section("眼镜") {
                            Picker("眼镜",selection: $model.appearance.glasses) {
                                ForEach(GlassesStyle.allCases,id: \.self) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                            if model.appearance.glasses != .none { swatches($model.appearance.glassesColor,label: "镜框") }
                        }
                        section("配饰") {
                            Picker("配饰",selection: $model.appearance.accessory) {
                                ForEach(HeadAccessory.allCases,id: \.self) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                            if model.appearance.accessory != .none { swatches($model.appearance.accessoryColor,label: "配饰") }
                        }
                        Button("恢复咪虎的蓝色经典搭配") { model.appearance = CharacterAppearance(); rotation = Rotation3() }
                            .font(.system(size: 12)).foregroundStyle(accent)
                    }.padding(24)
                }
            }.frame(width: 430)
        }.frame(width: 790,height: 650).background(Color(nsColor: .windowBackgroundColor))
    }
    private func section<Content: View>(_ title: String,@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading,spacing: 10) {
            Text(title).font(.system(size: 13,weight: .semibold))
            content()
        }
    }
    private func swatches(_ value: Binding<UInt32>,label: String) -> some View {
        VStack(alignment: .leading,spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(CharacterAppearance.palette.enumerated()),id: \.offset) { index,hex in
                    Button { value.wrappedValue = hex } label: {
                        Circle().fill(color(hex)).frame(width: 24,height: 24)
                            .overlay(Circle().strokeBorder(.black.opacity(0.08),lineWidth: 1))
                            .overlay {
                                if value.wrappedValue == hex {
                                    Image(systemName: "checkmark").font(.system(size: 10,weight: .bold))
                                        .foregroundStyle(index == 6 || index == 4 ? .black : .white)
                                }
                            }
                    }.buttonStyle(.plain).accessibilityLabel("\(label)颜色：\(colorNames[index])")
                        .accessibilityValue(value.wrappedValue == hex ? "已选" : "未选")
                }
            }
            ColorPicker("自选\(label)颜色",selection: Binding(get: { color(value.wrappedValue) },set: { picked in
                guard let rgb = NSColor(picked).usingColorSpace(.sRGB) else { return }
                func channel(_ c: CGFloat) -> UInt32 { UInt32((min(1,max(0,c))*255).rounded()) }
                value.wrappedValue = (channel(rgb.redComponent)<<16) | (channel(rgb.greenComponent)<<8) | channel(rgb.blueComponent)
            }),supportsOpacity: false).font(.system(size: 11))
        }
    }
    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex>>16)&255)/255,green: Double((hex>>8)&255)/255,blue: Double(hex&255)/255)
    }
    private func randomize() {
        var next = model.appearance
        next.shape = BodyShape.allCases.randomElement()!
        next.ears = EarStyle.allCases.randomElement()!
        next.eyes = EyeStyle.allCases.randomElement()!
        next.glasses = GlassesStyle.allCases.randomElement()!
        next.accessory = HeadAccessory.allCases.randomElement()!
        next.bodyColor = CharacterAppearance.palette.randomElement()!
        next.accessoryColor = CharacterAppearance.palette.randomElement()!
        next.glassesColor = CharacterAppearance.palette.randomElement()!
        model.appearance = next
    }
}
