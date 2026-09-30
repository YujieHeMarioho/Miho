import Foundation
import CryptoKit
import CStemSeparator
import MihoCore

struct SeparationResult {
    var rhythm = RhythmFrame()
    var inferenceMs = 0.0
    var error: String?
}

/// Fractional sample positions survive callback boundaries. This resampler is
/// only for analysis; the system's original stereo playback is untouched.
final class AnalysisResampler {
    private let stride: Double
    private var index = 0.0, next = 0.0
    private var previous: (Float,Float)?
    init(sampleRate: Double) { stride = sampleRate/44_100 }
    func consume(left: Float,right: Float,emit: (Float,Float) -> Void) {
        if let previous {
            while next <= index {
                let fraction = Float(min(1,max(0,next-(index-1))))
                emit(previous.0+(left-previous.0)*fraction,previous.1+(right-previous.1)*fraction)
                next += stride
            }
        } else { emit(left,right); next = stride }
        previous = (left,right); index += 1
    }
}

/// All model and signal state belongs to the analysis worker, never the audio IO
/// callback. Native inference uses preallocated tensors and 128-sample hops.
final class SeparatedAudioAnalyzer {
    private let separator: OpaquePointer
    private let learnedBeat: LearnedBeatAnalyzer
    private var resampler: AnalysisResampler
    private let sampleRate: Double
    private var mix = RhythmAnalyzer(sampleRate: 44_100,analyzeVoice: false)
    private var voice = RhythmAnalyzer(sampleRate: 44_100)
    private var percussion = RhythmAnalyzer(sampleRate: 44_100,analyzeVoice: false)
    private var left = [Float](repeating: 0,count: 128), right = [Float](repeating: 0,count: 128)
    private var vocals = [Float](repeating: 0,count: 128), drums = [Float](repeating: 0,count: 128), bass = [Float](repeating: 0,count: 128)
    private var count = 0, presence = 0.0, vocalEnvelope = 0.0
    private var result = SeparationResult()
    static var modelURL: URL {
        if let bundled = Bundle.main.url(forResource: "hop128",withExtension: "onnx") { return bundled }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/models/hop128.onnx")
    }
    init(sampleRate: Double,modelURL: URL = SeparatedAudioAnalyzer.modelURL) throws {
        learnedBeat = try LearnedBeatAnalyzer()
        self.sampleRate = sampleRate; resampler = AnalysisResampler(sampleRate: sampleRate)
        let modelData = try Data(contentsOf: modelURL,options: .mappedIfSafe)
        let hash = SHA256.hash(data: modelData).map { String(format: "%02x",$0) }.joined()
        guard hash == "77164d6a581fafb2a31f53fd8ffde44c07cf618472952a4cdba14e68dda3b8b9" else {
            throw NSError(domain: "Miho.Separation",code: 1,userInfo: [NSLocalizedDescriptionKey:"本机人声模型缺失或损坏，请重新构建 Miho。"])
        }
        var error = [CChar](repeating: 0,count: 2048)
        guard let separator = miho_separator_create(modelURL.path,&error,error.count) else {
            throw NSError(domain: "Miho.Separation",code: 2,userInfo: [NSLocalizedDescriptionKey:"无法启动本机人声分离：\(String(cString: error))"])
        }
        self.separator = separator
    }
    deinit { miho_separator_destroy(separator) }
    func reset() {
        miho_separator_reset(separator); learnedBeat.reset()
        resampler = AnalysisResampler(sampleRate: sampleRate)
        mix = RhythmAnalyzer(sampleRate: 44_100,analyzeVoice: false)
        voice = RhythmAnalyzer(sampleRate: 44_100)
        percussion = RhythmAnalyzer(sampleRate: 44_100,analyzeVoice: false)
        count = 0; presence = 0; vocalEnvelope = 0; result = SeparationResult()
    }
    func consume(stereo: [Float],sensitivity: Double) -> SeparationResult {
        let gain = sensitivity.isFinite ? min(2,max(0.5,sensitivity)) : 1
        for index in stride(from: 0,to: stereo.count-1,by: 2) {
            resampler.consume(left: stereo[index],right: stereo[index+1]) { l,r in
                self.left[self.count] = l.isFinite ? l : 0
                self.right[self.count] = r.isFinite ? r : 0
                self.count += 1
                if self.count == 128 { self.analyzeHop(sensitivity: gain); self.count = 0 }
            }
        }
        return result
    }
    private func analyzeHop(sensitivity: Double) {
        let start = ProcessInfo.processInfo.systemUptime
        let status = miho_separator_process(separator,&left,&right,&vocals,&drums,&bass)
        result.inferenceMs = (ProcessInfo.processInfo.systemUptime-start)*1000
        guard status != 0 else {
            result.rhythm = RhythmFrame()
            result.error = "人声分离中断：\(String(cString: miho_separator_error(separator)))"
            return
        }
        guard status == 1 else { return }
        result.error = nil
        var mixFrame = RhythmFrame(), vocalFrame = RhythmFrame(), drumFrame = RhythmFrame()
        var vocalPower = 0.0, mixPower = 0.0
        var pulse = BeatClockFrame()
        for index in 0..<128 {
            let original = (left[index]+right[index])*0.5
            do { pulse = try learnedBeat.consume(original) }
            catch { result.error = "节拍跟踪中断：\(error.localizedDescription)";result.rhythm = RhythmFrame();return }
            mixFrame = mix.consume(original,sensitivity: sensitivity)
            vocalFrame = voice.consume(vocals[index],sensitivity: sensitivity)
            drumFrame = percussion.consume(drums[index]+bass[index]*0.18,sensitivity: sensitivity)
            vocalPower += Double(vocals[index])*Double(vocals[index])
            mixPower += Double(original)*Double(original)
        }
        // Stem activity permits rough/unvoiced syllables; pitch confidence still
        // comes solely from periodicity and is required to move the pitch axis.
        let ratio = sqrt(vocalPower/max(mixPower,1e-12))
        // Full-band vocal loudness includes breathy/unvoiced syllables. Pitch
        // periodicity remains separate and is only used for melody and sustain.
        let envelopeTarget = 1-exp(-sqrt(vocalPower/128)*5*sensitivity)
        vocalEnvelope += (envelopeTarget-vocalEnvelope)*(1-exp(-128/44_100.0/(envelopeTarget > vocalEnvelope ? 0.025 : 0.10)))
        let vocalLevel = max(vocalFrame.vocalEnergy,vocalEnvelope)
        let activity = min(1,max(0,(ratio-0.07)/0.30))*min(1,vocalLevel*12)
        presence += (activity-presence)*(1-exp(-128/44_100.0/(activity > presence ? 0.035 : 0.18)))
        mixFrame.beatCount = drumFrame.beatCount; mixFrame.beatAge = drumFrame.beatAge+128/44_100.0
        mixFrame.beatStrength = drumFrame.beatStrength; mixFrame.beatWeight = drumFrame.beatWeight
        mixFrame.drumEnergy = drumFrame.energy
        mixFrame.vocalEnergy = vocalLevel; mixFrame.vocalPresence = presence
        mixFrame.vocalConfidence = vocalFrame.vocalConfidence; mixFrame.vocalSustain = vocalFrame.vocalSustain
        mixFrame.vocalPitch = vocalFrame.vocalPitch; mixFrame.vocalPitchMotion = vocalFrame.vocalPitchMotion
        mixFrame.vocalAccentCount = vocalFrame.vocalAccentCount
        mixFrame.vocalAccentAge = vocalFrame.vocalAccentAge+128/44_100.0
        mixFrame.vocalAccentStrength = vocalFrame.vocalAccentStrength
        mixFrame.pulse = pulse
        result.rhythm = mixFrame
    }
}

