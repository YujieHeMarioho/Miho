import XCTest
@testable import MihoCore

final class GrooveMotionTests: XCTestCase {
    func testInstrumentalAtAnyTempoStaysAtRestLikeSilence() {
        for bpm in [88.0,124,174] {
            let engine = Choreographer(seed: 42), silence = Choreographer(seed: 42)
            var f = RhythmFrame(); f.energy = 0.8; f.drumEnergy = 0.7
            f.pulse.bpm = bpm; f.pulse.confidence = 0.9
            for i in 0..<720 {
                f.pulse.position = Double(i+1)/60*bpm/60
                XCTAssertEqual(engine.update(dt: 1/60,rhythm: f),silence.update(dt: 1/60,rhythm: RhythmFrame()))
                XCTAssertEqual(engine.impact,0)
            }
        }
    }
    func testPhaseCorrectionsAndRapidRapAccentsDoNotProduceJerkyBodySpeed() {
        let e = Choreographer(seed: 42)
        var f = RhythmFrame();f.energy = 0.8;f.drumEnergy = 0.7
        f.pulse.bpm = 174;f.pulse.confidence = 0.9
        f.vocalPresence = 0.9;f.vocalEnergy = 0.7
        var previous = e.pose, velocity = Rotation3()
        for i in 0..<900 {
            f.pulse.position = Double(i+1)/60*174/60+(i > 350 ? 0.4 : 0)
            f.vocalAccentCount = UInt64(i/10);f.vocalAccentAge = Double(i%10)/60;f.vocalAccentStrength = 0.9
            let p = e.update(dt: 1/60,rhythm: f)
            let speed = Rotation3((p.body.x-previous.body.x)*60,(p.body.y-previous.body.y)*60,(p.body.z-previous.body.z)*60)
            XCTAssertLessThan(abs(speed.x),2.01);XCTAssertLessThan(abs(speed.y),2.81)
            XCTAssertLessThan(abs(speed.x-velocity.x)*60,12.1)
            XCTAssertLessThan(abs(speed.y-velocity.y)*60,14.1)
            previous = p;velocity = speed
        }
    }
}
