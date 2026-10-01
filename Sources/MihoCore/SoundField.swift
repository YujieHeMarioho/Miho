import Foundation

public struct SoundFieldFrame: Equatable, Sendable {
    public var spectrum = [Double](repeating: 0,count: 24)
    public var vocalSpectrum = [Double](repeating: 0,count: 24)
    public var voice = 0.0, drive = 0.0, bass = 0.0, transient = 0.0
    public var mode: DanceMode = .singer
    public init() {}
}

public struct SoundField {
    public private(set) var frame = SoundFieldFrame()
    public init() {}
    @discardableResult public mutating func update(rhythm: RhythmFrame,drive: Double,mode: DanceMode = .singer,enabled: Bool = true) -> SoundFieldFrame {
        func unit(_ v: Double) -> Double { v.isFinite ? min(1,max(0,v)) : 0 }
        let audibleVoice = enabled && unit(rhythm.vocalPresence) > 0.18 && unit(rhythm.vocalEnergy) > 0.025
        frame.mode = mode
        frame.voice = audibleVoice ? unit(rhythm.vocalEnergy) : 0
        frame.drive = enabled ? unit(drive) : 0
        frame.vocalSpectrum = (0..<24).map {
            audibleVoice && $0 < rhythm.vocalSpectrum.count ? unit(rhythm.vocalSpectrum[$0])*min(1,frame.drive*4) : 0
        }
        frame.spectrum = mode == .singer ? frame.vocalSpectrum : (0..<24).map {
            enabled && $0 < rhythm.spectrum.count ? unit(rhythm.spectrum[$0])*min(1,frame.drive*4) : 0
        }
        frame.bass = mode == .singer ? frame.spectrum.prefix(6).max() ?? 0 : enabled ? unit(rhythm.bass) : 0
        let age = mode == .singer ? rhythm.vocalAccentAge : rhythm.beatAge
        let strength = mode == .singer ? rhythm.vocalAccentStrength : rhythm.beatStrength*rhythm.beatWeight
        frame.transient = enabled && age.isFinite && age >= 0 ? unit(strength)*exp(-age/0.12)*frame.drive : 0
        return frame
    }
}