/// Bounded mailbox: overload drops stale audio and resets recurrent model state
/// instead of steadily increasing sound-to-motion latency. Cancellation also
/// invalidates an in-flight result. Only transient memory holds audio.
final class AudioAnalysisPipeline {
    struct Block {
        let stereo: [Float], sensitivity: Double, deliveredAt: TimeInterval
        let hostTime: UInt64
        var epoch: UInt64 = 0
    }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.miho.separation",qos: .userInitiated)
    private let analyze: ([Float],Double) -> SeparationResult
    private let reset: () -> Void
    private var pending: [Block] = []
    private var frames = 0, draining = false, cancelled = false, epoch: UInt64 = 1, workerEpoch: UInt64 = 1
    private let capacity: Int
    private let publish: (Block,SeparationResult) -> Void
    convenience init(sampleRate: Double,publish: @escaping (Block,SeparationResult) -> Void) throws {
        let analyzer = try SeparatedAudioAnalyzer(sampleRate: sampleRate)
        self.init(sampleRate: sampleRate,analyze: { analyzer.consume(stereo: $0,sensitivity: $1) },
                  reset: { analyzer.reset() },publish: publish)
    }
    init(sampleRate: Double,analyze: @escaping ([Float],Double) -> SeparationResult,
         reset: @escaping () -> Void,publish: @escaping (Block,SeparationResult) -> Void) {
        capacity = max(128,Int(sampleRate*0.06))
        self.analyze = analyze; self.reset = reset; self.publish = publish
    }
    func enqueue(_ incoming: Block) {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        if frames+incoming.stereo.count/2 > capacity {
            pending.removeAll(); frames = 0; epoch &+= 1
        }
        let trimmed = incoming.stereo.count/2 > capacity
        var block = trimmed ? Block(stereo: Array(incoming.stereo.suffix(capacity*2)),sensitivity: incoming.sensitivity,
                                    deliveredAt: incoming.deliveredAt,hostTime: 0) : incoming
        // An oversized callback is bounded too; host timestamp becomes unknown
        // rather than incorrectly measuring latency from its discarded beginning.
        block.epoch = epoch
        pending.append(block); frames += block.stereo.count/2
        let start = !draining; draining = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }
    func cancel() { lock.lock(); cancelled = true; pending.removeAll(); frames = 0; lock.unlock() }
    private func drain() {
        while true {
            lock.lock()
            guard !cancelled, !pending.isEmpty else { draining = false; lock.unlock(); return }
            let block = pending.removeFirst(); frames -= block.stereo.count/2
            lock.unlock()
            if block.epoch != workerEpoch { reset(); workerEpoch = block.epoch }
            let result = analyze(block.stereo,block.sensitivity)
            lock.lock()
            if !cancelled && block.epoch == epoch { publish(block,result) }
            lock.unlock()
        }
    }
}
