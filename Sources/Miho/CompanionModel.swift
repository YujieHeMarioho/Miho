import AppKit
import Combine
import CoreAudio
import MihoCore

struct PetMotion {
    var energy = 0.0
    var paused = false
    var pose = DancePose()
}

final class CharacterAnimation: ObservableObject {
    struct Frame {
        var pose = DancePose()
        var rotation = Rotation3()
        var appearance = CharacterAppearance()
        var rhythm = RhythmFrame()
        var impact = 0.0
        var gesture: VocalGesture = .idle
    }
    @Published var frame = Frame()
}

@available(macOS 14.2, *)
final class CompanionModel: ObservableObject {
    let animation = CharacterAnimation()
    var motion = PetMotion() {
        didSet { publishFrame() }
    }
    @Published var status = "准备好陪你听音乐"
    @Published var enabled = false
    @Published var motionIntensity = 1.0 {
        didSet {
            choreographer.intensity = motionIntensity
            defaults.set(motionIntensity,forKey: "motionIntensity")
        }
    }
    @Published var appearance = CharacterAppearance() {
        didSet {
            if let data = try? JSONEncoder().encode(appearance) { defaults.set(data,forKey: "characterAppearance") }
            publishFrame()
        }
    }
    @Published var autoReturnRotation = false {
        didSet {
            dragRotation.automaticallyReturns = autoReturnRotation
            defaults.set(autoReturnRotation,forKey: "rotationAutoReturn")
        }
    }
    @Published var mood: DanceMood = .dreamy
    @Published var gesture: VocalGesture = .idle
    @Published var separationReady = false
    @Published var inferenceMs = 0.0
    @Published var sensitivity: Double = 1 {
        didSet {
            capture.setSensitivity(sensitivity)
            defaults.set(sensitivity, forKey: "sensitivity")
        }
    }
    @Published var callbackCount: UInt64 = 0
    @Published var audibleCallbackCount: UInt64 = 0
    @Published var beats: UInt64 = 0
    @Published var worstCaptureToMotionMs = 0.0
    private var measuredWorstMs = 0.0
    private let capture: AudioCapturing
    private let defaults: UserDefaults
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var restartWork: DispatchWorkItem?
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var displayRhythm = RhythmFrame()
    private var lastCaptureGeneration: UInt64 = 0
    private var startedAt = 0.0
    private var sleeping = false
    private var errorMessage: String?
    private let choreographer = Choreographer()
    private let dragRotation = DragRotation()

