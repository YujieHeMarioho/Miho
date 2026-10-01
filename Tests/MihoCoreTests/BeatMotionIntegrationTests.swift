import XCTest
@testable import MihoCore

/// Irregular drum times over a sustained pad catch false synchronization that
/// would pass a metronome-only test. The analyzer frames feed the continuous pose controller.
final class BeatMotionIntegrationTests: XCTestCase {
    func testMixedDrumsAreDetectedButCannotMoveTheVocalOnlyCharacter() {
        let hits = [0.45,0.97,1.43,1.95,2.39,2.93,3.47]
        do {
            let rate = 48_000.0
            let analyzer = RhythmAnalyzer(sampleRate: rate,analyzeVoice: false)
            let engine = Choreographer(seed: 42)
            var frame = RhythmFrame(), previousCount: UInt64 = 0
            var detected: [Double] = [], visible: [Double] = []
            var pending: (time: Double, head: Double)?
            for sample in 0..<Int(rate*4.2) {
                let time = Double(sample)/rate
                var value = 0.065*sin(2 * .pi * 330*time)
                for (index,hit) in hits.enumerated() {
                    let age = time-hit
                    if age >= 0 && age < 0.10 {
                        if index%2 == 0 {
                            value += 0.28*sin(2 * .pi * 60*age)*exp(-age/0.035)
                        } else {
                            value += 0.17*(sin(2 * .pi * 2_300*age)+sin(2 * .pi * 6_400*age))*exp(-age/0.018)
                        }
                    }
                }
                frame = analyzer.consume(Float(value))
                if frame.beatCount != previousCount {
                    if time > 0.20 {
                        detected.append(time)
                        XCTAssertGreaterThan(frame.beatWeight,0.3,"kick/snare has low or mid body: \(frame.beatWeight)")
                        pending = (time,engine.pose.head.x)
                    }
                    previousCount = frame.beatCount
                }
                if (sample+1)%800 == 0 {
                    engine.update(dt: 1/60,rhythm: frame)
                    if let hit = pending, engine.impact > 0.15 && engine.pose.head.x > hit.head+0.02 {
                        visible.append(time); pending = nil
                    }
                }
            }
            XCTAssertEqual(detected.count,hits.count,"Accents: \(detected)")
            XCTAssertTrue(visible.isEmpty,"Drums must not animate the character: \(visible)")
            XCTAssertEqual(engine.pose.y,0,accuracy: 0.0001)
            XCTAssertEqual(engine.pose.head.x,0,accuracy: 0.0001)
            for hit in hits {
                let onset = detected.filter { $0 >= hit }.min() ?? 100
                XCTAssertLessThan(onset-hit,0.04,"mixed drum attack at \(hit)")
            }
        }
    }
    func testHighFrequencyOnlyHatsAreRecognizedAsLightDetail() {
        let analyzer = RhythmAnalyzer()
        let engine = Choreographer(seed: 42)
        var frame = RhythmFrame(), count: UInt64 = 0, hatCount = 0
        for sample in 0..<96_000 {
            let time = Double(sample)/48_000
            let age = time.truncatingRemainder(dividingBy: 0.125)
            let value = age < 0.04 ? 0.25*sin(2 * .pi * 8_000*age)*exp(-age/0.008) : 0
            frame = analyzer.consume(Float(value))
            if frame.beatCount != count {
                count = frame.beatCount; hatCount += 1
                XCTAssertLessThan(frame.beatWeight,0.30)
            }
            if (sample+1)%800 == 0 {
                engine.update(dt: 1/60,rhythm: frame)
                XCTAssertEqual(engine.impact,0)
                XCTAssertEqual(engine.pose.x,0,accuracy: 0.0001)
            }
        }
        XCTAssertGreaterThan(hatCount,10)
    }

    func testQuietAndFastDrumsAndChunkBoundariesPreserveEventAge() {
        for rate in [44_100.0,48_000.0,96_000.0] {
            let analyzer = RhythmAnalyzer(sampleRate: rate,analyzeVoice: false)
            let hits = [0.3,0.425,0.55,0.675,0.8]
            var frame = RhythmFrame(), count: UInt64 = 0
            var detected: [Double] = []
            for sample in 0..<Int(rate*1.2) {
                let time = Double(sample)/rate
                var value = 0.0
                for hit in hits {
                    let age = time-hit
                    if age >= 0 && age < 0.065 { value += 0.05*sin(2 * .pi * 80*age)*exp(-age/0.025) }
                }
                frame = analyzer.consume(Float(value))
                if frame.beatCount != count {
                    detected.append(time); count = frame.beatCount
                    XCTAssertLessThan(frame.beatAge,0.0001)
                    XCTAssertGreaterThan(frame.beatStrength,0.3)
                }
            }
            XCTAssertEqual(detected.count,hits.count,"\(rate): \(detected)")
            XCTAssertEqual(frame.beatAge,1.2-(detected.last ?? 0),accuracy: 0.002)
            for hit in hits {
                XCTAssertLessThan((detected.filter { $0 >= hit }.min() ?? 100)-hit,0.025)
            }
        }
    }
}
