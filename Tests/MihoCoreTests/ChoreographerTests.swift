import XCTest
@testable import MihoCore

final class ChoreographerTests: XCTestCase {
    func testAllSixDancesUseDistinctSoftBodyAndEarPoses() {
        let poses = DanceMove.allCases.map { Choreographer.dance(move: $0,phase: 0.65,energy: 0.8) }
        for i in poses.indices {
            for j in poses.indices where i != j { XCTAssertNotEqual(poses[i],poses[j]) }
        }
        XCTAssertLessThan(poses[2].leftEar.z,-0.2)
        XCTAssertGreaterThan(poses[4].body.y,0.2)
        XCTAssertGreaterThan(poses[5].y,0.1)
        XCTAssertNotEqual(poses[1].body.x,poses[1].head.x)
    }

    func testLivelyMusicCyclesThroughAllDances() {
        let engine = Choreographer()
        var frame = RhythmFrame(); frame.energy = 0.8; frame.brightness = 0.7
        var seen = Set<DanceMove>()
        for tick in 0..<1_800 {
            frame.beatCount = UInt64(tick/15)
            _ = engine.update(dt: 1/30,rhythm: frame)
            seen.insert(engine.move)
        }
        XCTAssertEqual(engine.mood,.lively)
        XCTAssertEqual(seen,Set(DanceMove.allCases))
    }

    func testSilenceAndPauseSmoothlyReturnToIdle() {
        for paused in [false,true] {
            let engine = Choreographer()
            var frame = RhythmFrame(); frame.energy = 0.8
            for _ in 0..<120 { engine.update(dt: 1/30,rhythm: frame) }
            let dancing = engine.pose
            if !paused { frame.energy = 0 }
            let first = engine.update(dt: 1/30,rhythm: frame,enabled: !paused)
            XCTAssertLessThan(abs(first.leftEar.z-dancing.leftEar.z),0.2)
            for _ in 0..<30 { engine.update(dt: 1/30,rhythm: frame,enabled: !paused) }
            XCTAssertLessThan(abs(engine.pose.x),0.002)
            XCTAssertLessThan(engine.pose.y,0.002)
            XCTAssertLessThan(abs(engine.pose.leftEar.z),0.3)
        }
    }

    func testGrooveAdaptsToPulsesAndIgnoresImplausibleTempo() {
        let engine = Choreographer()
        var frame = RhythmFrame(); frame.energy = 0.5
        for tick in 0..<360 {
            frame.beatCount = UInt64(tick/12)
            engine.update(dt: 1/30,rhythm: frame)
        }
        XCTAssertEqual(engine.groovePeriod,0.4,accuracy: 0.01)
        frame.beatCount += 1
        engine.update(dt: 0.001,rhythm: frame)
        XCTAssertTrue((0.28...0.9).contains(engine.groovePeriod))
    }

    func testMoodUsesHysteresisInsteadOfFlickeringEveryFrame() {
        let engine = Choreographer()
        var frame = RhythmFrame(); frame.energy = 0.25
        for _ in 0..<150 { engine.update(dt: 1/30,rhythm: frame) }
        XCTAssertEqual(engine.mood,.groovy)
        frame.energy = 0.9
        for _ in 0..<10 { engine.update(dt: 1/30,rhythm: frame) }
        XCTAssertEqual(engine.mood,.groovy)
        for _ in 0..<150 { engine.update(dt: 1/30,rhythm: frame) }
        XCTAssertEqual(engine.mood,.lively)
    }

    func testPoseStaysContinuousAcrossPhraseTransitions() {
        let engine = Choreographer()
        var frame = RhythmFrame(); frame.energy = 0.8
        var last = engine.pose
        for tick in 0..<900 {
            frame.beatCount = UInt64(tick/15)
            let pose = engine.update(dt: 1/60,rhythm: frame)
            XCTAssertLessThan(abs(pose.leftEar.z-last.leftEar.z),0.14)
            XCTAssertLessThan(abs(pose.body.y-last.body.y),0.12)
            XCTAssertLessThan(abs(pose.x-last.x),0.04)
            XCTAssertTrue(pose.squash.isFinite)
            last = pose
        }
    }

    func testTextureDistinguishesBassFromBrightSound() {
        func tone(_ frequency: Double) -> RhythmFrame {
            let analyzer = RhythmAnalyzer(); var frame = RhythmFrame()
            for i in 0..<48_000 { frame = analyzer.consume(Float(0.1*sin(2 * .pi*frequency*Double(i)/48_000))) }
            return frame
        }
        let bass = tone(60), bright = tone(3_000)
        XCTAssertGreaterThan(bass.bassShare,0.85)
        XCTAssertLessThan(bright.bassShare,0.01)
        XCTAssertGreaterThan(bright.brightness,bass.brightness*20)
    }

    func testPersonalityVariesButIsReproducibleForASeed() {
        let a = Choreographer(seed: 42), b = Choreographer(seed: 42), c = Choreographer(seed: 99)
        var differences = 0
        for _ in 0..<900 {
            let poseA = a.update(dt: 1/30,rhythm: RhythmFrame())
            let poseB = b.update(dt: 1/30,rhythm: RhythmFrame())
            let poseC = c.update(dt: 1/30,rhythm: RhythmFrame())
            XCTAssertEqual(poseA,poseB)
            if poseA != poseC { differences += 1 }
            XCTAssertLessThan(abs(poseA.body.y),0.3)
            XCTAssertTrue((0.90...1.08).contains(poseA.squash))
        }
        XCTAssertGreaterThan(differences,800)
    }

    func testInvalidMotionInputsStayFinite() {
        let pose = Choreographer.dance(move: .happyHop,phase: .infinity,energy: .nan,accent: .nan)
        XCTAssertTrue(pose.y.isFinite)
        XCTAssertTrue(pose.squash.isFinite)
        var frame = RhythmFrame(); frame.energy = .nan; frame.brightness = .infinity
        let engine = Choreographer(seed: 1)
        for _ in 0..<60 { engine.update(dt: .nan,rhythm: frame) }
        XCTAssertTrue(engine.pose.body.x.isFinite)
        XCTAssertEqual(engine.mood,.dreamy)
    }
}
