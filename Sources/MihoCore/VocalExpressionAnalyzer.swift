import Foundation

struct VocalExpressionFrame {
    var energy = 0.0, confidence = 0.0, sustain = 0.0, pitchMotion = 0.0, pitch = 0.0
    var accentCount: UInt64 = 0
    var accentAge = Double.infinity, accentStrength = 0.0
}

/// Periodic pitch and phrase cues. Production passes the separated vocal stem.
/// Band-limited, downsampled periodicity distinguishes held harmonic notes from
/// unvoiced hats. About 43 ms of scratch audio is overwritten continuously.
final class VocalExpressionAnalyzer {
    private let analysisRate: Double, dcAlpha: Double, lowAlpha: Double, ratio: Double
    private var dc = 0.0, low1 = 0.0, low2 = 0.0, samplePhase = 0.0
    private var ring = [Double](repeating: 0,count: 512)
    private var ordered = [Double](repeating: 0,count: 512)
    private var difference = [Double](repeating: 0,count: 160)
    private var cursor = 0, filled = 0, hop = 0
    private var clock = 0.0, voiceAge = 0.0, gap = 0.0, floor = 0.0, previousTarget = 0.0
    private var smoothedPitch: Double?, pendingAttack = 0.0, pendingUntil = -10.0, lastAccent = -10.0
    private var result = VocalExpressionFrame()

    init(sampleRate: Double) {
        analysisRate = min(12_000,sampleRate)
        ratio = analysisRate/sampleRate
        dcAlpha = 1-exp(-2 * .pi * 85/sampleRate)
        lowAlpha = 1-exp(-2 * .pi * 1_800/sampleRate)
    }
    func consume(_ input: Double, melodicShare: Double, sensitivity: Double) -> VocalExpressionFrame {
        dc += dcAlpha*(input-dc)
        low1 += lowAlpha*(input-dc-low1); low2 += lowAlpha*(low1-low2)
        samplePhase += ratio
        guard samplePhase >= 1 else { return result }
        samplePhase -= 1
        ring[cursor] = low2; cursor = (cursor+1)%512
        filled = min(512,filled+1); hop += 1; clock += 1/analysisRate
        result.accentAge = result.accentCount > 0 ? clock-lastAccent : .infinity
        guard filled == 512 && hop >= 128 else { return result }
        let dt = Double(hop)/analysisRate; hop = 0
        for i in 0..<512 { ordered[i] = ring[(cursor+i)%512] }
        let rms = sqrt(ordered.reduce(0) { $0+$1*$1 }/512)
        let minLag = max(2,Int(analysisRate/700)), maxLag = max(4,min(158,Int(analysisRate/85)))
        var running = 0.0
        for lag in 1...maxLag {
            var sum = 0.0
            for i in 0..<256 { let d = ordered[i]-ordered[i+lag]; sum += d*d }
            running += sum
            difference[lag] = running > 1e-12 ? sum*Double(lag)/running : 1
        }
        var selected: Int?
        if rms > 0.0008 && melodicShare > 0.08 && minLag+1 < maxLag {
            for lag in (minLag+1)..<maxLag {
                if difference[lag] < 0.22 && difference[lag] <= difference[lag-1] && difference[lag] < difference[lag+1] {
                    selected = lag; break
                }
            }
        }
        let harmonic = selected.map { max(0,1-difference[$0]) } ?? 0
        let share = min(1,max(0,(melodicShare-0.06)/0.35))
        let confidence = harmonic*share
        let target = 1-exp(-rms*5*sensitivity)
        result.energy += (target-result.energy)*(1-exp(-dt/(target > result.energy ? 0.045 : 0.15)))
        result.confidence += (confidence-result.confidence)*(1-exp(-dt/(confidence > result.confidence ? 0.055 : 0.12)))
        // A fresh syllable starts a new extension even if pitch stays voiced
        // through the whole verse. Small vibrato and gradual crescendos do not.
        let rearticulation = target > previousTarget+max(0.018,target*0.10) && target > floor*0.85+0.015
        if rearticulation { voiceAge = 0 }
        if confidence > 0.45 && target > 0.04 { voiceAge += dt; gap = 0 }
        else {
            gap += dt
            if gap > 0.12 { voiceAge = max(0,voiceAge-dt*4) }
        }
        let held = min(1,max(0,(voiceAge-0.16)/0.48))
        result.sustain += (held*result.confidence-result.sustain)*(1-exp(-dt/0.10))
        var pitchMotion = 0.0
        if let lag = selected, confidence > 0.45 {
            let a = difference[lag-1], b = difference[lag], c = difference[lag+1]
            let denominator = a-2*b+c
            let offset = abs(denominator) > 1e-9 ? min(0.5,max(-0.5,0.5*(a-c)/denominator)) : 0
            let pitch = log2(analysisRate/(Double(lag)+offset))
            if let old = smoothedPitch {
                let change = pitch-old
                // Reject octave jumps and suppress ordinary vibrato; follow the
                // direction of a sustained rise/fall rather than each waveform cycle.
                if abs(change) < 0.45 { pitchMotion = tanh(change/dt*0.12)*confidence }
                smoothedPitch = old+min(0.12,max(-0.12,change))*(1-exp(-dt/0.10))
            } else { smoothedPitch = pitch }
        } else if gap > 0.20 { smoothedPitch = nil }
        result.pitch = smoothedPitch.map { pow(2,$0) } ?? 0
        result.pitchMotion += (pitchMotion-result.pitchMotion)*(1-exp(-dt/0.16))
        // A quick voiced rise is an accent; a held vowel does not retrigger as it
        // vibrates. Briefly defer the attack until periodicity has been measured.
        if rearticulation && target > floor*1.05+0.025 {
            pendingAttack = min(1,(target-previousTarget)*4+target*0.60)
            pendingUntil = clock+0.12
        }
        if clock <= pendingUntil && pendingAttack > 0 && result.confidence > 0.40 && clock-lastAccent >= 0.22 {
            result.accentCount &+= 1; lastAccent = clock
            result.accentStrength = pendingAttack*(0.55+0.45*result.confidence)
            result.accentAge = 0; pendingAttack = 0
        }
        floor += (target-floor)*(1-exp(-dt/0.4)); previousTarget = target
        return result
    }
}