    init(capture: AudioCapturing = SystemAudioCapture(), defaults: UserDefaults = .standard) {
        self.capture = capture
        self.defaults = defaults
        appearance = CharacterAppearance.load(defaults.data(forKey: "characterAppearance"))
        publishFrame()
        autoReturnRotation = defaults.object(forKey: "rotationAutoReturn") as? Bool ?? false
        dragRotation.automaticallyReturns = autoReturnRotation
        let storedIntensity = defaults.object(forKey: "motionIntensity") as? Double ?? 1
        motionIntensity = storedIntensity.isFinite ? min(1.5,max(0.5,storedIntensity)) : 1
        choreographer.intensity = motionIntensity
        let stored = defaults.object(forKey: "sensitivity") as? Double ?? 1
        sensitivity = stored.isFinite ? min(2, max(0.5, stored)) : 1
        capture.setSensitivity(sensitivity)
        capture.onOutputChanged = { [weak self] in self?.scheduleRestart() }
        let notifications = NSWorkspace.shared.notificationCenter
        observers.append(notifications.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
            [weak self] _ in
            self?.sleeping = true
            self?.restartWork?.cancel()
            self?.capture.stop()
        })
        observers.append(notifications.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in
            self?.sleeping = false
            self?.scheduleRestart()
        })
        let tick = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: "captureEnabled")
        restartWork?.cancel()
        errorMessage = nil
        if value { start() } else { capture.stop(); status = "已暂停 · Miho 正在休息" }
    }

    func retry() {
        if enabled { start() } else { setEnabled(true) }
    }

    func beginRotation() { dragRotation.begin() }
    func rotate(dx: Double, dy: Double, dt: Double) {
        dragRotation.drag(dx: dx,dy: dy,dt: dt)
        publishFrame()
    }
    func endRotation() { dragRotation.end() }
    func resetRotation() {
        dragRotation.reset()
        publishFrame()
    }
    private func publishFrame() {
        animation.frame = .init(pose: motion.pose,rotation: dragRotation.rotation,appearance: appearance,
                               rhythm: displayRhythm,impact: choreographer.impact,gesture: choreographer.gesture)
    }

    private func start() {
        guard !sleeping else { return }
        measuredWorstMs = 0
        worstCaptureToMotionMs = 0
        errorMessage = nil
        startedAt = ProcessInfo.processInfo.systemUptime
        status = "正在连接系统声音…"
        capture.start { [weak self] error in
            guard let self, self.enabled else { return }
            if let error {
                self.errorMessage = error.localizedDescription
                self.status = error.localizedDescription
            } else {
                self.status = "等待声音 · 放首歌给 Miho 吧"
            }
        }
    }

    private func scheduleRestart() {
        guard enabled, !sleeping else { return }
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, !self.sleeping else { return }
            self.start()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func update() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now - lastTime))
        lastTime = now
        let current = capture.latest()
        if current.generation != lastCaptureGeneration {
            choreographer.resetInput()
            lastCaptureGeneration = current.generation
        }
        dragRotation.update(dt: dt)
        var energy = current.rhythm.energy
        if !enabled || sleeping || now - current.lastCallback > 0.25 {
            energy = motion.energy * exp(-dt / 0.16)
        }
        var next = motion
        next.energy = energy
        next.paused = !enabled
        var rhythm = current.rhythm
        rhythm.energy = energy
        // The latest audio age already includes all windows in its callback.
        // Add only time since delivery, so a render frame never restarts the beat.
        if rhythm.pulse.bpm > 0 { rhythm.pulse.position += max(0,now-current.lastCallback)*rhythm.pulse.bpm/60 }
        if rhythm.beatAge.isFinite { rhythm.beatAge += max(0,now-current.lastCallback) }
        if rhythm.vocalAccentAge.isFinite { rhythm.vocalAccentAge += max(0,now-current.lastCallback) }
        if !enabled || sleeping || now-current.lastCallback > 0.25 {
            rhythm.pulse.confidence = 0
            rhythm.bass = 0; rhythm.mid = 0; rhythm.treble = 0; rhythm.transient = 0
            rhythm.vocalPresence = 0; rhythm.vocalPitch = 0; rhythm.vocalEnergy = 0; rhythm.vocalConfidence = 0; rhythm.vocalSustain = 0; rhythm.vocalPitchMotion = 0
        }
        displayRhythm = rhythm
        next.pose = choreographer.update(dt: dt, rhythm: rhythm, enabled: enabled && !sleeping)
        motion = next
        if enabled && energy > 0.01 && current.inputHostTime != 0 {
            let hostNow = AudioGetCurrentHostTime()
            if hostNow >= current.inputHostTime && now - current.lastCallback < 0.25 {
                let delay = Double(AudioConvertHostTimeToNanos(hostNow - current.inputHostTime)) / 1_000_000
                measuredWorstMs = max(measuredWorstMs, delay)
            }
        }
        // Update diagnostics at one Hz; live pose and audio preview share 60 Hz frames.
        if Int(now) != Int(now - dt) {
            callbackCount = current.callbackCount
            audibleCallbackCount = current.audibleCallbackCount
            beats = current.rhythm.beatCount
            worstCaptureToMotionMs = measuredWorstMs
            mood = choreographer.mood
            gesture = choreographer.gesture
            separationReady = current.separationReady
            inferenceMs = current.inferenceMs
            if sleeping { status = "休眠中" }
            else if !enabled { status = "已暂停 · Miho 正在休息" }
            else if let errorMessage { status = errorMessage }
            else if let failure = current.separationError { status = failure }
            else if current.callbackCount == 0 && now - startedAt > 3 {
                status = "等待系统声音 · 若已播放，请检查音频权限"
            } else if now - current.lastCallback > 3 && now - startedAt > 3 {
                status = "音频连接中断 · 可重试连接"
            } else if energy > 0.01 { status = "\(gesture.label) ♪" }
            else { status = "等待声音 · 放首歌给 Miho 吧" }
        }
    }

    var captureDiagnostics: CaptureSnapshot { capture.latest() }

    func shutdown() {
        restartWork?.cancel()
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        capture.onOutputChanged = nil
        capture.dispose()
    }
}
