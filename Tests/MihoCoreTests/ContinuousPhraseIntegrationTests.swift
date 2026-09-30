import XCTest
@testable import MihoCore

final class ContinuousPhraseIntegrationTests: XCTestCase {
    func testAnalyzedRisingThenHeldVowelKeepsPostureUntilActualRelease() {
        let analyzer = RhythmAnalyzer(), e = Choreographer(seed: 42)
        var phase = 0.0, frame = RhythmFrame(), heights: [Double] = []
        for sample in 0..<480_000 {
            let time = Double(sample)/48_000
            let frequency = 220*pow(2,0.45*min(1,max(0,(time-1.05)/3)))
            phase += 2 * .pi*frequency/48_000
            let amplitude = time >= 1.05 && time < 8 ? 0.12*min(1,(time-1.05)/0.12)*min(1,(8-time)/0.3) : 0
            frame = analyzer.consume(Float(amplitude*(sin(phase)+0.4*sin(2*phase)+0.18*sin(3*phase))))
            frame.beatCount = 0
            if (sample+1)%800 == 0 {
                e.update(dt: 1/60,rhythm: frame)
                if time > 5 && time < 7.5 { heights.append(e.pose.y) }
                if (sample+1)%48_000 == 0 { print("phrase t=\(time) voice=\(frame.vocalEnergy) confidence=\(frame.vocalConfidence) pitch=\(frame.vocalPitch) y=\(e.pose.y)") }
            }
        }
        XCTAssertGreaterThan(heights.min() ?? 0,0.10)
        XCTAssertLessThan((heights.max() ?? 0)-(heights.min() ?? 0),0.008)
        XCTAssertLessThan(e.pose.y,0.005)
    }
}
