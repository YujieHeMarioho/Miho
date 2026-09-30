import Foundation

public enum BodyShape: String, CaseIterable, Codable, Sendable {
    case sphere, bean, squircle
    public var label: String { switch self { case .sphere: return "圆球"; case .bean: return "豆豆"; case .squircle: return "圆方" } }
    public var radii: (Double,Double,Double) {
        switch self { case .sphere: return (0.84,0.84,0.84); case .bean: return (0.78,0.91,0.78); case .squircle: return (0.82,0.82,0.82) }
    }
}
public enum EarStyle: String, CaseIterable, Codable, Sendable {
    case none, short, bunny, cat
    public var label: String { switch self { case .none: return "无"; case .short: return "短耳"; case .bunny: return "兔耳"; case .cat: return "猫耳" } }
}
public enum EyeStyle: String, CaseIterable, Codable, Sendable {
    case dot, happy, sleepy, wink
    public var label: String { switch self { case .dot: return "圆眼"; case .happy: return "开心"; case .sleepy: return "困困"; case .wink: return "眨眼" } }
}
public enum GlassesStyle: String, CaseIterable, Codable, Sendable {
    case none, sunglasses, round
    public var label: String { switch self { case .none: return "无"; case .sunglasses: return "墨镜"; case .round: return "圆框" } }
}
public enum HeadAccessory: String, CaseIterable, Codable, Sendable {
    case none, headphones, beanie, crown
    public var label: String { switch self { case .none: return "无"; case .headphones: return "耳机"; case .beanie: return "毛线帽"; case .crown: return "皇冠" } }
}
public enum SurfaceStyle: String, CaseIterable, Codable, Sendable {
    case velvet, satin
    public var label: String { self == .velvet ? "柔软" : "光泽" }
}

/// All choices are local procedural 3D geometry. This schema follows the public Dots
/// customization categories; it is not a copy of OpenAI's unpublished asset catalog.
public struct CharacterAppearance: Codable, Equatable, Sendable {
    public var name = "咪虎"
    public var shape: BodyShape = .sphere
    public var ears: EarStyle = .short
    public var eyes: EyeStyle = .dot
    public var glasses: GlassesStyle = .sunglasses
    public var accessory: HeadAccessory = .headphones
    public var surface: SurfaceStyle = .velvet
    public var bodyColor: UInt32 = 0x05B3E4
    public var accessoryColor: UInt32 = 0x844526
    public var glassesColor: UInt32 = 0x081A21
    public init() {}

    public var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "咪虎" : String(name.prefix(24)) }
    public static let palette: [UInt32] = [0x05B3E4,0x80CDB1,0xA799E4,0xF397B9,0xF1B553,0xE87957,0xF2EBDD,0x8EAECC,0x844526,0x29333E]
    public static func load(_ data: Data?) -> CharacterAppearance {
        guard let data, let decoded = try? JSONDecoder().decode(Self.self,from: data) else { return Self() }
        return decoded
    }
}
