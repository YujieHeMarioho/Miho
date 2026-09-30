import Foundation

public enum DanceMood: String, CaseIterable, Sendable {
    case dreamy, groovy, lively
    public var label: String {
        switch self { case .dreamy: return "轻柔陪伴"; case .groovy: return "松弛律动"; case .lively: return "活力满满" }
    }
}

public enum DanceMove: String, CaseIterable, Sendable {
    case twoStep, bodyRoll, armWave, pop, heelToe, happyHop
    public var label: String {
        switch self {
        case .twoStep: return "左右摇摆"
        case .bodyRoll: return "软糖波浪"
        case .armWave: return "耳朵 Wave"
        case .pop: return "重拍点头"
        case .heelToe: return "滑步转身"
        case .happyHop: return "开心弹跳"
        }
    }
}

public struct Rotation3: Equatable, Sendable {
    public var x: Double = 0, y: Double = 0, z: Double = 0
    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) { self.x = x; self.y = y; self.z = z }
    func mixed(with b: Self, by t: Double) -> Self { .init(x+(b.x-x)*t,y+(b.y-y)*t,z+(b.z-z)*t) }
}

/// Soft-body motion plus independently delayed ears and rigid accessories.
public struct DancePose: Equatable, Sendable {
    public var x = 0.0, y = 0.0, z = 0.0, squash = 1.0
    public var body = Rotation3(), head = Rotation3()
    public var leftEar = Rotation3(), rightEar = Rotation3()
    public var accessoryBounce = 0.0
    public init() {}
    public func mixed(with b: Self, by amount: Double) -> Self {
        let t = amount.isFinite ? min(1,max(0,amount)) : 0
        func mix(_ a: Double, _ b: Double) -> Double { a+(b-a)*t }
        var p = Self()
        p.x = mix(x,b.x); p.y = mix(y,b.y); p.z = mix(z,b.z); p.squash = mix(squash,b.squash)
        p.body = body.mixed(with: b.body,by: t); p.head = head.mixed(with: b.head,by: t)
        p.leftEar = leftEar.mixed(with: b.leftEar,by: t); p.rightEar = rightEar.mixed(with: b.rightEar,by: t)
        p.accessoryBounce = mix(accessoryBounce,b.accessoryBounce)
        return p
    }
}

/// Groove follows audio onsets; shuffled eight-count phrases and seeded personality gestures
/// add variation without resetting the beat clock or jerking between poses.
public final class Choreographer {
    public private(set) var mood: DanceMood = .dreamy
    public private(set) var move: DanceMove = .twoStep
    public private(set) var groovePeriod = 0.5
    public private(set) var pose = DancePose()
    private var time = 0.0, phase = 0.0, accent = 0.0, engagement = 0.0
    private var averageEnergy = 0.0, averageBass = 0.0, averageBrightness = 0.0
    private var lastBeatTime = -10.0, lastCount: UInt64 = 0, lastPhrase = -1
    private var previousMove: DanceMove = .twoStep, transition = 1.0
    private var bag: [DanceMove] = [], bagMood: DanceMood = .dreamy
    private var moodCandidate: DanceMood = .dreamy, moodHold = 0.0
    private var randomState: UInt64
    private let personalityPhase: Double
    private var nextGesture = 2.0, gestureStarted = -10.0, gestureDuration = 1.0
    private var gesture = 0, gestureDirection = 1.0

