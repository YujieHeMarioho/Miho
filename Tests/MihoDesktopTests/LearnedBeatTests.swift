import XCTest
import CStemSeparator
import MihoCore
@testable import MihoDesktop

final class LearnedBeatTests: XCTestCase {
    struct Golden: Decodable { var probabilities: [Float]; var features: [Float] }
    func testNativeFeatureAndRecurrentInferenceMatchIndependentPythonExportAndReset() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/beatnet-golden.json")
        let golden = try JSONDecoder().decode([Golden].self,from: Data(contentsOf: fixture))
        var error = [CChar](repeating: 0,count: 1024)
        let host = try XCTUnwrap(miho_beat_create(LearnedBeatAnalyzer.modelURL.path,&error,error.count),String(cString: error))
        defer { miho_beat_destroy(host) }
        for _ in 0..<2 {
            miho_beat_reset(host)
            for frame in 0..<30 {
                var audio = [Float](repeating: 0,count: 1411)
                for i in 0..<1411 {
                    let t = Double(i+frame*441)/22_050
                    audio[i] = Float((0.16+0.08*sin(t*7))*sin(2*Double.pi*330*t)+0.09*sin(2*Double.pi*123*t)+0.025*cos(2*Double.pi*3400*t))
                }
                var probabilities = [Float](repeating: 0,count: 3), features = [Float](repeating: 0,count: 272)
                XCTAssertEqual(miho_beat_process(host,&audio,&probabilities,&features),1)
                for i in 0..<3 { XCTAssertEqual(probabilities[i],golden[frame].probabilities[i],accuracy: 0.00002) }
                if !golden[frame].features.isEmpty {
                    for i in 0..<272 { XCTAssertEqual(features[i],golden[frame].features[i],accuracy: 0.000002) }
                }
            }
        }
    }
    func testSilenceCannotInventALearnedPulse() throws {
        let analyzer = try LearnedBeatAnalyzer()
        var frame = BeatClockFrame()
        for _ in 0..<44_100*5 { frame = try analyzer.consume(0) }
        XCTAssertLessThan(frame.confidence,0.05)
        XCTAssertEqual(frame.bpm,0)
    }
}
