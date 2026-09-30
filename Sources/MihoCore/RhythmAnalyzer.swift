import Foundation
import Accelerate

public struct RhythmFrame: Equatable {
    /// Learned musical pulse, separate from short transient/attack features.
    public var pulse = BeatClockFrame()
    public var energy: Double = 0
    public var bass: Double = 0
    public var mid: Double = 0
    public var treble: Double = 0
    public var bassShare: Double = 0
    public var brightness: Double = 0
    /// Fast onset envelope for audio meters; the dance engine shapes its own recovery.
    public var transient: Double = 0
    public var beatCount: UInt64 = 0
    /// Age is measured by the audio sample clock, not the UI timer. Strength belongs
    /// to the last onset and stays available between audio and display callbacks.
    public var beatAge: Double = .infinity
    public var beatStrength: Double = 0
    /// Low/mid-frequency share of the attack. Treble-only hats can animate detail
    /// without resetting the main body groove. Retained with the last onset.
    public var beatWeight: Double = 1
    /// Vocal features; production supplies these from the locally separated stem.
    public var vocalPitch: Double = 0
    public var vocalPresence: Double = 0
    public var drumEnergy: Double = 0
    public var vocalEnergy: Double = 0
    public var vocalConfidence: Double = 0
    public var vocalSustain: Double = 0
    public var vocalPitchMotion: Double = 0
    public var vocalAccentCount: UInt64 = 0
    public var vocalAccentAge: Double = .infinity
    public var vocalAccentStrength: Double = 0
    public var isActive: Bool = false
    public init() {}
}

/// Fixed-window, three-band streaming onset analysis. A drum need not raise the
/// entire mix's volume: positive changes in its own band can trigger an impact.
/// A short Hann-windowed FFT distinguishes the attack's low/mid body from hats.
/// Only the current 512-sample analysis window is kept; audio is never recorded.
public final class RhythmAnalyzer {
    public let sampleRate: Double
    private let windowSize = 512
    private let dcAlpha: Double, lowAlpha: Double, midAlpha: Double
    private var dc = 0.0, low1 = 0.0, low2 = 0.0, mid1 = 0.0, mid2 = 0.0
    private var samples = 0, squares = 0.0, differenceSquares = 0.0, previousSample = 0.0
    private var bandSquares = [Double](repeating: 0,count: 3)
    private var bandLevel = [Double](repeating: 0,count: 3)
    private var previousBand = [Double](repeating: 0,count: 3)
    private var bandFloor = [Double](repeating: 0,count: 3)
    private var fluxFloor = 0.0, level = 0.0, clock = 0.0, lastBeat = -10.0
    private var result = RhythmFrame()
    private let fftSetup: FFTSetup
    private var window = [Float](repeating: 0,count: 512)
    private var hann = [Float](repeating: 0,count: 512)
    private var fftReal = [Float](repeating: 0,count: 256)
    private var fftImaginary = [Float](repeating: 0,count: 256)
    private var previousPower = [Double](repeating: 0,count: 256)
    private var melodicShare = 0.0
    private let vocalAnalyzer: VocalExpressionAnalyzer?

    public init(sampleRate: Double = 48_000, analyzeVoice: Bool = true) {
        precondition(sampleRate.isFinite && sampleRate > 0)
        self.sampleRate = sampleRate
        vocalAnalyzer = analyzeVoice ? VocalExpressionAnalyzer(sampleRate: sampleRate) : nil
        fftSetup = vDSP_create_fftsetup(9,FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&hann,512,Int32(vDSP_HANN_NORM))
        dcAlpha = 1-exp(-2 * .pi * 25/sampleRate)
        lowAlpha = 1-exp(-2 * .pi * 200/sampleRate)
        midAlpha = 1-exp(-2 * .pi * 2_500/sampleRate)
    }
    deinit { vDSP_destroy_fftsetup(fftSetup) }

