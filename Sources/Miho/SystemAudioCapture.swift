import CoreAudio
import Foundation
import MihoCore

struct CaptureSnapshot {
    var inputAgeMs = 0.0
    var analysisMs = 0.0
    var bufferFrames = 0
    var separationReady = false
    var separationError: String?
    var inferenceMs = 0.0
    var generation: UInt64 = 0
    var rhythm = RhythmFrame()
    var lastCallback: TimeInterval = 0
    var inputHostTime: UInt64 = 0
    var callbackCount: UInt64 = 0
    var audibleCallbackCount: UInt64 = 0
}

@available(macOS 14.2, *)
protocol AudioCapturing: AnyObject {
    var onOutputChanged: (() -> Void)? { get set }
    func setSensitivity(_ value: Double)
    func latest() -> CaptureSnapshot
    func start(completion: @escaping (Error?) -> Void)
    func stop()
    func dispose()
}

enum CaptureError: LocalizedError {
    case coreAudio(String, OSStatus)
    case unsupportedFormat
    var errorDescription: String? {
        switch self {
        case let .coreAudio(operation, status):
            return "\(operation)失败（Core Audio \(status)）。请检查系统设置中的音频捕获权限，然后重试。"
        case .unsupportedFormat:
            return "当前音频设备未提供支持的 Float32 PCM 格式。请切换音频输出后重试。"
        }
    }
}

/// Lifecycle runs on a serial worker (Core Audio can wait for authorization).
/// A bounded analysis worker separates vocals/drums; a small
/// locked mailbox carries only scalar results to the UI, never recorded audio.
@available(macOS 14.2, *)
final class SystemAudioCapture: AudioCapturing {
    private var tapID: AudioObjectID = 0
    private var deviceID: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var pipeline: AudioAnalysisPipeline?
    private let controlQueue = DispatchQueue(label: "app.miho.capture-control", qos: .userInitiated)
    private var revision: UInt64 = 0
    private let ioQueue = DispatchQueue(label: "app.miho.audio", qos: .userInteractive)
    private let lock = NSLock()
    private var snapshot = CaptureSnapshot()
    private var gain = 1.0
    private var deviceListener: AudioObjectPropertyListenerBlock?
    var onOutputChanged: (() -> Void)?

    init() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onOutputChanged?()
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                               .main, listener) == noErr {
            deviceListener = listener
        }
    }

    func setSensitivity(_ value: Double) {
        lock.lock(); gain = value; lock.unlock()
    }

    func latest() -> CaptureSnapshot {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    func start(completion: @escaping (Error?) -> Void) {
        lock.lock(); revision &+= 1; let request = revision; lock.unlock()
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let isCurrent = self.revision == request; self.lock.unlock()
            guard isCurrent else { return }
            var failure: Error?
            do { try self.startOnWorker(generation: request) } catch { failure = error }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock(); let isCurrent = self.revision == request; self.lock.unlock()
                if isCurrent { completion(failure) }
            }
        }
    }

    private func startOnWorker(generation: UInt64) throws {
        stopOnWorker()
        do {
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            description.name = "Miho System Audio"
            description.uuid = UUID()
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tapID), "创建系统音频捕获")

            var format = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var formatAddress = Self.address(kAudioTapPropertyFormat)
            try check(AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format), "读取音频格式")
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mChannelsPerFrame == 2,
                  format.mSampleRate > 0 else { throw CaptureError.unsupportedFormat }

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Miho Audio Tap",
                kAudioAggregateDeviceUIDKey: "app.miho.aggregate.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                // Tap-only: never add a hardware input stream (e.g. a headset mic).
                kAudioAggregateDeviceSubDeviceListKey: [],
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID), "创建音频分析设备")
            let pipeline = try AudioAnalysisPipeline(sampleRate: format.mSampleRate) { [weak self] block,result in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                guard self.revision == generation else { return }
                self.snapshot.rhythm = result.rhythm
                self.snapshot.generation = (generation << 32) | block.epoch
                self.snapshot.lastCallback = block.deliveredAt
                self.snapshot.inputHostTime = block.hostTime
                self.snapshot.separationReady = result.error == nil
                self.snapshot.separationError = result.error
                self.snapshot.inferenceMs = result.inferenceMs
                self.snapshot.analysisMs = (ProcessInfo.processInfo.systemUptime-block.deliveredAt)*1000
            }
            self.pipeline = pipeline
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc,deviceID,ioQueue) {
                [weak self] _,input,inputTime,_,_ in
                guard let self else { return }
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let first = buffers.first, let firstData = first.mData else { return }
                let planar = first.mNumberChannels == 1 && buffers.count >= 2
                let count = Int(first.mDataByteSize)/MemoryLayout<Float>.size/(planar ? 1 : 2)
                guard count > 0 else { return }
                let l = firstData.assumingMemoryBound(to: Float.self)
                let r = planar ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
                if planar && (r == nil || buffers[1].mDataByteSize < first.mDataByteSize) { return }
                var stereo = [Float](repeating: 0,count: count*2)
                var audible = false
                for i in 0..<count {
                    stereo[i*2] = planar ? l[i] : l[i*2]
                    stereo[i*2+1] = planar ? r![i] : l[i*2+1]
                    audible = audible || abs(stereo[i*2]) > 0.0006 || abs(stereo[i*2+1]) > 0.0006
                }
                self.lock.lock()
                let sensitivity = self.gain
                self.snapshot.bufferFrames = count
                let nowHost = AudioGetCurrentHostTime(), inputHost = inputTime.pointee.mHostTime
                if inputTime.pointee.mFlags.contains(.hostTimeValid) && nowHost >= inputHost {
                    self.snapshot.inputAgeMs = Double(AudioConvertHostTimeToNanos(nowHost-inputHost))/1_000_000
                }
                self.snapshot.callbackCount &+= 1
                if audible { self.snapshot.audibleCallbackCount &+= 1 }
                self.lock.unlock()
                pipeline.enqueue(.init(stereo: stereo,sensitivity: sensitivity,
                    deliveredAt: ProcessInfo.processInfo.systemUptime,
                    hostTime: inputTime.pointee.mFlags.contains(.hostTimeValid) ? inputTime.pointee.mHostTime : 0))
            },"连接音频分析回调")
            try check(AudioDeviceStart(deviceID, ioProc), "开始系统音频捕获")
        } catch {
            stopOnWorker()
            throw error
        }
    }

    func stop() {
        lock.lock(); revision &+= 1; snapshot = CaptureSnapshot(); lock.unlock()
        controlQueue.async { self.stopOnWorker() }
    }

    private func stopOnWorker() {
        pipeline?.cancel(); pipeline = nil
        if let ioProc {
            AudioDeviceStop(deviceID, ioProc)
            AudioDeviceDestroyIOProcID(deviceID, ioProc)
        }
        ioProc = nil
        // Destroying the IO proc ends synchronous callbacks before reset.
        if deviceID != 0 { AudioHardwareDestroyAggregateDevice(deviceID) }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        deviceID = 0; tapID = 0
        lock.lock(); snapshot = CaptureSnapshot(); lock.unlock()
    }

    func dispose() {
        stop()
        if let listener = deviceListener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            deviceListener = nil
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                  mElement: kAudioObjectPropertyElementMain)
    }
    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw CaptureError.coreAudio(operation, status) }
    }
}
