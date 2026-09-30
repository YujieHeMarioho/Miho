import XCTest
@testable import MihoCore

final class VocalExpressionTests: XCTestCase {
    private func voicedSample(_ phase: Double,_ amplitude: Double) -> Float {
        Float(amplitude*(sin(phase)+0.40*sin(2*phase)+0.18*sin(3*phase)))
    }
    func testHeldHarmonicNoteDevelopsSustainWithoutRepeatedPunches() {
        for rate in [44_100.0,48_000.0,96_000.0] {
            let analyzer = RhythmAnalyzer(sampleRate: rate)
            var frame = RhythmFrame(), countAtOneSecond: UInt64 = 0
            for i in 0..<Int(rate*1.7) {
                let time = Double(i)/rate
                let envelope = min(1,time/0.08)*(0.12+0.008*sin(2 * .pi*5*time))
                frame = analyzer.consume(voicedSample(2 * .pi*220*time,envelope))
                if i == Int(rate) { countAtOneSecond = frame.vocalAccentCount }
            }
            XCTAssertGreaterThan(frame.vocalConfidence,0.85)
            XCTAssertGreaterThan(frame.vocalSustain,0.80)
            XCTAssertGreaterThan(frame.vocalEnergy,0.3)
            XCTAssertEqual(frame.vocalAccentCount,countAtOneSecond,"vibrato is not a string of punches")
            XCTAssertLessThan(abs(frame.vocalPitchMotion),0.08)
        }
    }
    func testRisingAndFallingMelodyHaveOppositeSmoothGestures() {
        func glide(_ rising: Bool) -> RhythmFrame {
            let analyzer = RhythmAnalyzer(); var phase = 0.0, frame = RhythmFrame()
            for i in 0..<72_000 {
                let time = Double(i)/48_000
                let frequency = rising ? 180*pow(2,time*0.30) : 350*pow(2,-time*0.30)
                phase += 2 * .pi*frequency/48_000
                frame = analyzer.consume(voicedSample(phase,0.13))
            }
            return frame
        }
        let up = glide(true), down = glide(false)
        XCTAssertGreaterThan(up.vocalConfidence,0.80); XCTAssertGreaterThan(down.vocalConfidence,0.80)
        XCTAssertGreaterThan(up.vocalPitchMotion,0.15)
        XCTAssertLessThan(down.vocalPitchMotion,-0.15)
        XCTAssertEqual(up.vocalPitch,180*pow(2,0.45),accuracy: 12)
        XCTAssertLessThan(down.vocalPitch,280)
    }
    func testShortVoicedEmphasesAreSeparateFromAQuietHeldPhrase() {
        let analyzer = RhythmAnalyzer(); var frame = RhythmFrame()
        let phrases = [0.15,0.75,1.35]
        var accents: [Double] = [], lastCount: UInt64 = 0
        for i in 0..<96_000 {
            let time = Double(i)/48_000
            var amplitude = 0.0
            for start in phrases {
                let age = time-start
                if age >= 0 && age < 0.30 { amplitude += 0.22*min(1,age/0.015)*min(1,(0.30-age)/0.04) }
            }
            frame = analyzer.consume(voicedSample(2 * .pi*245*time,amplitude))
            if frame.vocalAccentCount != lastCount { accents.append(time); lastCount = frame.vocalAccentCount }
        }
        XCTAssertEqual(accents.count,3,"\(accents)")
        for phrase in phrases { XCTAssertLessThan((accents.filter { $0 > phrase }.min() ?? 100)-phrase,0.15) }
        XCTAssertLessThan(frame.vocalSustain,0.25)
    }
    func testHatsAndLowKicksDoNotMasqueradeAsHeldSinging() {
        for frequency in [60.0,8_000.0] {
            let analyzer = RhythmAnalyzer(); var frame = RhythmFrame()
            for i in 0..<48_000 {
                let time = Double(i)/48_000
                frame = analyzer.consume(Float(0.2*sin(2 * .pi*frequency*time)))
            }
            XCTAssertLessThan(frame.vocalConfidence,0.15,"\(frequency)")
            XCTAssertLessThan(frame.vocalSustain,0.15)
        }
    }
    func testRealVoicedFeaturesDrivePunchWithoutRelyingOnDrumEvents() {
        let analyzer = RhythmAnalyzer(), engine = Choreographer(seed: 42)
        var frame = RhythmFrame(), count: UInt64 = 0
        var detected: Double?, response: Double?
        for i in 0..<48_000 {
            let time = Double(i)/48_000, age = time-0.15
            let amplitude = age >= 0 && age < 0.30 ? 0.22*min(1,age/0.015)*min(1,(0.30-age)/0.04) : 0
            frame = analyzer.consume(voicedSample(2 * .pi*245*time,amplitude))
            if frame.vocalAccentCount != count {
                detected = time; count = frame.vocalAccentCount
                XCTAssertGreaterThan(frame.vocalAccentStrength,0.20)
            }
            if (i+1)%800 == 0 {
                frame.beatCount = 0 // isolate the singing path from the drum path
                engine.update(dt: 1/60,rhythm: frame)
                if response == nil && engine.impact > 0.15 && engine.pose.body.x < -0.012 { response = time }
            }
        }
        XCTAssertNotNil(detected); XCTAssertNotNil(response)
        XCTAssertLessThan((response ?? 100)-0.15,0.15)
    }
}