    private func spectralAttackWeight() -> Double {
        // Real FFT packing: even samples in realp, odd samples in imagp.
        // https://developer.apple.com/documentation/accelerate/vdsp_fft_zrip
        for i in 0..<256 {
            fftReal[i] = window[i*2]*hann[i*2]
            fftImaginary[i] = window[i*2+1]*hann[i*2+1]
        }
        return fftReal.withUnsafeMutableBufferPointer { real in
            fftImaginary.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(realp: real.baseAddress!,imagp: imaginary.baseAddress!)
                vDSP_fft_zrip(fftSetup,&split,1,9,FFTDirection(FFT_FORWARD))
                var total = 0.0, grounded = 0.0, melodic = 0.0, allPower = 0.0
                // DC/Nyquist are packed together in bin zero; neither is a dance beat.
                for bin in 1..<256 {
                    let power = Double(real[bin])*Double(real[bin])+Double(imaginary[bin])*Double(imaginary[bin])
                    let rise = max(0,power-previousPower[bin])
                    total += rise
                    let frequency = Double(bin)*sampleRate/512
                    if frequency < 3_500 { grounded += rise }
                    if (120...2_200).contains(frequency) { melodic += power }
                    allPower += power
                    previousPower[bin] = power
                }
                melodicShare = melodic/max(allPower,1e-12)
                return min(1,sqrt(grounded/max(total,1e-12)))
            }
        }
    }

    @discardableResult public func consume(_ input: Float, sensitivity: Double = 1) -> RhythmFrame {
        let raw = input.isFinite ? min(4,max(-4,Double(input))) : 0
        let gain = sensitivity.isFinite ? min(2,max(0.5,sensitivity)) : 1
        let vocal = vocalAnalyzer?.consume(raw,melodicShare: melodicShare,sensitivity: gain) ?? VocalExpressionFrame()
        result.vocalPitch = vocal.pitch
        result.vocalPresence = vocal.confidence
        result.vocalEnergy = vocal.energy; result.vocalConfidence = vocal.confidence
        result.vocalSustain = vocal.sustain; result.vocalPitchMotion = vocal.pitchMotion
        result.vocalAccentCount = vocal.accentCount; result.vocalAccentAge = vocal.accentAge
        result.vocalAccentStrength = vocal.accentStrength
        dc += dcAlpha*(raw-dc)
        let value = raw-dc
        window[samples] = Float(value)
        low1 += lowAlpha*(value-low1); low2 += lowAlpha*(low1-low2)
        mid1 += midAlpha*(value-mid1); mid2 += midAlpha*(mid1-mid2)
        let low = low2, mid = mid2-low2, high = value-mid2
        squares += value*value
        bandSquares[0] += low*low; bandSquares[1] += mid*mid; bandSquares[2] += high*high
        let difference = value-previousSample
        differenceSquares += difference*difference; previousSample = value
        samples += 1
        guard samples == windowSize else {
            if result.beatCount > 0 { result.beatAge = clock+Double(samples)/sampleRate-lastBeat }
            return result
        }
        let dt = Double(windowSize)/sampleRate
        clock += dt
        let rms = sqrt(squares/Double(windowSize))
        let active = rms > 0.0006
        let target = active ? min(1,pow(rms*5*gain,0.65)) : 0
        level += (target-level)*(1-exp(-dt/(target > level ? 0.025 : 0.14)))

        let attackWeight = spectralAttackWeight()
        var flux = 0.0, strongestRise = 0.0, hasBandAttack = false
        for band in 0..<3 {
            let rms = sqrt(bandSquares[band]/Double(windowSize))
            bandLevel[band] += (rms-bandLevel[band])*(1-exp(-dt/(rms > bandLevel[band] ? 0.010 : 0.045)))
            let rise = max(0,log1p(bandLevel[band]*120*gain)-log1p(previousBand[band]*120*gain))
            let weight = band == 0 ? 1.0 : band == 1 ? 0.85 : 0.65
            flux += rise*weight
            strongestRise = max(strongestRise,rise)
            if bandLevel[band] > 0.0025/gain &&
                bandLevel[band] > bandFloor[band]*1.25+0.0007/gain &&
                bandLevel[band] > previousBand[band]*1.08+0.0003/gain {
                hasBandAttack = true
            }
        }
        let onset = active && hasBandAttack && flux > fluxFloor*1.6+0.055 &&
            strongestRise > 0.04 && clock-lastBeat >= 0.11
        let impulse = min(1,flux*2.2)
        result.transient = max(impulse,result.transient*exp(-dt/0.065))
        if onset {
            result.beatCount &+= 1
            lastBeat = clock
            result.beatStrength = min(1,0.25+impulse*0.55+target*0.20)
            result.beatWeight = attackWeight
        }
        fluxFloor += (flux-fluxFloor)*(1-exp(-dt/0.5))
        for band in 0..<3 {
            bandFloor[band] += (bandLevel[band]-bandFloor[band])*(1-exp(-dt/0.35))
            previousBand[band] = bandLevel[band]; bandSquares[band] = 0
        }
        result.beatAge = result.beatCount > 0 ? clock-lastBeat : .infinity
        result.energy = level
        result.bass = min(1,bandLevel[0]*7*gain)
        result.mid = min(1,bandLevel[1]*7*gain)
        result.treble = min(1,bandLevel[2]*7*gain)
        let textureSmoothing = 1-exp(-dt/0.25)
        let bassTarget = active ? min(1,bandLevel[0]*bandLevel[0]/max(rms*rms,1e-12)) : 0
        let brightTarget = active ? min(1,sqrt(differenceSquares/max(squares,1e-12))*sampleRate/(2 * .pi * 4_000)) : 0
        result.bassShare += (bassTarget-result.bassShare)*textureSmoothing
        result.brightness += (brightTarget-result.brightness)*textureSmoothing
        result.isActive = active || level > 0.01
        samples = 0; squares = 0; differenceSquares = 0
        return result
    }
}
