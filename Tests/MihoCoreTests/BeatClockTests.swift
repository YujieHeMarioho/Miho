import XCTest
@testable import MihoCore

final class BeatClockTests: XCTestCase {
    private func activation(t: Double,bpm: Double) -> Double {
        let p = t*bpm/60, distance = abs(p-round(p))
        return 0.02+0.83*exp(-pow(distance/0.065,2))
    }
    func testLearnedPulseLocksAcrossHipHopAndFastRockWithoutChasingSubdivisions() {
        for bpm in [88.0,124,174] {
            let clock = BeatClock();var f = BeatClockFrame(), errors: [Double] = []
            for i in 0..<600 {
                let t = Double(i+1)*0.02
                let p = t*bpm/60
                let weakHat = 0.07*exp(-pow((p*4-round(p*4))/0.08,2))
                f = clock.consume(beat: activation(t: t-705/22_050.0,bpm: bpm)+weakHat,downbeat: 0)
                if i > 350 {
                    // The decoder stamps the window centre, not its trailing edge.
                    let actual = (t-705/22_050.0)*bpm/60
                    let d = f.position-actual;errors.append(abs(d-round(d)))
                }
            }
            XCTAssertEqual(f.bpm,bpm,accuracy: 3)
            XCTAssertGreaterThan(f.confidence,0.6)
            XCTAssertLessThan(errors.reduce(0,+)/Double(errors.count),0.09)
        }
    }
    func testFillDoesNotSwitchTempoAndSilenceReleasesConfidence() {
        let clock = BeatClock();var f = BeatClockFrame()
        for i in 0..<400 { f = clock.consume(beat: activation(t: Double(i+1)*0.02,bpm: 120),downbeat: 0) }
        let bpm = f.bpm
        for i in 0..<25 { f = clock.consume(beat: i%5 == 0 ? 0.8 : 0.02,downbeat: 0) }
        XCTAssertEqual(f.bpm,bpm,accuracy: 5)
        for _ in 0..<150 { f = clock.consume(beat: 0,downbeat: 0) }
        XCTAssertLessThan(f.confidence,0.15)
        clock.reset();XCTAssertEqual(clock.frame,BeatClockFrame())
    }
    func testClockRecoversAfterAHalfBeatPhaseShiftWithoutGettingStuckOffBeat() {
        let clock = BeatClock();var errors: [Double] = []
        for i in 0..<800 {
            let t = Double(i+1)*0.02, centre = t-705/22_050.0
            let shift = t > 8 ? 0.25 : 0
            let f = clock.consume(beat: activation(t: centre-shift,bpm: 120),downbeat: 0)
            if t > 14 {
                let desired = (centre-shift)*2, d = f.position-desired
                errors.append(abs(d-round(d)))
                XCTAssertEqual(f.bpm,120,accuracy: 3)
            }
        }
        XCTAssertLessThan(errors.reduce(0,+)/Double(errors.count),0.10)
    }
    func testContinuousRapVoiceDoesNotSuppressGrooveAndPauseSettles() {
        let e = Choreographer(seed: 42)
        var f = RhythmFrame();f.energy = 0.8;f.drumEnergy = 0.7
        f.vocalEnergy = 0.6;f.vocalPresence = 0.95;f.vocalConfidence = 0.1;f.vocalSustain = 0.9
        f.pulse.bpm = 124;f.pulse.confidence = 0.9
        var heights: [Double] = [], turns: [Double] = []
        for i in 0..<600 {
            f.pulse.position = Double(i+1)/60*124/60
            let p = e.update(dt: 1/60,rhythm: f)
            if i > 180 { heights.append(p.y);turns.append(p.body.y) }
        }
        XCTAssertGreaterThan(heights.max()!-heights.min()!,0.045)
        XCTAssertGreaterThan(turns.max()!-turns.min()!,0.15)
        XCTAssertEqual(e.gesture,.bouncing)
        for _ in 0..<90 { e.update(dt: 1/60,rhythm: f,enabled: false) }
        XCTAssertLessThan(e.pose.y,0.01)
    }
}
