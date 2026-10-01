import Foundation

public struct BeatClockFrame: Equatable {
    /// Unwrapped position in beats, extrapolatable with the audio clock.
    public var position = 0.0
    public var bpm = 0.0
    public var confidence = 0.0
    public var probability = 0.0
    public var downbeatProbability = 0.0
    public init() {}
}

/// Causal tempo/phase decoder for learned BeatNet probabilities. The 8-second
/// history contains scalar activations, not buffered audio or look-ahead. Tempo
/// evidence spans several beats; the current beat phase advances immediately.
/// This is Miho's decoder, not a port of BeatNet's particle filter.
public final class BeatClock {
    private var history: [Double] = []
    private var peaks: [(Double,Double)] = []
    private var clock = 0.0, estimateAt = 0.0, lastPeak = -10.0
    private var previous = 0.0, beforePrevious = 0.0
    private var period = 0.5, position = 0.0, confidence = 0.0
    private var locked = false, evidence = 0.0, candidateBPM = 0.0, candidateAge = 0.0
    public private(set) var frame = BeatClockFrame()
    public init() {}
    public func reset() {
        history.removeAll(keepingCapacity: true);peaks.removeAll(keepingCapacity: true)
        clock = 0;estimateAt = 0;lastPeak = -10;previous = 0;beforePrevious = 0
        period = 0.5;position = 0;confidence = 0;locked = false;evidence = 0;candidateAge = 0;candidateBPM = 0
        frame = BeatClockFrame()
    }
    public func consume(beat: Double,downbeat: Double) -> BeatClockFrame {
        func unit(_ x: Double) -> Double { x.isFinite ? min(1,max(0,x)) : 0 }
        let dt = 0.02, activation = unit(beat)+unit(downbeat)
        clock += dt
        // Shift timestamps to the centre of the trailing Hann window. Peak
        // confirmation adds one hop but never changes the feature timestamp.
        let featureTime = clock-705/22_050.0
        if locked { position += dt/period }
        history.append(activation);if history.count > 400 { history.removeFirst() }
        if previous > beforePrevious && previous >= activation && previous > 0.12 && featureTime-dt-lastPeak > 0.16 {
            let peakTime = featureTime-dt
            lastPeak = peakTime;peaks.append((peakTime,previous))
            if locked {
                let phaseError = (position-dt/period)-round(position-dt/period)
                // Correct a small timing error gradually; do not snap to every
                // subdivision or jump halfway around the cycle on a fill.
                if abs(phaseError) < 0.23 {
                    let adjustment = phaseError*min(0.18,previous*0.22)
                    position -= min(dt/period*0.7,max(-dt/period*0.7,adjustment))
                }
            }
        }
        beforePrevious = previous;previous = activation
        peaks.removeAll { featureTime-$0.0 > 8 }
        if clock >= estimateAt {
            estimateAt = clock+0.20
            estimate(featureTime: featureTime)
        }
        let supported = featureTime-lastPeak < max(1.2,period*3) && (history.suffix(50).max() ?? 0) > 0.12
        let desiredConfidence = locked && supported ? evidence : 0
        confidence += (desiredConfidence-confidence)*(1-exp(-dt/(desiredConfidence > confidence ? 0.25 : 0.55)))
        frame.position = position
        frame.bpm = locked ? 60/period : 0
        frame.confidence = confidence
        frame.probability = unit(beat);frame.downbeatProbability = unit(downbeat)
        return frame
    }
    private func estimate(featureTime: Double) {
        guard peaks.count >= 3,history.count >= 90 else { return }
        let values = history
        func correlation(_ lag: Double) -> Double {
            let first = Int(ceil(lag));guard first+30 < values.count else { return 0 }
            var cross = 0.0, aa = 0.0, bb = 0.0
            for i in first..<values.count {
                let old = Double(i)-lag, j = Int(old), f = old-Double(j)
                let a = max(0,values[i]-0.035)
                let b = max(0,values[j]*(1-f)+values[min(j+1,values.count-1)]*f-0.035)
                let w = exp(-Double(values.count-1-i)*0.02/3.5)
                cross += a*b*w;aa += a*a*w;bb += b*b*w
            }
            return cross/sqrt(max(1e-12,aa*bb))
        }
        var bestBPM = 0.0, bestScore = 0.0
        for bpm in 55...215 {
            let p = 60/Double(bpm)
            guard Double(values.count)*0.02 >= max(1.8,p*2.6) else { continue }
            let lag = p/0.02
            let correlationScore = correlation(lag)*0.90+correlation(lag*2)*0.10
            // A weak prior resolves equally plausible half/double-time readings;
            // evidence and an established tempo dominate this preference.
            var phaseReal = 0.0, phaseImaginary = 0.0, mass = 0.0
            for (t,strength) in peaks where featureTime-t < 5 {
                let w = strength*exp(-(featureTime-t)/2.5), angle = 2*Double.pi*t/p
                phaseReal += cos(angle)*w;phaseImaginary += sin(angle)*w;mass += w
            }
            let coherence = hypot(phaseReal,phaseImaginary)/max(1e-9,mass)
            let rhythmicScore = correlationScore*0.55+coherence*0.45
            let prior = 1-0.09*abs(log2(Double(bpm)/115))
            let continuity = locked ? 1+0.07*exp(-pow(log2(Double(bpm)/(60/period))/0.10,2)) : 1
            let score = rhythmicScore*prior*continuity
            if score > bestScore { bestScore = score;bestBPM = Double(bpm) }
        }
        guard bestBPM > 0,bestScore > 0.22 else { evidence *= 0.8;return }
        if !locked {
            period = 60/bestBPM
            // Weighted circular phase across recent learned beats, rather than
            // guessing phase from the loudest high-frequency transient.
            var real = 0.0, imaginary = 0.0
            for (t,strength) in peaks.suffix(12) {
                let angle = 2*Double.pi*t/period,w = strength*exp(-(featureTime-t)/3)
                real += cos(angle)*w;imaginary += sin(angle)*w
            }
            let anchor = atan2(imaginary,real)/(2*Double.pi)*period
            position = (featureTime-anchor)/period;locked = true
        } else {
            let relative = abs(log2(bestBPM/(60/period)))
            if relative < 0.12 {
                let desiredPeriod = 60/bestBPM
                period += (desiredPeriod-period)*0.20;candidateAge = 0
            } else {
                if abs(bestBPM-candidateBPM) < 5 { candidateAge += 0.2 }
                else { candidateBPM = bestBPM;candidateAge = 0.2 }
                // A new section or real tempo change needs sustained evidence.
                // Double-time hats or one fill cannot replace the body pulse.
                if candidateAge >= (confidence < 0.45 ? 0.6 : 1.0) {
                    let ratio = bestBPM/(60/period)
                    // An octave is a metrical reinterpretation, not a gradual
                    // tempo ramp through musically unrelated intermediate BPMs.
                    if abs(log2(ratio)-1) < 0.12 { position *= 2 }
                    else if abs(log2(ratio)+1) < 0.12 { position *= 0.5 }
                    period = 60/bestBPM;candidateAge = 0
                }
            }
        }
        // Re-anchor gradually to a circular consensus of recent strong peaks.
        // Peak-only PLLs cannot recover when a section change leaves them half
        // a beat away: every new peak would otherwise fall outside the gate.
        var phaseReal = 0.0, phaseImaginary = 0.0, phaseMass = 0.0
        for (t,strength) in peaks where featureTime-t < period*5 {
            let w = strength*strength*exp(-(featureTime-t)/(period*2))
            let angle = 2*Double.pi*t/period
            phaseReal += cos(angle)*w;phaseImaginary += sin(angle)*w;phaseMass += w
        }
        let phaseCoherence = hypot(phaseReal,phaseImaginary)/max(1e-9,phaseMass)
        if phaseCoherence > 0.35 {
            let anchor = atan2(phaseImaginary,phaseReal)/(2*Double.pi)*period
            let desiredPosition = (featureTime-anchor)/period
            let error = position-desiredPosition
            let wrapped = error-round(error)
            position -= min(0.055,max(-0.055,wrapped*0.22))
        }
        evidence = min(1,max(0,(bestScore-0.15)/0.55))*min(1,phaseCoherence/0.5)
    }
}
