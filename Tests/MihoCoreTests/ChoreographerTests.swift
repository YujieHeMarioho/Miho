import XCTest
@testable import MihoCore

final class ChoreographerTests: XCTestCase {
    private func vocal(_ pitch: Double = 220) -> RhythmFrame {
        var f = RhythmFrame(); f.energy = 0.75; f.vocalEnergy = 0.7
        f.vocalPresence = 0.9; f.vocalConfidence = 0.95; f.vocalSustain = 0.9; f.vocalPitch = pitch
        return f
    }
    func testLongNoteUnfurlsThenHoldsForFiveSecondsWithoutReturningOrSwaying() {
        let e = Choreographer(seed: 42), f = vocal()
        var heights: [Double] = [], turns: [Double] = []
        for tick in 0..<480 {
            e.update(dt: 1/60,rhythm: f)
            if tick > 180 { heights.append(e.pose.y); turns.append(e.pose.body.y) }
        }
        XCTAssertGreaterThan(e.pose.y,0.16)
        XCTAssertLessThan(heights.max()!-heights.min()!,0.01)
        XCTAssertLessThan(turns.max()!-turns.min()!,0.012)
        XCTAssertEqual(e.gesture,.holding)
        XCTAssertEqual(e.impact,0)
    }
    func testDecrescendoKeepsHeldDirectionButReducesMotionAmplitude() {
        let e = Choreographer(seed: 42); var f = vocal()
        for _ in 0..<240 { e.update(dt: 1/60,rhythm: f) }
        let height = e.pose.y, yaw = e.pose.body.y
        f.vocalEnergy = 0.1
        for _ in 0..<180 { e.update(dt: 1/60,rhythm: f) }
        XCTAssertLessThan(e.pose.y,height*0.25)
        XCTAssertGreaterThan(e.pose.y,0.008)
        XCTAssertGreaterThan(e.pose.body.y*yaw,0)
        XCTAssertEqual(e.gesture,.holding)
    }
    func testPitchRiseContinuesIntoHeldPostureAndFallReleasesIt() {
        let e = Choreographer(seed: 1)
        var f = vocal()
        for _ in 0..<90 { e.update(dt: 1/60,rhythm: f) }
        let before = e.pose.y
        for tick in 0..<180 {
            f.vocalPitch = 220*pow(2,Double(tick)/180*0.6)
            f.vocalPitchMotion = 0.2
            e.update(dt: 1/60,rhythm: f)
        }
        let peak = e.pose.y
        XCTAssertGreaterThan(peak-before,0.10)
        f.vocalPitchMotion = 0
        for _ in 0..<240 { e.update(dt: 1/60,rhythm: f) }
        XCTAssertEqual(e.pose.y,peak,accuracy: 0.02)
        f.vocalPitchMotion = -0.2
        for tick in 0..<180 {
            f.vocalPitch = 220*pow(2,0.6-Double(tick)/180*0.6)
            e.update(dt: 1/60,rhythm: f)
        }
        XCTAssertLessThan(e.pose.y,peak-0.06)
        for _ in 0..<60 { e.update(dt: 1/60,rhythm: RhythmFrame()) }
        XCTAssertEqual(e.pose.y,0,accuracy: 0.008)
        XCTAssertEqual(e.pose.x,0,accuracy: 0.008)
    }
    func testDrumsDoNotInterruptHeldVocalAndPunchReturnsToHeldPosture() {
        let e = Choreographer(seed: 42)
        var f = vocal()
        for _ in 0..<240 { e.update(dt: 1/60,rhythm: f) }
        let held = e.pose
        var minimum = held.y
        for tick in 0..<120 {
            if tick%15 == 0 { f.beatCount += 1; f.beatAge = 0; f.beatStrength = 1 }
            else { f.beatAge += 1/60 }
            e.update(dt: 1/60,rhythm: f); minimum = min(minimum,e.pose.y)
        }
        XCTAssertGreaterThan(minimum,held.y-0.005)
        f.vocalAccentCount = 1; f.vocalAccentAge = 0; f.vocalAccentStrength = 0.9
        for _ in 0..<8 { e.update(dt: 1/60,rhythm: f); f.vocalAccentAge += 1/60 }
        XCTAssertGreaterThan(e.impact,0.3)
        XCTAssertGreaterThan(abs(e.pose.body.y-held.body.y),0.025)
        for _ in 0..<90 { e.update(dt: 1/60,rhythm: f); f.vocalAccentAge += 1/60 }
        XCTAssertEqual(e.pose.y,held.y,accuracy: 0.005)
        XCTAssertEqual(e.pose.body.y,held.body.y,accuracy: 0.005)
    }
    func testRapidIrregularChangesStayWithinSpeedAndAccelerationLimits() {
        let e = Choreographer(seed: 5)
        var previous = e.pose, speed = 0.0
        for tick in 0..<600 {
            var f = vocal(tick%70 < 35 ? 330 : 180)
            if tick%17 == 0 { f.vocalAccentCount = UInt64(tick/17+1); f.vocalAccentAge = 0; f.vocalAccentStrength = 1 }
            else { f.vocalAccentCount = UInt64(tick/17+1); f.vocalAccentAge = Double(tick%17)/60 }
            if tick%101 > 85 { f.vocalPresence = 0; f.vocalEnergy = 0 }
            let p = e.update(dt: 1/60,rhythm: f)
            let nextSpeed = (p.y-previous.y)*60
            XCTAssertLessThan(abs(nextSpeed),0.91)
            XCTAssertLessThan(abs(nextSpeed-speed)*60,8.1)
            XCTAssertLessThan(abs(p.body.y-previous.body.y),2.8/60+0.001)
            previous = p; speed = nextSpeed
        }
    }
    func testBriefAnalysisResetDoesNotReverseOrRestartAHeldPhrase() {
        let e = Choreographer(seed: 42); let f = vocal()
        for _ in 0..<240 { e.update(dt: 1/60,rhythm: f) }
        let held = e.pose
        e.resetInput()
        for _ in 0..<4 { e.update(dt: 1/60,rhythm: RhythmFrame()) }
        for _ in 0..<60 { e.update(dt: 1/60,rhythm: f) }
        XCTAssertEqual(e.pose.y,held.y,accuracy: 0.006)
        XCTAssertEqual(e.pose.body.y,held.body.y,accuracy: 0.006)
    }
    func testPauseAndCaptureResetDoNotSnapPoseOrReplayOldAccents() {
        let e = Choreographer(seed: 42); var f = vocal()
        for _ in 0..<180 { e.update(dt: 1/60,rhythm: f) }
        let before = e.pose
        e.resetInput()
        e.update(dt: 1/60,rhythm: f,enabled: false)
        XCTAssertLessThan(abs(e.pose.y-before.y),0.01)
        for _ in 0..<90 { e.update(dt: 1/60,rhythm: f,enabled: false) }
        XCTAssertLessThan(e.pose.y,0.003)
        f.energy = .nan; f.vocalPitch = .infinity; f.vocalEnergy = .nan
        XCTAssertTrue(e.update(dt: .nan,rhythm: f).y.isFinite)
    }
}
