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
    func testDrumsAndMixedSpectrumCannotChangeVoiceMotionOrSurroundingWave() {
        let singer = Choreographer(seed: 42), mixed = Choreographer(seed: 42)
        var a = SoundField(), b = SoundField()
        for i in 0..<600 {
            var f = voice(i < 360 ? 0.35 : 0)
            f.vocalSpectrum[8] = i < 360 ? 0.6 : 0
            f.vocalAccentCount = UInt64(i/30+1); f.vocalAccentAge = Double(i%30)/60; f.vocalAccentStrength = 0.8
            var loud = f
            loud.energy = 1; loud.drumEnergy = 1; loud.bass = 1
            loud.beatCount = UInt64(i/5+1); loud.beatAge = Double(i%5)/60; loud.beatStrength = 1; loud.beatWeight = 1
            loud.pulse.bpm = 174; loud.pulse.confidence = 1; loud.pulse.position = Double(i)*174/3600
            loud.spectrum = Array(repeating: 1,count: 24); loud.drumSpectrum = loud.spectrum
            XCTAssertEqual(singer.update(dt: 1/60,rhythm: f),mixed.update(dt: 1/60,rhythm: loud))
            XCTAssertEqual(a.update(rhythm: f,drive: singer.soundDrive),b.update(rhythm: loud,drive: mixed.soundDrive))
        }
        XCTAssertLessThan(mixed.pose.y,0.001)
        XCTAssertEqual(mixed.pose.scale,1,accuracy: 0.001)
        XCTAssertEqual(b.frame.drive,0,accuracy: 0.001)
        XCTAssertEqual(b.frame.vocalSpectrum,Array(repeating: 0,count: 24))
    }
    func testSurroundingWaveFollowsVocalLoudnessAndStopsOnPause() {
        var field = SoundField(), f = voice(0.08)
        f.vocalSpectrum[8] = 0.20
        field.update(rhythm: f,drive: 0.1)
        let quiet = field.frame
        f.vocalEnergy = 0.60; f.vocalSpectrum[8] = 0.75
        field.update(rhythm: f,drive: 0.8)
        XCTAssertGreaterThan(field.frame.voice,quiet.voice*6)
        XCTAssertGreaterThan(field.frame.vocalSpectrum[8],quiet.vocalSpectrum[8]*6)
        field.update(rhythm: f,drive: 1,enabled: false)
        XCTAssertEqual(field.frame,SoundFieldFrame())
        f.vocalSpectrum = [.nan,.infinity,-1,2]
        field.update(rhythm: f,drive: .nan)
        XCTAssertTrue(field.frame.vocalSpectrum.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertEqual(field.frame.drive,0)
    }
    func testRepeatedVocalRisesContinueToRaiseTheBodyAndDropFollowsCurrentVolume() {
        let e = Choreographer(seed: 42)
        var heights: [Double] = []
        for level in [0.06,0.22,0.6] {
            for _ in 0..<15 { e.update(dt: 1/60,rhythm: voice(level)) }
            heights.append(e.pose.y)
        }
        XCTAssertGreaterThan(heights[1],heights[0]+0.015)
        XCTAssertGreaterThan(heights[2],heights[1]+0.04)
        let raised = e.pose
        for _ in 0..<45 { e.update(dt: 1/60,rhythm: voice(0.06)) }
        XCTAssertLessThan(e.pose.y,raised.y*0.15)
        XCTAssertLessThan(e.pose.scale,1.02)
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
