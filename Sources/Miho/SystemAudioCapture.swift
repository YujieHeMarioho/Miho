import CoreAudio
import Foundation
import MihoCore

struct CaptureSnapshot {
    var rhythm = RhythmFrame()
    var lastCallback: TimeInterval = 0
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
/// The IO queue owns the analyzer; a small
/// locked mailbox carries only scalar results to the UI, never recorded audio.
@available(macOS 14.2, *)
final class SystemAudioCapture: AudioCapturing {
    private var tapID: AudioObjectID = 0
    private var deviceID: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
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
            do { try self.startOnWorker() } catch { failure = error }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock(); let isCurrent = self.revision == request; self.lock.unlock()
                if isCurrent { completion(failure) }
            }
        }
    }

    private func startOnWorker() throws {
        stopOnWorker()
        do {
            let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
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
                  format.mBitsPerChannel == 32, format.mChannelsPerFrame == 1,
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
            let analyzer = RhythmAnalyzer(sampleRate: format.mSampleRate)
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, ioQueue) {
                [weak self] _, input, _, _, _ in
                guard let self else { return }
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let buffer = buffers.first, let data = buffer.mData else { return }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let values = data.assumingMemoryBound(to: Float.self)
                self.lock.lock(); let sensitivity = self.gain; self.lock.unlock()
                var frame = RhythmFrame()
                var audible = false
                for index in 0..<count {
                    let sample = values[index]
                    audible = audible || abs(sample) > 0.0006
                    frame = analyzer.consume(sample, sensitivity: sensitivity)
                }
                guard count > 0 else { return }
                self.lock.lock()
                self.snapshot.rhythm = frame
                self.snapshot.lastCallback = ProcessInfo.processInfo.systemUptime
                self.snapshot.callbackCount &+= 1
                if audible { self.snapshot.audibleCallbackCount &+= 1 }
                self.lock.unlock()
            }, "连接音频分析回调")
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