    public init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        randomState = seed
        personalityPhase = Double(seed % 10_000)/10_000 * 2 * .pi
    }
    private func random() -> Double {
        randomState &+= 0x9E3779B97F4A7C15
        var z = randomState
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11)/Double(UInt64(1)<<53)
    }
    private func nextMove() -> DanceMove {
        if bag.isEmpty || bagMood != mood {
            bagMood = mood
            switch mood {
            case .dreamy: bag = [.twoStep,.bodyRoll,.armWave]
            case .groovy: bag = [.twoStep,.bodyRoll,.armWave,.heelToe,.pop]
            case .lively: bag = DanceMove.allCases
            }
            for index in stride(from: bag.count-1,through: 1,by: -1) {
                bag.swapAt(index,Int(random()*Double(index+1)))
            }
            if averageBass > 0.4 && mood != .dreamy, let index = bag.firstIndex(of: .pop) {
                bag.swapAt(index,bag.count-1)
            }
        }
        if bag.last == move && bag.count > 1 { bag.swapAt(0,bag.count-1) }
        return bag.removeLast()
    }
    @discardableResult public func update(dt rawDT: Double, rhythm: RhythmFrame, enabled: Bool = true) -> DancePose {
        let dt = rawDT.isFinite ? min(0.1,max(0,rawDT)) : 0
        time += dt
        func safe(_ v: Double) -> Double { v.isFinite ? min(1,max(0,v)) : 0 }
        let energy = enabled ? safe(rhythm.energy) : 0
        let smoothing = 1-exp(-dt/0.65)
        averageEnergy += (energy-averageEnergy)*smoothing
        averageBass += (safe(rhythm.bassShare)-averageBass)*smoothing
        averageBrightness += (safe(rhythm.brightness)-averageBrightness)*smoothing
        let candidate: DanceMood = averageEnergy > 0.52 || (averageEnergy > 0.30 && averageBrightness > 0.45) ? .lively : averageEnergy > 0.12 ? .groovy : .dreamy
        if candidate == moodCandidate { moodHold += dt } else { moodCandidate = candidate; moodHold = 0 }
        if moodHold > 1.2 { mood = moodCandidate }
        if rhythm.beatCount < lastCount { lastBeatTime = -10; lastCount = rhythm.beatCount }
        if enabled && rhythm.beatCount > lastCount {
            let interval = time-lastBeatTime
            if (0.28...0.9).contains(interval) { groovePeriod += (interval-groovePeriod)*0.25 }
            lastBeatTime = time; lastCount = rhythm.beatCount; accent = 1
        }
        accent *= exp(-dt/0.10)
        let elapsed = time-lastBeatTime
        let error = elapsed < 1 ? sin((elapsed/groovePeriod-phase)*2 * .pi) : 0
        phase += dt/groovePeriod + error*dt*0.65
        let target = energy > 0.012 ? min(1,0.25+energy*1.3) : 0
        engagement += (target-engagement)*(1-exp(-dt/(target > engagement ? 0.10 : 0.18)))
        let phrase = Int(phase/8)
        if phrase != lastPhrase && engagement > 0.15 {
            lastPhrase = phrase; previousMove = move; move = nextMove(); transition = 0
        }
        transition = min(1,transition+dt/0.38)
        let ease = transition*transition*(3-2*transition)
        let danced = Self.dance(move: previousMove,phase: phase,energy: energy,accent: accent)
            .mixed(with: Self.dance(move: move,phase: phase,energy: energy,accent: accent),by: ease)
        var idle = DancePose()
        idle.squash = 1+sin(time*1.9+personalityPhase)*0.012
        idle.body = Rotation3(sin(time*0.7)*0.018,sin(time*0.43+personalityPhase)*0.045,sin(time*0.9+0.7)*0.025)
        idle.leftEar = Rotation3(sin(time*1.2)*0.018,0,sin(time*1.7+personalityPhase)*0.025)
        idle.rightEar = Rotation3(sin(time*1.4+1.1)*0.016,0,sin(time*1.3+2.1)*0.018)
        pose = idle.mixed(with: danced,by: engagement)
        addPersonality(energy: energy)
        return pose
    }
    private func addPersonality(energy: Double) {
        if time >= nextGesture {
            gesture = Int(random()*4); gestureDirection = random() < 0.5 ? -1 : 1
            gestureStarted = time; gestureDuration = 0.8+random()*1.0
            nextGesture = time+gestureDuration+1.6+random()*3.8
        }
        let age = (time-gestureStarted)/gestureDuration
        guard age >= 0 && age < 1 else { return }
        let weight = pow(sin(age * .pi),2)*(energy > 0.1 ? 0.45 : 1)
        switch gesture {
        case 0: // A curious peek, with the headset trailing the body slightly.
            pose.body.y += weight*gestureDirection*0.20
            pose.head.y -= weight*gestureDirection*0.12
            pose.body.z += weight*gestureDirection*0.05
        case 1:
            pose.body.z += weight*gestureDirection*0.11
            pose.leftEar.z -= weight*0.10; pose.rightEar.z += weight*0.05
        case 2: // One ear first, then the other; never a synchronized metronome.
            pose.leftEar.z += sin(age * 2 * .pi)*weight*0.24
            pose.rightEar.x += sin(age * 2 * .pi-0.9)*weight*0.20
        default:
            pose.squash -= weight*0.025
            pose.head.z += weight*gestureDirection*0.07
            pose.accessoryBounce += weight*0.012
        }
    }
    /// The exporter and interactive studio share these exact live-motion definitions.
    public static func dance(move: DanceMove, phase: Double, energy: Double, accent: Double = 0) -> DancePose {
        let a = energy.isFinite ? min(1,max(0,energy)) : 0
        let b = (phase.isFinite ? phase : 0)*2 * .pi
        let hit = accent.isFinite ? min(1,max(0,accent)) : 0
        let s = sin(b/2), pulse = (1-cos(b))/2
        var p = DancePose()
        p.y = 0.018+pulse*0.025+hit*0.018
        p.body = Rotation3(pulse*0.055,s*0.08,-s*0.06)
        p.head = Rotation3(-sin(b-0.35)*0.05,-s*0.08,s*0.06)
        p.leftEar = Rotation3(sin(b-0.65)*0.06,0,sin(b/2-0.7)*0.08)
        p.rightEar = Rotation3(sin(b-1.1)*0.06,0,sin(b/2-1.5)*0.06)
        p.accessoryBounce = sin(b-0.45)*0.008+hit*0.007
        switch move {
        case .twoStep:
            p.x = s*0.15; p.body.z = -s*0.13; p.body.y = s*0.14
            p.squash = 1-pulse*0.035
        case .bodyRoll:
            p.x = sin(b/2+0.6)*0.08; p.z = cos(b/2)*0.04
            p.body = Rotation3(sin(b/2)*0.18,cos(b/2)*0.16,sin(b/2+1)*0.13)
            p.squash = 1+cos(b/2)*0.045
            p.head = Rotation3(-sin(b/2-0.8)*0.13,-cos(b/2)*0.10,-sin(b/2)*0.12)
        case .armWave:
            p.body.z = s*0.10
            p.leftEar = Rotation3(cos(b/2)*0.17,0,-sin(b/2)*0.36)
            p.rightEar = Rotation3(cos(b/2-1.1)*0.16,0,sin(b/2-1.3)*0.34)
            p.head.z = -sin(b/2-0.5)*0.10
        case .pop:
            let pop = pow(max(0,cos(b)),6)
            p.body = Rotation3(-pop*0.10,s*0.20,-s*0.055)
            p.head.x = pop*0.16
            p.squash = 1-pop*0.055; p.y = 0.02+pop*0.03+hit*0.02
            p.leftEar.x = pop*0.18; p.rightEar.x = pop*0.14
        case .heelToe:
            p.x = s*0.19; p.z = cos(b/2)*0.04
            p.body.y = s*0.34; p.body.z = -s*0.09
            p.head.y = -s*0.12
            p.leftEar.z = -s*0.09; p.rightEar.z = -s*0.06
        case .happyHop:
            p.y = 0.025+pulse*(0.15+a*0.07); p.x = s*0.085
            p.squash = 1+cos(b)*0.055
            p.body = Rotation3(sin(b)*0.065,s*0.12,-s*0.13)
            p.leftEar.x = -sin(b-0.55)*0.27; p.rightEar.x = -sin(b-0.9)*0.23
            p.accessoryBounce = -sin(b-0.8)*0.016
        }
        return DancePose().mixed(with: p,by: 0.35+a*0.65)
    }
}
