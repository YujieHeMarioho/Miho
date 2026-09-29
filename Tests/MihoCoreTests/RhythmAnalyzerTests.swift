import XCTest
@testable import MihoCore

final class RhythmAnalyzerTests: XCTestCase {
    private func feed(_ analyzer: RhythmAnalyzer, seconds: Double, amplitude: Double,
                      frequency: Double = 100, sensitivity: Double = 1) -> RhythmFrame {
        var result = RhythmFrame()
        for index in 0..<Int(seconds * analyzer.sampleRate) {
            result = analyzer.consume(Float(amplitude * sin(2 * .pi * frequency * Double(index) / analyzer.sampleRate)),
                                      sensitivity: sensitivity)
        }
        return result
    }

    func testSilenceIsIdleWithoutBeats() {
        let result = feed(RhythmAnalyzer(), seconds: 2, amplitude: 0)
        XCTAssertEqual(result.energy, 0)
        XCTAssertEqual(result.beatCount, 0)
        XCTAssertFalse(result.isActive)
    }

    func testLoudnessAndSensitivityDriveLargerMotion() {
        let quiet = feed(RhythmAnalyzer(), seconds: 0.5, amplitude: 0.01)
        let loud = feed(RhythmAnalyzer(), seconds: 0.5, amplitude: 0.15)
        let sensitive = feed(RhythmAnalyzer(), seconds: 0.5, amplitude: 0.01, sensitivity: 2)
        XCTAssertGreaterThan(loud.energy, quiet.energy * 2)
        XCTAssertGreaterThan(sensitive.energy, quiet.energy)
    }

    func testPulsedBassTriggersBeatsWithoutContinuousRetriggering() {
        let analyzer = RhythmAnalyzer()
        var result = RhythmFrame()
        for _ in 0..<4 {
            result = feed(analyzer, seconds: 0.08, amplitude: 0.3, frequency: 60)
            result = feed(analyzer, seconds: 0.42, amplitude: 0)
        }
        XCTAssertEqual(result.beatCount, 4)
        let sustained = feed(RhythmAnalyzer(), seconds: 2, amplitude: 0.1)
        XCTAssertLessThanOrEqual(sustained.beatCount, 2)
    }

    func testSpeechFrequencyMovesAndSilenceSettlesWithinOneSecond() {
        let analyzer = RhythmAnalyzer()
        let playing = feed(analyzer, seconds: 0.5, amplitude: 0.05, frequency: 1_000)
        XCTAssertTrue(playing.isActive)
        XCTAssertGreaterThan(playing.energy, 0.1)
        let stopped = feed(analyzer, seconds: 1, amplitude: 0)
        XCTAssertLessThan(stopped.energy, 0.01)
        XCTAssertFalse(stopped.isActive)
    }

    func testInvalidSamplesStayFinite() {
        let analyzer = RhythmAnalyzer()
        var result = RhythmFrame()
        for _ in 0..<1024 { result = analyzer.consume(.nan) }
        XCTAssertEqual(result.energy, 0)
        XCTAssertEqual(result.beatCount, 0)
    }

    func testCommonDeviceSampleRates() {
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            let analyzer = RhythmAnalyzer(sampleRate: rate)
            let result = feed(analyzer, seconds: 0.1, amplitude: 0.2, frequency: 60)
            XCTAssertGreaterThan(result.energy, 0.3)
            XCTAssertEqual(result.beatCount, 1)
        }
    }
}
