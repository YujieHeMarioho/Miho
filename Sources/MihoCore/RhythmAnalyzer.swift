import Foundation

public struct RhythmFrame: Equatable {
    public var energy: Double = 0
    public var bass: Double = 0
    public var beatCount: UInt64 = 0
    public var isActive: Bool = false
    public init() {}
}

/// Streaming analysis with fixed windows: results do not depend on device callback size.
/// No PCM is retained beyond scalar accumulators.
public final class RhythmAnalyzer {
    public let sampleRate: Double
    private let windowSize = 512
    private var samples = 0
    private var squares = 0.0
    private var bassSquares = 0.0
    private var lowPass = 0.0
    private var baseline = 0.0
    private var previousStrength = 0.0
    private var level = 0.0
    private var clock = 0.0
    private var lastBeat = -1.0
    private var result = RhythmFrame()

    public init(sampleRate: Double = 48_000) {
        precondition(sampleRate.isFinite && sampleRate > 0)
        self.sampleRate = sampleRate
    }

    @discardableResult
    public func consume(_ input: Float, sensitivity: Double = 1) -> RhythmFrame {
        let value = input.isFinite ? Double(input) : 0
        let alpha = 1 - exp(-2 * .pi * 180 / sampleRate)
        lowPass += alpha * (value - lowPass)
        squares += value * value
        bassSquares += lowPass * lowPass
        samples += 1
        guard samples == windowSize else { return result }
        let dt = Double(windowSize) / sampleRate
        clock += dt
        let rms = sqrt(squares / Double(windowSize))
        let bassRMS = sqrt(bassSquares / Double(windowSize))
        let gain = min(2, max(0.5, sensitivity))
        let active = rms > 0.0006
        let target = active ? min(1, pow(rms * 5 * gain, 0.65)) : 0
        let smoothing = 1 - exp(-dt / (target > level ? 0.025 : 0.16))
        level += smoothing * (target - level)
        let strength = rms * 0.45 + bassRMS * 0.55
        // Require an onset as well as energy above the recent adaptive floor.
        if active && strength > 0.006 / gain &&
            strength > baseline * 1.45 + 0.002 / gain &&
            strength > previousStrength * 1.12 + 0.001 / gain &&
            clock - lastBeat >= 0.18 {
            result.beatCount &+= 1
            lastBeat = clock
        }
        baseline += (strength - baseline) * (1 - exp(-dt / 0.45))
        previousStrength = strength
        result.energy = level
        result.bass = min(1, bassRMS * 7 * gain)
        result.isActive = active || level > 0.01
        samples = 0
        squares = 0
        bassSquares = 0
        return result
    }
}
