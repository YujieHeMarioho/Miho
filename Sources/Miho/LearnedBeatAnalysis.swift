import Foundation
import CryptoKit
import CStemSeparator
import MihoCore

/// Shared worker-owned BeatNet host. Audio storage is a 64 ms trailing window.
/// Fixed-rate features are independent of system callback size and sensitivity.
final class LearnedBeatAnalyzer {
    private let tracker: OpaquePointer
    private let decoder = BeatClock()
    private var samples = [Float](repeating: 0,count: 1411), window = [Float](repeating: 0,count: 1411)
    private var cursor = 0, hop = 0, pair = 0
    private var low = 0.0, low2 = 0.0
    private var probabilities = [Float](repeating: 0,count: 3)
    private var inferenceMs = 0.0
    private var frame = BeatClockFrame()
    static var modelURL: URL {
        if let url = Bundle.main.url(forResource: "beatnet",withExtension: "onnx") { return url }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Models/beatnet.onnx")
    }
    init(modelURL: URL = LearnedBeatAnalyzer.modelURL) throws {
        let hash = SHA256.hash(data: try Data(contentsOf: modelURL,options: .mappedIfSafe)).map { String(format: "%02x",$0) }.joined()
        guard hash == "9f17e72c12ffda524b042e55f3a1ad1e81acddd1baaf3c0440d7544437f8fe3e" else {
            throw NSError(domain: "Miho.BeatNet",code: 1,userInfo: [NSLocalizedDescriptionKey:"本机节拍模型缺失或损坏，请重新构建 Miho。"])
        }
        var error = [CChar](repeating: 0,count: 1024)
        guard let tracker = miho_beat_create(modelURL.path,&error,error.count) else {
            throw NSError(domain: "Miho.BeatNet",code: 2,userInfo: [NSLocalizedDescriptionKey:"无法启动本机节拍跟踪：\(String(cString: error))"])
        }
        self.tracker = tracker
    }
    deinit { miho_beat_destroy(tracker) }
    func reset() {
        miho_beat_reset(tracker);decoder.reset();samples = Array(repeating: 0,count: 1411)
        cursor = 0;hop = 0;pair = 0;low = 0;low2 = 0;frame = BeatClockFrame()
    }
    /// Production has already resampled to 44.1 kHz. A two-stage lowpass reduces
    /// aliasing before 2:1 analysis decimation; original playback is untouched.
    func consume(_ sample: Float) throws -> BeatClockFrame {
        let alpha = 1-exp(-2*Double.pi*8_000/44_100)
        low += alpha*(Double(sample)-low);low2 += alpha*(low-low2)
        pair += 1
        if pair == 2 {
            pair = 0;samples[cursor] = Float(low2);cursor = (cursor+1)%1411;hop += 1
            if hop == 441 {
                hop = 0
                for i in 0..<1411 { window[i] = samples[(cursor+i)%1411] }
                let start = ProcessInfo.processInfo.systemUptime
                guard miho_beat_process(tracker,&window,&probabilities,nil) == 1 else {
                    throw NSError(domain: "Miho.BeatNet",code: 3,userInfo: [NSLocalizedDescriptionKey:String(cString: miho_beat_error(tracker))])
                }
                inferenceMs = (ProcessInfo.processInfo.systemUptime-start)*1000
                frame = decoder.consume(beat: Double(probabilities[0]),downbeat: Double(probabilities[1]))
            }
        }
        var now = frame
        // The decoder is stamped at feature centre; advance through its known
        // analysis offset and the partial hop using the same sample clock.
        if now.bpm > 0 { now.position += (705/22_050.0+Double(hop)/22_050)*now.bpm/60 }
        return now
    }
}
