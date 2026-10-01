import XCTest
@testable import MihoCore

final class VocalPriorityTests: XCTestCase {
    private func note() -> RhythmFrame {
        var f = RhythmFrame();f.energy = 0.8;f.drumEnergy = 0.8
        f.vocalPresence = 0.95;f.vocalEnergy = 0.7;f.vocalConfidence = 0.95
        f.vocalSustain = 0.9;f.vocalPitch = 220
        return f
    }
    func testLongNoteKeepsFullExtensionEvenWithLoudOffbeatAccompaniment() {
        let singer = Choreographer(seed: 42), mix = Choreographer(seed: 42)
        var f = note()
        for i in 0..<480 {
            let expected = singer.update(dt: 1/60,rhythm: f)
            var loud = f;loud.pulse.bpm = 174;loud.pulse.confidence = 1
            loud.pulse.position = Double(i)/60*174/60+0.5
            loud.beatCount = UInt64(i/8+1);loud.beatAge = Double(i%8)/60;loud.beatStrength = 1
            let actual = mix.update(dt: 1/60,rhythm: loud)
            XCTAssertEqual(actual.body.y,expected.body.y,accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(actual.y,expected.y-0.001)
            XCTAssertLessThan(actual.y-expected.y,0.012)
            XCTAssertLessThan(actual.scale-expected.scale,0.010)
        }
        XCTAssertGreaterThan(mix.pose.y,0.16)
        f.vocalPitch = 330;f.vocalPitchMotion = 0.2
        for _ in 0..<90 { mix.update(dt: 1/60,rhythm: f) }
        XCTAssertGreaterThan(mix.pose.y,0.24)
    }
    func testBriefBreathDoesNotSwitchToAccompanimentDance() {
        let a = Choreographer(seed: 42), b = Choreographer(seed: 42)
        var f = note()
        for _ in 0..<180 { a.update(dt: 1/60,rhythm: f);b.update(dt: 1/60,rhythm: f) }
        f.vocalPresence = 0;f.vocalEnergy = 0;f.vocalSustain = 0;f.vocalConfidence = 0
        for i in 0..<18 {
            let p = a.update(dt: 1/60,rhythm: f)
            var withDrums = f;withDrums.pulse.bpm = 174;withDrums.pulse.confidence = 1
            withDrums.pulse.position = Double(i)/60*174/60;withDrums.beatCount = UInt64(i/5+1)
            withDrums.beatAge = Double(i%5)/60;withDrums.beatStrength = 1
            let q = b.update(dt: 1/60,rhythm: withDrums)
            XCTAssertEqual(q.body.y,p.body.y,accuracy: 0.0001)
            XCTAssertLessThan(abs(q.y-p.y),0.01)
        }
    }
    func testHumanAccentsRetainTheirStrengthWithOrWithoutTheBeatModel() {
        let a = Choreographer(seed: 42), b = Choreographer(seed: 42)
        var f = note();f.vocalSustain = 0
        for i in 0..<180 {
            f.vocalAccentCount = UInt64(i/30+1);f.vocalAccentAge = Double(i%30)/60;f.vocalAccentStrength = 0.8
            let p = a.update(dt: 1/60,rhythm: f)
            var withBeat = f;withBeat.pulse.bpm = 124;withBeat.pulse.confidence = 1;withBeat.pulse.position = Double(i)*124/3600
            let q = b.update(dt: 1/60,rhythm: withBeat)
            XCTAssertEqual(p,q);XCTAssertEqual(a.impact,b.impact)
        }
        XCTAssertGreaterThan(a.pose.y,0.03)
    }
}
