import XCTest
@testable import MihoCore

final class DanceModeTests: XCTestCase {
    private func singer() -> RhythmFrame {
        var f = RhythmFrame(); f.energy = 0.8; f.vocalPresence = 1; f.vocalEnergy = 0.7
        f.vocalPitch = 220; f.vocalConfidence = 1; f.vocalSustain = 0.9
        return f
    }
    func testVocalArticulationProducesAlternatingTurnsAndNotOnlyForwardStretch() {
        let engine = Choreographer(seed: 42)
        var f = singer(); f.vocalSustain = 0
        for _ in 0..<90 { engine.update(dt: 1/60,rhythm: f) }
        let restingYaw = engine.pose.body.y, restingRoll = engine.pose.body.z
        var turns: [Double] = []
        for hit in 1...2 {
            f.vocalAccentCount = UInt64(hit); f.vocalAccentAge = 0; f.vocalAccentStrength = 0.9
            for _ in 0..<10 { engine.update(dt: 1/60,rhythm: f); f.vocalAccentAge += 1/60 }
            turns.append(engine.pose.body.y-restingYaw)
            XCTAssertGreaterThan(abs(engine.pose.body.z-restingRoll),0.015)
            for _ in 0..<90 { engine.update(dt: 1/60,rhythm: f); f.vocalAccentAge += 1/60 }
        }
        XCTAssertLessThan(turns[0]*turns[1],0)
        XCTAssertGreaterThan(abs(turns[1]-turns[0]),0.08)
    }
    func testSingerMelodyChangesMultipleAxesAndHoldsWithoutTimer() {
        let engine = Choreographer(seed: 42); var f = singer()
        for _ in 0..<120 { engine.update(dt: 1/60,rhythm: f) }
        let before = engine.pose
        f.vocalPitch = 330
        for _ in 0..<180 { engine.update(dt: 1/60,rhythm: f) }
        let peak = engine.pose
        XCTAssertGreaterThan(peak.y-before.y,0.10)
        XCTAssertGreaterThan(abs(peak.body.y-before.body.y),0.10)
        XCTAssertGreaterThan(abs(peak.body.z-before.body.z),0.06)
        for _ in 0..<180 { engine.update(dt: 1/60,rhythm: f) }
        XCTAssertEqual(engine.pose.y,peak.y,accuracy: 0.004)
        XCTAssertEqual(engine.pose.body.y,peak.body.y,accuracy: 0.004)
    }
    func testMusicModeMovesToInstrumentalWhileSingerRestsAndModesSwitchContinuously() {
        let voice = Choreographer(seed: 42), music = Choreographer(seed: 42)
        music.mode = .music
        var f = RhythmFrame(); f.energy = 0.8; f.drumEnergy = 0.7; f.bass = 0.6
        f.pulse.bpm = 124; f.pulse.confidence = 0.9
        var largestNod = 0.0, largestSway = 0.0
        for i in 0..<360 {
            f.pulse.position = Double(i)*124/3600
            let p = music.update(dt: 1/60,rhythm: f)
            voice.update(dt: 1/60,rhythm: f)
            largestNod = max(largestNod,abs(p.body.x))
            largestSway = max(largestSway,abs(p.x))
            XCTAssertEqual(voice.pose.y,0); XCTAssertEqual(voice.impact,0)
        }
        XCTAssertGreaterThan(largestNod,0.04); XCTAssertGreaterThan(largestSway,0.04)
        let before = music.pose; music.mode = .singer
        let after = music.update(dt: 1/60,rhythm: f)
        XCTAssertLessThan(abs(after.y-before.y),0.016)
        XCTAssertLessThan(abs(after.body.y-before.body.y),2.8/60+0.001)
        for _ in 0..<120 { music.update(dt: 1/60,rhythm: f) }
        XCTAssertEqual(music.pose.x,0,accuracy: 0.002)
        XCTAssertEqual(music.pose.scale,1,accuracy: 0.002)
    }
    func testMusicModeAndEdgeSpectrumFadeOnPauseAndUseFullAudioBands() {
        let e = Choreographer(seed: 42); e.mode = .music
        var field = SoundField(), f = RhythmFrame()
        f.energy = 0.8; f.drumEnergy = 0.9; f.bass = 0.7; f.spectrum[1] = 0.8; f.spectrum[16] = 0.4
        for _ in 0..<60 { e.update(dt: 1/60,rhythm: f) }
        let loud = field.update(rhythm: f,drive: e.soundDrive,mode: .music)
        XCTAssertEqual(loud.spectrum[1],0.8); XCTAssertEqual(loud.spectrum[16],0.4)
        XCTAssertEqual(loud.vocalSpectrum,Array(repeating: 0,count: 24))
        XCTAssertGreaterThan(loud.bass,0.6)
        for _ in 0..<120 { e.update(dt: 1/60,rhythm: f,enabled: false) }
        field.update(rhythm: f,drive: e.soundDrive,mode: .music,enabled: false)
        XCTAssertEqual(field.frame.drive,0); XCTAssertEqual(field.frame.spectrum,Array(repeating: 0,count: 24))
        XCTAssertEqual(e.pose.scale,1,accuracy: 0.002)
    }
}
