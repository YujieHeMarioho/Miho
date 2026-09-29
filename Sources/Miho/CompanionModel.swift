import AppKit
import Combine
import CoreAudio
import MihoCore

struct PetMotion {
    var time = 0.0
    var phase = 0.0
    var energy = 0.0
    var bounce = 0.0
    var paused = false
    var pose = DancePose()
}

@available(macOS 14.2, *)
final class CompanionModel: ObservableObject {
    @Published var motion = PetMotion()
    @Published var status = "准备好陪你听音乐"
    @Published var enabled = false
    @Published var mood: DanceMood = .dreamy
    @Published var danceMove: DanceMove = .twoStep
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
    private var lastBeatTime = -10.0
    private var lastBeatCount: UInt64 = 0
    private var startedAt = 0.0
    private var sleeping = false
    private var errorMessage: String?
    private let choreographer = Choreographer()

    init(capture: AudioCapturing = SystemAudioCapture(), defaults: UserDefaults = .standard) {
        self.capture = capture
        self.defaults = defaults
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
        let tick = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.update() }
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

    private func start() {
        guard !sleeping else { return }
        lastBeatCount = 0
        lastBeatTime = -10
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
        var energy = current.rhythm.energy
        if !enabled || sleeping || now - current.lastCallback > 0.25 {
            energy = motion.energy * exp(-dt / 0.16)
        }
        if enabled && current.rhythm.beatCount != lastBeatCount {
            lastBeatTime = now
            lastBeatCount = current.rhythm.beatCount
        }
        var next = motion
        next.time += dt
        next.phase += dt * (1.8 + energy * 8)
        next.energy = energy
        let age = now - lastBeatTime
        next.bounce = age >= 0 && age < 0.36 && enabled ? sin(.pi * age / 0.36) : 0
        next.paused = !enabled
        var rhythm = current.rhythm
        rhythm.energy = energy
        next.pose = choreographer.update(dt: dt, rhythm: rhythm, enabled: enabled && !sleeping)
        motion = next
        if enabled && energy > 0.01 && current.inputHostTime != 0 {
            let hostNow = AudioGetCurrentHostTime()
            if hostNow >= current.inputHostTime && now - current.lastCallback < 0.25 {
                let delay = Double(AudioConvertHostTimeToNanos(hostNow - current.inputHostTime)) / 1_000_000
                measuredWorstMs = max(measuredWorstMs, delay)
            }
        }
        // Update diagnostics at one Hz; pet movement remains at 30 Hz.
        if Int(now) != Int(now - dt) {
            callbackCount = current.callbackCount
            audibleCallbackCount = current.audibleCallbackCount
            beats = current.rhythm.beatCount
            worstCaptureToMotionMs = measuredWorstMs
            mood = choreographer.mood
            danceMove = choreographer.move
            if sleeping { status = "休眠中" }
            else if !enabled { status = "已暂停 · Miho 正在休息" }
            else if let errorMessage { status = errorMessage }
            else if current.callbackCount == 0 && now - startedAt > 3 {
                status = "等待系统声音 · 若已播放，请检查音频权限"
            } else if now - current.lastCallback > 3 && now - startedAt > 3 {
                status = "音频连接中断 · 可重试连接"
            } else if energy > 0.01 { status = "\(mood.label) · \(danceMove.label) ♪" }
            else { status = "等待声音 · 放首歌给 Miho 吧" }
        }
    }

    func shutdown() {
        restartWork?.cancel()
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        capture.onOutputChanged = nil
        capture.dispose()
    }
}
