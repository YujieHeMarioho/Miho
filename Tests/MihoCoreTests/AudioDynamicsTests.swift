import XCTest
@testable import MihoCore

final class AudioDynamicsTests: XCTestCase {
    private func voice(_ volume: Double) -> RhythmFrame {
        var f = RhythmFrame();f.energy = 0.8;f.vocalPresence = 0.95;f.vocalEnergy = volume
        f.vocalConfidence = 0.95;f.vocalPitch = 220
        return f
    }
    func testLoudSyllableImmediatelyGrowsCharacterAndJumpsHigherThanQuietOne() {
        let e = Choreographer(seed: 42)
        for _ in 0..<120 { e.update(dt: 1/60,rhythm: voice(0.06)) }
        let quiet = e.pose
        for _ in 0..<8 { e.update(dt: 1/60,rhythm: voice(0.60)) }
        XCTAssertGreaterThan(e.pose.scale-quiet.scale,0.07)
        XCTAssertGreaterThan(e.pose.y-quiet.y,0.04)
        for _ in 0..<90 { e.update(dt: 1/60,rhythm: voice(0.60)) }
        XCTAssertGreaterThan(e.pose.y,quiet.y*6)
        XCTAssertGreaterThan(e.pose.scale,1.11)
        for _ in 0..<90 { e.update(dt: 1/60,rhythm: voice(0.06)) }
        XCTAssertEqual(e.pose.y,quiet.y,accuracy: 0.003)
        XCTAssertEqual(e.pose.scale,quiet.scale,accuracy: 0.003)
    }
    func testHeldNoteKeepsDirectionButFollowsItsCurrentLoudness() {
        let e = Choreographer(seed: 42)
        var loud = voice(0.7);loud.vocalSustain = 0.95
        for _ in 0..<240 { e.update(dt: 1/60,rhythm: loud) }
        let peak = e.pose
        var soft = loud;soft.vocalEnergy = 0.08
        for _ in 0..<90 { e.update(dt: 1/60,rhythm: soft) }
        XCTAssertLessThan(e.pose.y,peak.y*0.20)
        XCTAssertLessThan(e.pose.scale,1.025)
        XCTAssertGreaterThan(e.pose.body.y*peak.body.y,0)
        XCTAssertEqual(e.gesture,.holding)
    }
    func testDrumAccentCombinesWithVoiceWithoutReplacingItsDirection() {
        let voiceOnly = Choreographer(seed: 42), combined = Choreographer(seed: 42)
        var f = voice(0.35)
        for _ in 0..<120 { voiceOnly.update(dt: 1/60,rhythm: f);combined.update(dt: 1/60,rhythm: f) }
        var largestBoost = 0.0
        for i in 0..<90 {
            let plain = voiceOnly.update(dt: 1/60,rhythm: f)
            f.beatCount = UInt64(i/30+1);f.beatAge = Double(i%30)/60;f.beatStrength = 1;f.beatWeight = 1;f.drumEnergy = 0.9
            let mixed = combined.update(dt: 1/60,rhythm: f)
            largestBoost = max(largestBoost,mixed.y-plain.y)
            XCTAssertEqual(mixed.body.y,plain.body.y,accuracy: 0.0001)
            f.beatCount = 0;f.beatAge = .infinity
        }
        XCTAssertGreaterThan(largestBoost,0.004)
        XCTAssertLessThan(largestBoost,0.025)
    }
    func testSoundFieldHasNoInventedMotionAndQuietHistoryIsSmaller() {
        var field = SoundField(), f = voice(0.08)
        f.drumEnergy = 0.15;f.spectrum[8] = 0.20
        for _ in 0..<96 { field.update(dt: 1/30,rhythm: f,drive: 0.1) }
        let quiet = field.frame.vocals.last!
        f.vocalEnergy = 0.60;f.spectrum[8] = 0.75
        field.update(dt: 1/30,rhythm: f,drive: 0.8)
        XCTAssertGreaterThan(field.frame.vocals.last!,quiet*6)
        XCTAssertEqual(field.frame.spectrum[8],0.75)
        for _ in 0..<100 { field.update(dt: 1/30,rhythm: f,drive: 1,enabled: false) }
        XCTAssertEqual(field.frame.vocals,Array(repeating: 0,count: 96))
        XCTAssertEqual(field.frame.drums,Array(repeating: 0,count: 96))
        XCTAssertEqual(field.frame.spectrum,Array(repeating: 0,count: 24))
        XCTAssertEqual(field.frame.drive,0)
    }
    func testSpectrumShowsActualFrequencyAndPreservesLoudnessDifference() {
        func tone(_ frequency: Double,_ amplitude: Double) -> [Double] {
            let a = RhythmAnalyzer(analyzeVoice: false)
            var f = RhythmFrame()
            for i in 0..<24_000 { f = a.consume(Float(amplitude*sin(Double(i)/48_000*2*Double.pi*frequency))) }
            return f.spectrum
        }
        let soft = tone(500,0.015), loud = tone(500,0.20), high = tone(2_500,0.20)
        let lowPeak = loud.indices.max(by: { loud[$0] < loud[$1] })!
        let highPeak = high.indices.max(by: { high[$0] < high[$1] })!
        XCTAssertGreaterThan(highPeak,lowPeak+3)
        XCTAssertGreaterThan(loud[lowPeak],soft[lowPeak]*2)
        XCTAssertTrue(loud.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }
}
