import Foundation

/// Audio-derived graphics only: no clock-generated waves or random bars.
public struct SoundFieldFrame: Equatable, Sendable {
    public var spectrum = [Double](repeating: 0,count: 24)
    public var vocalSpectrum = [Double](repeating: 0,count: 24)
    public var drumSpectrum = [Double](repeating: 0,count: 24)
    public var vocals = [Double](repeating: 0,count: 96)
    public var drums = [Double](repeating: 0,count: 96)
    public var voice = 0.0, percussion = 0.0, drive = 0.0
    public init() {}
}

public struct SoundField {
    public private(set) var frame = SoundFieldFrame()
    private var elapsed = 0.0
    public init() {}
    @discardableResult public mutating func update(dt: Double,rhythm: RhythmFrame,drive: Double,enabled: Bool = true) -> SoundFieldFrame {
        func unit(_ v: Double) -> Double { v.isFinite ? min(1,max(0,v)) : 0 }
        func bands(_ v: [Double]) -> [Double] {
            (0..<24).map { enabled && $0 < v.count ? unit(v[$0]) : 0 }
        }
        frame.spectrum = bands(rhythm.spectrum)
        frame.vocalSpectrum = bands(rhythm.vocalSpectrum)
        frame.drumSpectrum = bands(rhythm.drumSpectrum)
        frame.voice = enabled ? unit(rhythm.vocalEnergy)*unit(rhythm.vocalPresence) : 0
        frame.percussion = enabled ? unit(rhythm.drumEnergy) : 0
        frame.drive = enabled ? unit(drive) : 0
        elapsed += dt.isFinite ? min(0.1,max(0,dt)) : 0
        while elapsed >= 1.0/30 {
            elapsed -= 1.0/30
            frame.vocals.removeFirst(); frame.vocals.append(frame.voice)
            frame.drums.removeFirst(); frame.drums.append(frame.percussion)
        }
        return frame
    }
}
