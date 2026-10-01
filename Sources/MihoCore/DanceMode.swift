import Foundation

public enum DanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case singer, music
    public var id: String { rawValue }
    public var label: String { self == .singer ? "歌手模式" : "音乐模式" }
}
