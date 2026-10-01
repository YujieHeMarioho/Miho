import Foundation

/// Only separated vocal data reaches the character's surrounding sound wave.
public struct SoundFieldFrame: Equatable, Sendable {
    public var vocalSpectrum = [Double](repeating: 0,count: 24)
    public var voice = 0.0, drive = 0.0
    public init() {}
}

public struct SoundField {
    public private(set) var frame = SoundFieldFrame()
    public init() {}
    @discardableResult public mutating func update(rhythm: RhythmFrame,drive: Double,enabled: Bool = true) -> SoundFieldFrame {
        func unit(_ v: Double) -> Double { v.isFinite ? min(1,max(0,v)) : 0 }
        let audible = enabled && unit(rhythm.vocalPresence) > 0.18 && unit(rhythm.vocalEnergy) > 0.025
        frame.voice = audible ? unit(rhythm.vocalEnergy) : 0
        frame.drive = enabled ? unit(drive) : 0
        frame.vocalSpectrum = (0..<24).map {
            audible && $0 < rhythm.vocalSpectrum.count ? unit(rhythm.vocalSpectrum[$0])*min(1,frame.drive*4) : 0
        }
        return frame
    }
}
